# Pendrive_X — Get Started

A friendly, step-by-step guide for first-time users.

**What you're building:** a private AI chat assistant that lives entirely on a USB drive. After a one-time setup, it works with **no internet** and leaves **no trace on the computer** you plug it into.

**What you need:**

- A USB drive (16 GB minimum, 64 GB to install all models)
- The drive formatted as **exFAT** — *not* FAT32 (see [Step 0](#step-0-check-your-usb-drive))
- Internet access **for the first install only**
- A 64-bit computer (Windows, macOS, or Linux)

> 💡 Not sure which model to pick? Start with **model 1** (best quality) or **model 5** (lightweight, works on almost anything). You can add more later — re-running the installer never re-downloads what you already have.

---

## Step 0: Check your USB drive

FAT32 drives **cannot** hold the model files (they have a 4 GB per-file limit). You need **exFAT** (or NTFS / ext4).

**Windows:** right-click the drive in File Explorer → **Format** → File system: `exFAT` → Start.
⚠️ Formatting erases everything on the drive — back up first.

**Linux:** check with `lsblk -f` or `df -T /media/$USER/YOURUSB`. Reformat with `mkfs.exfat` if needed.

**macOS:** the drive is almost certainly already fine (APFS/HFS+/exFAT all work).

---

## Step 1: Copy the files to the USB

Copy **everything** from this project to the **root** of the USB — the launchers must sit directly on the drive, like this:

```text
E:\
├── install.bat
├── start-windows.bat
├── start-mac.command
├── linux\
└── models\
```

Don't nest the project inside a folder on the drive.

---

## Step 2: Install

Pick your operating system:

### 🪟 Windows

1. Open the USB drive in File Explorer.
2. Double-click **`install.bat`**.
3. When asked for models, type a number like `1`, several like `1,3`, or `all`.
4. **Wait.** This downloads gigabytes — it can take a while depending on your internet.
5. ⚠️ **Important:** when the **AnythingLLM installer** window pops up, click **Browse** and choose a folder **inside the USB**, e.g. `E:\anythingllm`. Do *not* pick Program Files — it must live on the drive.
6. Close the AnythingLLM installer when it finishes. Installation is done.

### 🐧 Linux

```bash
# 1. Go to the USB and make scripts executable
cd /media/$USER/YOUR_USB_NAME
chmod +x linux/*.sh doctor.sh

# 2. Run the preflight check — it verifies filesystem, space, and speed
bash linux/preflight-check.sh

# 3. Install (preflight offers to launch this for you)
bash linux/install.sh
# or directly:
bash linux/install-core.sh /media/$USER/YOUR_USB_NAME
```

Needed tools (usually preinstalled): `curl, tar, zstd, dd, df, lsblk, awk, findmnt`

Non-interactive install:

```bash
bash linux/install-core.sh /media/$USER/YOUR_USB_NAME --engine ollama --models 1,3 --yes
```

### 🍎 macOS

No separate install needed — just run the launcher (Step 3). On first launch it downloads the macOS engine and AnythingLLM **directly onto the USB**.

If macOS blocks it: right-click `start-mac.command` → **Open** → confirm.

---

## Step 3: Launch the AI

| OS | Command |
|----|---------|
| Windows | Double-click **`start-windows.bat`** |
| Linux | `bash linux/start-linux.sh` |
| macOS | `./start-mac.command` (or double-click it) |

What happens:

1. A terminal window opens and starts the AI engine.
2. **AnythingLLM** (the chat app) opens automatically.
3. **Keep the terminal window open** the whole time you use the AI.

⏱️ First launch takes longer while the model loads into memory. That's normal.

---

## Step 4: Using it day-to-day

### Switching models

- Open AnythingLLM → **Settings → LLM Provider** → pick **Ollama** or **Generic OpenAI** (depends on your engine) → choose a model.
- Installed models are listed in `models/installed-models.txt`.
- Or launch with a specific model: `start-windows.bat --model=qwen-local`

### Adding models later

Just run the installer again and pick more numbers — it skips everything already downloaded.

### Using it from your phone 📱

```bat
start-windows.bat --server
```
```bash
bash linux/start-linux.sh --server
```
```bash
./start-mac.command --lan
```

The terminal prints a LAN address and a **QR code** — scan it with your phone camera. Both devices must be on the same Wi-Fi. There's no password, so only do this on networks you trust.

---

## Step 5: Shutting down safely

1. Go back to the launcher terminal window.
2. Press **any key** (Windows) or **Enter** (Linux/macOS).
3. Wait for the "shutdown complete" message.
4. **Safely eject** the USB.

Never unplug while it's running — chats and settings save to the drive and could corrupt.

---

## Common questions

**Do I need internet every time?** No — only for the first install. Everything runs offline after that.

**Does it slow down my computer?** It uses your computer's RAM and CPU/GPU like any app, but installs *nothing* on it. Close other apps if it feels slow, or use a smaller model (5 or 6).

**Can I move it between computers?** Yes — that's the point. Just plug into any PC and run the launcher. Your chats and settings travel with the drive.

**Is my data private?** Chats, models, and settings all live on the USB in `anythingllm_data/`. Nothing is sent anywhere. ⚠️ But anyone who gets the drive can read it — use BitLocker or VeraCrypt if it holds sensitive info.

**Which engine should I choose?**

| Engine | Choose it if… |
|--------|---------------|
| `ollama` (default) | You want the simplest, most compatible setup |
| `llamacpp` | Your PC is low on RAM — it saves ~1.5–2 GB |

Set it in `.env` on the USB root: `INFERENCE_ENGINE=llamacpp`, then relaunch.

**How do I increase the AI's memory (context)?**

Edit `anythingllm_data/storage/.env` on the USB and raise `OLLAMA_MODEL_TOKEN_LIMIT` (default `4096` → try `8192`). More memory needs more RAM — if things get slow, lower it again.

---

## Troubleshooting

| Problem | Try this |
|---------|----------|
| "FAT32 is not supported" | Reformat the USB as **exFAT** (Step 0) |
| AnythingLLM window missing | Re-run the installer; when it asks, pick `E:\anythingllm` on the USB |
| AI is very slow | Use model `5` or `6`; lower token limit to `4096`; use a USB 3.0 port; close other apps |
| Engine won't start | Run `doctor.bat` (Windows) or `bash doctor.sh` (Linux/macOS) for diagnostics |
| Download failed halfway | Re-run the installer — it resumes/skips valid files. Check you have enough free space |
| Phone can't connect | Same Wi-Fi? Allow the port in the firewall? Avoid guest networks |

Still stuck? Check `anythingllm_data/logs/` on the USB for detailed logs.

---

## What's next?

- 📖 Full technical reference: [`README.md`](README.md)
- 🛠️ Contribute or report issues: [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`SECURITY.md`](SECURITY.md)
- 📜 License: Apache 2.0 — [`LICENSE`](LICENSE)
