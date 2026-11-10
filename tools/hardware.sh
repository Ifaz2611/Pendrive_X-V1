#!/usr/bin/env bash
# ================================================================
# Pendrive_X - Hardware acceleration auto-tuner (Linux / macOS)
# ================================================================
# Detects NVIDIA CUDA, AMD ROCm, Vulkan, Apple Metal and CPU
# AVX2/AVX-512 support. Prints eval-safe KEY=VALUE lines by default
# or JSON with --json.
#
# Usage:
#   eval "$(bash tools/hardware.sh --model path/to/model.gguf)"
#   bash tools/hardware.sh --model-gb 4.1 --json
# ================================================================

set -uo pipefail

MODEL_PATH=""
MODEL_GB="0"
FORMAT="env"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL_PATH="${2:-}"; shift 2 ;;
        --model-gb) MODEL_GB="${2:-0}"; shift 2 ;;
        --json) FORMAT="json"; shift ;;
        --env) FORMAT="env"; shift ;;
        -h|--help)
            echo "Usage: bash tools/hardware.sh [--model path/to/model.gguf] [--model-gb 4.1] [--json]"
            exit 0
            ;;
        *) shift ;;
    esac
done

OS="$(uname -s 2>/dev/null || echo unknown)"
ARCH="$(uname -m 2>/dev/null || echo unknown)"

if [[ -z "$MODEL_GB" || "$MODEL_GB" == "0" ]]; then
    if [[ -n "$MODEL_PATH" && -f "$MODEL_PATH" ]]; then
        MODEL_GB=$(awk -v bytes="$(stat -c%s "$MODEL_PATH" 2>/dev/null || stat -f%z "$MODEL_PATH" 2>/dev/null || echo 0)" 'BEGIN { printf "%.2f", bytes/1073741824 }')
    fi
fi
[[ -z "$MODEL_GB" || "$MODEL_GB" == "0" ]] && MODEL_GB="4.0"
MODEL_GB_NUM=$(awk -v m="$MODEL_GB" 'BEGIN { printf "%.2f", m+0 }')

CPU_NAME="$(uname -m 2>/dev/null || echo CPU)"
RAM_GB="0"
THREADS="4"
CTX="4096"
BACKEND="cpu"
GPU_NAME=""
VRAM_GB="0"
NOTE=""
CPU_FEATURES=""

# ── CPU / RAM / OS ───────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
    CPU_NAME="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")"
    RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
    RAM_GB=$(awk -v b="$RAM_BYTES" 'BEGIN { printf "%.1f", b/1073741824 }')
    THREADS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    # Apple Silicon exposes performance/efficiency cores; use all for generation.
    CPU_FEATURES="arm64"
elif [[ "$OS" == "Linux" ]]; then
    CPU_NAME=$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "CPU")
    MEM_KB=$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
    RAM_GB=$(awk -v k="$MEM_KB" 'BEGIN { printf "%.1f", k/1048576 }')
    LOGICAL=$(nproc 2>/dev/null || echo 4)
    PHYSICAL=""
    if command -v lscpu >/dev/null 2>&1; then
        PHYSICAL=$(lscpu -p=Core,Socket 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' ')
    fi
    if [[ -z "$PHYSICAL" || "$PHYSICAL" == "0" ]]; then
        PHYSICAL=$(( LOGICAL / 2 )); (( PHYSICAL < 1 )) && PHYSICAL=1
    fi
    THREADS="$PHYSICAL"
    CPU_FEATURES=$(awk -F': ' '/^flags/{print $2; exit}' /proc/cpuinfo 2>/dev/null || echo "")
fi
(( THREADS > 16 )) && THREADS=16
(( THREADS < 1 )) && THREADS=1

# ── GPU detection ────────────────────────────────────────────────
if [[ "$OS" == "Darwin" ]]; then
    BACKEND="metal"
    GPU_NAME="$CPU_NAME"
    VRAM_GB="$RAM_GB"  # Unified memory
    NOTE="$GPU_NAME / Metal / unified memory (${RAM_GB} GB)"
else
    # NVIDIA CUDA
    if command -v nvidia-smi >/dev/null 2>&1; then
        NVIDIA_LINE=$(nvidia-smi --query-gpu=name,memory.total,compute_cap --format=csv,noheader,nounits 2>/dev/null | head -1 || true)
        if [[ -n "$NVIDIA_LINE" ]]; then
            GPU_NAME=$(echo "$NVIDIA_LINE" | awk -F',' '{gsub(/^ +| +$/,"",$1); print $1}')
            VRAM_MB=$(echo "$NVIDIA_LINE" | awk -F',' '{gsub(/^ +| +$/,"",$2); print $2}')
            CC=$(echo "$NVIDIA_LINE" | awk -F',' '{gsub(/^ +| +$/,"",$3); print $3}')
            VRAM_GB=$(awk -v m="$VRAM_MB" 'BEGIN { printf "%.1f", m/1024 }')
            BACKEND="cuda"
            NOTE="NVIDIA $GPU_NAME / CUDA ${CC:-unknown} / ${VRAM_GB} GB VRAM"
        fi
    fi

    # AMD ROCm
    if [[ "$BACKEND" == "cpu" && -e /dev/kfd ]]; then
        if command -v rocm-smi >/dev/null 2>&1; then
            GPU_NAME=$(rocm-smi --showproductname 2>/dev/null | awk -F': ' '/GPU\[/{print $2; exit}' | xargs 2>/dev/null || true)
            [[ -z "$GPU_NAME" ]] && GPU_NAME="AMD GPU"
            VRAM_BYTES=$(rocm-smi --showmeminfo vram 2>/dev/null | awk -F': ' 'tolower($1) ~ /total/ {gsub(/[^0-9]/,"",$2); print $2; exit}' || true)
            if [[ -n "${VRAM_BYTES:-}" && "$VRAM_BYTES" =~ ^[0-9]+$ ]]; then
                VRAM_GB=$(awk -v b="$VRAM_BYTES" 'BEGIN { if (b > 1000000000) printf "%.1f", b/1073741824; else printf "%.1f", b/1024 }')
            fi
            BACKEND="rocm"
            NOTE="AMD $GPU_NAME / ROCm / ${VRAM_GB} GB VRAM"
        else
            GPU_NAME="AMD GPU"
            BACKEND="rocm"
            NOTE="AMD GPU / ROCm detected (/dev/kfd)"
        fi
    fi

    # Vulkan (Intel / AMD / NVIDIA fallback). Only choose the Vulkan build
    # when a Vulkan loader/ICD is actually present, otherwise the binary
    # cannot start; CPU is the safe fallback.
    HAS_VULKAN="false"
    if command -v vulkaninfo >/dev/null 2>&1; then
        HAS_VULKAN="true"
    elif ls /usr/share/vulkan/icd.d/*.json /etc/vulkan/icd.d/*.json >/dev/null 2>&1; then
        HAS_VULKAN="true"
    fi
    if [[ "$BACKEND" == "cpu" && "$HAS_VULKAN" == "true" ]] && command -v lspci >/dev/null 2>&1; then
        GPU_LINE=$(lspci 2>/dev/null | grep -Ei 'vga compatible|3d controller|display controller' | head -1 || true)
        if [[ -n "$GPU_LINE" ]]; then
            GPU_NAME=$(echo "$GPU_LINE" | sed -E 's/^[^:]+: [^:]+: //' | xargs 2>/dev/null || echo "GPU")
            BACKEND="vulkan"
            NOTE="$GPU_NAME / Vulkan"
        fi
    fi

    # CPU feature note
    if [[ "$BACKEND" == "cpu" ]]; then
        if [[ "$CPU_FEATURES" == *avx512f* ]]; then
            NOTE="CPU only ($CPU_NAME, AVX-512, $THREADS threads)"
        elif [[ "$CPU_FEATURES" == *avx2* ]]; then
            NOTE="CPU only ($CPU_NAME, AVX2, $THREADS threads)"
        else
            NOTE="CPU only ($CPU_NAME, $THREADS threads)"
        fi
    fi
fi

# ── Layer offload heuristics ─────────────────────────────────────
# Rough layer counts for common model sizes. llama.cpp clamps -ngl to the
# real layer count, so these only exist to express *partial* offload.
# (999 is the "all layers" sentinel.)
NGL=0
TOTAL_LAYERS=$(awk -v m="$MODEL_GB_NUM" 'BEGIN{
    if (m > 70) print 96
    else if (m > 45) print 80
    else if (m > 30) print 64
    else if (m > 22) print 60
    else if (m > 15) print 48
    else if (m > 9) print 40
    else print 32
}')
case "$BACKEND" in
    cuda|rocm)
        if [[ "$VRAM_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] && (( $(awk -v v="$VRAM_GB" -v m="$MODEL_GB_NUM" 'BEGIN{print (v>=m*0.95)?1:0}') )); then
            NGL=999
        elif [[ "$VRAM_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] && (( $(awk -v v="$VRAM_GB" 'BEGIN{print (v>0)?1:0}') )); then
            # Reserve ~1 GB of VRAM for the KV cache and compute buffers.
            NGL=$(awk -v v="$VRAM_GB" -v m="$MODEL_GB_NUM" -v t="$TOTAL_LAYERS" 'BEGIN{
                u = v - 1.0; if (u < 0) u = 0
                r = u / m; if (r > 1) r = 1
                n = int(t * r)
                if (n >= t) n = 999
                print n
            }')
        else
            NGL=999
        fi
        ;;
    metal)
        NGL=999
        ;;
    vulkan)
        if [[ "$GPU_NAME" == *"Intel"* || "$GPU_NAME" == *"UHD"* || "$GPU_NAME" == *"Iris"* ]]; then
            NGL=$(( TOTAL_LAYERS < 24 ? TOTAL_LAYERS : 24 ))
        else
            NGL=999
        fi
        ;;
    *)
        NGL=0
        ;;
esac

# Overrides from .env (already exported by the launcher)
[[ "${LLAMACPP_NGL:-}" =~ ^[0-9]+$ ]] && NGL="$LLAMACPP_NGL"
if [[ "${LLAMACPP_THREADS:-}" =~ ^[0-9]+$ ]]; then THREADS="$LLAMACPP_THREADS"; fi
if [[ "${LLAMACPP_CTX:-}" =~ ^[0-9]+$ ]]; then
    CTX="$LLAMACPP_CTX"
elif [[ "$RAM_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] && (( $(awk -v r="$RAM_GB" 'BEGIN{print (r>0 && r<=8)?1:0}') )); then
    CTX=2048
elif [[ "$RAM_GB" =~ ^[0-9]+([.][0-9]+)?$ ]] && (( $(awk -v r="$RAM_GB" 'BEGIN{print (r>=32)?1:0}') )); then
    CTX=8192
fi

[[ "${AUTO_TUNE:-1}" == "0" || "${AUTO_TUNE:-1}" == "false" ]] && NOTE="$NOTE (auto-tune disabled)"

VARIANT="cpu"
case "$BACKEND" in
    cuda) VARIANT="cuda" ;;
    rocm) VARIANT="rocm" ;;
    vulkan) VARIANT="vulkan" ;;
    metal) VARIANT="metal" ;;
    *) VARIANT="cpu" ;;
esac

# ── Output ──────────────────────────────────────────────────────
json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/ }
    s=${s//$'\r'/ }
    printf '%s' "$s"
}

if [[ "$FORMAT" == "json" ]]; then
    printf '{"PENDRIVE_ACCEL":"%s","PENDRIVE_GPU_NAME":"%s","PENDRIVE_VRAM_GB":"%s","PENDRIVE_NGL":%s,"PENDRIVE_THREADS":%s,"PENDRIVE_CTX":%s,"PENDRIVE_RAM_GB":"%s","PENDRIVE_CPU":"%s","PENDRIVE_LLAMACPP_VARIANT":"%s","PENDRIVE_ACCEL_NOTE":"%s"}\n' \
        "$(json_escape "$BACKEND")" "$(json_escape "$GPU_NAME")" "$VRAM_GB" "$NGL" "$THREADS" "$CTX" \
        "$RAM_GB" "$(json_escape "$CPU_NAME")" "$VARIANT" "$(json_escape "$NOTE")"
else
    printf 'PENDRIVE_ACCEL=%q\n' "$BACKEND"
    printf 'PENDRIVE_GPU_NAME=%q\n' "$GPU_NAME"
    printf 'PENDRIVE_VRAM_GB=%q\n' "$VRAM_GB"
    printf 'PENDRIVE_NGL=%q\n' "$NGL"
    printf 'PENDRIVE_THREADS=%q\n' "$THREADS"
    printf 'PENDRIVE_CTX=%q\n' "$CTX"
    printf 'PENDRIVE_RAM_GB=%q\n' "$RAM_GB"
    printf 'PENDRIVE_CPU=%q\n' "$CPU_NAME"
    printf 'PENDRIVE_LLAMACPP_VARIANT=%q\n' "$VARIANT"
    printf 'PENDRIVE_ACCEL_NOTE=%q\n' "$NOTE"
fi
