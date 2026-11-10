#!/bin/bash
# ================================================================
# PENDRIVE_X AI - MAC LAUNCHER
# ================================================================
# Just double-click this file on any Mac to start your portable AI.
# Everything runs from the USB drive. Nothing is installed on the Mac.
#
# Usage:
#   ./start-mac.command                 Start with settings from .env
#   ./start-mac.command --server        LAN mode + terminal QR code
#   ./start-mac.command --engine=llamacpp
#   ./start-mac.command --update-engine
# ================================================================

set -uo pipefail

# ── Locate the USB root (allow: ./start-mac.command /Volumes/USB)
cd "$(dirname "$0")" || exit 1
USB_DIR="$(pwd)"
if [[ -n "${1:-}" && -d "${1:-}" ]]; then
    USB_DIR="$(cd "$1" && pwd)"
    shift
fi

# ── Shared helpers (config, hardware, AnythingLLM, LAN, QR)
# shellcheck source=tools/common.sh
source "$USB_DIR/tools/common.sh" 2>/dev/null || {
    echo "ERROR: tools/common.sh is missing from the USB drive."
    exit 1
}

px_load_config "$USB_DIR"

# ── CLI flags
ENGINE_OVERRIDE=""
MODEL_OVERRIDE=""
SERVER_FLAG=""
UPDATE_MODE=""
ASSUME_YES="false"
WITH_UI="false"
HEADLESS="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server|--lan) SERVER_FLAG="1"; shift ;;
        --headless) SERVER_FLAG="1"; HEADLESS="true"; shift ;;
        --with-ui) WITH_UI="true"; shift ;;
        --update-engine) UPDATE_MODE="all"; shift ;;
        --update-engine=*) UPDATE_MODE="${1#--update-engine=}"; shift ;;
        --update) UPDATE_MODE="all"; shift ;;
        --engine) ENGINE_OVERRIDE="${2:-}"; shift 2 ;;
        --engine=*) ENGINE_OVERRIDE="${1#--engine=}"; shift ;;
        --model) MODEL_OVERRIDE="${2:-}"; shift 2 ;;
        --model=*) MODEL_OVERRIDE="${1#--model=}"; shift ;;
        --yes|-y) ASSUME_YES="true"; shift ;;
        --help|-h)
            echo "Usage: ./start-mac.command [--server|--lan] [--headless] [--with-ui]"
            echo "       [--engine=ollama|llamacpp] [--model=NAME] [--update-engine] [--yes]"
            exit 0
            ;;
        *) shift ;;
    esac
done

if [[ -n "$ENGINE_OVERRIDE" ]]; then
    case "$(printf '%s' "$ENGINE_OVERRIDE" | tr '[:upper:]' '[:lower:]')" in
        llamacpp|llama.cpp|llama-cpp) INFERENCE_ENGINE="llamacpp" ;;
        *) INFERENCE_ENGINE="ollama" ;;
    esac
fi
export INFERENCE_ENGINE
[[ -n "$SERVER_FLAG" ]] && SERVER_MODE="1"
export SERVER_MODE

# ── Logging
LOG_DIR="$USB_DIR/anythingllm_data/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/launcher-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date)] Launcher macOS started — USB: $USB_DIR"

# ── In-place engine update mode
if [[ -n "$UPDATE_MODE" ]]; then
    echo "Updating engines/UI (models and chats preserved)..."
    [[ "$UPDATE_MODE" == "both" ]] && UPDATE_MODE="all"
    UPDATE_ARGS=("$USB_DIR" mac --engine "$UPDATE_MODE")
    [[ "$ASSUME_YES" == "true" ]] && UPDATE_ARGS+=(--yes)
    bash "$USB_DIR/tools/update-engine.sh" "${UPDATE_ARGS[@]}"
    exit $?
fi

# ── State for cleanup
OLLAMA_PID=""
LLAMA_PID=""
LAN_CHAT_PID=""
ANYTHINGLLM_PID=""

cleanup() {
    echo ""
    echo -e "${YELLOW}[SHUTDOWN]${NC} Shutting down AI Engine..."
    if [[ -n "$ANYTHINGLLM_PID" ]]; then kill "$ANYTHINGLLM_PID" 2>/dev/null || true; fi
    if [[ -n "$LAN_CHAT_PID" ]]; then kill "$LAN_CHAT_PID" 2>/dev/null || true; fi
    if [[ -n "$LLAMA_PID" ]]; then kill "$LLAMA_PID" 2>/dev/null || true; fi
    if [[ -n "$OLLAMA_PID" ]]; then kill "$OLLAMA_PID" 2>/dev/null || true; fi
    sleep 1
    px_kill_by_path "$USB_DIR/ollama_mac"
    px_kill_by_path "$USB_DIR/llamacpp"
    px_kill_by_path "$USB_DIR/tools/lan-chat.py"
    echo -e "${GREEN}[EXITO]${NC} AI shut down. You may safely eject the USB."
}
trap cleanup EXIT INT TERM HUP

echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Launching PENDRIVE_X Engine for Mac...${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${DGRAY}[CFG]${NC} Engine: ${CYAN}${INFERENCE_ENGINE}${NC}"

MAC_OLLAMA_DIR="$USB_DIR/ollama_mac"
DATA_DIR="$USB_DIR/ollama/data"
MODELS_DIR="$USB_DIR/models"
STORAGE_DIR="$USB_DIR/anythingllm_data"
OLLAMA_BIN=""
LLAMA_SERVER="$USB_DIR/llamacpp/llama-server"

# ═══════════════════════════════════════════════════════════════
# STEP 1: Ensure the selected engine exists (first run only)
# ═══════════════════════════════════════════════════════════════
echo -e "${DGRAY}[STEP 1/7]${NC} Checking ${INFERENCE_ENGINE} engine on USB..."

if [[ "$INFERENCE_ENGINE" == "llamacpp" ]]; then
    if [[ ! -x "$LLAMA_SERVER" ]]; then
        echo -e "${YELLOW}[FIRST RUN]${NC} Downloading llama.cpp (Metal)..."
        bash "$USB_DIR/tools/install-llamacpp.sh" "$USB_DIR" auto || {
            echo -e "${RED}[ERROR]${NC} llama.cpp download failed."
            exit 1
        }
    fi
    if [[ ! -x "$LLAMA_SERVER" ]]; then
        echo -e "${RED}[ERROR]${NC} llama-server not found at $LLAMA_SERVER"
        exit 1
    fi
    echo -e "${GREEN}[✓]${NC} llama.cpp engine ready (Metal)"
else
    OLLAMA_MAC_URL_EFFECTIVE="${OLLAMA_MAC_URL:-https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.zip}"
    if [[ ! -d "$MAC_OLLAMA_DIR/Ollama.app" && ! -f "$MAC_OLLAMA_DIR/ollama" ]]; then
        echo -e "${YELLOW}[FIRST RUN]${NC} Downloading the AI Engine for macOS..."
        echo -e "${DGRAY}→ Fetching from official Ollama release channel...${NC}"
        mkdir -p "$MAC_OLLAMA_DIR"
        curl -fL --progress-bar --retry 2 --retry-delay 5 \
            "$OLLAMA_MAC_URL_EFFECTIVE" \
            -o "$MAC_OLLAMA_DIR/ollama-darwin.zip" || true
        echo -e "${DGRAY}→ Extracting engine binaries...${NC}"
        unzip -o -q "$MAC_OLLAMA_DIR/ollama-darwin.zip" -d "$MAC_OLLAMA_DIR/" 2>/dev/null || true
        rm -f "$MAC_OLLAMA_DIR/ollama-darwin.zip"
        if [[ -f "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama" ]]; then
            chmod +x "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama"
        elif [[ -f "$MAC_OLLAMA_DIR/ollama" ]]; then
            chmod +x "$MAC_OLLAMA_DIR/ollama"
        fi
    fi
    if [[ -f "$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama" ]]; then
        OLLAMA_BIN="$MAC_OLLAMA_DIR/Ollama.app/Contents/MacOS/Ollama"
    elif [[ -f "$MAC_OLLAMA_DIR/ollama" ]]; then
        OLLAMA_BIN="$MAC_OLLAMA_DIR/ollama"
    else
        echo -e "${RED}[ERROR]${NC} Could not find the Ollama binary on the USB drive!"
        exit 1
    fi
    echo -e "${GREEN}[✓]${NC} Ollama engine ready"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2: Ensure AnythingLLM is on the USB (first run only)
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${DGRAY}[STEP 2/7]${NC} Checking AnythingLLM Interface on USB..."
if [ ! -d "$USB_DIR/anythingllm_mac/AnythingLLM.app" ]; then
    echo -e "${YELLOW}[FIRST RUN]${NC} Downloading AnythingLLM directly to USB..."
    echo -e "${DGRAY}→ NO installation on the Mac! Everything stays on the drive.${NC}"
    mkdir -p "$USB_DIR/anythingllm_mac"
    ARCH=$(uname -m 2>/dev/null || echo "arm64")
    DEFAULT_DMG_URL="https://cdn.anythingllm.com/latest/AnythingLLMDesktop-Silicon.dmg"
    if [[ "$ARCH" == "x86_64" ]]; then
        DEFAULT_DMG_URL="https://cdn.anythingllm.com/latest/AnythingLLMDesktop.dmg"
    fi
    ANYTHINGLLM_MAC_URL_EFFECTIVE="${ANYTHINGLLM_MAC_URL:-$DEFAULT_DMG_URL}"
    curl -fL --progress-bar --retry 2 --retry-delay 5 \
        "$ANYTHINGLLM_MAC_URL_EFFECTIVE" \
        -o "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg" || true

    MOUNT_OUTPUT=$(hdiutil attach -nobrowse "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg" 2>&1 || true)
    DEV_NODE=$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/dev/disk[0-9][^[:space:]]*' | head -1)
    MOUNT_DIR=$(printf '%s\n' "$MOUNT_OUTPUT" | grep -o '/Volumes/[^[:space:]]*' | tail -1)
    if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR/AnythingLLM.app" ]]; then
        echo -e "${RED}[ERROR]${NC} Could not mount the AnythingLLM DMG."
        [[ -n "$DEV_NODE" ]] && hdiutil detach "$DEV_NODE" 2>/dev/null || true
        rm -f "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg"
        exit 1
    fi
    cp -R "$MOUNT_DIR/AnythingLLM.app" "$USB_DIR/anythingllm_mac/"
    [[ -n "$DEV_NODE" ]] && hdiutil detach "$DEV_NODE" 2>/dev/null || true
    rm -f "$USB_DIR/anythingllm_mac/AnythingLLM_Installer.dmg"
    xattr -rc "$USB_DIR/anythingllm_mac/AnythingLLM.app" 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} AnythingLLM extracted and ready!"
else
    echo -e "${GREEN}[✓]${NC} AnythingLLM Interface already present on USB"
fi

# ═══════════════════════════════════════════════════════════════
# STEP 3: Resolve model + portable runtime paths
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${DGRAY}[STEP 3/7]${NC} Configuring portable runtime paths..."
px_resolve_model "$USB_DIR" "$MODEL_OVERRIDE"

if [[ "$INFERENCE_ENGINE" == "llamacpp" && -z "$PX_MODEL_PATH" ]]; then
    echo -e "${RED}[ERROR]${NC} No GGUF model found in $MODELS_DIR"
    echo "Run install.sh first to download a model."
    exit 1
fi

export OLLAMA_MODELS="$DATA_DIR"
mkdir -p "$STORAGE_DIR/storage" "$DATA_DIR"

PREFERRED_PORT="$OLLAMA_PORT"
[[ "$INFERENCE_ENGINE" == "llamacpp" ]] && PREFERRED_PORT="$LLAMACPP_PORT"
ENGINE_PORT=$(px_find_free_port "$PREFERRED_PORT")
BIND_HOST="127.0.0.1"
[[ "${SERVER_MODE:-0}" == "1" ]] && BIND_HOST="0.0.0.0"
export OLLAMA_HOST="${BIND_HOST}:${ENGINE_PORT}"
export OLLAMA_KEEP_ALIVE OLLAMA_NUM_PARALLEL

echo -e "${GREEN}[✓]${NC} Engine port: ${CYAN}${ENGINE_PORT}${NC} (bind ${BIND_HOST})"
echo -e "${GREEN}[✓]${NC} Model: ${CYAN}${PX_MODEL_LOCAL}${NC}"

# Normalise the mobile chat port before writing the AnythingLLM config
# (0 or invalid = pick a free port, same contract as the engine ports).
if ! [[ "$LAN_CHAT_PORT" =~ ^[0-9]+$ ]] || (( LAN_CHAT_PORT == 0 )); then
    LAN_CHAT_PORT=$(px_find_free_port 8090)
fi
export LAN_CHAT_PORT

# XDG overrides for Electron/AnythingLLM
export XDG_CONFIG_HOME="$STORAGE_DIR/config"
export XDG_DATA_HOME="$STORAGE_DIR/data"
export XDG_CACHE_HOME="$STORAGE_DIR/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

# ═══════════════════════════════════════════════════════════════
# STEP 4: Hardware auto-tuning
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${DGRAY}[STEP 4/7]${NC} Detecting hardware acceleration..."
px_detect_hardware "$USB_DIR" "$PX_MODEL_PATH"
echo -e "${GREEN}[✓]${NC} ${PENDRIVE_ACCEL_NOTE}"
echo -e "${DGRAY}     layers=${PENDRIVE_NGL} threads=${PENDRIVE_THREADS} ctx=${PENDRIVE_CTX}${NC}"

# ═══════════════════════════════════════════════════════════════
# STEP 5: Configure AnythingLLM
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${DGRAY}[STEP 5/7]${NC} Validating AnythingLLM configuration..."
TOKEN_LIMIT=$(px_config_anythingllm "$USB_DIR" "$INFERENCE_ENGINE" "127.0.0.1" "$ENGINE_PORT" "$PX_MODEL_LOCAL")
[[ -z "$TOKEN_LIMIT" ]] && TOKEN_LIMIT="4096"
echo -e "${GREEN}[✓]${NC} Configured: ${CYAN}${PX_MODEL_LOCAL}${NC} via ${INFERENCE_ENGINE} @ ${ENGINE_PORT} (token_limit=${TOKEN_LIMIT})"

# ═══════════════════════════════════════════════════════════════
# STEP 6: Start the inference engine
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${DGRAY}[STEP 6/7]${NC} Starting ${INFERENCE_ENGINE} from USB..."
if [[ "$INFERENCE_ENGINE" == "llamacpp" ]]; then
    MMPROJ_ARG=()
    if [[ -n "$PX_MMPROJ_PATH" && -f "$PX_MMPROJ_PATH" ]]; then
        MMPROJ_ARG=(--mmproj "$PX_MMPROJ_PATH")
        echo -e "${DGRAY}  Vision projector: ${PX_MMPROJ_FILE}${NC}"
    fi
    # shellcheck disable=SC2086
    "$LLAMA_SERVER" \
        -m "$PX_MODEL_PATH" \
        "${MMPROJ_ARG[@]}" \
        --host "$BIND_HOST" \
        --port "$ENGINE_PORT" \
        -ngl "$PENDRIVE_NGL" \
        -c "$PENDRIVE_CTX" \
        -t "$PENDRIVE_THREADS" \
        --alias "$PX_MODEL_LOCAL" \
        ${LLAMACPP_EXTRA_ARGS:-} >/dev/null 2>&1 &
    LLAMA_PID=$!
    renice -n -1 -p "$LLAMA_PID" 2>/dev/null || true
    HEALTH_URL="http://127.0.0.1:${ENGINE_PORT}/health"
    MAX_WAIT=120
else
    "$OLLAMA_BIN" serve >/dev/null 2>&1 &
    OLLAMA_PID=$!
    renice -n -1 -p "$OLLAMA_PID" 2>/dev/null || true
    HEALTH_URL="http://127.0.0.1:${ENGINE_PORT}/api/tags"
    MAX_WAIT=30
fi

echo -e "${DGRAY}→ Waiting for engine${NC}"
READY=false
for (( i=0; i<MAX_WAIT; i++ )); do
    if curl -fsS "$HEALTH_URL" >/dev/null 2>&1; then
        echo -e " ${GREEN}[OK]${NC} ${BOLD}Engine ready.${NC}"
        READY=true
        break
    fi
    printf "."
    sleep 1
done

if ! $READY; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Engine failed to start on port $ENGINE_PORT within ${MAX_WAIT}s."
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# STEP 7: LAN mode, then launch the desktop UI
# ═══════════════════════════════════════════════════════════════
LAN_URL=""
if [[ "${SERVER_MODE:-0}" == "1" ]]; then
    LAN_IP=$(px_lan_ip)
    if [[ "$INFERENCE_ENGINE" == "llamacpp" ]]; then
        LAN_URL="http://${LAN_IP}:${ENGINE_PORT}/"
    elif command -v python3 >/dev/null 2>&1 && [[ -f "$USB_DIR/tools/lan-chat.py" ]]; then
        python3 "$USB_DIR/tools/lan-chat.py" \
            --port "$LAN_CHAT_PORT" \
            --ollama "http://127.0.0.1:${ENGINE_PORT}" \
            --model "$PX_MODEL_LOCAL" \
            >>"$LOG_DIR/lan-chat.log" 2>&1 &
        LAN_CHAT_PID=$!
        LAN_URL="http://${LAN_IP}:${LAN_CHAT_PORT}/"
    else
        LAN_URL="http://${LAN_IP}:${ENGINE_PORT}/"
    fi

    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}LAN / PHONE MODE${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "  ${YELLOW}${LAN_URL}${NC}"
    echo -e "${DGRAY}  Engine API: http://${LAN_IP}:${ENGINE_PORT}${NC}"
    px_show_qr "$USB_DIR" "$LAN_URL"
fi

if [[ "${SERVER_MODE:-0}" == "1" && "$WITH_UI" != "true" ]]; then
    echo -e "${DGRAY}[STEP 7/7]${NC} Headless mode - desktop UI skipped."
else
    echo ""
    echo -e "${DGRAY}[STEP 7/7]${NC} Launching AI Interface from USB..."
    xattr -rc "$USB_DIR/anythingllm_mac/AnythingLLM.app" 2>/dev/null || true
    xattr -rc "$MAC_OLLAMA_DIR" 2>/dev/null || true

    ANYTHINGLLM_CACHE="$XDG_CONFIG_HOME/anythingllm-desktop"
    rm -rf "$ANYTHINGLLM_CACHE/GPUCache" 2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/Cache" 2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/Code Cache" 2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/ShaderCache" 2>/dev/null || true

    APP_BIN="$USB_DIR/anythingllm_mac/AnythingLLM.app/Contents/MacOS/AnythingLLM"
    if [[ -x "$APP_BIN" ]]; then
        "$APP_BIN" --user-data-dir="$STORAGE_DIR" >/dev/null 2>&1 &
        ANYTHINGLLM_PID=$!
    else
        open -a "$USB_DIR/anythingllm_mac/AnythingLLM.app" --args --user-data-dir="$STORAGE_DIR" >/dev/null 2>&1 || true
    fi
    echo -e "${GREEN}[✓]${NC} Interface launched"
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN} SYSTEM ONLINE: Your AI is running from USB!${NC}  ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
echo -e "  Engine:     ${BOLD}${INFERENCE_ENGINE}${NC} @ http://127.0.0.1:${ENGINE_PORT}"
echo -e "  Model:      ${BOLD}${PX_MODEL_LOCAL}${NC} (token_limit=${TOKEN_LIMIT})"
[[ -n "$LAN_URL" ]] && echo -e "  Phone/LAN:  ${CYAN}${LAN_URL}${NC}"
echo ""
echo -e "${YELLOW}Keep this terminal open while you chat.${NC}"
echo -e "${DGRAY}────────────────────────────────────────────────────${NC}"
echo -e "  Press ${BOLD}[ENTER]${NC} to shut down the AI safely."
read -r _ || true

# Cleanup runs automatically via EXIT trap
