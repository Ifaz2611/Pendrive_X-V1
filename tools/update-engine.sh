#!/usr/bin/env bash
# ================================================================
# Pendrive_X - in-place engine / UI updater (macOS + Linux)
# ================================================================
# Refreshes Ollama, AnythingLLM and/or llama.cpp from versions.env.
# Models (models/*.gguf), Ollama data (ollama/data) and user chat
# databases (anythingllm_data/) are never touched.
#
# Usage:
#   bash tools/update-engine.sh /path/to/usb mac|linux [--engine all|ollama|anythingllm|llamacpp] [--yes]
# ================================================================

set -uo pipefail

USB_DIR="${1:-}"
PLATFORM="${2:-linux}"
[[ $# -ge 2 ]] && shift 2 || { [[ $# -eq 1 ]] && shift; }
ENGINE="all"
ASSUME_YES="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --engine) ENGINE="${2:-all}"; shift 2 ;;
        --engine=*) ENGINE="${1#--engine=}"; shift ;;
        --yes|-y) ASSUME_YES="true"; shift ;;
        *) shift ;;
    esac
done

if [[ -z "$USB_DIR" || ! -d "$USB_DIR" ]]; then
    echo "ERROR: USB directory not found: ${USB_DIR:-<empty>}" >&2
    exit 1
fi
USB_DIR="$(cd "$USB_DIR" && pwd)"
if [[ "$(basename "$USB_DIR")" == "linux" && -f "$USB_DIR/../versions.env" ]]; then
    USB_DIR="$(cd "$USB_DIR/.." && pwd)"
fi

if [[ -f "$USB_DIR/versions.env" ]]; then
    set -a; source "$USB_DIR/versions.env" 2>/dev/null || true; set +a
fi

# Colour helpers (plain when not a TTY)
if [[ -t 1 ]]; then
    C_G="\033[1;92m"; C_Y="\033[1;93m"; C_R="\033[1;91m"; C_C="\033[1;96m"; C_D="\033[2;90m"; C_N="\033[0m"
else
    C_G=""; C_Y=""; C_R=""; C_C=""; C_D=""; C_N=""
fi

TMP_ROOT="$USB_DIR/installer_data/update-tmp"
mkdir -p "$TMP_ROOT" 2>/dev/null || true
ERRORS=0
UPDATED=()

log()  { echo -e "${C_D}[*]${C_N} $*"; }
ok()   { echo -e "${C_G}[OK]${C_N} $*"; }
warn() { echo -e "${C_Y}[WARN]${C_N} $*"; }
fail() { echo -e "${C_R}[FAIL]${C_N} $*"; ERRORS=$((ERRORS + 1)); }

download() {
    local url="$1" dest="$2"
    local part="${dest}.part"
    rm -f "$part" 2>/dev/null || true
    if curl -fL --progress-bar --retry 3 --retry-delay 5 -o "$part" "$url"; then
        mv "$part" "$dest"
        return 0
    fi
    rm -f "$part" 2>/dev/null || true
    return 1
}

extract_archive() {    local archive="$1" dest="$2"
    mkdir -p "$dest" 2>/dev/null || true
    case "$archive" in
        *.zip)
            if command -v unzip >/dev/null 2>&1; then
                unzip -q -o "$archive" -d "$dest"
            else
                return 1
            fi
            ;;
        *.tgz|*.tar.gz)
            tar -xzf "$archive" -C "$dest"
            ;;
        *.tar.zst)
            if command -v zstd >/dev/null 2>&1 && zstd -d "$archive" -o "${archive%.zst}" 2>/dev/null; then
                tar -xf "${archive%.zst}" -C "$dest"
                rm -f "${archive%.zst}"
            else
                tar -I zstd -xf "$archive" -C "$dest" 2>/dev/null || tar -xf "$archive" -C "$dest"
            fi
            ;;
        *) return 1 ;;
    esac
}

stop_usb_apps() {
    local needle="$1"
    command -v pgrep >/dev/null 2>&1 || return 0
    local pids
    pids=$(pgrep -f "$needle" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        warn "Stopping running processes from the USB before update..."
        echo "$pids" | xargs kill 2>/dev/null || true
        sleep 1
        pids=$(pgrep -f "$needle" 2>/dev/null || true)
        [[ -n "$pids" ]] && echo "$pids" | xargs kill -9 2>/dev/null || true
    fi
}

# Remove entries in a directory, optionally keeping one name. Portable to BSD.
clear_dir_except() {
    local dir="$1" keep="${2:-}" entry name
    for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        [[ -n "$keep" && "$name" == "$keep" ]] && continue
        rm -rf "$entry" 2>/dev/null || true
    done
}

# -----------------------------------------------------------------
# Ollama
# -----------------------------------------------------------------
update_ollama() {
    if [[ "$PLATFORM" == "mac" ]]; then
        local dir="$USB_DIR/ollama_mac"
        local url="${OLLAMA_MAC_URL:-}"
        local archive="$TMP_ROOT/ollama-darwin.zip"
        local extract="$TMP_ROOT/ollama-mac"
        if [[ -z "$url" ]]; then fail "OLLAMA_MAC_URL is not set in versions.env"; return; fi
        log "Updating Ollama $OLLAMA_VERSION (macOS)..."
        rm -rf "$extract"; download "$url" "$archive" || { fail "Ollama download failed"; return; }
        extract_archive "$archive" "$extract" || { fail "Could not extract Ollama"; return; }
        mkdir -p "$dir"
        # ollama_mac contains only the engine; model data lives in ollama/data.
        clear_dir_except "$dir"
        cp -R "$extract"/. "$dir"/ 2>/dev/null || true
        chmod +x "$dir/Ollama.app/Contents/MacOS/Ollama" "$dir/ollama" 2>/dev/null || true
        rm -rf "$archive" "$extract" 2>/dev/null || true
        UPDATED+=("Ollama $OLLAMA_VERSION")
        ok "Ollama updated (models in ollama/data preserved)"
    else
        local dir="$USB_DIR/ollama"
        local url="${OLLAMA_LINUX_URL:-${OLLAMA_LINUX_ALT_URL:-}}"
        local archive="$TMP_ROOT/ollama-linux.tar.gz"
        local extract="$TMP_ROOT/ollama-linux"
        if [[ -z "$url" ]]; then fail "OLLAMA_LINUX_URL is not set in versions.env"; return; fi
        log "Updating Ollama $OLLAMA_VERSION (Linux)..."
        rm -rf "$extract"; download "$url" "$archive" || { fail "Ollama download failed"; return; }
        extract_archive "$archive" "$extract" || { fail "Could not extract Ollama"; return; }
        mkdir -p "$dir"
        # Preserve ollama/data (multi-GB GGUF model store).
        clear_dir_except "$dir" "data"
        if [[ -d "$extract/bin" || -d "$extract/lib" ]]; then
            [[ -d "$extract/bin" ]] && cp -R "$extract/bin"/. "$dir"/ 2>/dev/null || true
            [[ -d "$extract/lib" ]] && cp -R "$extract/lib" "$dir"/ 2>/dev/null || true
        else
            cp -R "$extract"/. "$dir"/ 2>/dev/null || true
        fi
        # Compatibility: expose the binary at ollama/ollama as before.
        if [[ -x "$dir/bin/ollama" ]]; then cp -f "$dir/bin/ollama" "$dir/ollama" 2>/dev/null || true; fi
        chmod +x "$dir/ollama" "$dir/bin/ollama" 2>/dev/null || true
        rm -rf "$archive" "$extract" 2>/dev/null || true
        UPDATED+=("Ollama $OLLAMA_VERSION")
        ok "Ollama updated (models in ollama/data preserved)"
    fi
}

# -----------------------------------------------------------------
# AnythingLLM
# -----------------------------------------------------------------
update_anythingllm() {
    if [[ "$PLATFORM" == "mac" ]]; then
        local url="${ANYTHINGLLM_MAC_URL:-}"
        local archive="$TMP_ROOT/AnythingLLM.dmg"
        local app_dir="$USB_DIR/anythingllm_mac"
        if [[ "$(uname -m 2>/dev/null || echo arm64)" == "x86_64" && -n "${ANYTHINGLLM_MAC_INTEL_URL:-}" ]]; then
            url="$ANYTHINGLLM_MAC_INTEL_URL"
        fi
        if [[ -z "$url" ]]; then fail "ANYTHINGLLM_MAC_URL is not set"; return; fi
        log "Updating AnythingLLM $ANYTHINGLLM_VERSION (macOS)..."
        download "$url" "$archive" || { fail "AnythingLLM download failed"; return; }
        local mount_out mount_dir dev_node
        mount_out=$(hdiutil attach -nobrowse "$archive" 2>&1 || true)
        dev_node=$(echo "$mount_out" | grep -o '/dev/disk[0-9][^[:space:]]*' | head -1)
        mount_dir=$(echo "$mount_out" | grep -o '/Volumes/[^[:space:]]*' | tail -1)
        if [[ -z "$mount_dir" || ! -d "$mount_dir/AnythingLLM.app" ]]; then
            fail "Could not mount AnythingLLM DMG"
            [[ -n "${dev_node:-}" ]] && hdiutil detach "$dev_node" 2>/dev/null || true
            return
        fi
        mkdir -p "$app_dir"
        rm -rf "$app_dir/AnythingLLM.app" 2>/dev/null || true
        cp -R "$mount_dir/AnythingLLM.app" "$app_dir/" 2>/dev/null || { fail "Could not copy AnythingLLM.app"; }
        hdiutil detach "$dev_node" 2>/dev/null || hdiutil detach "$mount_dir" 2>/dev/null || true
        rm -f "$archive" 2>/dev/null || true
        xattr -rc "$app_dir/AnythingLLM.app" 2>/dev/null || true
        UPDATED+=("AnythingLLM $ANYTHINGLLM_VERSION")
        ok "AnythingLLM updated (chats in anythingllm_data preserved)"
    else
        local url="${ANYTHINGLLM_LINUX_URL:-}"
        local dest="$USB_DIR/anythingllm/AnythingLLM.AppImage"
        local new="$USB_DIR/installer_data/AnythingLLM.AppImage.new"
        [[ -z "$url" ]] && { fail "ANYTHINGLLM_LINUX_URL is not set"; return; }
        log "Updating AnythingLLM $ANYTHINGLLM_VERSION (Linux AppImage)..."
        mkdir -p "$USB_DIR/anythingllm" "$USB_DIR/installer_data" 2>/dev/null || true
        download "$url" "$new" || { fail "AnythingLLM download failed"; return; }
        chmod +x "$new" 2>/dev/null || true
        mv -f "$new" "$dest" 2>/dev/null || { fail "Could not replace AppImage"; return; }
        UPDATED+=("AnythingLLM $ANYTHINGLLM_VERSION")
        ok "AnythingLLM updated (chats in anythingllm_data preserved)"
    fi
}

# -----------------------------------------------------------------
# llama.cpp
# -----------------------------------------------------------------
update_llamacpp() {
    local variant="${LLAMACPP_VARIANT:-auto}"
    local stamp="$USB_DIR/installer_data/llamacpp-variant.txt"
    if [[ "$variant" == "auto" && -f "$stamp" ]]; then
        variant=$(grep -E '^LLAMACPP_VARIANT=' "$stamp" 2>/dev/null | cut -d= -f2 | tr -d '[:space:]' || true)
        [[ -z "$variant" ]] && variant="auto"
    fi
    local installer="$USB_DIR/tools/install-llamacpp.sh"
    if [[ ! -f "$installer" ]]; then fail "tools/install-llamacpp.sh missing"; return; fi
    log "Updating llama.cpp $LLAMACPP_VERSION ($variant)..."
    if bash "$installer" "$USB_DIR" "$variant" --force; then
        UPDATED+=("llama.cpp $LLAMACPP_VERSION")
    else
        fail "llama.cpp update failed"
    fi
}

# -----------------------------------------------------------------
# Main
# -----------------------------------------------------------------
echo -e "${C_C}Pendrive_X — In-place engine updater${C_N}"
echo -e "${C_D}USB: $USB_DIR${C_N}"
echo -e "${C_D}Models, Ollama data and AnythingLLM chats will NOT be modified.${C_N}"
echo ""

stop_usb_apps "$USB_DIR/ollama"
stop_usb_apps "$USB_DIR/llamacpp"
stop_usb_apps "$USB_DIR/anythingllm"

case "$ENGINE" in
    all)
        # Refresh only components that are actually installed; a llama.cpp-only
        # USB should not pull a multi-hundred-MB Ollama archive.
        if [[ -x "$USB_DIR/ollama/ollama" || -d "$USB_DIR/ollama_mac" ]]; then
            update_ollama
        else
            log "Ollama not installed - skipping"
        fi
        if [[ -d "$USB_DIR/anythingllm" || -d "$USB_DIR/anythingllm_mac" ]]; then
            update_anythingllm
        else
            log "AnythingLLM not installed - skipping"
        fi
        if [[ -x "$USB_DIR/llamacpp/llama-server" || -f "$USB_DIR/installer_data/llamacpp-variant.txt" ]]; then
            update_llamacpp
        else
            log "llama.cpp not installed - skipping"
        fi
        ;;
    ollama) update_ollama ;;
    anythingllm|ui) update_anythingllm ;;
    llamacpp|llama.cpp|llama) update_llamacpp ;;
    *) fail "Unknown --engine '$ENGINE' (use all|ollama|anythingllm|llamacpp)" ;;
esac

STAMP="$USB_DIR/installer_data/engine-versions.txt"
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
{
    echo "# Updated by tools/update-engine.sh"
    echo "UPDATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "OLLAMA_VERSION=${OLLAMA_VERSION:-unknown}"
    echo "ANYTHINGLLM_VERSION=${ANYTHINGLLM_VERSION:-unknown}"
    echo "LLAMACPP_VERSION=${LLAMACPP_VERSION:-unknown}"
} > "$STAMP" 2>/dev/null || true

echo ""
if (( ERRORS > 0 )); then
    echo -e "${C_Y}Update finished with $ERRORS error(s).${C_N}"
    rm -rf "$TMP_ROOT" 2>/dev/null || true
    exit 1
fi
echo -e "${C_G}Update complete.${C_N}"
if (( ${#UPDATED[@]} )); then
    for item in "${UPDATED[@]}"; do
        echo -e "  ${C_G}✔${C_N} $item"
    done
fi
rm -rf "$TMP_ROOT" 2>/dev/null || true
exit 0
