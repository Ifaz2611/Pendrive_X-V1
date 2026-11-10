# ================================================================
# Pendrive_X - in-place engine / UI updater (Windows)
# ================================================================
# Refreshes Ollama, AnythingLLM and/or llama.cpp from versions.env.
# Models (models\*.gguf), Ollama data (ollama\data) and user chat
# databases (anythingllm_data\) are never touched.
#
# Usage:
#   powershell -NoProfile -File tools\update-engine.ps1 -UsbRoot E:\
#   powershell -NoProfile -File tools\update-engine.ps1 -UsbRoot E:\ -Engine llamacpp -Yes
# ================================================================
param(
    [string]$UsbRoot = "",
    [ValidateSet("all", "ollama", "anythingllm", "ui", "llamacpp", "llama.cpp", "llama")]
    [string]$Engine = "all",
    [switch]$Yes,
    [switch]$Help
)

$ErrorActionPreference = "Continue"

if ($Help) {
    Write-Host "Pendrive_X engine updater - Usage:" -ForegroundColor Cyan
    Write-Host "  powershell -NoProfile -File tools\update-engine.ps1 [-UsbRoot E:\] [-Engine all|ollama|anythingllm|llamacpp] [-Yes]" -ForegroundColor White
    exit 0
}

if (-not $UsbRoot) { $UsbRoot = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $UsbRoot)) {
    Write-Host "ERROR: USB directory not found: $UsbRoot" -ForegroundColor Red
    exit 1
}
$UsbRoot = (Resolve-Path -LiteralPath $UsbRoot).Path.TrimEnd('\')

# -----------------------------------------------------------------
# Pinned versions from versions.env
# -----------------------------------------------------------------
$cfg = @{}
$VersionsFile = Join-Path $UsbRoot "versions.env"
if (Test-Path -LiteralPath $VersionsFile) {
    Get-Content -LiteralPath $VersionsFile | ForEach-Object {
        if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
            $cfg[$Matches[1]] = $Matches[2]
        }
    }
}
$OllamaVersion = if ($cfg.ContainsKey("OLLAMA_VERSION")) { $cfg["OLLAMA_VERSION"] } else { "unknown" }
$AnythingLLMVersion = if ($cfg.ContainsKey("ANYTHINGLLM_VERSION")) { $cfg["ANYTHINGLLM_VERSION"] } else { "unknown" }
$LlamaVersion = if ($cfg.ContainsKey("LLAMACPP_VERSION")) { $cfg["LLAMACPP_VERSION"] } else { "unknown" }

$InstallerData = Join-Path $UsbRoot "installer_data"
$TmpRoot = Join-Path $InstallerData "update-tmp"
New-Item -ItemType Directory -Force -Path $InstallerData | Out-Null
if (Test-Path -LiteralPath $TmpRoot) {
    Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $TmpRoot | Out-Null

# -----------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------
$script:Errors = 0
$script:Updated = @()

function Write-Step($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Ok($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) {
    Write-Host "[FAIL] $msg" -ForegroundColor Red
    $script:Errors++
}

# -----------------------------------------------------------------
# Download / extract helpers
# -----------------------------------------------------------------
function Invoke-Download {
    param([string]$Url, [string]$Dest, [long]$MinBytes = 1000000)
    $part = "$Dest.part"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if ($attempt -gt 1) { Write-Host "    Retry $attempt..." -ForegroundColor Yellow }
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        $curlArgs = @("-L", "--fail", "--progress-bar", "--retry", "2", "--retry-delay", "5", "-o", $part, $Url)
        & curl.exe @curlArgs
        if ((Test-Path -LiteralPath $part) -and (Get-Item -LiteralPath $part).Length -gt $MinBytes) {
            Move-Item -LiteralPath $part -Destination $Dest -Force
            return $true
        }
    }
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    return $false
}

function Expand-ZipSafe {
    param([string]$Archive, [string]$Dest)
    try {
        New-Item -ItemType Directory -Force -Path $Dest | Out-Null
        Expand-Archive -LiteralPath $Archive -DestinationPath $Dest -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Host "    Extract failed: $_" -ForegroundColor DarkGray
        return $false
    }
}

# Stop only processes whose executables live on THIS USB drive.
function Stop-UsbProcesses {
    param([string]$Name)
    try {
        Get-Process -Name $Name -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.Path -and $_.Path.StartsWith($UsbRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    } catch { }
}

# -----------------------------------------------------------------
# Ollama (Windows zip)
# -----------------------------------------------------------------
function Update-Ollama {
    $url = if ($cfg.ContainsKey("OLLAMA_WIN_URL")) { $cfg["OLLAMA_WIN_URL"] } else { "" }
    if (-not $url) { Write-Fail "OLLAMA_WIN_URL is not set in versions.env"; return }

    $target = Join-Path $UsbRoot "ollama"
    $archive = Join-Path $TmpRoot "ollama-windows-amd64.zip"
    $extract = Join-Path $TmpRoot "ollama-win"

    Write-Step "Updating Ollama $OllamaVersion (Windows)..."
    if (-not (Invoke-Download -Url $url -Dest $archive -MinBytes 10000000)) {
        Write-Fail "Ollama download failed"; return
    }
    if (-not (Expand-ZipSafe -Archive $archive -Dest $extract)) {
        Write-Fail "Could not extract Ollama"; return
    }

    # Locate ollama.exe (archives sometimes have one nested folder).
    $exe = Get-ChildItem -LiteralPath $extract -Recurse -Filter "ollama.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) {
        Write-Fail "ollama.exe not found in archive"; return
    }
    $sourceDir = $exe.Directory.FullName

    New-Item -ItemType Directory -Force -Path $target | Out-Null
    # Preserve ollama\data (multi-GB model store); clear only engine files.
    Get-ChildItem -LiteralPath $target -Force | Where-Object { $_.Name -ne "data" } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -Path (Join-Path $sourceDir "*") -Destination $target -Recurse -Force

    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    $script:Updated += "Ollama $OllamaVersion"
    Write-Ok "Ollama updated (models in ollama\data preserved)"
}

# -----------------------------------------------------------------
# AnythingLLM (NSIS desktop installer)
# -----------------------------------------------------------------
function Update-AnythingLLM {
    $url = if ($cfg.ContainsKey("ANYTHINGLLM_WIN_URL")) { $cfg["ANYTHINGLLM_WIN_URL"] } else { "" }
    if (-not $url) { Write-Fail "ANYTHINGLLM_WIN_URL is not set in versions.env"; return }

    $target = Join-Path $UsbRoot "anythingllm"
    $installer = Join-Path $InstallerData "AnythingLLMDesktop.exe"
    $appExe = Join-Path $target "AnythingLLM.exe"

    Write-Step "Updating AnythingLLM $AnythingLLMVersion (Windows)..."

    if ((-not (Test-Path -LiteralPath $installer)) -or ((Get-Item -LiteralPath $installer).Length -lt 10000000)) {
        if (-not (Invoke-Download -Url $url -Dest $installer -MinBytes 10000000)) {
            Write-Fail "AnythingLLM download failed"; return
        }
    }

    Write-Host "    Installing silently to $target ..." -ForegroundColor DarkGray
    $silent = $false
    try {
        # NSIS: /S must be followed by /D=<path> as the last argument.
        Start-Process -FilePath $installer -ArgumentList @("/S", "/D=$target") -Wait
        $silent = $true
    } catch {
        $silent = $false
    }

    # Some NSIS wrappers spawn the real installer and exit; give it time.
    if ($silent -and -not (Test-Path -LiteralPath $appExe)) {
        $deadline = (Get-Date).AddSeconds(120)
        while (-not (Test-Path -LiteralPath $appExe) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
        }
    }

    if ($silent -and (Test-Path -LiteralPath $appExe)) {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        $script:Updated += "AnythingLLM $AnythingLLMVersion"
        Write-Ok "AnythingLLM updated (chats in anythingllm_data preserved)"
        return
    }

    # Fallback: the installer needs a human (some builds ignore /S).
    if ($Yes) {
        Write-Warn "Silent install did not create $appExe - manual install required."
        Write-Warn "Run: $installer  and choose '$target' as the install location."
        Write-Fail "AnythingLLM update incomplete"
        return
    }

    Write-Host ""
    Write-Host "  The AnythingLLM installer will open." -ForegroundColor Yellow
    Write-Host "  Install location: $target" -ForegroundColor White
    Write-Host "  Wait for it to finish, then close the installer." -ForegroundColor Yellow
    Write-Host ""
    try { Start-Process -FilePath $installer -Wait } catch { }
    if (Test-Path -LiteralPath $appExe) {
        Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
        $script:Updated += "AnythingLLM $AnythingLLMVersion"
        Write-Ok "AnythingLLM updated (chats in anythingllm_data preserved)"
    } else {
        Write-Fail "AnythingLLM.exe not found at $appExe"
    }
}

# -----------------------------------------------------------------
# llama.cpp (portable llama-server)
# -----------------------------------------------------------------
function Update-LlamaCpp {
    $variant = "auto"
    if ($cfg.ContainsKey("LLAMACPP_VARIANT")) { $variant = $cfg["LLAMACPP_VARIANT"] }
    if ($env:LLAMACPP_VARIANT) { $variant = $env:LLAMACPP_VARIANT }

    $stamp = Join-Path $InstallerData "llamacpp-variant.txt"
    if ($variant -eq "auto" -and (Test-Path -LiteralPath $stamp)) {
        $line = Get-Content -LiteralPath $stamp | Where-Object { $_ -match '^LLAMACPP_VARIANT=(.+)$' } | Select-Object -First 1
        if ($line) { $variant = ($line -split "=", 2)[1].Trim() }
    }

    $installer = Join-Path $UsbRoot "tools\install-llamacpp.ps1"
    if (-not (Test-Path -LiteralPath $installer)) {
        Write-Fail "tools\install-llamacpp.ps1 is missing"; return
    }

    Write-Step "Updating llama.cpp $LlamaVersion ($variant)..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -UsbRoot $UsbRoot -Variant $variant -Force
    if ($LASTEXITCODE -eq 0) {
        $script:Updated += "llama.cpp $LlamaVersion"
    } else {
        Write-Fail "llama.cpp update failed"
    }
}

# -----------------------------------------------------------------
# Main
# -----------------------------------------------------------------
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Pendrive_X - In-place engine updater" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  USB: $UsbRoot" -ForegroundColor DarkGray
Write-Host "  Models, Ollama data and AnythingLLM chats will NOT be modified." -ForegroundColor DarkGray
Write-Host ""

Write-Step "Stopping running processes from this USB..."
Stop-UsbProcesses -Name "ollama"
Stop-UsbProcesses -Name "llama-server"
Stop-UsbProcesses -Name "AnythingLLM"
Start-Sleep -Milliseconds 500

$engineKey = $Engine.ToLower()
switch ($engineKey) {
    "all" {
        # Refresh only components that are actually installed.
        if (Test-Path -LiteralPath (Join-Path $UsbRoot "ollama\ollama.exe")) {
            Update-Ollama
        } else {
            Write-Step "Ollama not installed - skipping"
        }
        if (Test-Path -LiteralPath (Join-Path $UsbRoot "anythingllm")) {
            Update-AnythingLLM
        } else {
            Write-Step "AnythingLLM not installed - skipping"
        }
        if ((Test-Path -LiteralPath (Join-Path $UsbRoot "llamacpp\llama-server.exe")) -or
            (Test-Path -LiteralPath (Join-Path $InstallerData "llamacpp-variant.txt"))) {
            Update-LlamaCpp
        } else {
            Write-Step "llama.cpp not installed - skipping"
        }
    }
    "ollama" { Update-Ollama }
    "anythingllm" { Update-AnythingLLM }
    "ui" { Update-AnythingLLM }
    "llamacpp" { Update-LlamaCpp }
    "llama.cpp" { Update-LlamaCpp }
    "llama" { Update-LlamaCpp }
    default {
        Write-Fail "Unknown -Engine '$Engine' (use all|ollama|anythingllm|llamacpp)"
    }
}

# Record what this updater touched.
$stampFile = Join-Path $InstallerData "engine-versions.txt"
try {
    Set-Content -LiteralPath $stampFile -Encoding ASCII -Force -Value @(
        "# Updated by tools/update-engine.ps1",
        "UPDATED_AT=$((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))",
        "OLLAMA_VERSION=$OllamaVersion",
        "ANYTHINGLLM_VERSION=$AnythingLLMVersion",
        "LLAMACPP_VERSION=$LlamaVersion"
    )
} catch { }

Remove-Item -LiteralPath $TmpRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Errors -gt 0) {
    Write-Host "Update finished with $($script:Errors) error(s)." -ForegroundColor Yellow
    exit 1
}
Write-Host "Update complete." -ForegroundColor Green
foreach ($item in $script:Updated) {
    Write-Host "  + $item" -ForegroundColor Green
}
exit 0
