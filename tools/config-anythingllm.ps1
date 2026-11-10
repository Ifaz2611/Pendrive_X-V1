# ================================================================
# Pendrive_X - configure AnythingLLM for the selected engine
# ================================================================
# Rewrites only the LLM provider keys in anythingllm_data\storage\.env
# and preserves unrelated user settings plus their custom token limit.
# Prints the effective token limit on stdout.
# ================================================================
param(
    [string]$UsbRoot = "",
    [Parameter(Mandatory = $true)][ValidateSet("ollama", "llamacpp")][string]$Engine,
    [Parameter(Mandatory = $true)][int]$Port,
    [string]$Model = "local",
    [switch]$ServerMode,
    [int]$LanPort = 8090
)

$ErrorActionPreference = "Continue"
if (-not $UsbRoot) { $UsbRoot = Split-Path -Parent $PSScriptRoot }
$UsbRoot = (Resolve-Path -LiteralPath $UsbRoot).Path.TrimEnd('\')

$storage = Join-Path $UsbRoot "anythingllm_data\storage"
$envFile = Join-Path $storage ".env"
New-Item -ItemType Directory -Force -Path $storage | Out-Null

$existing = @()
if (Test-Path -LiteralPath $envFile) {
    $existing = @(Get-Content -LiteralPath $envFile -ErrorAction SilentlyContinue)
}

$token = 4096
foreach ($line in $existing) {
    if ($line -match '^(?:OLLAMA_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT)=(\d+)\s*$') {
        $token = [int]$Matches[1]
        break
    }
}

$managed = '^(LLM_PROVIDER|OLLAMA_BASE_PATH|OLLAMA_MODEL_PREF|OLLAMA_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_BASE_PATH|GENERIC_OPEN_AI_MODEL_PREF|GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_MAX_TOKENS|GENERIC_OPEN_AI_API_KEY|EMBEDDING_ENGINE|VECTOR_DB)='
$kept = @($existing | Where-Object { $_ -notmatch $managed })

$new = @($kept)
if ($Engine -eq "llamacpp") {
    $new += "LLM_PROVIDER=generic-openai"
    $new += "GENERIC_OPEN_AI_BASE_PATH=http://127.0.0.1:$Port/v1"
    $new += "GENERIC_OPEN_AI_MODEL_PREF=$Model"
    $new += "GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=$token"
    $new += "GENERIC_OPEN_AI_MAX_TOKENS=$token"
    $new += "GENERIC_OPEN_AI_API_KEY=sk-no-key"
} else {
    $new += "LLM_PROVIDER=ollama"
    $new += "OLLAMA_BASE_PATH=http://127.0.0.1:$Port"
    $new += "OLLAMA_MODEL_PREF=$Model"
    $new += "OLLAMA_MODEL_TOKEN_LIMIT=$token"
}
$new += "EMBEDDING_ENGINE=native"
$new += "VECTOR_DB=lancedb"
if ($ServerMode) {
    # Desktop builds ignore these; headless/server builds honour them.
    $new += "HOST=0.0.0.0"
    $new += "SERVER_PORT=$LanPort"
}

# BOM-free UTF-8; AnythingLLM's dotenv loader should not have to strip a BOM.
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($envFile, [string[]]$new, $enc)
Write-Output $token
