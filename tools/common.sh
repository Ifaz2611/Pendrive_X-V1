#!/usr/bin/env bash
# ================================================================
# Pendrive_X - shared helpers for macOS / Linux launchers
# ================================================================
# Sourced by start-mac.command and linux/start-linux.sh.
# Keeps configuration parsing, hardware tuning, AnythingLLM env
# patching, LAN URL detection and terminal QR rendering in one place.
# ================================================================

# Guard against double-sourcing
[[ -n "${PX_COMMON_LOADED:-}" ]] && return 0
PX_COMMON_LOADED=1

# ── Colours (callers may override) ──────────────────────────────
: "${RED:=\033[1;91m}"
: "${GREEN:=\033[1;92m}"
: "${YELLOW:=\033[1;93m}"
: "${CYAN:=\033[1;96m}"
: "${MAGENTA:=\033[1;95m}"
: "${DGRAY:=\033[2;90m}"
: "${BOLD:=\033[1m}"
: "${NC:=\033[0m}"

# ── Defaults (overridden by <USB>/.env) ─────────────────────────
px_load_config() {
    local usb="$1"
    export INFERENCE_ENGINE="${INFERENCE_ENGINE:-ollama}"
    export AUTO_TUNE="${AUTO_TUNE:-1}"
    export SERVER_MODE="${SERVER_MODE:-0}"
    export OLLAMA_PORT="${OLLAMA_PORT:-0}"
    export LLAMACPP_PORT="${LLAMACPP_PORT:-0}"
    export LAN_CHAT_PORT="${LAN_CHAT_PORT:-8090}"
    export LLAMACPP_MODEL="${LLAMACPP_MODEL:-}"
    export LLAMACPP_NGL="${LLAMACPP_NGL:-auto}"
    export LLAMACPP_THREADS="${LLAMACPP_THREADS:-auto}"
    export LLAMACPP_CTX="${LLAMACPP_CTX:-auto}"
    export LLAMACPP_EXTRA_ARGS="${LLAMACPP_EXTRA_ARGS:-}"
    export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-30m}"
    export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"

    local env_file="$usb/.env"
    [[ -f "$env_file" ]] || return 0

    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        # Trim surrounding whitespace
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        # Strip optional quotes
        if [[ "$val" == \"*\" && "$val" == *\" ]]; then val="${val:1:${#val}-2}"; fi
        if [[ "$val" == \'*\' && "$val" == *\' ]]; then val="${val:1:${#val}-2}"; fi
        # Only export known Pendrive_X keys (avoid clobbering PATH, HOME, etc.)
        case "$key" in
            INFERENCE_ENGINE|AUTO_TUNE|SERVER_MODE|OLLAMA_PORT|LLAMACPP_PORT|LAN_CHAT_PORT|\
            LLAMACPP_MODEL|LLAMACPP_NGL|LLAMACPP_THREADS|LLAMACPP_CTX|LLAMACPP_EXTRA_ARGS|\
            OLLAMA_KEEP_ALIVE|OLLAMA_NUM_PARALLEL|HF_TOKEN)
                export "$key=$val"
                ;;
            *) : ;;
        esac
    done < "$env_file"

    local engine_lc
    engine_lc=$(printf '%s' "${INFERENCE_ENGINE:-ollama}" | tr '[:upper:]' '[:lower:]')
    case "$engine_lc" in
        ollama|llamacpp) ;;
        both|llama.cpp|llama-cpp) engine_lc="llamacpp" ;;
        *) engine_lc="ollama" ;;
    esac
    INFERENCE_ENGINE="$engine_lc"
    export INFERENCE_ENGINE
}

# ── Hardware tuning (exports PENDRIVE_* variables) ───────────────
px_detect_hardware() {
    local usb="$1"
    local model_path="${2:-}"
    local hw_script="$usb/tools/hardware.sh"
    local out=""

    if [[ -f "$hw_script" ]]; then
        out=$(bash "$hw_script" --model "$model_path" 2>/dev/null || true)
    fi
    if [[ -n "$out" ]]; then
        # Output is printf %q quoted and safe to eval.
        eval "$out" 2>/dev/null || true
    fi

    : "${PENDRIVE_ACCEL:=cpu}"
    : "${PENDRIVE_GPU_NAME:=}"
    : "${PENDRIVE_VRAM_GB:=0}"
    : "${PENDRIVE_NGL:=0}"
    : "${PENDRIVE_THREADS:=4}"
    : "${PENDRIVE_CTX:=4096}"
    : "${PENDRIVE_RAM_GB:=0}"
    : "${PENDRIVE_CPU:=unknown}"
    : "${PENDRIVE_LLAMACPP_VARIANT:=cpu}"
    : "${PENDRIVE_ACCEL_NOTE:=CPU only}"
    export PENDRIVE_ACCEL PENDRIVE_GPU_NAME PENDRIVE_VRAM_GB PENDRIVE_NGL \
           PENDRIVE_THREADS PENDRIVE_CTX PENDRIVE_RAM_GB PENDRIVE_CPU \
           PENDRIVE_LLAMACPP_VARIANT PENDRIVE_ACCEL_NOTE
}

# ── Resolve a model alias to its GGUF file ───────────────────────
# Sets PX_MODEL_LOCAL, PX_MODEL_FILE, PX_MODEL_PATH, PX_MODEL_GB.
px_resolve_model() {
    local usb="$1"
    local requested="${2:-}"
    local models_dir="$usb/models"
    local local_name=""
    local file=""

    if [[ -n "$requested" ]]; then
        local_name="$requested"
    elif [[ -n "${LLAMACPP_MODEL:-}" ]]; then
        local_name="$LLAMACPP_MODEL"
    elif [[ -f "$models_dir/installed-models.txt" ]]; then
        local_name=$(head -n 1 "$models_dir/installed-models.txt" 2>/dev/null | cut -d '|' -f 1 | tr -d '\r\n ')
    fi

    # Normalise a short name (qwen -> qwen-local) when possible.
    if [[ -n "$local_name" && ! -f "$models_dir/Modelfile-$local_name" && -f "$models_dir/Modelfile-$local_name-local" ]]; then
        local_name="$local_name-local"
    fi

    if [[ -n "$local_name" && -f "$models_dir/Modelfile-$local_name" ]]; then
        file=$(awk 'tolower($1)=="from" { gsub(/^\.\//,"",$2); print $2; exit }' "$models_dir/Modelfile-$local_name" 2>/dev/null | tr -d '\r')
    fi

    # Fallback 1: requested value is already a filename.
    if [[ -z "$file" && -f "$models_dir/${requested}" ]]; then
        file="$requested"
    fi

    # Fallback 2: first GGUF in the models directory (BSD find-safe).
    if [[ -z "$file" && -d "$models_dir" ]]; then
        local candidate
        for candidate in "$models_dir"/*.gguf; do
            [[ -f "$candidate" ]] || continue
            file=$(basename "$candidate")
            break
        done
    fi

    PX_MODEL_LOCAL="${local_name:-nemomix-local}"
    PX_MODEL_FILE="$file"
    if [[ -n "$file" && -f "$models_dir/$file" ]]; then
        PX_MODEL_PATH="$models_dir/$file"
        PX_MODEL_GB=$(awk -v b="$(stat -c%s "$PX_MODEL_PATH" 2>/dev/null || stat -f%z "$PX_MODEL_PATH" 2>/dev/null || echo 0)" 'BEGIN { printf "%.2f", b/1073741824 }')
    else
        PX_MODEL_PATH=""
        PX_MODEL_GB="0"
    fi

    PX_MMPROJ_FILE=""
    PX_MMPROJ_PATH=""
    if [[ -n "$local_name" && -f "$models_dir/Modelfile-$local_name" ]]; then
        local mm_cand
        mm_cand=$(awk 'tolower($1)=="from" { gsub(/^\.\//,"",$2); if ($2 ~ /mmproj/) { print $2; exit } }' "$models_dir/Modelfile-$local_name" 2>/dev/null | tr -d '\r')
        if [[ -n "$mm_cand" && -f "$models_dir/$mm_cand" ]]; then
            PX_MMPROJ_FILE="$mm_cand"
            PX_MMPROJ_PATH="$models_dir/$mm_cand"
        fi
    fi
    export PX_MODEL_LOCAL PX_MODEL_FILE PX_MODEL_PATH PX_MODEL_GB PX_MMPROJ_FILE PX_MMPROJ_PATH
}

# ── Port helpers ─────────────────────────────────────────────────
px_is_port_free() {
    local p="$1"
    if command -v nc >/dev/null 2>&1; then
        ! nc -z 127.0.0.1 "$p" 2>/dev/null
    elif command -v lsof >/dev/null 2>&1; then
        ! lsof -iTCP:"$p" -sTCP:LISTEN -P -n 2>/dev/null | grep -q LISTEN
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket; s=socket.socket(); s.settimeout(1); exit(0 if s.connect_ex(('127.0.0.1', $p))!=0 else 1)" 2>/dev/null
    else
        (exec 3<>/dev/tcp/127.0.0.1/"$p") 2>/dev/null && { exec 3<&- 3>&-; return 1; } || return 0
    fi
}

px_find_free_port() {
    local preferred="${1:-0}"
    if [[ "$preferred" =~ ^[0-9]+$ ]] && (( preferred > 0 )) && px_is_port_free "$preferred"; then
        echo "$preferred"
        return 0
    fi
    local port
    for ((port = 11434; port <= 11534; port++)); do
        if px_is_port_free "$port"; then echo "$port"; return 0; fi
    done
    echo "11434"
}

# ── AnythingLLM configuration (preserves token limit / chat data) ─
px_config_anythingllm() {
    local usb="$1"
    local engine="$2"
    local host="$3"
    local port="$4"
    local model="$5"
    local emb_model="${6:-}"
    local storage="$usb/anythingllm_data/storage"
    local env_file="$storage/.env"
    mkdir -p "$storage" 2>/dev/null || true

    local token=4096
    if [[ -f "$env_file" ]]; then
        local existing
        existing=$(grep -E '^(OLLAMA_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT)=' "$env_file" 2>/dev/null | head -n 1 | cut -d '=' -f 2 | tr -d '[:space:]\r' || true)
        [[ "$existing" =~ ^[0-9]+$ ]] && token="$existing"
    fi

    # Resolve embedding model preference for local RAG
    if [[ -z "$emb_model" ]]; then
        local installed_file="$usb/models/installed-models.txt"
        if [[ -f "$installed_file" ]]; then
            while IFS='|' read -r m_local m_name m_label _; do
                m_local=$(echo "$m_local" | tr -d '\r\n ')
                m_label=$(echo "$m_label" | tr -d '\r\n ')
                if [[ "$m_label" == "EMBEDDING" || "$m_local" =~ (embed|bge) ]]; then
                    emb_model="$m_local"
                    break
                fi
            done < "$installed_file"
        fi
    fi
    [[ -z "$emb_model" ]] && emb_model="${EMBEDDING_MODEL:-nomic-embed-local}"

    local tmp="${env_file}.tmp"
    if [[ -f "$env_file" ]]; then
        grep -vE '^(LLM_PROVIDER|OLLAMA_BASE_PATH|OLLAMA_MODEL_PREF|OLLAMA_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_BASE_PATH|GENERIC_OPEN_AI_MODEL_PREF|GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT|GENERIC_OPEN_AI_API_KEY|GENERIC_OPEN_AI_MAX_TOKENS|EMBEDDING_ENGINE|EMBEDDING_BASE_PATH|EMBEDDING_MODEL_PREF|EMBEDDING_MODEL_MAX_CHUNK_LENGTH|VECTOR_DB|HOST|SERVER_PORT)=' "$env_file" > "$tmp" 2>/dev/null || true
    else
        : > "$tmp"
    fi

    {
        if [[ "$engine" == "llamacpp" ]]; then
            echo "LLM_PROVIDER=generic-openai"
            echo "GENERIC_OPEN_AI_BASE_PATH=http://127.0.0.1:${port}/v1"
            echo "GENERIC_OPEN_AI_MODEL_PREF=${model}"
            echo "GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT=${token}"
            echo "GENERIC_OPEN_AI_MAX_TOKENS=${token}"
            echo "GENERIC_OPEN_AI_API_KEY=sk-no-key"
            echo "EMBEDDING_ENGINE=native"
            echo "VECTOR_DB=lancedb"
        else
            echo "LLM_PROVIDER=ollama"
            echo "OLLAMA_BASE_PATH=http://127.0.0.1:${port}"
            echo "OLLAMA_MODEL_PREF=${model}"
            echo "OLLAMA_MODEL_TOKEN_LIMIT=${token}"
            echo "EMBEDDING_ENGINE=ollama"
            echo "EMBEDDING_BASE_PATH=http://127.0.0.1:${port}"
            echo "EMBEDDING_MODEL_PREF=${emb_model}"
            echo "EMBEDDING_MODEL_MAX_CHUNK_LENGTH=8192"
            echo "VECTOR_DB=lancedb"
        fi
        # LAN mode: desktop builds ignore these, but server builds honour them.
        if [[ "${SERVER_MODE:-0}" == "1" ]]; then
            echo "HOST=0.0.0.0"
            echo "SERVER_PORT=${LAN_CHAT_PORT:-8090}"
        fi
    } >> "$tmp"

    mv "$tmp" "$env_file" 2>/dev/null || cp "$tmp" "$env_file" 2>/dev/null || true
    rm -f "$tmp" 2>/dev/null || true
    echo "$token"
}

# ── LAN helpers ──────────────────────────────────────────────────
px_lan_ip() {
    local ip=""
    case "$(uname -s 2>/dev/null || echo unknown)" in
        Darwin)
            for iface in en0 en1 en2; do
                ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
                [[ -n "$ip" ]] && break
            done
            ;;
        *)
            if command -v ip >/dev/null 2>&1; then
                ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' || true)
            fi
            if [[ -z "$ip" ]]; then
                ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
            fi
            ;;
    esac
    if [[ -z "$ip" ]]; then
        ip=$(hostname 2>/dev/null || echo "127.0.0.1")
    fi
    echo "$ip"
}

px_show_qr() {
    local usb="$1"
    local url="$2"
    echo ""
    echo -e "${CYAN}┌──────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  ${BOLD}Scan to open on your phone / tablet${NC}                ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${YELLOW}${url}${NC}"
    echo ""
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t ANSIUTF8 "$url" 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1 && [[ -f "$usb/tools/qr.py" ]]; then
        python3 "$usb/tools/qr.py" --no-url "$url" 2>/dev/null || echo -e "  ${DGRAY}(QR renderer failed; open the URL above)${NC}"
    else
        echo -e "  ${DGRAY}Install 'qrencode' or Python 3 for an in-terminal QR code.${NC}"
    fi
    echo ""
}

px_print_lan_info() {
    local usb="$1"
    local port="$2"
    local scheme="${3:-http}"
    local path="${4:-/}"
    local ip
    ip=$(px_lan_ip)
    local url="${scheme}://${ip}:${port}${path}"
    echo -e "${DGRAY}  LAN address: ${CYAN}${url}${NC}"
    px_show_qr "$usb" "$url"
}

# ── Process helpers ──────────────────────────────────────────────
px_kill_by_path() {
    local needle="$1"
    command -v pgrep >/dev/null 2>&1 || return 0
    local pids
    pids=$(pgrep -f "$needle" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
}
