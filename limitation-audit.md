# Pendrive_X AI — New User Readiness & Quality Audit Report

**Target Audience:** New users running the project from a portable USB flash drive across Windows, Linux, and macOS.  
**Audit Date:** November 2026  
**Overall Readiness Score:** **B+ (85/100)** — Highly capable, robust architectural foundation, but has 4 critical friction points that will impede new users during initial setup and day-to-day operation.

---

## 1. Executive Summary

Pendrive_X is an ambitious, well-architected portable AI distribution. Its hardware auto-tuning, dual inference engine support (`ollama` and `llama.cpp`), dependency-free ANSI QR code generators, and host isolation are implemented with remarkable care.

However, if a **brand-new user** clones this repository and attempts to set it up today, they will likely encounter **four major hurdles**:

1. **AnythingLLM Windows Installer Does Not Default to USB:** The installer script asks users to manually choose the USB path in the GUI installer, but the official AnythingLLM NSIS installer defaults to a one-click local install (`%LOCALAPPDATA%\Programs\AnythingLLM`), resulting in `AnythingLLM.exe not found on USB`.
2. **Re-running the Installer Erases Previously Installed Models:** The installer is advertised as idempotent ("add models anytime"), but it truncates and overwrites [installed-models.txt] with only the current selection, wiping out previously installed models.
3. **Ollama Duplicate Model Storage on exFAT Exhausts 16 GB Drives:** Because exFAT does not support hardlinks, `ollama create` duplicates GGUF weights into `ollama/data/blobs/`. A 7–8.7 GB model consumes 14–17 GB of drive space, causing 16 GB drives (advertised as minimum in the documentation) to run out of disk space during installation.
4. **Document Chat / Local RAG Fails in AnythingLLM:** If the user does not download an embedding model (Models 10–12), the launcher still configures AnythingLLM to request `nomic-embed-local` from Ollama, causing a `404 Model Not Found` error when uploading documents.

Below is the complete verification breakdown, followed by step-by-step issue descriptions and exact code fixes.

---

## 2. Infrastructure & Asset Verification

Every external URL, script syntax, and tool was tested in the active environment:

| Component | Status | Details |
| :--- | :---: | :--- |
| **All 12 Catalog Models** | **100% Active** | All GGUF URLs in [`models/catalog.json`](Pendrive_X-V1/models/catalog.json) returned HTTP `200 OK`. |
| **Engine Binaries** | **100% Active** | Ollama (v0.6.8 for Win/Linux/Mac) and llama.cpp (b12244 Vulkan/CPU/CUDA/Metal) in [`versions.env`](Pendrive_X-V1/versions.env) returned HTTP `200 OK`. |
| **AnythingLLM Binaries** | **100% Active** | Windows `.exe`, Linux `.AppImage`, and macOS `.dmg` (Silicon & Intel) all verified live. |
| **PowerShell Scripts** | **Valid** | AST parsed all `.ps1` files without syntax errors. |
| **Bash & Command Scripts** | **Valid** | `bash -n` passed on all `.sh` and `.command` scripts. |
| **Python Utilities** | **Valid** | `py_compile` passed on [`tools/lan-chat.py`](Pendrive_X-V1/tools/lan-chat.py) and [`tools/qr.py`](Pendrive_X-V1/tools/qr.py). |
| **Hardware Detection** | **Functional** | [`tools/hardware.ps1`](Pendrive_X-V1/tools/hardware.ps1) accurately identified GPU, VRAM, RAM, CPU threads, and assigned Vulkan offload layers. |
| **Terminal QR Renderers** | **Functional** | Both [`tools/qr.ps1`](Pendrive_X-V1/tools/qr.ps1) and [`tools/qr.py`](Pendrive_X-V1/tools/qr.py) output clean, scannable ANSI blocks without external dependencies. |
| **Diagnostic Tools** | **Functional** | [`doctor.bat`](Pendrive_X-V1/doctor.bat) and [`doctor.sh`](Pendrive_X-V1/doctor.sh) executed cleanly and reported disk, RAM, engine, and port statuses. |

---

## 3. Critical Issues & User Roadblocks

### Issue 1: AnythingLLM Desktop Installation on Windows Fails Portability
- **Location:** [`install-core.ps1#L1364-L1389`](Pendrive_X-V1/install-core.ps1#L1364-L1389)
- **User Experience:**
  1. The user runs `install.bat`.
  2. The script displays a warning: *"2. When it asks for 'Install Location', choose your USB! Path: E:\anythingllm"*.
  3. The official AnythingLLM Desktop installer opens.
  4. Because AnythingLLM's NSIS installer defaults to a single-click user install, **it never prompts the user for a folder**; it silently installs to `C:\Users\<User>\AppData\Local\Programs\AnythingLLM`.
  5. The installer finishes, and `install-core.ps1` checks for `E:\anythingllm\AnythingLLM.exe`, which does not exist.
  6. The user is greeted with `WARNING: AnythingLLM.exe not found on USB. If you installed it locally, it won't be portable!`
- **Why it's already solved elsewhere in the project:**
  In [`tools/update-engine.ps1#L181`](Pendrive_X-V1/tools/update-engine.ps1#L181), the updater passes silent NSIS arguments:
  ```powershell
  Start-Process -FilePath $installer -ArgumentList @("/S", "/D=$target") -Wait
  ```
  NSIS installers honor `/S /D=<path>` to install silently into a designated directory without user interaction.
- **Fix:** Update [`install-core.ps1`](Pendrive_X-V1/install-core.ps1) to attempt the silent install with `/S /D=$USB_Drive\anythingllm` first before falling back to manual launch.

---

### Issue 2: Re-running the Installer Wipes Previously Installed Models
- **Location:** [`install-core.ps1#L1261-L1263`](Pendrive_X-V1/install-core.ps1#L1261-L1263) and [`linux/install-core.sh#L1194-L1198`](Pendrive_X-V1/linux/install-core.sh#L1194-L1198)
- **User Experience:**
  1. User installs Model 1 (`nemomix-local`).
  2. Next week, user wants to add Model 4 (`qwen-local`).
  3. User runs `install.bat`, enters `4`, and waits for the download.
  4. The installer writes `installed-models.txt`:
     ```powershell
     $installedList = @($SelectedModels | ForEach-Object { "$($_.Local)|$($_.Name)|$($_.Label)" })
     Write-TextFile -Path "$USB_Drive\models\installed-models.txt" -Lines $installedList
     ```
  5. [`models/installed-models.txt`](Pendrive_X-V1/models/installed-models.txt) is completely truncated. `nemomix-local` is deleted from the list.
  6. When the user launches `start-windows.bat`, it only sees `qwen-local`. `doctor.bat` only lists `qwen-local`. AnythingLLM cannot automatically discover the first model anymore.
- **Fix:** Merge newly selected models into the existing [`models/installed-models.txt`](Pendrive_X-V1/models/installed-models.txt), deduplicating by local alias.

---

### Issue 3: Ollama Weight Duplication on exFAT Causes Premature Disk Full
- **Location:** [`install-core.ps1#L1457`](Pendrive_X-V1/install-core.ps1#L1457) and [`GET-STARTED.md#L9`](Pendrive_X-V1/GET-STARTED.md#L9)
- **User Experience:**
  1. A user buys a 16 GB or 32 GB USB drive formatted as exFAT as instructed in [`GET-STARTED.md`](Pendrive_X-V1/GET-STARTED.md).
  2. The user selects Model 1 (NemoMix Unleashed 12B, ~7–8.7 GB).
  3. The installer downloads the `.gguf` file to `models/` (7–8.7 GB).
  4. The installer runs `ollama create nemomix-local -f Modelfile-nemomix-local`.
  5. Because exFAT **does not support hardlinks**, Ollama copies the entire 7–8.7 GB file into `ollama/data/blobs/`.
  6. The USB drive runs out of disk space halfway through `ollama create`, crashing with an I/O or disk full error.
- **Note:** In llama.cpp mode (`INFERENCE_ENGINE=llamacpp`), `llama-server` reads `models/*.gguf` directly without copying, saving 50% disk space.
- **Fix:**
  - Update [`GET-STARTED.md`](Pendrive_X-V1/GET-STARTED.md) and [`README.md`](Pendrive_X-V1/README.md) to explain that for 16 GB drives, `INFERENCE_ENGINE=llamacpp` or lightweight 3B models (Model 5 or 6) must be used.
  - In `install-core.ps1`, add a disk space pre-check specifically for Ollama (`model_size * 2 + 3 GB`).

---

### Issue 4: Local Document Chat (RAG) 404 in AnythingLLM
- **Location:** [`tools/config-anythingllm.ps1#L65-L87`](Pendrive_X-V1/tools/config-anythingllm.ps1#L65-L87) and [`tools/common.sh#L233-L259`](Pendrive_X-V1/tools/common.sh#L233-L259)
- **User Experience:**
  1. User installs Model 1 (Text only) with Ollama.
  2. User opens AnythingLLM, creates a workspace, and uploads a PDF to chat with it.
  3. AnythingLLM queries Ollama at `http://127.0.0.1:11434/api/embeddings` for `nomic-embed-local`.
  4. Ollama returns `404: model 'nomic-embed-local' not found`.
  5. Document embedding fails, and the user cannot use workspace documents.
- **Fix:**
  If no embedding model (Models 10–12) is found in [`models/installed-models.txt`](Pendrive_X-V1/models/installed-models.txt), fallback to `EMBEDDING_ENGINE=native` instead of forcing `EMBEDDING_ENGINE=ollama`. AnythingLLM has built-in native embeddings (`xenova/all-MiniLM-L6-v2`) that run 100% offline out-of-the-box.

---

### Issue 5: macOS `.app` Execution on exFAT Flash Drives
- **Location:** [`start-mac.command#L201`](Pendrive_X-V1/start-mac.command#L201)
- **User Experience:**
  - On macOS, when `start-mac.command` mounts `AnythingLLMDesktop-Silicon.dmg` and runs `cp -R "$MOUNT_DIR/AnythingLLM.app" "$USB_DIR/anythingllm_mac/"`:
  - If the USB drive is formatted as exFAT (recommended in Step 0 for Windows/Linux interoperability), exFAT does not support macOS symlinks.
  - Electron apps contain internal symlinks (`Electron Framework.framework/Versions/Current -> A`).
  - Depending on the macOS version, `cp -R` may fail, or the app will fail to launch with `dyld: Library not loaded`.
- **Mitigation:**
  Note in [`GET-STARTED.md`](Pendrive_X-V1/GET-STARTED.md) that Mac-only drives benefit from APFS, or test `ditto` instead of `cp -R` for preserving resource forks.

---

## 4. Usability & Documentation Friction Points

| Area | Current Behavior | Impact on New User |
| :--- | :--- | :--- |
| **Model Count Mismatch** | [`README.md`](Pendrive_X-V1/README.md) & [`GET-STARTED.md`](Pendrive_X-V1/GET-STARTED.md) say *"6 curated models"* and list 1 to 6. But the installer displays 12 models (Vision, RAG, Embeddings), a HuggingFace Search CLI `[S]`, and Quantization Tiers `[1-4]`. | Users feel confused or think they downloaded a different branch or version. |
| **Model 1 Quantization** | README lists Model 1 as `Q5_K_M (~8.7 GB)`. `catalog.json` default is `Q4_K_M (~6.96 GB)`. | User expects an 8.7 GB download and sees a 7.0 GB download. |
| **Spanish Alternative Launcher** | [`optimiced.bat`](Pendrive_X-V1/optimiced.bat) has a typo in its name (`optimiced` vs `optimized`) and nested quotes in line 191 (`set "LLM_ARGS=--user-data-dir="%DATA_DIR%"..."`). | Can cause path-splitting issues if the USB path contains spaces. |
| **Abrupt Terminal Close** | If the user closes `start-windows.bat` with the `[X]` button instead of pressing any key, `taskkill` does not execute. | `ollama.exe` or `llama-server.exe` remains running on the host, preventing the USB from being safely ejected and holding the port open. |
| **`SECURITY.md` Table** | Table in [`SECURITY.md`](Pendrive_X-V1/SECURITY.md#L6) has an empty cell (`| 1.1.x \| \|`), and references `todo.md P3` instead of uppercase `TODO.md Phase 4`. | Minor documentation polish issue. |

---

## 5. Recommended Fixes & Patches

### Patch 1: Automatic Silent AnythingLLM Install in `install-core.ps1`

Replace lines 1364–1389 of [`install-core.ps1`]():

```powershell
    # Install AnythingLLM silently to USB with /S /D=<path>
    if (Test-Path $InstallerDest) {
        Write-Host "      Installing AnythingLLM directly to USB..." -ForegroundColor Magenta
        $targetDir = "$USB_Drive\anythingllm"
        $installed = $false

        try {
            # NSIS installer accepts /S for silent and /D=<path> as last parameter
            Start-Process -FilePath $InstallerDest -ArgumentList @("/S", "/D=$targetDir") -Wait
            # Wait up to 30s for the spawned NSIS child worker to finish writing files
            $timeout = (Get-Date).AddSeconds(30)
            while (-not (Test-Path "$targetDir\AnythingLLM.exe") -and (Get-Date) -lt $timeout) {
                Start-Sleep -Seconds 2
            }
            if (Test-Path "$targetDir\AnythingLLM.exe") {
                $installed = $true
            }
        } catch { }

        if ($installed) {
            Write-Host "      AnythingLLM installed successfully to USB!" -ForegroundColor Green
            Remove-Item $InstallerDest -Force -ErrorAction SilentlyContinue
        } else {
            # Fallback to interactive mode if silent install fails
            Write-Host "  Automatic install did not complete. Launching installer window..." -ForegroundColor Yellow
            Write-Host "  Please select install location: $targetDir" -ForegroundColor White
            Start-Process -FilePath $InstallerDest -Wait
            if (Test-Path "$targetDir\AnythingLLM.exe") {
                Write-Host "      AnythingLLM installed successfully to USB!" -ForegroundColor Green
                Remove-Item $InstallerDest -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "      WARNING: AnythingLLM.exe not found at $targetDir." -ForegroundColor Yellow
            }
        }
    }
```

---

### Patch 2: Non-Destructive `installed-models.txt` Merging in `install-core.ps1`

Replace lines 1260–1263 of [`install-core.ps1`]():

```powershell
    $installedFile = "$USB_Drive\models\installed-models.txt"
    $existingEntries = @{}
    if (Test-Path -LiteralPath $installedFile) {
        Get-Content -LiteralPath $installedFile -ErrorAction SilentlyContinue | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#')) {
                $alias = $line.Split('|')[0].Trim()
                if ($alias) { $existingEntries[$alias] = $line }
            }
        }
    }
    foreach ($m in $SelectedModels) {
        $existingEntries[$m.Local] = "$($m.Local)|$($m.Name)|$($m.Label)"
    }
    Write-TextFile -Path $installedFile -Lines @($existingEntries.Values)
    Write-Host "      Saved model list to installed-models.txt ($($existingEntries.Count) total)" -ForegroundColor DarkGray
```

And in [`linux/install-core.sh#L1194-L1199`]():

```bash
    INSTALLED_FILE="$USB_DIR/models/installed-models.txt"
    touch "$INSTALLED_FILE"
    for (( i=0; i<SEL_COUNT; i++ )); do
        sed -i "/^${SEL_LOCALS[$i]}|/d" "$INSTALLED_FILE" 2>/dev/null || true
        echo "${SEL_LOCALS[$i]}|${SEL_NAMES[$i]}|${SEL_LABELS[$i]}" >> "$INSTALLED_FILE"
    done
    echo -e "${DGRAY}      Saved model list to installed-models.txt${NC}"
```

---

### Patch 3: Safe Fallback for Local Embeddings in `config-anythingllm.ps1`

In [`tools/config-anythingllm.ps1`]() (lines 65–90):

```powershell
    $hasLocalEmbedding = $false
    if ($embPref -and $embPref -ne "nomic-embed-local") {
        $hasLocalEmbedding = $true
    } elseif ($embPref -eq "nomic-embed-local") {
        # Check if nomic-embed-local is actually in installed-models.txt
        $installedFile = Join-Path $UsbRoot "models\installed-models.txt"
        if (Test-Path -LiteralPath $installedFile) {
            $content = Get-Content -LiteralPath $installedFile -Raw -ErrorAction SilentlyContinue
            if ($content -match 'nomic-embed-local') { $hasLocalEmbedding = $true }
        }
    }

    if ($Engine -eq "llamacpp" -or -not $hasLocalEmbedding) {
        # If llama.cpp is selected OR no embedding model was installed into Ollama,
        # use AnythingLLM's built-in native embedding engine.
        $new += "EMBEDDING_ENGINE=native"
    } else {
        $new += "EMBEDDING_ENGINE=ollama"
        $new += "EMBEDDING_BASE_PATH=http://127.0.0.1:$Port"
        $new += "EMBEDDING_MODEL_PREF=$embPref"
        $new += "EMBEDDING_MODEL_MAX_CHUNK_LENGTH=8192"
    }
```

---

## 6. Summary Conclusion

The project's codebase is clean, well-tested, modular, and has zero external internet dependencies once downloaded. Addressing the 4 primary points above (AnythingLLM silent install, `installed-models.txt` merging, Ollama storage duplication guidance, and embedding fallback) will eliminate virtually all friction a new user could experience.
