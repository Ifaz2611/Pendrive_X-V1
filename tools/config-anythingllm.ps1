# ================================================================
# Pendrive_X - configure AnythingLLM for the selected engine
# ================================================================
# Rewrites LLM and Embedding provider keys in anythingllm_data\storage\.env
# and preserves unrelated user settings plus their custom token limit.
# Configures local Ollama embedding endpoint for local RAG.
# Prints the effective token limit on stdout.
# ================================================================
param(
    [string]$UsbRoot = "",
    [Parameter(Mandatory = $true)][ValidateSet("ollama", "llamacpp")][string]$Engine,
    [Parameter(Mandatory = $true)][int]$Port,
    [string]$Model = "local",
    [string]$EmbeddingModel = "",
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

# Resolve embedding model preference for local RAG
$embPref = $EmbeddingModel
if (-not $embPref) {
    $installedFile = Join-Path $UsbRoot "models\installed-models.txt"
    if (Test-Path -LiteralPath $installedFile) {
        foreach ($line in (Get-Content -LiteralPath $installedFile -ErrorAction SilentlyContinue)) {
            $parts = $line.Split('|')
            if ($parts.Count -gt 2 -and ($parts[2] -eq "EMBEDDING" -or $parts[0] -match "embed|bge")) {
                $embPref = $parts[0].Trim()
                break
            }
        }
    }
}
if (-not $embPref) {
    $rootEnv = Join-Path $UsbRoot ".env"
    if (Test-Path -LiteralPath $rootEnv) {
        foreach ($line in (Get-Content -LiteralPath $rootEnv -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*EMBEDDING_MODEL\s*=\s*(.+)$') {
                $embPref = $Matches[1].Trim()
                break
            }
        }
    }
}
if (-not $embPref) { $embPref = "nomic-embed-local" }

$managed = '^(LLM_PROVIDER|OLLAMA_BASE_PATH|OLLAMA_MODEL_PREF|OLLAMA_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_BASE_PATH|GENERIC_OPEN_AI_MODEL_PREF|GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_MAX_TOKENS|GENERIC_OPEN_AI_API_KEY|EMBEDDING_ENGINE|EMBEDDING_BASE_PATH|EMBEDDING_MODEL_PREF|EMBEDDING_MODEL_MAX_CHUNK_LENGTH|VECTOR_DB|HOST|SERVER_PORT)='
$kept = @($existing | Where-Object { $_ -notmatch $managed })

$new = @($kept)
if ($Engine -eq "llamacpp") {
    $new += "LLM_PROVIDER=generic-openai"
    $new += "GENERIC_OPEN_AI_BASE_PATH=http://127.0.0.1:$Port/v1"
    $new += "GENERIC_OPEN_AI_MODEL_PREF=$Model"
    $new += "GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=$token"
    $new += "GENERIC_OPEN_AI_MAX_TOKENS=$token"
    $new += "GENERIC_OPEN_AI_API_KEY=sk-no-key"
    $new += "EMBEDDING_ENGINE=native"
    $new += "VECTOR_DB=lancedb"
} else {
    $new += "LLM_PROVIDER=ollama"
    $new += "OLLAMA_BASE_PATH=http://127.0.0.1:$Port"
    $new += "OLLAMA_MODEL_PREF=$Model"
    $new += "OLLAMA_MODEL_TOKEN_LIMIT=$token"
    $new += "EMBEDDING_ENGINE=ollama"
    $new += "EMBEDDING_BASE_PATH=http://127.0.0.1:$Port"
    $new += "EMBEDDING_MODEL_PREF=$embPref"
    $new += "EMBEDDING_MODEL_MAX_CHUNK_LENGTH=8192"
    $new += "VECTOR_DB=lancedb"
}

if ($ServerMode) {
    # Desktop builds ignore these; headless/server builds honour them.
    $new += "HOST=0.0.0.0"
    $new += "SERVER_PORT=$LanPort"
}

# BOM-free UTF-8; AnythingLLM's dotenv loader should not have to strip a BOM.
$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($envFile, [string[]]$new, $enc)
Write-Output $token
