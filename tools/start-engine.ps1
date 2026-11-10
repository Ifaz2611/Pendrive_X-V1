# ================================================================
# Pendrive_X - start an inference engine (Windows)
# ================================================================
# Starts Ollama or llama-server with portable paths and prints the
# process id on stdout. Used by start-windows.bat.
#
# Usage:
#   powershell -NoProfile -File tools\start-engine.ps1 -Engine llamacpp `
#       -UsbRoot E:\ -ModelPath E:\models\x.gguf -Port 8081 -Ngl 999
# ================================================================
param(
    [Parameter(Mandatory = $true)][ValidateSet("ollama", "llamacpp")][string]$Engine,
    [string]$UsbRoot = "",
    [string]$ModelPath = "",
    [string]$ModelAlias = "local",
    [int]$Port = 11434,
    [string]$BindHost = "127.0.0.1",
    [int]$Ngl = 0,
    [int]$Ctx = 4096,
    [int]$Threads = 4,
    [string]$ExtraArgs = "",
    [string]$KeepAlive = "30m",
    [int]$NumParallel = 1,
    [string]$LogFile = ""
)

$ErrorActionPreference = "Stop"

if (-not $UsbRoot) { $UsbRoot = Split-Path -Parent $PSScriptRoot }
$UsbRoot = (Resolve-Path -LiteralPath $UsbRoot).Path.TrimEnd('\')

# Split a command-line fragment into arguments, honouring "quotes".
function Split-Arguments {
    param([string]$Text)
    $result = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Text)) { return $result }
    $current = New-Object System.Text.StringBuilder
    $inQuotes = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '"') {
            $inQuotes = -not $inQuotes
        } elseif ([char]::IsWhiteSpace($ch) -and -not $inQuotes) {
            if ($current.Length -gt 0) {
                $result.Add($current.ToString())
                [void]$current.Clear()
            }
        } else {
            [void]$current.Append($ch)
        }
    }
    if ($current.Length -gt 0) { $result.Add($current.ToString()) }
    return $result
}

# Start-Process joins -ArgumentList with spaces without quoting, so wrap
# values that contain whitespace (USB paths often do).
function Format-Argument {
    param([string]$Value)
    if ($Value -match '[\s"]' -or $Value -eq "") {
        return '"' + ($Value -replace '"', '\"') + '"'
    }
    return $Value
}

$arguments = @()
if ($Engine -eq "ollama") {
    $exe = Join-Path $UsbRoot "ollama\ollama.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Error "Ollama not found: $exe"
        exit 2
    }
    # Point Ollama at the USB model store and bind to the requested host.
    $env:OLLAMA_MODELS = Join-Path $UsbRoot "ollama\data"
    $env:OLLAMA_HOST = "${BindHost}:${Port}"
    $env:OLLAMA_KEEP_ALIVE = $KeepAlive
    $env:OLLAMA_NUM_PARALLEL = "$NumParallel"
    New-Item -ItemType Directory -Force -Path $env:OLLAMA_MODELS | Out-Null
    $arguments = @("serve")
} else {
    $exe = Join-Path $UsbRoot "llamacpp\llama-server.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        Write-Error "llama-server not found: $exe"
        exit 2
    }
    if (-not $ModelPath -or -not (Test-Path -LiteralPath $ModelPath)) {
        Write-Error "GGUF model not found: $ModelPath"
        exit 2
    }
    $arguments = @(
        "-m", (Format-Argument $ModelPath),
        "--host", $BindHost,
        "--port", "$Port",
        "-ngl", "$Ngl",
        "-c", "$Ctx",
        "-t", "$Threads",
        "--alias", (Format-Argument $ModelAlias)
    )
    if (-not [string]::IsNullOrWhiteSpace($ExtraArgs)) {
        foreach ($extra in (Split-Arguments $ExtraArgs)) { $arguments += $extra }
    }
}

$startArgs = @{
    FilePath = $exe
    ArgumentList = $arguments
    WorkingDirectory = $UsbRoot
    WindowStyle = "Hidden"
    PassThru = $true
}

if ($LogFile) {
    $logDir = Split-Path -Parent $LogFile
    if ($logDir) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $startArgs.RedirectStandardOutput = "$LogFile.out.log"
    $startArgs.RedirectStandardError = "$LogFile.err.log"
}

try {
    $proc = Start-Process @startArgs
    Write-Output $proc.Id
    exit 0
} catch {
    Write-Error "Could not start ${Engine}: $_"
    exit 3
}
