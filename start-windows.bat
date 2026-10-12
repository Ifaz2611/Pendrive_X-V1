@echo off
setlocal enabledelayedexpansion
title PENDRIVE_X AI - Launcher
color 0A

echo ===================================================
echo     Launching PENDRIVE_X Engine from USB...       
echo ===================================================

:: -------------------------------------------------------
:: LOGGING — tee to anythingllm_data\logs\launcher-*.log
:: -------------------------------------------------------
set "LOG_DIR=%~dp0anythingllm_data\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul
for /f "usebackq tokens=*" %%d in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmmss'"`) do set "LOG_TS=%%d"
if not defined LOG_TS set "LOG_TS=session"
set "LOG_FILE=%LOG_DIR%\launcher-%LOG_TS%.log"
:: Simple log: append key events
echo [%date% %time%] Launcher started >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: FAT32 GUARD — mirror preflight-check.sh:484
:: -------------------------------------------------------
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$d='%~d0'; try{$v=Get-CimInstance -ClassName Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d) -ErrorAction Stop; $v.FileSystem} catch {''}"`) do set "FS_TYPE=%%a"
if /I "%FS_TYPE%"=="FAT32" (
    echo [ERROR] FAT32 filesystem detected on %~d0 — 4 GB per-file limit will block GGUF models ^! >> "%LOG_FILE%" 2>nul
    echo.
    echo ERROR: FAT32 filesystem detected — Reformat USB as exFAT ^(Right-click drive -^> Format -^> exFAT^).
    echo Current FS: %FS_TYPE% on %~d0
    pause
    exit /b 1
)
if /I "%FS_TYPE%"=="FAT" (
    echo [ERROR] FAT filesystem detected — Reformat as exFAT. >> "%LOG_FILE%" 2>nul
    echo ERROR: FAT filesystem not supported — Reformat as exFAT.
    pause
    exit /b 1
)

:: -------------------------------------------------------
:: IMPORTANT: All paths must point to USB, not the PC!
:: -------------------------------------------------------
:: Use quoted assignments to handle spaces in USB path (e.g. "Pendrive X/Test Drive")
set "OLLAMA_EXE=%~dp0ollama\ollama.exe"
set "APP_PATH=%~dp0anythingllm\AnythingLLM.exe"
set "ESC_OLLAMA_EXE=%OLLAMA_EXE:'=''%"
set "ESC_APP_PATH=%APP_PATH:'=''%"
set "OLLAMA_MODELS=%~dp0ollama\data"
set "STORAGE_DIR=%~dp0anythingllm_data"
set "ANYTHINGLLM_PROFILE=%STORAGE_DIR%\anythingllm-desktop"
set "APPDATA=%~dp0anythingllm_data"
set "LOCALAPPDATA=%~dp0anythingllm_data"

:: Validate core executables early before starting background services
if not exist "%OLLAMA_EXE%" (
    echo.
    echo ERROR: Ollama engine was not found at:
    echo   %OLLAMA_EXE%
    echo Please run install.bat first to set up the engine and models.
    echo.
    pause
    exit /b 1
)

if not exist "%APP_PATH%" (
    echo.
    echo ERROR: AnythingLLM was not found at:
    echo   %APP_PATH%
    echo Please run install.bat first to install AnythingLLM.
    echo.
    pause
    exit /b 1
)

:: Create the data folder on USB if it doesn't exist
if not exist "%~dp0anythingllm_data" mkdir "%~dp0anythingllm_data" 2>nul
if not exist "%ANYTHINGLLM_PROFILE%" mkdir "%ANYTHINGLLM_PROFILE%" 2>nul
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

:: -------------------------------------------------------
:: DYNAMIC PORT — avoid collision with host Ollama (like optimiced.bat:76)
:: -------------------------------------------------------
set "OLLAMA_PORT="
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$l=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); $p"`) do set "OLLAMA_PORT=%%p"
if not defined OLLAMA_PORT set "OLLAMA_PORT=11434"
set "OLLAMA_HOST=127.0.0.1:%OLLAMA_PORT%"
echo [+] Ollama port allocated: %OLLAMA_PORT%
echo [%date% %time%] Port %OLLAMA_PORT% >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: ENSURE ANYTHINGLLM USES EXTERNAL OLLAMA (not built-in) — preserve token limit
:: -------------------------------------------------------
set "ENV_FILE=%~dp0anythingllm_data\storage\.env"
if not exist "%~dp0anythingllm_data\storage" mkdir "%~dp0anythingllm_data\storage" 2>nul

:: Read model preference (preserve user UI choice if existing)
set "DEFAULT_MODEL=nemomix-local"
set "SAVED_MODEL="
if exist "%ENV_FILE%" (
    for /f "usebackq tokens=1,2 delims==" %%a in ("%ENV_FILE%") do (
        if /I "%%a"=="OLLAMA_MODEL_PREF" if not "%%b"=="" set "SAVED_MODEL=%%b"
    )
)
if defined SAVED_MODEL (
    set "DEFAULT_MODEL=%SAVED_MODEL%"
) else (
    if exist "%~dp0models\installed-models.txt" (
        for /f "usebackq tokens=1 delims=|" %%a in ("%~dp0models\installed-models.txt") do (
            set "DEFAULT_MODEL=%%a"
            goto :GotModel
        )
    )
)
:GotModel
:: Migrate legacy alias if present
if "%DEFAULT_MODEL%"=="nemomix-local_X" set "DEFAULT_MODEL=nemomix-local"

:: Check if .env needs fixing (missing or using built-in ollama)
set "NEEDS_FIX=0"
if not exist "%ENV_FILE%" set "NEEDS_FIX=1"
if exist "%ENV_FILE%" (
    findstr /C:"LLM_PROVIDER=ollama" "%ENV_FILE%" >nul 2>&1
    if errorlevel 1 set "NEEDS_FIX=1"
    findstr /C:"LLM_PROVIDER=anythingllm_ollama" "%ENV_FILE%" >nul 2>&1
    if not errorlevel 1 set "NEEDS_FIX=1"
)

:: Preserve custom token limit if user edited it (like optimiced.bat:142)
set "TOKEN_LIMIT=4096"
if exist "%ENV_FILE%" (
    for /f "usebackq tokens=1,2 delims==" %%a in ("%ENV_FILE%") do (
        if /I "%%a"=="OLLAMA_MODEL_TOKEN_LIMIT" set "TOKEN_LIMIT=%%b"
    )
)
:: Validate numeric
for /f "delims=0123456789" %%x in ("%TOKEN_LIMIT%") do set "TOKEN_LIMIT=4096"
if "%TOKEN_LIMIT%"=="" set "TOKEN_LIMIT=4096"

if "%NEEDS_FIX%"=="1" (
    echo Configuring AnythingLLM to use external Ollama engine...
    echo [%date% %time%] Configuring .env DEFAULT_MODEL=%DEFAULT_MODEL% TOKEN_LIMIT=%TOKEN_LIMIT% >> "%LOG_FILE%" 2>nul
    (
        echo LLM_PROVIDER=ollama
        echo OLLAMA_BASE_PATH=http://%OLLAMA_HOST%
        echo OLLAMA_MODEL_PREF=%DEFAULT_MODEL%
        echo OLLAMA_MODEL_TOKEN_LIMIT=%TOKEN_LIMIT%
        echo EMBEDDING_ENGINE=native
        echo VECTOR_DB=lancedb
    ) > "%ENV_FILE%"
    echo Done. Default model: %DEFAULT_MODEL% @ %OLLAMA_HOST% ^(token_limit=%TOKEN_LIMIT%^)
) else (
    :: Even if not NEEDS_FIX, ensure OLLAMA_BASE_PATH points to current dynamic port, preserving token limit
    :: Patch port without clobbering token limit
    set "ESC_ENV_FILE=%ENV_FILE:'=''%"
    powershell -NoProfile -Command "$f='%ESC_ENV_FILE%'; $c=Get-Content $f -Raw -ErrorAction SilentlyContinue; if($c){ $c=$c -replace 'OLLAMA_BASE_PATH=http://[^\r\n]+', 'OLLAMA_BASE_PATH=http://%OLLAMA_HOST%'; Set-Content -Path $f -Value $c -NoNewline -Encoding UTF8 }" >nul 2>&1
    echo [+] Patched OLLAMA_BASE_PATH to %OLLAMA_HOST% ^(preserved token_limit=%TOKEN_LIMIT%^)
)

:: -------------------------------------------------------
:: SHOW INSTALLED MODELS
:: -------------------------------------------------------
if exist "%~dp0models\installed-models.txt" (
    echo.
    echo Installed models:
    for /f "usebackq tokens=1,2,3 delims=|" %%a in ("%~dp0models\installed-models.txt") do (
        echo   - %%b [%%c]
    )
    echo.
)

:: Start Ollama Engine silently in the background with PID capture — use quoted path for spaces
echo Starting Ollama Engine on %OLLAMA_HOST%...
set "OLLAMA_PID="
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$p=Start-Process -FilePath '%ESC_OLLAMA_EXE%' -ArgumentList 'serve' -WindowStyle Hidden -PassThru; $p.Id"`) do set "OLLAMA_PID=%%p"
if not defined OLLAMA_PID (
    echo [WARN] Could not capture Ollama PID - fallback to background start
    echo [%date% %time%] WARN PID capture failed, fallback >> "%LOG_FILE%" 2>nul
    start "" /B "%OLLAMA_EXE%" serve
) else (
    echo Ollama PID: %OLLAMA_PID%
    echo [%date% %time%] Ollama PID %OLLAMA_PID% >> "%LOG_FILE%" 2>nul
    :: Bump priority if permitted (best-effort)
    powershell -NoProfile -Command "(Get-Process -Id %OLLAMA_PID% -ErrorAction SilentlyContinue).PriorityClass = 'AboveNormal'" >nul 2>&1
)
set "PID_FILE=%~dp0anythingllm_data\.session_pids"
if defined OLLAMA_PID echo %OLLAMA_PID% > "%PID_FILE%"

:: Health check: wait for Ollama API in single PowerShell polling loop
echo Waiting for Ollama to be ready...
set "OLLAMA_READY=0"
powershell -NoProfile -Command "$ready=$false; for($i=0; $i -lt 30; $i++){ try{ Invoke-RestMethod -Uri 'http://%OLLAMA_HOST%/api/tags' -TimeoutSec 1 | Out-Null; $ready=$true; break } catch { Start-Sleep -Seconds 1 } }; if($ready){ exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 set "OLLAMA_READY=1"

if "%OLLAMA_READY%"=="0" (
    echo [WARN] Ollama did not become ready in 30s - continuing anyway...
    echo [%date% %time%] WARN Ollama not ready 30s >> "%LOG_FILE%" 2>nul
) else (
    echo Ollama is ready.
)

:: Launch AnythingLLM Interface
echo Starting AnythingLLM Interface...

:LaunchApp
:: CRITICAL: We MUST wipe ONLY hardware-dependent Electron caches for portability.
:: Do NOT delete config.json — it holds user settings. Only wipe GPU/Shader caches.
set "ELECTRON_CACHE=%~dp0anythingllm_data\anythingllm-desktop"
if exist "%ELECTRON_CACHE%\GPUCache" rmdir /s /q "%ELECTRON_CACHE%\GPUCache" 2>nul
if exist "%ELECTRON_CACHE%\Cache" rmdir /s /q "%ELECTRON_CACHE%\Cache" 2>nul
if exist "%ELECTRON_CACHE%\Code Cache" rmdir /s /q "%ELECTRON_CACHE%\Code Cache" 2>nul
if exist "%ELECTRON_CACHE%\ShaderCache" rmdir /s /q "%ELECTRON_CACHE%\ShaderCache" 2>nul
:: Legacy fallback — older versions stored cache at root
if exist "%~dp0anythingllm_data\Cache" rmdir /s /q "%~dp0anythingllm_data\Cache" 2>nul
if exist "%~dp0anythingllm_data\GPUCache" rmdir /s /q "%~dp0anythingllm_data\GPUCache" 2>nul

:: CRITICAL: We MUST pushd into the app directory for the portable app to find its own resources!
pushd "%~dp0anythingllm"
:: Pass --user-data-dir — quoted for spaces
start "" "AnythingLLM.exe" --user-data-dir="%~dp0anythingllm_data"
popd

:Running
echo.
echo ===================================================
echo   SYSTEM ONLINE: Your AI is running from the USB!  
echo   Ollama API: http://%OLLAMA_HOST%
echo   Model: %DEFAULT_MODEL% (token_limit=%TOKEN_LIMIT%)
echo ===================================================
echo.
echo You can now use the AnythingLLM window to chat.
echo Keep this black window open to keep the AI engine running!
echo.
echo TIP: Go to Settings ^> LLM to switch between models.
echo.
echo Press any key to SHUT DOWN the AI safely...
echo.
pause

:: Clean shutdown — kill only OUR PIDs, never a host Ollama blindly
if defined OLLAMA_PID (
    taskkill /PID %OLLAMA_PID% /T /F >nul 2>&1
) else if exist "%PID_FILE%" (
    for /f "tokens=1" %%a in (%PID_FILE%) do taskkill /PID %%a /T /F >nul 2>&1
    del "%PID_FILE%" 2>nul
) else (
    :: Last resort: only kill ollama.exe that lives on THIS USB path
    for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "Get-Process ollama -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq '%ESC_OLLAMA_EXE%'} | Select-Object -ExpandProperty Id -First 1"`) do taskkill /PID %%p /T /F >nul 2>&1
)

:: Terminate AnythingLLM only from this USB path to avoid affecting host instances
powershell -NoProfile -Command "Get-Process -Name AnythingLLM -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '%ESC_APP_PATH%' -or $_.Path -like '%~dp0*' } | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }" >nul 2>&1
if exist "%PID_FILE%" del "%PID_FILE%" 2>nul
echo [%date% %time%] Shutdown complete >> "%LOG_FILE%" 2>nul
echo.
echo AI Engine shut down. You may safely eject the USB.
timeout /t 3 >nul
endlocal
