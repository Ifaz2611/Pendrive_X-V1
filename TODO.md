# Pendrive_X AI — Development Roadmap & TODO

This document tracks upcoming architectural improvements, features, security hardenings, model catalog expansions, and tooling for the **Pendrive_X Portable AI** project.

---

## Phase 1: Engine & Architecture Enhancements

- [x] **Dual Inference Engine Support (`llama.cpp` / `llama-server`)**
  - Integrate standalone portable `llama-server` binaries for Windows (`llama-server.exe`), macOS (Metal), and Linux (CUDA/ROCm/CPU).
  - Provide a zero-overhead alternative to Ollama for low-RAM hosts (saves ~1.5–2 GB RAM and reduces cold-start latency).
  - Allow toggling backend in `.env` (`INFERENCE_ENGINE=ollama` vs `INFERENCE_ENGINE=llamacpp`).
  - Implementation: `tools/install-llamacpp.sh` / `.ps1`, pinned `LLAMACPP_*` URLs in `versions.env`, and `tools/start-engine.ps1` for Windows.

- [x] **In-Place Engine & UI Updater (`--update-engine`)**
  - Add an update flag to `install.bat`, `install-core.ps1`, `start-mac.command`, and `linux/install-core.sh`.
  - Downloads and extracts updated Ollama and AnythingLLM versions from `versions.env` without touching existing multi-gigabyte GGUF models or user chat databases.
  - Implementation: `tools/update-engine.sh` / `.ps1`; `all` refreshes only installed components and preserves `ollama/data` + `anythingllm_data/`.

- [x] **LAN / Headless Server Mode (`--server` / `--lan`)**
  - Add optional `--server` flag to launchers to bind Ollama and AnythingLLM web interfaces to `0.0.0.0` or local network IP.
  - Enable other devices on the same Wi-Fi/local network (phones, tablets, laptops) to access the USB AI via browser.
  - Include QR code generation in terminal for instant mobile browser connection (`qrencode` / PowerShell ANSI QR).
  - Implementation: `--server`/`--lan`/`--headless` flags, llama.cpp built-in web UI, mobile proxies (`tools/lan-chat.py` / `.ps1`), and bundled QR renderers (`tools/qr.py` / `.ps1`).

- [x] **Hardware Acceleration Auto-Tuning**
  - Windows: Auto-detect NVIDIA CUDA compute capability and Intel/AMD Vulkan devices, configuring layer offloading (`--n-gpu-layers`).
  - Linux: Detect NVIDIA drivers (`nvidia-smi`), AMD ROCm, or fallback to optimized AVX2/AVX-512 CPU flags.
  - macOS: Auto-tune Unified Memory allocations for Apple Silicon M1–M4 chips.
  - Implementation: `tools/hardware.ps1` / `hardware.sh`, consumed by all launchers; results saved to `installer_data/hardware.json`.

---

## Phase 2: Model Catalog & AI Capabilities Expansion

- [x] **Quantization Tier Selector**
  - Expand `models/catalog.json` with multi-quantization options per model:
    - `Q4_K_M`: Fast, standard memory footprint (default).
    - `Q5_K_M`: High accuracy / reasoning fidelity.
    - `Q8_0`: Maximum quality where 16GB+ RAM is available.
    - `Q2_K` / `IQ3_XXS`: Ultra-compact for low-end laptops (4GB RAM).
  - Implementation: Added multi-tier `quantizations` map to all catalog models, `-Quant` / `--quant` CLI flags, token syntax parsing (`<num>:<tier>`), and interactive tier selector menus across Windows and Linux/macOS installers.

- [x] **Vision & Multimodal Support**
  - Add Vision-capable presets to `models/catalog.json`:
    - `Llama-3.2-11B-Vision-Instruct-GGUF`
    - `Qwen2.5-VL-7B-Instruct-GGUF`
    - `Moondream2-GGUF` (compact ~1.8 GB for low-spec systems).
  - Ensure clip projector files (`mmproj-*.gguf`) are automatically downloaded and linked in Modelfiles.
  - Implementation: Added vision presets with clip projector metadata, automated `mmproj` download in Windows and Linux installers, generated dual `FROM` Modelfiles for Ollama, and wired `--mmproj` arguments into `start-windows.bat`, `tools/start-engine.ps1`, `linux/start-linux.sh`, and `start-mac.command`.

- [x] **Dedicated Embedding & Reranker Models for Local RAG**
  - Pre-configure lightweight embedding models on USB for fast local document ingestion:
    - `nomic-embed-text-v1.5-GGUF` (~270 MB)
    - `bge-small-en-v1.5-GGUF` (~130 MB)
    - `bge-reranker-v2-m3-GGUF`
  - Update AnythingLLM `.env` to leverage local Ollama embedding endpoints instead of native fallbacks.
  - Implementation: Added models 10-12 to catalog, configured Ollama embedding endpoints (`EMBEDDING_ENGINE=ollama`, `EMBEDDING_MODEL_PREF`, `EMBEDDING_MODEL_MAX_CHUNK_LENGTH=8192`) in `tools/config-anythingllm.ps1`, `tools/common.sh`, `optimiced.bat`, and `install-core.sh`.

- [x] **Interactive HuggingFace Search CLI**
  - Add CLI search feature in `install-core.ps1` and `linux/install-core.sh` using the HuggingFace Hub API:
    - Query models directly (e.g. `search: deepseek-r1-distill`).
    - Filter by GGUF format and display available quantizations with direct one-click download.
  - Implementation: Built-in HuggingFace Hub search CLI (`Invoke-HuggingFaceSearch` in PowerShell, `search_huggingface` in Bash), supporting direct query via CLI flags (`-Search` / `--search`), search commands (`s`, `search: <query>`), live repository search with download/like metrics, quantization tree listing, mmproj projector detection, and 1-click install.

---

## Phase 3: User Interface & Experience (UI/UX)


- [ ] **Portable Desktop Shortcut Generator**
  - Add a utility script (`create-shortcut.bat` / `create-shortcut.sh`):
    - Windows: Generates a `.lnk` shortcut with custom USB icon pointing to `start-windows.bat`.
    - macOS: Generates a desktop `.command` or `.app` launcher.
    - Linux: Generates a `pendrive-ai.desktop` launcher for GNOME/KDE/XFCE.

- [ ] **System Tray Companion Utility**
  - Minimal portable tray icon app (e.g., using Go or lightweight C#):
    - Real-time engine health indicator (Running / Stopped / Starting).
    - Active model display & one-click model switcher.
    - VRAM / RAM consumption metrics.
    - Safe drive unmount / eject trigger.

- [ ] **Multi-Language Localization**
  - Complete multi-language strings (English, Spanish, French, German, Chinese, Japanese) across:
    - `install.bat` & `install-core.ps1`
    - `linux/preflight-check.sh` & `linux/install-core.sh`
    - `doctor.bat` & `doctor.sh`

---

## Phase 4: Storage, Security & Privacy

- [ ] **Dual-Partition Layout Architecture**
  - **Partition 1 (Read-Only / exFAT or ISO9660)**:
    - Holds immutable core binaries (`ollama`, `AnythingLLM`), GGUF models, and static Modelfiles.
    - Prevents malware infection, ransomware encryption, or accidental user deletion.
  - **Partition 2 (Encrypted Read-Write / exFAT or ext4)**:
    - Houses mutable user data: `anythingllm_data/storage`, chat sessions, uploaded PDFs, LanceDB vectors.

- [ ] **Hardware & Software Encryption Integration**
  - Windows: Automated setup guide for BitLocker To Go on the portable data partition.
  - Linux: Scripted setup for LUKS2 container with portable mount/unmount scripts.
  - macOS: Encrypted APFS volume container guidance.

- [ ] **Emergency Secure Wipe / Panic Clean Script (`wipe-data.bat` / `wipe-data.sh`)**
  - Multi-pass shredding / cryptographic wipe of `anythingllm_data` (chat history, vector embeddings, uploaded PDFs, cached documents).
  - Preserves system engine and downloaded models so the USB remains instantly usable after wipe.

- [ ] **Strict Offline & Outbound Telemetry Firewall Rules**
  - Add firewall profiles on launch:
    - Block all outbound traffic for Electron and Ollama processes except to localhost `127.0.0.1`.
    - Guarantee zero leakage of sensitive documents or queries even when plugged into an internet-connected host.

---

## Phase 5: Multi-OS Automation, Tooling & CI/CD

- [ ] **Universal Root Entry Router (`run.bat` / `run.sh`)**
  - Root-level auto-detection script that identifies the host OS and seamlessly routes to the correct launcher (`start-windows.bat`, `start-mac.command`, or `linux/start-linux.sh`).

- [ ] **Automated USB Formatter & Provisioner (`make-usb.ps1` / `make-usb.sh`)**
  - Single command setup to format a new flash drive as exFAT, apply cluster-size optimization (128KB/256KB clusters for faster large file reads), and clone Pendrive_X directly.

- [ ] **Continuous Integration (GitHub Actions Workflow)**
  - Automated CI matrix testing:
    - `shellcheck` linting for all `.sh` and `.command` scripts.
    - PowerShell AST validation for `install-core.ps1` on Windows PowerShell 5.1 and PowerShell 7+.
    - Batch file syntax validation.
    - Model catalog validator checking schema, SHA-256 hashes, and HuggingFace download URL availability.
