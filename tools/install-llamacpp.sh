#!/usr/bin/env bash
# ================================================================
# Pendrive_X - install / update portable llama.cpp (llama-server)
# ================================================================
# Usage:
#   bash tools/install-llamacpp.sh /path/to/usb [variant] [--force]
#
# variant: auto | cuda | rocm | vulkan | cpu
# The script only touches <USB>/llamacpp and installer_data; models,
# Ollama data and AnythingLLM chats are never modified.
# ================================================================

set -uo pipefail

USB_DIR="${1:-}"
[[ $# -gt 0 ]] && shift
VARIANT="auto"
FORCE="false"
for arg in "$@"; do
    case "$arg" in
        --force) FORCE="true" ;;
        --*) : ;;
        *) VARIANT="$arg" ;;
    esac
done

if [[ -z "$USB_DIR" || ! -d "$USB_DIR" ]]; then
    echo "ERROR: USB directory not found: ${USB_DIR:-<empty>}" >&2
    exit 1
fi
USB_DIR="$(cd "$USB_DIR" && pwd)"
if [[ "$(basename "$USB_DIR")" == "linux" ]]; then USB_DIR="$(cd "$USB_DIR/.." && pwd)"; fi

# ── Load pinned versions ────────────────────────────────────────
if [[ -f "$USB_DIR/versions.env" ]]; then
    set -a; source "$USB_DIR/versions.env" 2>/dev/null || true; set +a
fi

LLAMACPP_VERSION="${LLAMACPP_VERSION:-b12244}"
TARGET_DIR="$USB_DIR/llamacpp"
STAMP="$USB_DIR/installer_data/llamacpp-variant.txt"
TMP_DIR="$USB_DIR/installer_data/llamacpp-tmp"

if [[ -x "$TARGET_DIR/llama-server" || -x "$TARGET_DIR/llama-server.exe" ]] && [[ "$FORCE" != "true" ]]; then
    echo "[OK] llama.cpp already installed at $TARGET_DIR"
    exit 0
fi

OS="$(uname -s 2>/dev/null || echo Linux)"
ARCH="$(uname -m 2>/dev/null || echo x86_64)"

# Resolve auto variant from hardware detection
if [[ "$VARIANT" == "auto" ]]; then
    HW_OUT=""
    if [[ -f "$USB_DIR/tools/hardware.sh" ]]; then
        HW_OUT=$(bash "$USB_DIR/tools/hardware.sh" --model-gb "${LLAMACPP_MODEL_GB:-4.0}" 2>/dev/null || true)
    fi
    VARIANT=$(printf '%s\n' "$HW_OUT" | sed -n 's/^PENDRIVE_LLAMACPP_VARIANT=//p' | head -1)
    VARIANT="${VARIANT//\'/}"
    # CPU is the safe fallback when hardware detection is unavailable.
    [[ -z "$VARIANT" ]] && VARIANT="cpu"
fi

# ROCm builds require the ROCm runtime tools; fall back to Vulkan.
if [[ "$VARIANT" == "rocm" ]] && ! command -v rocm-smi >/dev/null 2>&1; then
    echo "[WARN] ROCm runtime not found; using Vulkan build instead."
    VARIANT="vulkan"
fi

MAIN_URL=""
RUNTIME_URL=""
case "$OS" in
    Darwin)
        if [[ "$ARCH" == "arm64" ]]; then
            MAIN_URL="${LLAMACPP_MAC_ARM_URL:-}"
        else
            MAIN_URL="${LLAMACPP_MAC_X64_URL:-}"
        fi
        VARIANT="metal"
        ;;
    *)
        case "$VARIANT" in
            cuda)
                MAIN_URL="${LLAMACPP_LINUX_CUDA_URL:-}"
                RUNTIME_URL="${LLAMACPP_LINUX_CUDA_RUNTIME_URL:-}"
                ;;
            rocm)
                MAIN_URL="${LLAMACPP_LINUX_ROCM_URL:-}"
                ;;
            vulkan)
                MAIN_URL="${LLAMACPP_LINUX_VULKAN_URL:-}"
                ;;
            *)
                MAIN_URL="${LLAMACPP_LINUX_URL:-}"
                VARIANT="cpu"
                ;;
        esac
        ;;
esac

if [[ -z "$MAIN_URL" ]]; then
    echo "ERROR: No llama.cpp URL configured for variant '$VARIANT' in versions.env" >&2
    exit 1
fi

echo "[*] Installing llama.cpp $LLAMACPP_VERSION ($VARIANT) for $OS/$ARCH"
echo "    URL: $MAIN_URL"

mkdir -p "$USB_DIR/installer_data" "$TARGET_DIR" 2>/dev/null || true
rm -rf "$TMP_DIR" 2>/dev/null || true
mkdir -p "$TMP_DIR" 2>/dev/null || true

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

ARCHIVE="$USB_DIR/installer_data/llamacpp-${VARIANT}.tar.gz"
if ! download "$MAIN_URL" "$ARCHIVE"; then
    echo "ERROR: llama.cpp download failed." >&2
    exit 1
fi

echo "[*] Extracting..."
if ! tar -xzf "$ARCHIVE" -C "$TMP_DIR" 2>/dev/null; then
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$ARCHIVE" -d "$TMP_DIR" 2>/dev/null || {
            echo "ERROR: could not extract llama.cpp archive." >&2
            rm -f "$ARCHIVE"
            exit 1
        }
    else
        echo "ERROR: could not extract llama.cpp archive (tar/unzip failed)." >&2
        rm -f "$ARCHIVE"
        exit 1
    fi
fi

# Optional CUDA runtime bundle (extracted separately, merged below)
RUNTIME_DIR="$TMP_DIR/runtime"
if [[ -n "$RUNTIME_URL" ]]; then
    RUNTIME_ARCHIVE="$USB_DIR/installer_data/llamacpp-cudart.tar.gz"
    if download "$RUNTIME_URL" "$RUNTIME_ARCHIVE"; then
        mkdir -p "$RUNTIME_DIR"
        tar -xzf "$RUNTIME_ARCHIVE" -C "$RUNTIME_DIR" 2>/dev/null || true
    fi
    rm -f "$RUNTIME_ARCHIVE" 2>/dev/null || true
fi

# Find llama-server (archives usually contain it at the root or build/bin)
SERVER_PATH=$(find "$TMP_DIR" -type f \( -name 'llama-server' -o -name 'llama-server.exe' \) 2>/dev/null | head -1 || true)
if [[ -z "$SERVER_PATH" ]]; then
    echo "ERROR: llama-server binary not found in archive." >&2
    rm -rf "$TMP_DIR" "$ARCHIVE" 2>/dev/null || true
    exit 1
fi
SOURCE_DIR="$(cd "$(dirname "$SERVER_PATH")" && pwd)"

echo "[*] Installing to $TARGET_DIR (models and chats untouched)"
# Copy binaries/libraries but never any user data (there is none in the archive).
# Remove only previous llama.cpp engine files, not the whole USB tree.
# Portable glob cleanup (macOS find has no -mindepth/-maxdepth).
for entry in "$TARGET_DIR"/* "$TARGET_DIR"/.[!.]* "$TARGET_DIR"/..?*; do
    [[ -e "$entry" ]] || continue
    rm -rf "$entry" 2>/dev/null || true
done
cp -R "$SOURCE_DIR"/. "$TARGET_DIR"/ 2>/dev/null || true

# CUDA runtime libraries must sit next to llama-server. Archives sometimes
# wrap them in a top-level folder, so locate the cudart files first.
if [[ -d "$RUNTIME_DIR" ]]; then
    RUNTIME_SRC=$(find "$RUNTIME_DIR" -type f \( -name 'libcudart*' -o -name 'cudart*.dll' \) 2>/dev/null | head -1 || true)
    if [[ -n "$RUNTIME_SRC" ]]; then RUNTIME_SRC="$(dirname "$RUNTIME_SRC")"; else RUNTIME_SRC="$RUNTIME_DIR"; fi
    # -P keeps the .so -> .so.N symlinks needed by the dynamic loader.
    cp -RP "$RUNTIME_SRC"/. "$TARGET_DIR"/ 2>/dev/null || true
fi

# If the archive used a nested bin/ layout, flatten if necessary.
if [[ ! -x "$TARGET_DIR/llama-server" && -x "$TARGET_DIR/bin/llama-server" ]]; then
    cp -R "$TARGET_DIR/bin"/. "$TARGET_DIR"/ 2>/dev/null || true
fi
chmod +x "$TARGET_DIR"/llama-server "$TARGET_DIR"/llama-cli 2>/dev/null || true

mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
printf 'LLAMACPP_VERSION=%s\nLLAMACPP_VARIANT=%s\nINSTALLED_AT=%s\n' \
    "$LLAMACPP_VERSION" "$VARIANT" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" > "$STAMP" 2>/dev/null || true

rm -rf "$TMP_DIR" "$ARCHIVE" 2>/dev/null || true
echo "[OK] llama.cpp ready: $TARGET_DIR/llama-server ($VARIANT)"
