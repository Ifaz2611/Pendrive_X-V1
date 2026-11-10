# Pendrive_X — Portable AI on a USB Drive

**A fully private, portable, uncensored AI assistant that runs 100% from a USB flash drive.** No internet required after setup. No data leaves the drive. Works on **Windows**, **macOS**, and **Linux**.

> **6 curated models + custom GGUF support.** Pick one small model for old laptops or load them all on a 64 GB stick.

---

## Table of Contents

- [Features](#features)
- [Available Models](#available-models)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Inference Engines & `.env`](#inference-engines--env)
- [Detailed Setup](#detailed-setup)
- [How to Run](#how-to-run)
- [LAN / Phone Mode](#lan--phone-mode)
- [Updating Engines & UI](#updating-engines--ui)
- [USB Drive Layout](#usb-drive-layout)
- [Switching Models](#switching-models)
- [Token Limit / Context Size](#token-limit--context-size)
- [Privacy & Portability](#privacy--portability)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

- **100% offline after install** — downloads once, runs forever without internet.
- **Zero host footprint** — no registry keys, no `AppData` leftovers, no admin required.
- **Cross-platform** — native launchers for Windows (`.bat`), macOS (`.command`), and Linux (`.sh`).
- **Multi-model** — install 1–6 presets or bring any HuggingFace `GGUF` URL.
- **Dual inference engine** — choose **Ollama** or **standalone llama.cpp** (`llama-server`) in `.env`. llama.cpp skips Ollama's background service and saves ~1.5–2 GB RAM.
- **Hardware auto-tuning** — detects NVIDIA CUDA, AMD ROCm, Intel/AMD Vulkan, Apple Metal, and AVX2/AVX-512 CPUs, then picks layer offload, threads, and context size.
- **LAN / phone mode** — `--server` binds the engine to the LAN and prints a terminal QR code so a phone or tablet can connect over Wi-Fi.
- **In-place engine updater** — `--update-engine` refreshes engines and the UI from `versions.env` without touching GGUF models or chat databases.
- **Idempotent installer** — re-run to add models; already-downloaded files are skipped.
- **Safe shutdown** — PID-tracked engine + AnythingLLM, no orphan processes on the host.
- **Health checks** — launchers poll the engine's health endpoint instead of blind `sleep`.

---

## Available Models

Choose during install (interactive menu: `1,3` or `all` or `1,c` for custom).

| # | Model | Size | Label | Strength |
|---|-------|------|-------|----------|
| 1 | **NemoMix Unleashed 12B** (`Q5_K_M`) | ~8.73 GB | `UNCENSORED` | Recommended — best uncensored quality |
| 2 | **Dolphin 2.9 Llama 3 8B** (`Q4_K_M`) | ~4.9 GB | `UNCENSORED` | Classic all-rounder |
| 3 | **Mistral 7B Instruct v0.3** | ~4.1 GB | `STANDARD` | Strong reasoning & coding |
| 4 | **Qwen 2.5 7B Instruct** | ~4.7 GB | `STANDARD` | Multilingual |
| 5 | **Llama 3.2 3B Instruct** | ~2.0 GB | `STANDARD` | Lightweight — fast on old PCs |
| 6 | **Phi-3.5 Mini 3.8B** | ~2.2 GB | `STANDARD` | Lightweight — good reasoning |
| C | **Custom GGUF** | varies | `CUSTOM` | Paste any `https://huggingface.co/.../resolve/.../*.gguf` |

> `UNCENSORED` = no content filters. `STANDARD` = normal safety guidelines.

Update the catalog in `models/catalog.json` (single source) or `install-core.ps1:42` / `linux/install-core.sh:80` if you need a different quantization. Pinned engine URLs in `versions.env`.

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| USB size (1 lightweight model) | 16 GB exFAT | 16 GB |
| USB size (NemoMix 12B) | 16 GB | 32 GB |
| USB size (2–3 models) | 32 GB | 64 GB |
| USB size (all 6 presets ≈ 26 GB + engine 1 GB) | 64 GB | 64 GB |
| RAM (3B models) | 6 GB | 8 GB |
| RAM (7B models) | 8 GB | 16 GB |
| RAM (12B NemoMix) | 12 GB | 16 GB |
| CPU | x64, any modern | x64 with 4+ cores |
| Filesystem | **exFAT** (or ext4/NTFS) | exFAT — required for >4 GB files; FAT32 will fail |
| Network | Internet for first install only | — |

> **USB must be `exFAT`.** FAT32 has a 4 GB per-file limit and will corrupt the 7–8 GB GGUF downloads. The Linux `preflight-check.sh` detects this automatically. On Windows, right-click the drive → Format → `exFAT`.

---

## Quick Start

### Windows

1. Copy **all files** from this repo to the **root of your USB** (not a subfolder).
2. Double-click **`install.bat`** → pick models (e.g. `1` or `1,3` or `all`).
3. When the **AnythingLLM installer** pops up, click **Browse** and select `E:\anythingllm` (your USB path). Wait, then close it.
4. Done. Launch with **`start-windows.bat`** (or `optimiced.bat` for the hardened launcher).

### macOS

1. Copy all files to USB root.
2. Double-click **`start-mac.command`** — first run auto-downloads the macOS Ollama engine (~150 MB) and AnythingLLM (`AnythingLLMDesktop-Silicon.dmg`) directly to the USB. No Mac installation.
3. To pre-install models on a Mac, use a Windows/Linux PC first, or run `bash linux/install-core.sh` inside a Linux VM pointing at the mounted USB.

### Linux

```bash
# 1. Make scripts executable
chmod +x linux/preflight-check.sh linux/install.sh linux/install-core.sh linux/start-linux.sh

# 2. Validate the drive (checks space, FS, speed, removable detection)
bash linux/preflight-check.sh          # auto-detects USB
# or
bash linux/preflight-check.sh /media/$USER/MYUSB

# 3. Install (preflight launches this automatically if you confirm)
bash linux/install.sh
# or directly:
bash linux/install-core.sh /media/$USER/MYUSB

# 4. Launch
bash linux/start-linux.sh
```

Non-interactive install examples:

```bash
# Ollama, models 1 and 3
bash linux/install-core.sh /media/$USER/MYUSB --engine ollama --models 1,3 --yes

# llama.cpp only, recommended 12B model
bash linux/install-core.sh /media/$USER/MYUSB --engine llamacpp --models 1 --yes
```

On Windows the same flags work through `install.bat`:

```bat
install.bat --engine=llamacpp --models 1 --yes
install.bat --update-engine
install.bat --update-engine=anythingllm
```

---

## Inference Engines & `.env`

Every launcher reads `<USB>/.env` (created from `.env.example` on first install).
Change a value there and relaunch; no reinstall is needed.

| Key | Default | Meaning |
|-----|---------|---------|
| `INFERENCE_ENGINE` | `ollama` | `ollama` or `llamacpp` (`llama-server`) |
| `AUTO_TUNE` | `1` | Detect GPU/CPU and tune layer offload, threads, context |
| `SERVER_MODE` | `0` | `1` binds to `0.0.0.0` (same as `--server` for one session) |
| `OLLAMA_PORT` / `LLAMACPP_PORT` | `0` | `0` = pick a free port automatically |
| `LAN_CHAT_PORT` | `8090` | Mobile chat page used by the Ollama LAN proxy |
| `LLAMACPP_MODEL` | empty | Model alias or `.gguf` filename; empty = first installed |
| `LLAMACPP_NGL` / `LLAMACPP_THREADS` / `LLAMACPP_CTX` | `auto` | Manual tuning overrides |
| `LLAMACPP_VARIANT` | `auto` | `auto`, `cuda`, `rocm`, `vulkan`, or `cpu` build |
| `LLAMACPP_EXTRA_ARGS` | empty | Extra `llama-server` flags, e.g. `--flash-attn --no-mmap` |
| `OLLAMA_KEEP_ALIVE` / `OLLAMA_NUM_PARALLEL` | `30m` / `1` | Ollama runtime tuning |

Command-line overrides:

```bat
start-windows.bat --engine=llamacpp --model=qwen-local
start-windows.bat --server
start-windows.bat --server --headless
```

```bash
bash linux/start-linux.sh --engine=llamacpp --model=qwen-local
bash linux/start-linux.sh --server
```

- **Ollama mode** keeps the existing AnythingLLM `LLM_PROVIDER=ollama` setup.
- **llama.cpp mode** configures AnythingLLM with `LLM_PROVIDER=generic-openai`,
  `GENERIC_OPEN_AI_BASE_PATH=http://127.0.0.1:<port>/v1`, and the dummy key
  `sk-no-key`. `llama-server` reads GGUF files directly from `models/`, so no
  Ollama import step is required.
- Engine binaries live in `llamacpp/` and are downloaded from pinned URLs in
  `versions.env`; the installer picks CUDA/Vulkan/ROCm/CPU/Metal automatically.

---

## Detailed Setup

### What the installer does (6 numbered steps, plus hardware profile)

1. **Model selection** — interactive menu, supports `1,3`, `all`, `c`/`custom`, and mixes like `1,3,c`.
2. **Folder creation** — `models/`, `ollama/`, `llamacpp/`, `anythingllm/`, `anythingllm_data/`, `installer_data/`, plus `.env`.
3. **Model downloads** — `curl` with `--retry 2` to temp `.part` files, verified by minimum byte size before `mv`.
4. **Modelfiles** — generates `models/Modelfile-<localName>` per model + legacy `models/Modelfile` + `installed-models.txt`.
5. **Inference engine** — installs Ollama (`ollama/` or `ollama_mac/`) and/or portable `llama-server` in `llamacpp/` for the selected `--engine`. llama.cpp URLs are pinned in `versions.env`.
6. **AnythingLLM UI** — Windows: prompts manual install to USB; Linux: AppImage; macOS: DMG extracted to `anythingllm_mac/`. The LLM provider is configured for the selected engine.
7. **Hardware profile** — detection results are saved to `installer_data/hardware.json`; launchers re-detect on every start.

Re-running the installer **never re-downloads** valid files (`file_is_valid` / `Test-DownloadedFile` checks). Use it to add models later.

### If a download fails

The script retries once automatically. If it still fails:

1. Copy the HuggingFace `.../resolve/main/*.gguf` URL shown in the error.
2. Download manually (browser or `curl -L -o models/file.gguf URL`).
3. Place the `.gguf` in `models/` on the USB.
4. Re-run `install.bat` / `install-core.sh` — it will detect and skip it.

### Custom models

Pick `C` at the menu, paste a direct `.gguf` URL, give a short name (auto-suffixed `-local`), and optionally a system prompt. Validation warns if URL lacks `.gguf` but lets you proceed with confirmation.

---

## How to Run

### Windows (`start-windows.bat`)

- Reads `<USB>\.env`, applies `--engine`, `--model`, `--server`, and `--update-engine` overrides.
- Detects hardware through `tools\hardware.ps1` and starts the engine through `tools\start-engine.ps1` (Ollama `serve` or `llama-server` with CUDA/Vulkan tuning).
- Clears **only** `anythingllm-desktop/GPUCache|Cache|Code Cache|ShaderCache` (never `config.json`).
- Captures the engine PID, polls `/health` (llama.cpp) or `/api/tags` (Ollama), stores PIDs in `anythingllm_data\.session_pids`.
- Rewrites only the LLM keys in `anythingllm_data\storage\.env` and preserves a custom token limit.
- Launches `AnythingLLM.exe --user-data-dir="%USB%\anythingllm_data"`.
- **Keep the black terminal open.** Press any key to shut down — kills only PIDs from this USB, never a host Ollama.

Alternative hardened launcher: **`optimiced.bat`** (Spanish UI, Ollama-focused).

### macOS (`start-mac.command`)

- First run: downloads the selected engine (Ollama `ollama-darwin.zip` or llama.cpp Metal) to `ollama_mac/` / `llamacpp/`, and `AnythingLLMDesktop-Silicon.dmg` → `anythingllm_mac/AnythingLLM.app` via `hdiutil attach`.
- Uses Apple Silicon unified memory for auto-tuning (`-ngl 999`, context scaled to RAM).
- Finds a free port via `nc -z` / `lsof` / Python socket fallback (not `/dev/tcp`, which is absent on macOS).
- Sets `OLLAMA_MODELS`, `XDG_*_HOME` to USB paths, polls the engine health endpoint, clears hardware caches, launches `Contents/MacOS/AnythingLLM --user-data-dir=...`.
- `trap cleanup` on EXIT/INT/TERM/HUP.

### Linux (`linux/start-linux.sh`)

- Mirrors the macOS pattern with `tools/common.sh`: `.env` loading, engine selection, hardware auto-tuning (CUDA/ROCm/Vulkan/AVX2/AVX-512), free-port scan, health poll.
- AppImage launch with `FUSE` detection + `APPIMAGE_EXTRACT_AND_RUN` fallback, `renice -n -1`.
- llama.cpp uses the standalone `llamacpp/llama-server` binary; no Ollama background service is started.

---

## LAN / Phone Mode

Use `--server`, `--lan`, or `--headless` to bind the engine to `0.0.0.0` and
reach it from another device on the same Wi-Fi:

```bat
start-windows.bat --server
start-windows.bat --headless        :: no desktop UI
start-windows.bat --server --with-ui
```

```bash
bash linux/start-linux.sh --server
./start-mac.command --lan
```

- **llama.cpp** serves its built-in web UI at `http://<LAN-IP>:<port>/`.
- **Ollama** starts a lightweight mobile chat page (`tools/lan-chat.py` /
  `tools/lan-chat.ps1`) on `LAN_CHAT_PORT` because Ollama itself has no web UI.
- The terminal prints the LAN URL and a QR code (via `qrencode` when available,
  otherwise the bundled Python/PowerShell renderer). Scan it with a phone camera.
- LAN mode exposes the engine to your local network only. Do not use it on
  untrusted Wi-Fi; there is no authentication layer.

---

## Updating Engines & UI

`--update-engine` refreshes only the installed engine binaries and AnythingLLM.
Models, `ollama/data`, and `anythingllm_data/` (chats and settings) are never
modified.

```bat
install.bat --update-engine
install.bat --update-engine=ollama
install.bat --update-engine=anythingllm
install.bat --update-engine=llamacpp
start-windows.bat --update-engine
```

```bash
bash linux/install-core.sh /path/to/usb --update-engine
bash linux/start-linux.sh --update-engine=llamacpp
./start-mac.command --update-engine=all
```

Bump the pinned versions in `versions.env` to choose what "latest" means for
your drive. `all` skips components that are not installed, so a llama.cpp-only
USB does not download Ollama.

---

## USB Drive Layout

**Windows** (after successful install):

```
E:\
├── .env                        ← runtime config (engine, ports, tuning)
├── .env.example                ← documented defaults
├── install.bat                 ← Windows installer entry
├── install-core.ps1            ← Core logic (called by install.bat)
├── start-windows.bat           ← Main Windows launcher
├── optimiced.bat               ← Hardened alt launcher (Ollama-focused)
├── start-mac.command           ← macOS launcher (works from same USB)
├── versions.env                ← pinned Ollama / AnythingLLM / llama.cpp
├── tools/                      ← shared helpers (hardware, QR, updater, LAN chat)
│   ├── common.sh               ← shared macOS/Linux helpers
│   ├── hardware.sh / .ps1      ← acceleration auto-tuning
│   ├── install-llamacpp.sh/.ps1
│   ├── update-engine.sh/.ps1
│   ├── start-engine.ps1
│   ├── config-anythingllm.ps1
│   ├── lan-chat.py / .ps1
│   └── qr.py / qr.ps1
├── linux/                      ← Linux scripts (also usable from Windows USB)
│   ├── install.sh
│   ├── install-core.sh
│   ├── preflight-check.sh
│   └── start-linux.sh
├── ollama/                     ← Windows/Linux Ollama engine
│   ├── ollama.exe (or ollama)
│   └── data/                   ← Ollama model storage (OLLAMA_MODELS)
├── ollama_mac/                 ← macOS Ollama engine
├── llamacpp/                   ← portable llama-server + DLLs/libraries
├── models/
│   ├── *.gguf                  ← Model weights
│   ├── Modelfile-<localName>   ← Per-model configs
│   ├── Modelfile               ← Legacy alias → first model
│   └── installed-models.txt    ← "local|Display Name|LABEL" per line
├── anythingllm/                ← Windows AnythingLLM install
├── anythingllm_mac/            ← macOS AnythingLLM.app
├── anythingllm_data/           ← ALL chats, settings, caches (portable!)
│   ├── storage/.env            ← LLM provider + model settings
│   ├── config/  data/  cache/  ← XDG dirs (Linux/macOS)
│   └── anythingllm-desktop/    ← Electron profile + GPU caches
└── installer_data/             ← Temp files, logs, hardware.json (auto-cleaned)
```

**Linux/macOS** paths are identical except `ollama_mac/` and `anythingllm_mac/` are used instead of `ollama/` + `anythingllm/`.

---

## Switching Models

- **Ollama:** AnythingLLM → **Settings → LLM Provider → Ollama → Model** — pick any `*-local` alias from `models/installed-models.txt`, or override the default with `--model=<alias>`.
- **llama.cpp:** set `LLAMACPP_MODEL=<alias or file.gguf>` in `.env`, or launch with `--model=qwen-local`. AnythingLLM's model preference is updated automatically to the selected alias.

The first installed model is used when no explicit selection is made. UI changes persist across restarts.

---

## Token Limit / Context Size

Default is `4096` tokens (good for 6–8 GB RAM). To increase:

1. Close the launcher.
2. Open `anythingllm_data/storage/.env` on the USB in a text editor.
3. Change `OLLAMA_MODEL_TOKEN_LIMIT=4096` → e.g. `8192` or `16384`.
   In llama.cpp mode the equivalent keys are
   `GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT` and `GENERIC_OPEN_AI_MAX_TOKENS`.
4. Save and relaunch via `start-windows.bat` / `start-mac.command` / `linux/start-linux.sh`.

> **Preservation fix:** launchers now **preserve** a custom token limit instead
> of blindly overwriting it on every start, and only rewrite the LLM provider keys.

Re-running the *installer* (`install.bat` / `install-core.sh`) will still honor the existing `.env` if it already points at `ollama`; delete `.env` to force a reset.

---

## Privacy & Portability

- `STORAGE_DIR`, `APPDATA`, `LOCALAPPDATA`, `XDG_*` all point at `anythingllm_data/` on the USB.
- Electron is launched with `--user-data-dir=<USB>\anythingllm_data` — nothing under `%APPDATA%` or `~/Library/Application Support` on the host.
- `ollama/data` lives on the USB (`OLLAMA_MODELS`); llama.cpp reads `models/*.gguf` directly.
- Moving between PCs: hardware caches (`GPUCache`, `ShaderCache`, etc.) are wiped on launch to avoid `ENOENT` / GPU mismatch errors. Your chats and model settings stay intact.
- LAN/phone mode is opt-in. When enabled, the engine and chat page listen on all interfaces; there is no built-in authentication, so only use it on a trusted network.
- **Always eject safely** after the shutdown message appears.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| `FAT32 — 4 GB per-file limit will block` | Reformat USB as **exFAT** (Windows: right-click → Format → exFAT). |
| `No usable USB drive selected` (preflight) | Ensure USB is **mounted**; pass path explicitly: `bash linux/preflight-check.sh /media/$USER/USB`. |
| `File seems too small (… MB)` then `ERROR: Download failed` | Partial download — check free space, retry, or manual download to `models/`. |
| `AnythingLLM.exe not found` | Re-run `install.bat` and when prompted, **Browse → `E:\anythingllm`** (not `C:\Program Files`). |
| `Ollama failed to start on port …` / `Timeout` | Host Ollama already on 11434; launcher tries 11434–11534 but may collide if all busy. Close host Ollama or reboot. Check firewall. |
| `llama-server was not found` | Run `install.bat --engine=llamacpp` (or `--update-engine=llamacpp`) once with internet. |
| llama.cpp exits immediately / GPU error | Set `LLAMACPP_VARIANT=cpu` in `.env`, then `--update-engine=llamacpp`, or update your GPU driver. |
| Phone cannot open the LAN URL | Confirm both devices are on the same Wi-Fi, allow the port through the host firewall, and avoid guest/AP-isolated networks. |
| No QR code in terminal | Install `qrencode`, or keep Python 3 available — the bundled `tools/qr.py` / `tools/qr.ps1` renderer is used otherwise. The URL is always printed. |
| `JavaScript error ENOENT` on new PC | Fixed in this revision — launcher wipes only GPU/Shader caches. Re-run `start-windows.bat`. |
| `FUSE launch failed` on Linux | AppImage fallback is automatic (`APPIMAGE_EXTRACT_AND_RUN=1`). Install `fuse3` / `libfuse2` for native speed, or keep extract-and-run. |
| `xargs: kill: No such process` on macOS exit | Fixed — now uses `xargs -r`. |
| Slow writes / AI loads 30+ s | USB 2.0 stick in USB 2.0 port. Use USB 3.0 drive in a blue USB 3.0 port. Check `preflight-check.sh` benchmark. |
| Nothing happens double-clicking `.command` on Mac | Right-click → Open, or `chmod +x start-mac.command` then double-click. Gatekeeper: `xattr -rc anythingllm_mac/AnythingLLM.app` is done automatically. |
| Need diagnostics | Run `doctor.bat` (Windows) or `bash doctor.sh` (Linux/macOS) — checks FS, RAM, models, ports, logs. |

---

## License

Apache 2.0 — see [LICENSE](LICENSE).

```
Copyright ©️ All Right Reserved @Ifaz Md Zahin
```

---

```
                                   |
                                  |||
                                 |||||
                   |    |    |   |||||||
                  )_)  )_)  )_)   ~|~
                 )___))___))___)\  |
                )____)____)_____)\\|
              _____|____|____|_____\\\__
              \                       /
        ~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~
                ~^~  Welcome aboard!  ~^~
        ~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~~^~^~
```
