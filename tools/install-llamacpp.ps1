# ================================================================
# Pendrive_X - install / update portable llama.cpp (Windows)
# ================================================================
# Downloads a standalone llama-server build into <USB>\llamacpp.
# Only that folder and installer_data are touched; models, Ollama
# data and AnythingLLM chats are preserved.
#
# Usage:
#   powershell -NoProfile -File tools\install-llamacpp.ps1 -UsbRoot E:\ -Variant auto
#   powershell -NoProfile -File tools\install-llamacpp.ps1 -UsbRoot E:\ -Variant cuda -Force
# ================================================================
param(
    [Parameter(Mandatory = $true)][string]$UsbRoot,
    [ValidateSet("auto", "cuda", "rocm", "vulkan", "metal", "cpu")][string]$Variant = "auto",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$UsbRoot = (Resolve-Path -LiteralPath $UsbRoot).Path.TrimEnd('\')

# -----------------------------------------------------------------
# Pinned versions / URLs
# -----------------------------------------------------------------
$VersionsFile = Join-Path $UsbRoot "versions.env"
$cfg = @{}
if (Test-Path -LiteralPath $VersionsFile) {
    Get-Content -LiteralPath $VersionsFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
            $cfg[$Matches[1]] = $Matches[2]
        }
    }
}
$LlamaVersion = if ($cfg.ContainsKey("LLAMACPP_VERSION")) { $cfg["LLAMACPP_VERSION"] } else { "b12244" }
$TargetDir = Join-Path $UsbRoot "llamacpp"
$ServerExe = Join-Path $TargetDir "llama-server.exe"

if ((Test-Path -LiteralPath $ServerExe) -and -not $Force) {
    Write-Host "[OK] llama.cpp already installed at $TargetDir" -ForegroundColor Green
    exit 0
}

# -----------------------------------------------------------------
# Pick a build variant
# -----------------------------------------------------------------
if ($Variant -eq "auto") {
    $hwScript = Join-Path $UsbRoot "tools\hardware.ps1"
    if (Test-Path -LiteralPath $hwScript) {
        try {
            $hw = & powershell -NoProfile -ExecutionPolicy Bypass -File $hwScript -Format json 2>$null | ConvertFrom-Json
            if ($hw.PENDRIVE_LLAMACPP_VARIANT) { $Variant = [string]$hw.PENDRIVE_LLAMACPP_VARIANT }
        } catch { }
    }
}
# A .env written on Linux/macOS may say rocm/metal; the Windows build is Vulkan.
if ($Variant -eq "auto" -or $Variant -eq "rocm" -or $Variant -eq "metal") { $Variant = "vulkan" }

$MainUrl = ""
$RuntimeUrl = ""
switch ($Variant) {
    "cuda" {
        $MainUrl = $cfg["LLAMACPP_WIN_CUDA_URL"]
        $RuntimeUrl = $cfg["LLAMACPP_WIN_CUDA_RUNTIME_URL"]
    }
    "vulkan" { $MainUrl = $cfg["LLAMACPP_WIN_VULKAN_URL"] }
    "cpu" { $MainUrl = $cfg["LLAMACPP_WIN_CPU_URL"] }
}
if (-not $MainUrl) { $MainUrl = $cfg["LLAMACPP_WIN_URL"] }
if (-not $MainUrl) {
    Write-Host "ERROR: No llama.cpp Windows URL configured in versions.env" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------
# Download helper
# -----------------------------------------------------------------
function Invoke-Download {
    param([string]$Url, [string]$Dest, [long]$MinBytes = 5000000)
    $part = "$Dest.part"
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        if ($attempt -gt 1) { Write-Host "    Retry $attempt..." -ForegroundColor Yellow }
        $curlArgs = @("-L", "--fail", "--progress-bar", "--retry", "2", "--retry-delay", "5", "-o", $part, $Url)
        & curl.exe @curlArgs
        if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -gt $MinBytes) {
            Move-Item -LiteralPath $part -Destination $Dest -Force
            return $true
        }
        if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -eq 0) {
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    return $false
}

$InstallerData = Join-Path $UsbRoot "installer_data"
$TmpDir = Join-Path $InstallerData "llamacpp-tmp"
New-Item -ItemType Directory -Force -Path $InstallerData | Out-Null
if (Test-Path -LiteralPath $TmpDir) { Remove-Item -LiteralPath $TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

Write-Host "[*] Installing llama.cpp $LlamaVersion ($Variant)" -ForegroundColor Cyan
Write-Host "    URL: $MainUrl" -ForegroundColor DarkGray
$Archive = Join-Path $InstallerData "llamacpp-$Variant.zip"
if (-not (Invoke-Download -Url $MainUrl -Dest $Archive)) {
    Write-Host "ERROR: llama.cpp download failed." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Extracting..." -ForegroundColor DarkGray
try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $TmpDir -Force
} catch {
    Write-Host "ERROR: could not extract llama.cpp archive: $_" -ForegroundColor Red
    Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
    exit 1
}

# Optional CUDA runtime DLLs (extracted separately, merged below)
$RuntimeDir = Join-Path $TmpDir "runtime"
if ($RuntimeUrl) {
    $RuntimeArchive = Join-Path $InstallerData "llamacpp-cudart.zip"
    if (Invoke-Download -Url $RuntimeUrl -Dest $RuntimeArchive) {
        try { Expand-Archive -LiteralPath $RuntimeArchive -DestinationPath $RuntimeDir -Force } catch { }
    }
    Remove-Item -LiteralPath $RuntimeArchive -Force -ErrorAction SilentlyContinue
}

# Locate llama-server.exe and copy its directory
$server = Get-ChildItem -LiteralPath $TmpDir -Recurse -Filter "llama-server.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $server) {
    Write-Host "ERROR: llama-server.exe not found in archive." -ForegroundColor Red
    Remove-Item -LiteralPath $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
    exit 1
}
$sourceDir = $server.Directory.FullName

if (Test-Path -LiteralPath $TargetDir) {
    Get-ChildItem -LiteralPath $TargetDir -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
} else {
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}
Write-Host "[*] Installing to $TargetDir (models and chats untouched)" -ForegroundColor DarkGray
Copy-Item -Path (Join-Path $sourceDir "*") -Destination $TargetDir -Recurse -Force
if (-not (Test-Path -LiteralPath $ServerExe) -and (Test-Path -LiteralPath (Join-Path $TargetDir "bin\llama-server.exe"))) {
    Copy-Item -Path (Join-Path $TargetDir "bin\*") -Destination $TargetDir -Recurse -Force
}

# CUDA runtime DLLs must sit next to llama-server.exe. Flatten them so a
# wrapper folder inside the cudart archive does not matter.
if (Test-Path -LiteralPath $RuntimeDir) {
    Get-ChildItem -LiteralPath $RuntimeDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $TargetDir -Force -ErrorAction SilentlyContinue
    }
}

$stamp = Join-Path $InstallerData "llamacpp-variant.txt"
Set-Content -LiteralPath $stamp -Value @(
    "LLAMACPP_VERSION=$LlamaVersion",
    "LLAMACPP_VARIANT=$Variant",
    "INSTALLED_AT=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
) -Force -Encoding ASCII

Remove-Item -LiteralPath $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
Write-Host "[OK] llama.cpp ready: $ServerExe ($Variant)" -ForegroundColor Green
exit 0
