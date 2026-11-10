#!/usr/bin/env bash
# ===================================================
#     PENDRIVE_X AI - Launcher (Linux)
# ===================================================
# Usage:
#   bash linux/start-linux.sh                  Start with settings from .env
#   bash linux/start-linux.sh --server         LAN mode + terminal QR code
#   bash linux/start-linux.sh --engine=llamacpp
#   bash linux/start-linux.sh --update-engine
# ===================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional positional USB directory (must be first).
if [[ -n "${1:-}" && -d "${1:-}" ]]; then
    USB_DIR="$(cd "$1" && pwd)"
    shift
elif [[ -f "$SCRIPT_DIR/../versions.env" || -d "$SCRIPT_DIR/../models" || -f "$SCRIPT_DIR/../start-windows.bat" ]]; then
    USB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    USB_DIR="$SCRIPT_DIR"
fi

# shellcheck source=../tools/common.sh
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server|--lan) SERVER_FLAG="1"; shift ;;
        --headless) SERVER_FLAG="1"; shift ;;
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
            echo "Usage: bash linux/start-linux.sh [--server|--lan] [--headless] [--with-ui]"
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
echo "[$(date)] Launcher Linux started — USB: $USB_DIR"

# ── In-place engine update mode
if [[ -n "$UPDATE_MODE" ]]; then
    echo "Updating engines/UI (models and chats preserved)..."
    [[ "$UPDATE_MODE" == "both" ]] && UPDATE_MODE="all"
    UPDATE_ARGS=("$USB_DIR" linux --engine "$UPDATE_MODE")
    [[ "$ASSUME_YES" == "true" ]] && UPDATE_ARGS+=(--yes)
    bash "$USB_DIR/tools/update-engine.sh" "${UPDATE_ARGS[@]}"
    exit $?
fi

# ── State for cleanup
OLLAMA_PID=""
LLAMA_PID=""
LAN_CHAT_PID=""
ANYTHINGLLM_PID=""
APPIMAGE_EXTRACTED=0

cleanup() {
    echo ""
    echo -e "${YELLOW}[SHUTDOWN]${NC} Shutting down AI Engine..."
    if [[ -n "$ANYTHINGLLM_PID" ]]; then kill "$ANYTHINGLLM_PID" 2>/dev/null || true; fi
    if [[ -n "$LAN_CHAT_PID" ]]; then kill "$LAN_CHAT_PID" 2>/dev/null || true; fi
    if [[ -n "$LLAMA_PID" ]]; then kill "$LLAMA_PID" 2>/dev/null || true; fi
    if [[ -n "$OLLAMA_PID" ]]; then kill "$OLLAMA_PID" 2>/dev/null || true; fi
    sleep 1
    px_kill_by_path "$USB_DIR/ollama/ollama"
    px_kill_by_path "$USB_DIR/llamacpp"
    px_kill_by_path "$USB_DIR/tools/lan-chat.py"
    px_kill_by_path "$USB_DIR/anythingllm"
    if (( APPIMAGE_EXTRACTED )); then
        for tmp in /tmp/.mount_Anything*; do
            [[ -d "$tmp" ]] && rm -rf "$tmp" 2>/dev/null || true
        done
    fi
    echo -e "${GREEN}AI Engine shut down. You may safely eject the USB.${NC}"
}
trap cleanup EXIT INT TERM HUP

# ── Header
echo -e "${CYAN}==================================================="
echo -e "     Launching PENDRIVE_X AI Engine from USB..."
echo -e "===================================================${NC}"
echo -e "${DGRAY}[CFG]${NC} Engine: ${CYAN}${INFERENCE_ENGINE}${NC}"

# ── Path virtualization (everything stays on USB)
export OLLAMA_MODELS="$USB_DIR/ollama/data"
export STORAGE_DIR="$USB_DIR/anythingllm_data"
export XDG_CONFIG_HOME="$STORAGE_DIR/config"
export XDG_DATA_HOME="$STORAGE_DIR/data"
export XDG_CACHE_HOME="$STORAGE_DIR/cache"
mkdir -p "$STORAGE_DIR" "$STORAGE_DIR/storage" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

OLLAMA_BIN="$USB_DIR/ollama/ollama"
LLAMA_SERVER="$USB_DIR/llamacpp/llama-server"
APPIMAGE="$USB_DIR/anythingllm/AnythingLLM.AppImage"

# ── Ensure the selected engine is installed (first run only)
if [[ "$INFERENCE_ENGINE" == "llamacpp" ]]; then
    if [[ ! -x "$LLAMA_SERVER" ]]; then
        echo -e "${YELLOW}[FIRST RUN]${NC} Downloading llama.cpp..."
        bash "$USB_DIR/tools/install-llamacpp.sh" "$USB_DIR" auto || {
            echo -e "${RED}ERROR:${NC} llama.cpp download failed."
            exit 1
        }
    fi
    if [[ ! -x "$LLAMA_SERVER" ]]; then
        echo -e "${RED}ERROR:${NC} llama-server not found at: $LLAMA_SERVER"
        echo "Please run install.sh first."
        exit 1
    fi
else
    if [[ ! -x "$OLLAMA_BIN" ]]; then
        echo -e "${RED}ERROR:${NC} Ollama binary not found at: $OLLAMA_BIN"
        echo "Please run install.sh first."
        exit 1
    fi
fi

if [[ ! -f "$APPIMAGE" && "${SERVER_MODE:-0}" != "1" ]]; then
    echo -e "${RED}ERROR:${NC} AnythingLLM AppImage not found at: $APPIMAGE"
    echo "Please run install.sh first."
    exit 1
fi
[[ -f "$APPIMAGE" ]] && chmod +x "$APPIMAGE" 2>/dev/null || true

# ── Resolve model
px_resolve_model "$USB_DIR" "$MODEL_OVERRIDE"
if [[ "$INFERENCE_ENGINE" == "llamacpp" && -z "$PX_MODEL_PATH" ]]; then
    echo -e "${RED}ERROR:${NC} No GGUF model found in $USB_DIR/models"
    echo "Run install.sh first to download a model."
    exit 1
fi

# ── Ports
PREFERRED_PORT="$OLLAMA_PORT"
[[ "$INFERENCE_ENGINE" == "llamacpp" ]] && PREFERRED_PORT="$LLAMACPP_PORT"
ENGINE_PORT=$(px_find_free_port "$PREFERRED_PORT")
BIND_HOST="127.0.0.1"
[[ "${SERVER_MODE:-0}" == "1" ]] && BIND_HOST="0.0.0.0"
export OLLAMA_HOST="${BIND_HOST}:${ENGINE_PORT}"
export OLLAMA_KEEP_ALIVE OLLAMA_NUM_PARALLEL
echo -e "${DGRAY}  Engine port: ${ENGINE_PORT} (bind ${BIND_HOST})${NC}"
echo -e "${DGRAY}  Model: ${PX_MODEL_LOCAL}${NC}"

# Normalise the mobile chat port before writing the AnythingLLM config
# (0 or invalid = pick a free port, same contract as the engine ports).
if ! [[ "$LAN_CHAT_PORT" =~ ^[0-9]+$ ]] || (( LAN_CHAT_PORT == 0 )); then
    LAN_CHAT_PORT=$(px_find_free_port 8090)
fi
export LAN_CHAT_PORT

# ── Hardware auto-tuning
px_detect_hardware "$USB_DIR" "$PX_MODEL_PATH"
echo -e "${DGRAY}  ${PENDRIVE_ACCEL_NOTE}${NC}"
echo -e "${DGRAY}  layers=${PENDRIVE_NGL} threads=${PENDRIVE_THREADS} ctx=${PENDRIVE_CTX}${NC}"

# ── Configure AnythingLLM
TOKEN_LIMIT=$(px_config_anythingllm "$USB_DIR" "$INFERENCE_ENGINE" "127.0.0.1" "$ENGINE_PORT" "$PX_MODEL_LOCAL")
[[ -z "$TOKEN_LIMIT" ]] && TOKEN_LIMIT="4096"
echo -e "${GREEN}  AnythingLLM: ${INFERENCE_ENGINE} @ ${ENGINE_PORT} (token_limit=${TOKEN_LIMIT})${NC}"

# ── Show installed models
MODELS_FILE="$USB_DIR/models/installed-models.txt"
if [[ -f "$MODELS_FILE" ]]; then
    echo ""
    echo "Installed models:"
    while IFS='|' read -r local_name display_name label _; do
        local_name="${local_name%$'\r'}"
        display_name="${display_name%$'\r'}"
        label="${label%$'\r'}"
        tag=""
        [[ "$label" == "UNCENSORED" ]] && tag="${RED}[UNCENSORED]${NC}"
        [[ "$label" == "CUSTOM" ]] && tag="${GREEN}[CUSTOM]${NC}"
        [[ -z "$tag" ]] && tag="${CYAN}[STANDARD]${NC}"
        echo -e "  - ${display_name} ${tag}"
    done < "$MODELS_FILE"
    echo ""
fi

# ── Start the engine
echo -e "${YELLOW}Starting ${INFERENCE_ENGINE} on ${BIND_HOST}:${ENGINE_PORT}...${NC}"
if [[ "$INFERENCE_ENGINE" == "llamacpp" ]]; then
    # shellcheck disable=SC2086
    "$LLAMA_SERVER" \
        -m "$PX_MODEL_PATH" \
        --host "$BIND_HOST" \
        --port "$ENGINE_PORT" \
        -ngl "$PENDRIVE_NGL" \
        -c "$PENDRIVE_CTX" \
        -t "$PENDRIVE_THREADS" \
        --alias "$PX_MODEL_LOCAL" \
        ${LLAMACPP_EXTRA_ARGS:-} >/dev/null 2>&1 &
    LLAMA_PID=$!
    renice -n -1 -p "$LLAMA_PID" &>/dev/null || true
    HEALTH_URL="http://127.0.0.1:${ENGINE_PORT}/health"
    MAX_WAIT=120
else
    "$OLLAMA_BIN" serve &>/dev/null &
    OLLAMA_PID=$!
    renice -n -1 -p "$OLLAMA_PID" &>/dev/null || true
    HEALTH_URL="http://127.0.0.1:${ENGINE_PORT}/api/tags"
    MAX_WAIT=30
fi

echo -en "${DGRAY}  Waiting for engine...${NC}"
READY=false
for (( i=0; i<MAX_WAIT; i++ )); do
    if curl -fsS "$HEALTH_URL" &>/dev/null; then
        echo -e "${GREEN} Ready!${NC}"
        READY=true
        break
    fi
    echo -n "."
    sleep 1
done
if ! $READY; then
    echo -e "${RED} Timeout!${NC}"
    echo -e "${RED}Engine failed to start on port ${ENGINE_PORT}.${NC}"
    exit 1
fi

# ── LAN / QR mode
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
    echo -e "${CYAN}===================================================${NC}"
    echo -e "${BOLD}  LAN / PHONE MODE${NC}"
    echo -e "${CYAN}===================================================${NC}"
    echo -e "  ${YELLOW}${LAN_URL}${NC}"
    echo -e "${DGRAY}  Engine API: http://${LAN_IP}:${ENGINE_PORT}${NC}"
    px_show_qr "$USB_DIR" "$LAN_URL"
fi

# ── Launch AnythingLLM (unless headless server mode)
if [[ "${SERVER_MODE:-0}" == "1" && "$WITH_UI" != "true" ]]; then
    echo -e "${DGRAY}  Headless mode - desktop UI skipped.${NC}"
elif [[ ! -f "$APPIMAGE" ]]; then
    echo -e "${YELLOW}  AnythingLLM AppImage not found - desktop UI skipped.${NC}"
else
    echo -e "${YELLOW}Starting AnythingLLM Interface...${NC}"
    FUSE_OK=false
    if command -v fusermount3 &>/dev/null || command -v fusermount &>/dev/null; then
        [[ -c /dev/fuse ]] && FUSE_OK=true
    fi

    ANYTHINGLLM_CACHE="$XDG_CONFIG_HOME/anythingllm-desktop"
    rm -rf "$ANYTHINGLLM_CACHE/GPUCache"    2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/Cache"       2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/Code Cache"  2>/dev/null || true
    rm -rf "$ANYTHINGLLM_CACHE/ShaderCache" 2>/dev/null || true

    launch_appimage() {
        "$APPIMAGE" \
            --user-data-dir="$STORAGE_DIR/anythingllm-desktop" \
            --no-sandbox \
            &>/dev/null &
        ANYTHINGLLM_PID=$!
    }

    if $FUSE_OK; then
        launch_appimage
        sleep 2
        if ! kill -0 "$ANYTHINGLLM_PID" 2>/dev/null; then
            echo -e "${YELLOW}  FUSE launch failed, switching to extract-and-run...${NC}"
            APPIMAGE_EXTRACTED=1
            APPIMAGE_EXTRACT_AND_RUN=1 launch_appimage
        fi
    else
        echo -e "${DGRAY}  FUSE not available, using extract-and-run mode...${NC}"
        APPIMAGE_EXTRACTED=1
        APPIMAGE_EXTRACT_AND_RUN=1 launch_appimage
    fi
fi

echo ""
echo -e "${CYAN}==================================================="
echo -e "   SYSTEM ONLINE: Your AI is running from USB!"
echo -e "===================================================${NC}"
echo ""
echo -e "  Engine:      ${BOLD}${INFERENCE_ENGINE}${NC} @ http://127.0.0.1:${ENGINE_PORT}"
echo -e "  Model:       ${BOLD}${PX_MODEL_LOCAL}${NC} (token_limit=${TOKEN_LIMIT})"
[[ -n "$LAN_URL" ]] && echo -e "  Phone/LAN:   ${CYAN}${LAN_URL}${NC}"
echo ""
echo -e "${YELLOW}Keep this terminal open to keep the AI engine running!${NC}"
echo ""
echo -e "${RED}Press Enter to SHUT DOWN the AI safely...${NC}"
read -r _ || true

# Cleanup runs automatically via EXIT trap
