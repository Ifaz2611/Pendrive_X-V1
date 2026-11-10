# Pendrive_X — Portable AI on a USB Drive

A private AI assistant that runs entirely from a USB flash drive. No internet needed after setup, no data leaves the drive. Works on **Windows**, **macOS**, and **Linux**.

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![License](https://img.shields.io/badge/license-Apache%202.0-green)

---

## Features

- **100% offline after install** — download once, run forever.
- **Zero host footprint** — no registry keys, no `AppData` leftovers, no admin required.
- **6 curated models + custom GGUF** — small models for old laptops, big models for 64 GB sticks.
- **Two inference engines** — Ollama (easy) or llama.cpp `llama-server` (saves ~1.5–2 GB RAM).
- **Hardware auto-tuning** — detects NVIDIA CUDA, AMD ROCm, Intel/AMD Vulkan, Apple Metal, AVX2/AVX-512.
- **LAN / phone mode** — share the AI to phones and tablets over Wi-Fi with a QR code.
- **Idempotent installer** — re-run it anytime to add models; existing files are skipped.
- **Safe shutdown** — PID-tracked; only kills processes started from the USB.

---

## Available Models

Pick during install (`1`, `1,3`, `all`, or `c` for custom). Catalog lives in `models/catalog.json`.

| # | Model | Size | Type | Strength |
|---|-------|------|------|----------|
| 1 | NemoMix Unleashed 12B (Q5_K_M) | ~8.7 GB | `UNCENSORED` | Best quality — recommended |
| 2 | Dolphin 2.9 Llama 3 8B | ~4.9 GB | `UNCENSORED` | Classic all-rounder |
| 3 | Mistral 7B Instruct v0.3 | ~4.1 GB | `STANDARD` | Reasoning & coding |
| 4 | Qwen 2.5 7B Instruct | ~4.7 GB | `STANDARD` | Multilingual |
| 5 | Llama 3.2 3B Instruct | ~2.0 GB | `STANDARD` | Lightweight, fast |
| 6 | Phi-3.5 Mini 3.8B | ~2.2 GB | `STANDARD` | Lightweight, good reasoning |
| C | Custom GGUF URL | varies | `CUSTOM` | Any HuggingFace `.gguf` link |

`UNCENSORED` = no content filters. `STANDARD` = normal safety guidelines.

---

## System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| USB size (1 small model) | 16 GB exFAT | 32 GB |
| USB size (all 6 models ≈ 26 GB) | 64 GB | 64 GB |
| RAM (3B models) | 6 GB | 8 GB |
| RAM (7–12B models) | 8 GB | 16 GB |
| CPU | x64 | x64, 4+ cores |
| Filesystem | **exFAT** / NTFS / ext4 | exFAT |
| Network | Internet for first install only | — |

> **exFAT is required** — FAT32 has a 4 GB per-file limit and will fail on the 7–8 GB GGUF downloads.

---

## Quick Start

**New here? Follow [`GET-STARTED.md`](GET-STARTED.md) — it's the step-by-step beginner guide.**

The short version:

| OS | Install | Launch |
|----|---------|--------|
| Windows | `install.bat` | `start-windows.bat` |
| Linux | `bash linux/install.sh` | `bash linux/start-linux.sh` |
| macOS | `./start-mac.command` (auto-installs on first run) | `./start-mac.command` |

Alternative launchers: `optimiced.bat` (hardened, Ollama-focused, Spanish UI), `doctor.bat` / `doctor.sh` (diagnostics).

---

## Inference Engines & `.env`

Every launcher reads `<USB>/.env` (created from `.env.example`). Edit it and relaunch — no reinstall needed.

| Key | Default | Meaning |
|-----|---------|---------|
| `INFERENCE_ENGINE` | `ollama` | `ollama` or `llamacpp` |
| `AUTO_TUNE` | `1` | Auto-detect GPU/CPU tuning |
| `SERVER_MODE` | `0` | `1` = bind to LAN permanently |
| `OLLAMA_PORT` / `LLAMACPP_PORT` | `0` | `0` = pick a free port |
| `LAN_CHAT_PORT` | `8090` | Mobile chat page for Ollama LAN mode |
| `LLAMACPP_MODEL` | empty | Alias or `.gguf` filename; empty = first installed |
| `LLAMACPP_NGL` / `LLAMACPP_THREADS` / `LLAMACPP_CTX` | `auto` | Manual tuning overrides |
| `LLAMACPP_VARIANT` | `auto` | `auto`, `cuda`, `rocm`, `vulkan`, `cpu` |
| `LLAMACPP_EXTRA_ARGS` | empty | Extra `llama-server` flags |

CLI overrides:

```bat
start-windows.bat --engine=llamacpp --model=qwen-local --server
```

```bash
bash linux/start-linux.sh --engine=llamacpp --server
```

- **Ollama mode** — AnythingLLM uses `LLM_PROVIDER=ollama`.
- **llama.cpp mode** — AnythingLLM uses `LLM_PROVIDER=generic-openai` pointed at `llama-server`, which reads GGUF files directly from `models/` (no import step). Binaries live in `llamacpp/`, downloaded from pinned URLs in `versions.env`.

---

## Detailed Setup (what the installer does)

1. **Model selection** — interactive menu: `1,3`, `all`, `c`/`custom`, or mixes like `1,3,c`.
2. **Folder creation** — `models/`, `ollama/`, `llamacpp/`, `anythingllm/`, `anythingllm_data/`, `installer_data/`, `.env`.
3. **Model downloads** — `curl` with retries to `.part` files, verified by size before finalizing.
4. **Modelfiles** — one `models/Modelfile-<name>` per model + `installed-models.txt`.
5. **Engine install** — Ollama and/or portable `llama-server` per `--engine`.
6. **AnythingLLM UI** — Windows: manual install to USB; Linux: AppImage; macOS: DMG → `anythingllm_mac/`.
7. **Hardware profile** — saved to `installer_data/hardware.json`; re-detected on every launch.

Re-running the installer **never re-downloads** valid files. If a download fails: copy the HuggingFace URL, download manually to `models/`, re-run — it detects and skips it.

Non-interactive examples:

```bat
install.bat --engine=llamacpp --models 1 --yes
install.bat --update-engine
```

```bash
bash linux/install-core.sh /media/$USER/MYUSB --engine ollama --models 1,3 --yes
bash linux/preflight-check.sh        # validates FS, space, speed before install
```

---

## How to Run

Keep the launcher terminal **open** while using the AI — it runs the engine and AnythingLLM. Press any key (Windows) or Enter (Linux/macOS) to shut down cleanly; only PIDs started from this USB are killed.

- **`start-windows.bat`** — reads `.env`, auto-tunes hardware, wipes GPU caches, polls engine health, launches `AnythingLLM.exe --user-data-dir=<USB>\anythingllm_data`.
- **`start-mac.command`** — first run downloads the macOS engine + AnythingLLM directly to USB; Apple Silicon unified memory for tuning.
- **`linux/start-linux.sh`** — mirrors macOS: `.env`, CUDA/ROCm/Vulkan/AVX tuning, AppImage with FUSE fallback.

---

## LAN / Phone Mode

```bat
start-windows.bat --server        :: or --lan / --headless / --with-ui
```

```bash
bash linux/start-linux.sh --server
./start-mac.command --lan
```

- Prints a LAN URL + QR code (scan with phone camera).
- llama.cpp serves its built-in web UI; Ollama uses `tools/lan-chat.py` on `LAN_CHAT_PORT`.
- **No authentication** — trusted networks only.

---

## Updating Engines & UI

`--update-engine` refreshes engine binaries and AnythingLLM only — models, `ollama/data`, and `anythingllm_data/` (chats/settings) are never touched.

```bat
install.bat --update-engine=llamacpp
start-windows.bat --update-engine=all
```

```bash
bash linux/start-linux.sh --update-engine=anythingllm
./start-mac.command --update-engine=all
```

Pin versions in `versions.env` to control what "latest" means.

---

## USB Drive Layout

```
E:\
├── .env                  ← runtime config (engine, ports, tuning)
├── .env.example          ← documented defaults
├── install.bat / install-core.ps1   ← Windows installer
├── start-windows.bat / optimiced.bat ← Windows launchers
├── start-mac.command     ← macOS launcher
├── versions.env          ← pinned engine/UI versions
├── tools/                ← hardware detect, QR, engine start, LAN chat
├── linux/                ← Linux scripts (install, preflight, start)
├── ollama/  ollama_mac/  ← Ollama engines per OS
├── llamacpp/             ← portable llama-server + libs
├── models/               ← *.gguf, Modelfiles, installed-models.txt
├── anythingllm/  anythingllm_mac/   ← AnythingLLM app per OS
├── anythingllm_data/     ← ALL chats, settings, caches (fully portable)
└── installer_data/       ← temp files, logs, hardware.json
```

---

## Switching Models

- **Ollama:** AnythingLLM → Settings → LLM Provider → Ollama → pick a `*-local` alias.
- **llama.cpp:** set `LLAMACPP_MODEL=<alias or file.gguf>` in `.env`, or `--model=<alias>`.
- First installed model is the default. Model list: `models/installed-models.txt`.

---

## Token Limit / Context Size

Default `4096` tokens (safe for 6–8 GB RAM). To raise it: close the launcher, edit `anythingllm_data/storage/.env`, change `OLLAMA_MODEL_TOKEN_LIMIT` (or `GENERIC_OPEN_AI_MODEL_TOKEN_LIMIT` / `GENERIC_OPEN_AI_MAX_TOKENS` for llama.cpp), save, relaunch. Launchers now preserve custom values instead of overwriting them.

---

## Privacy & Portability

- `STORAGE_DIR`, `APPDATA`, `XDG_*`, `--user-data-dir` all point at `anythingllm_data/` on the USB — nothing touches the host.
- Model storage (`ollama/data`) and llama.cpp GGUF reads are on the drive.
- GPU caches are wiped on each launch to survive PC-to-PC moves; chats and settings persist.
- **Encrypt the drive** (BitLocker/VeraCrypt) if it holds sensitive chats.
- Always eject safely after the shutdown message.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `FAT32 — 4 GB limit` error | Reformat USB as exFAT |
| `AnythingLLM.exe not found` | Re-run installer; pick `E:\anythingllm` (not Program Files) |
| Ollama won't start / port busy | Close host Ollama; launcher scans 11434–11534 |
| `llama-server was not found` | Run `install.bat --engine=llamacpp` once online |
| llama.cpp crashes on GPU | Set `LLAMACPP_VARIANT=cpu` in `.env`, then `--update-engine=llamacpp` |
| Slow on old PC | Use model 5 or 6, token limit 4096, USB 3.0 port, free RAM |
| Phone can't connect | Same Wi-Fi, allow port in firewall, no AP isolation |
| Need diagnostics | `doctor.bat` (Windows) / `bash doctor.sh` (Linux, macOS) |

Full table in [`GET-STARTED.md`](GET-STARTED.md#troubleshooting).

---

## License

Apache 2.0 — see [LICENSE](LICENSE).

```
Copyright ©️ All Right Reserved @Ifaz Md Zahin
```
