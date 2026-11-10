# ================================================================
# Pendrive_X - Hardware acceleration auto-tuner (Windows)
# ================================================================
# Detects NVIDIA CUDA, AMD/Intel Vulkan and CPU capabilities, then
# recommends llama.cpp / Ollama tuning values. Emits either `KEY=VALUE`
# lines (for .bat launchers) or JSON (for installers/diagnostics).
#
# Usage:
#   powershell -NoProfile -File tools\hardware.ps1 -ModelPath E:\models\model.gguf
#   powershell -NoProfile -File tools\hardware.ps1 -Format json
# ================================================================
param(
    [string]$ModelPath = "",
    [double]$ModelGB = 0,
    [ValidateSet("env", "json")][string]$Format = "env"
)

$ErrorActionPreference = "Continue"

function Get-ModelSizeGB {
    if ($ModelGB -gt 0) { return [math]::Round($ModelGB, 2) }
    if ($ModelPath -and (Test-Path -LiteralPath $ModelPath)) {
        try { return [math]::Round((Get-Item -LiteralPath $ModelPath).Length / 1GB, 2) } catch { }
    }
    return 0
}

$modelSize = Get-ModelSizeGB
if ($modelSize -le 0) { $modelSize = 4.0 }  # safe default for a 7B Q4 model

# -----------------------------------------------------------------
# CPU / RAM
# -----------------------------------------------------------------
$cpuName = "Unknown CPU"
$physicalCores = 0
$logicalCores = 0
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $cpuName = $cpu.Name.Trim()
    $physicalCores = [int]$cpu.NumberOfCores
    $logicalCores = [int]$cpu.NumberOfLogicalProcessors
} catch {
    $logicalCores = [int]$env:NUMBER_OF_PROCESSORS
    $physicalCores = [math]::Max(1, [math]::Floor($logicalCores / 2))
}
if ($physicalCores -le 0) { $physicalCores = [math]::Max(1, [math]::Floor($logicalCores / 2)) }

$ramGB = 0
try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) } catch { }

# -----------------------------------------------------------------
# GPUs
# -----------------------------------------------------------------
$videoControllers = @()
try {
    $videoControllers = @(Get-CimInstance Win32_VideoController -ErrorAction Stop)
} catch { }

$vramGB = 0
$gpuName = ""
$backend = "cpu"
$note = "CPU only ($cpuName, $physicalCores threads)"

# NVIDIA first (compute capability drives CUDA layer offload)
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if ($nvidiaSmi) {
    try {
        $line = (& $nvidiaSmi.Source --query-gpu=name,memory.total,compute_cap --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
        if ($line) {
            $parts = @($line -split "," | ForEach-Object { $_.Trim() })
            if ($parts.Count -ge 2) {
                $gpuName = $parts[0]
                $vramGB = [math]::Round(([double]$parts[1]) / 1024, 1)
                $cc = 0.0
                if ($parts.Count -ge 3) { [void][double]::TryParse($parts[2], [ref]$cc) }
                $backend = "cuda"
                if ($cc -gt 0) {
                    $note = "NVIDIA $gpuName / CUDA compute $cc / ${vramGB} GB VRAM"
                } else {
                    $note = "NVIDIA $gpuName / CUDA / ${vramGB} GB VRAM"
                }
            }
        }
    } catch { }
}

if ($backend -eq "cpu") {
    $candidate = $videoControllers | Where-Object {
        $_.Name -and $_.Name -notmatch 'Microsoft Basic|Remote Display|Virtual|Parsec|DameWare'
    } | Select-Object -First 1
    if ($candidate) {
        $gpuName = $candidate.Name.Trim()
        if ($candidate.AdapterRAM -and $candidate.AdapterRAM -gt 0) {
            $vramGB = [math]::Round($candidate.AdapterRAM / 1GB, 1)
        }
        $isDedicated = $gpuName -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro|Arc|Iris Xe MAX'
        $backend = "vulkan"
        if ($isDedicated -and $vramGB -ge 2) {
            $note = "$gpuName / Vulkan / ${vramGB} GB VRAM"
        } elseif ($vramGB -ge 2) {
            $note = "$gpuName / Vulkan / ${vramGB} GB VRAM"
        } else {
            $note = "$gpuName / Vulkan (shared memory)"
        }
    }
}

# -----------------------------------------------------------------
# Tuning heuristics
# -----------------------------------------------------------------
$overrideNgl = $env:LLAMACPP_NGL
$overrideThreads = $env:LLAMACPP_THREADS
$overrideCtx = $env:LLAMACPP_CTX
$autoTune = $true
if ($env:AUTO_TUNE -eq "0" -or $env:AUTO_TUNE -eq "false") { $autoTune = $false }

$ngl = 0
# Rough layer counts for common model sizes. llama.cpp clamps -ngl to the
# real layer count, so these only exist to express *partial* offload.
# (999 is the "all layers" sentinel.)
$totalLayers = 32
if ($modelSize -gt 70) { $totalLayers = 96 }
elseif ($modelSize -gt 45) { $totalLayers = 80 }
elseif ($modelSize -gt 30) { $totalLayers = 64 }
elseif ($modelSize -gt 22) { $totalLayers = 60 }
elseif ($modelSize -gt 15) { $totalLayers = 48 }
elseif ($modelSize -gt 9) { $totalLayers = 40 }

if ($backend -eq "cuda") {
    if ($vramGB -le 0 -or $vramGB -ge ($modelSize * 0.95)) {
        $ngl = 999
    } else {
        # Reserve ~1 GB of VRAM for the KV cache and compute buffers.
        $usable = [math]::Max(0.0, $vramGB - 1.0)
        $ratio = [math]::Min(1.0, $usable / $modelSize)
        $ngl = [int][math]::Floor($totalLayers * $ratio)
        if ($ngl -ge $totalLayers) { $ngl = 999 }
    }
} elseif ($backend -eq "vulkan") {
    # Vulkan: offload everything on dedicated GPUs; be conservative on shared memory.
    $isDedicated = $gpuName -match 'NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Radeon Pro|Arc'
    if ($isDedicated) {
        $ngl = 999
    } elseif ($vramGB -ge 2) {
        $ratio = [math]::Min(1.0, $vramGB / $modelSize)
        $ngl = [math]::Min(999, [int][math]::Floor($totalLayers * $ratio))
    } else {
        $ngl = [math]::Min(24, $totalLayers)
    }
}

if ($overrideNgl -and $overrideNgl -match '^\d+$') { $ngl = [int]$overrideNgl }
if ($overrideThreads -and $overrideThreads -match '^\d+$') { $threads = [int]$overrideThreads }
else { $threads = [math]::Min(16, [math]::Max(1, $physicalCores)) }

if ($overrideCtx -and $overrideCtx -match '^\d+$') {
    $ctx = [int]$overrideCtx
} elseif ($ramGB -gt 0 -and $ramGB -le 8) {
    $ctx = 2048
} elseif ($ramGB -ge 32) {
    $ctx = 8192
} else {
    $ctx = 4096
}

# If a model is huge relative to RAM, reduce context to avoid OOM.
if ($ramGB -gt 0 -and $modelSize -gt ($ramGB * 0.6)) { $ctx = [math]::Min($ctx, 2048) }

$variant = switch ($backend) {
    "cuda" { "cuda" }
    "vulkan" { "vulkan" }
    default { "cpu" }
}

if (-not $autoTune) { $note = "$note (auto-tune disabled)" }

$result = [ordered]@{
    PENDRIVE_ACCEL          = $backend
    PENDRIVE_GPU_NAME       = $gpuName
    PENDRIVE_VRAM_GB        = $vramGB
    PENDRIVE_NGL            = $ngl
    PENDRIVE_THREADS        = $threads
    PENDRIVE_CTX            = $ctx
    PENDRIVE_RAM_GB         = $ramGB
    PENDRIVE_CPU            = $cpuName
    PENDRIVE_LLAMACPP_VARIANT = $variant
    PENDRIVE_ACCEL_NOTE     = $note
}

if ($Format -eq "json") {
    $result | ConvertTo-Json -Compress
} else {
    foreach ($key in $result.Keys) {
        $value = [string]$result[$key]
        $value = $value -replace "(`r|`n)", " "
        Write-Output ("{0}={1}" -f $key, $value)
    }
}
