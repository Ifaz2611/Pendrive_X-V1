# Pendrive_X Quick Start

Pendrive_X lets you run a private AI assistant from a USB drive using Ollama and AnythingLLM.

After the first installation, your models, chats, settings, and application data are stored on the USB drive.

## Before you begin

You need:

- A USB drive formatted as **exFAT**, NTFS, or a Linux filesystem that supports files larger than 4 GB.
- Internet access for the first installation.
- At least **16 GB** of free space for one small model.
- At least **32 GB** for a larger model.
- At least **64 GB** if you want to install all preset models.
- A modern 64-bit computer.

Do not use FAT32. FAT32 cannot store the larger GGUF model files.

## 1. Copy the project to your USB drive

Copy all files and folders from this project to the **root** of the USB drive.

The launchers should be directly visible on the drive, for example:

```text
E:\
├── install.bat
├── start-windows.bat
├── start-mac.command
├── models\
└── linux\
```

Do not put the project inside another folder unless you also run the scripts from that folder.

## 2. Install on Windows

1. Open the USB drive in File Explorer.
2. Double-click `install.bat`.
3. Choose a model:
   - `1` for the recommended larger model.
   - `3` for a good coding model.
   - `5` or `6` for a lightweight model.
   - `1,3` to install multiple models.
   - `all` to install every preset model.
   - `c` to download a custom GGUF model.
4. Wait while the model, Ollama, and AnythingLLM are downloaded.
5. If the AnythingLLM installer opens, choose a location inside the USB drive:

   ```text
   E:\anythingllm
   ```

6. When installation finishes, double-click `start-windows.bat`.

For an additional Windows launcher with extra disk and process checks, you can use `optimiced.bat`.

## 3. Install on Linux

Open a terminal and replace `/media/$USER/MYUSB` with the actual USB path if necessary:

```bash
cd /media/$USER/MYUSB
chmod +x linux/*.sh doctor.sh
bash linux/preflight-check.sh
```

The preflight check verifies the USB filesystem, available space, removable-drive detection, and read/write speed. Confirm the installation when prompted.

To install directly:

```bash
bash linux/install-core.sh /media/$USER/MYUSB
```

Then start Pendrive_X:

```bash
bash linux/start-linux.sh
```

If the USB is mounted somewhere else, pass its path explicitly:

```bash
bash linux/start-linux.sh /path/to/usb
```

Linux may require these tools:

```text
curl, tar, zstd, dd, df, lsblk, awk, findmnt
```

## 4. Use macOS

1. Copy the project to the USB drive.
2. Open Terminal.
3. Make the launcher executable:

   ```bash
   cd /Volumes/YOUR_USB_NAME
   chmod +x start-mac.command
   ```

4. Start it:

   ```bash
   ./start-mac.command
   ```

On the first run, the launcher downloads the macOS versions of Ollama and AnythingLLM directly to the USB drive. This may take several minutes and requires internet access.

If macOS blocks the launcher, right-click `start-mac.command`, choose **Open**, and confirm. The AnythingLLM application may also require permission the first time it runs.

## 5. Starting the AI after installation

Use the launcher for your operating system:

| Operating system | Launcher |
|---|---|
| Windows | `start-windows.bat` |
| Linux | `bash linux/start-linux.sh` |
| macOS | `./start-mac.command` |

Keep the terminal window open while using the AI. It runs the selected engine
(Ollama or llama.cpp) in the background and uses a local address such as:

```text
http://127.0.0.1:11434     (Ollama)
http://127.0.0.1:8081      (llama.cpp)
```

AnythingLLM should open automatically.

## 6. Choosing the inference engine

Pendrive_X can run two engines:

| Engine | Best for | Notes |
|---|---|---|
| **Ollama** (`ollama`) | Default, easiest | Background service; supports `ollama` model aliases |
| **llama.cpp** (`llamacpp`) | Low-RAM PCs | Standalone `llama-server`; saves ~1.5–2 GB RAM and starts faster |

Choose at install time:

```bat
install.bat --engine=ollama
install.bat --engine=llamacpp
```

```bash
bash linux/install-core.sh /path/to/usb --engine=llamacpp
```

Or switch later by editing `.env` on the USB root:

```text
INFERENCE_ENGINE=llamacpp
```

Useful llama.cpp settings in the same file:

```text
LLAMACPP_VARIANT=auto     # auto, cuda, rocm, vulkan, cpu
LLAMACPP_MODEL=           # empty = first installed model
LLAMACPP_NGL=auto         # GPU layers (auto = hardware detection)
LLAMACPP_THREADS=auto
LLAMACPP_CTX=auto
```

The launchers automatically configure AnythingLLM for the chosen engine, so
you do not need to change the provider by hand.

## 7. Choosing a model

The launchers select the first installed model (or `LLAMACPP_MODEL` in `.env`)
automatically. To pick a different one inside AnythingLLM:

1. Open **Settings**.
2. Open the **LLM** or **LLM Provider** section.
3. Select **Ollama** (Ollama engine) or **Generic OpenAI** (llama.cpp engine).
4. Choose one of the installed models.
5. Save the settings.

Installed models are listed in:

```text
models\installed-models.txt
```

You can also change the default model in:

```text
anythingllm_data\storage\.env
```

The relevant setting is:

```text
OLLAMA_MODEL_PREF=model-name-local
```

or, for the llama.cpp engine:

```text
GENERIC_OPEN_AI_MODEL_PREF=model-name-local
```

## 8. Changing the token limit

The default context size is 4096 tokens. To increase it:

1. Close Pendrive_X.
2. Open `anythingllm_data/storage/.env` on the USB.
3. Change this value:

   ```text
   OLLAMA_MODEL_TOKEN_LIMIT=4096
   ```

   For example:

   ```text
   OLLAMA_MODEL_TOKEN_LIMIT=8192
   ```

4. Save the file and start Pendrive_X again.

Higher values require more RAM. If the computer becomes slow or the model stops responding, use a lower value.

## 9. Adding another model later

Run the installer again and select the additional model. Existing valid downloads are skipped.

On Windows:

```text
install.bat
```

On Linux:

```bash
bash linux/install-core.sh /path/to/usb
```

You can also choose `c` or `custom` and provide a direct `.gguf` URL from Hugging Face.

## 10. Using it from a phone (LAN mode)

Start the launcher with `--server` (or `--lan`) to reach the AI from another
device on the same Wi-Fi:

```bat
start-windows.bat --server
start-windows.bat --headless
```

```bash
bash linux/start-linux.sh --server
./start-mac.command --lan
```

The terminal shows a LAN address such as `http://192.168.1.20:8081/` and a QR
code. Scan the QR code with a phone camera, or type the address into the phone's
browser.

- With **llama.cpp**, the browser opens llama-server's built-in chat UI.
- With **Ollama**, Pendrive_X starts a small mobile chat page on port `8090`.
- `--headless` skips the desktop AnythingLLM window and keeps only the server.
- There is no password. Use this only on a network you trust.

## 11. Shutting down safely

When you finish using the AI:

1. Return to the terminal window running the launcher.
2. Press a key on Windows, or press **Enter** on Linux/macOS.
3. Wait for the shutdown message.
4. Safely eject the USB drive.

Do not unplug the USB while the AI is still running. Chats and settings are saved on the drive.

## 12. Updating engines and the UI

The updater replaces engine binaries and AnythingLLM, but **never** touches
`models/*.gguf`, `ollama/data`, or `anythingllm_data` (chats and settings).

```bat
install.bat --update-engine
install.bat --update-engine=llamacpp
start-windows.bat --update-engine
```

```bash
bash linux/install-core.sh /path/to/usb --update-engine
bash linux/start-linux.sh --update-engine=anythingllm
./start-mac.command --update-engine
```

`all` refreshes only components that are installed. To change which version is
installed, edit `versions.env` first, then run the updater.

## Troubleshooting

### The installer says FAT32 is not supported

Back up the USB, reformat it as **exFAT**, and copy the project back to it. Formatting erases the drive.

### AnythingLLM is missing

Run the installer again. On Windows, make sure the AnythingLLM installation location is inside the USB drive:

```text
E:\anythingllm
```

### Ollama does not start

- Close another Ollama instance running on the computer.
- Restart the launcher.
- Make sure the USB has free space.
- Check the launcher logs in `anythingllm_data/logs`.

### llama.cpp does not start

- Make sure `llamacpp/` exists on the USB. If not, run `install.bat --engine=llamacpp` or `bash linux/install-core.sh /path/to/usb --engine=llamacpp`.
- If the GPU build crashes, set `LLAMACPP_VARIANT=cpu` in `.env` and run `--update-engine=llamacpp`.
- Check `anythingllm_data/logs` for the engine log.

### The phone cannot connect in LAN mode

- Both devices must be on the same Wi-Fi network.
- Allow the displayed port through the host firewall.
- Guest networks and "AP isolation" often block device-to-device traffic.

### The AI is slow

- Use model `5` or `6`.
- Reduce the token limit to 4096.
- Use a USB 3.0 or newer port.
- Close other applications to free RAM.

### You need diagnostics

On Windows, run:

```text
doctor.bat
```

On Linux or macOS, run:

```bash
bash doctor.sh
```

## Privacy note

Pendrive_X is designed to run locally after setup. Models, chats, settings, and logs are stored on the USB drive. Anyone who obtains the USB may be able to read the stored data, so use BitLocker, VeraCrypt, or another encryption method if the drive contains sensitive information.
