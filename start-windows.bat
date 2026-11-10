@echo off
setlocal enabledelayedexpansion
title PENDRIVE_X AI - Launcher
color 0A

set "USB=%~dp0"
:: %~dp0 always ends with a backslash. Passing that to PowerShell as
:: -UsbRoot "E:\path\" makes \" escape the closing quote, so strip it.
set "USB_ARG=%USB:~0,-1%"
set "TOOLS=%~dp0tools"

echo ===================================================
echo     Launching PENDRIVE_X Engine from USB...       
echo ===================================================

:: -------------------------------------------------------
:: ARGUMENT PARSING
::   --server / --lan   bind to the LAN and show a QR code
::   --engine=NAME      ollama or llamacpp (overrides .env)
::   --model=NAME       model alias or .gguf filename
::   --update-engine    refresh engines/UI, then exit
::   --with-ui          also open the desktop AnythingLLM
::   --headless         server mode without the desktop app
::   --help             show usage
:: -------------------------------------------------------
set "OPT_SERVER="
set "OPT_ENGINE="
set "OPT_MODEL="
set "OPT_UPDATE="
set "OPT_YES="
set "OPT_HELP="
set "OPT_WITH_UI="
set "OPT_HEADLESS="

:parse_args
if "%~1"=="" goto args_done
set "ARG=%~1"

if /I "%ARG%"=="--server" (
    set "OPT_SERVER=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--lan" (
    set "OPT_SERVER=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--headless" (
    set "OPT_SERVER=1"
    set "OPT_HEADLESS=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--with-ui" (
    set "OPT_WITH_UI=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--update-engine" (
    set "OPT_UPDATE=all"
    shift
    goto parse_args
)
if /I "%ARG%"=="--update" (
    set "OPT_UPDATE=all"
    shift
    goto parse_args
)
if /I "%ARG%"=="--yes" (
    set "OPT_YES=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="-y" (
    set "OPT_YES=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--help" (
    set "OPT_HELP=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="-h" (
    set "OPT_HELP=1"
    shift
    goto parse_args
)
if /I "%ARG%"=="--engine" (
    set "OPT_ENGINE=%~2"
    shift
    shift
    goto parse_args
)
if /I "%ARG%"=="--model" (
    set "OPT_MODEL=%~2"
    shift
    shift
    goto parse_args
)

:: Prefix checks use substring expansion to survive & and | in values.
if /I "!ARG:~0,9!"=="--engine=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "OPT_ENGINE=%%b"
    shift
    goto parse_args
)
if /I "!ARG:~0,8!"=="--model=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "OPT_MODEL=%%b"
    shift
    goto parse_args
)
if /I "!ARG:~0,16!"=="--update-engine=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "OPT_UPDATE=%%b"
    shift
    goto parse_args
)

echo [WARN] Ignoring unknown option: %ARG% >> "%~dp0anythingllm_data\logs\launcher-args.log" 2>nul
shift
goto parse_args

:args_done
if defined OPT_HELP goto show_help

:: -------------------------------------------------------
:: LOGGING — tee to anythingllm_data\logs\launcher-*.log
:: -------------------------------------------------------
set "LOG_DIR=%~dp0anythingllm_data\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul
for /f "usebackq tokens=*" %%d in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmmss'"`) do set "LOG_TS=%%d"
if not defined LOG_TS set "LOG_TS=session"
set "LOG_FILE=%LOG_DIR%\launcher-%LOG_TS%.log"
echo [%date% %time%] Launcher started >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: FAT32 GUARD — 4 GB per-file limit blocks GGUF models
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
:: RUNTIME CONFIG — <USB>\.env (created from .env.example)
:: -------------------------------------------------------
if not exist "%~dp0.env" if exist "%~dp0.env.example" copy /y "%~dp0.env.example" "%~dp0.env" >nul 2>&1

set "CFG_ENGINE=ollama"
set "CFG_AUTO_TUNE=1"
set "CFG_SERVER=0"
set "CFG_OLLAMA_PORT=0"
set "CFG_LLAMACPP_PORT=0"
set "CFG_LAN_CHAT_PORT=8090"
set "CFG_LLAMACPP_MODEL="
set "CFG_LLAMACPP_NGL=auto"
set "CFG_LLAMACPP_THREADS=auto"
set "CFG_LLAMACPP_CTX=auto"
set "CFG_LLAMACPP_EXTRA_ARGS="
set "CFG_OLLAMA_KEEP_ALIVE=30m"
set "CFG_OLLAMA_NUM_PARALLEL=1"

if exist "%~dp0.env" (
    for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0.env") do (
        set "ENV_K=%%a"
        set "ENV_V=%%b"
        if not "!ENV_K:~0,1!"=="#" (
            if /I "!ENV_K!"=="INFERENCE_ENGINE" set "CFG_ENGINE=!ENV_V!"
            if /I "!ENV_K!"=="AUTO_TUNE" set "CFG_AUTO_TUNE=!ENV_V!"
            if /I "!ENV_K!"=="SERVER_MODE" set "CFG_SERVER=!ENV_V!"
            if /I "!ENV_K!"=="OLLAMA_PORT" set "CFG_OLLAMA_PORT=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_PORT" set "CFG_LLAMACPP_PORT=!ENV_V!"
            if /I "!ENV_K!"=="LAN_CHAT_PORT" set "CFG_LAN_CHAT_PORT=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_MODEL" set "CFG_LLAMACPP_MODEL=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_NGL" set "CFG_LLAMACPP_NGL=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_THREADS" set "CFG_LLAMACPP_THREADS=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_CTX" set "CFG_LLAMACPP_CTX=!ENV_V!"
            if /I "!ENV_K!"=="LLAMACPP_EXTRA_ARGS" set "CFG_LLAMACPP_EXTRA_ARGS=!ENV_V!"
            if /I "!ENV_K!"=="OLLAMA_KEEP_ALIVE" set "CFG_OLLAMA_KEEP_ALIVE=!ENV_V!"
            if /I "!ENV_K!"=="OLLAMA_NUM_PARALLEL" set "CFG_OLLAMA_NUM_PARALLEL=!ENV_V!"
        )
    )
)

:: Strip common whitespace/quotes from engine and numeric values.
set "CFG_ENGINE=!CFG_ENGINE: =!"
set "CFG_ENGINE=!CFG_ENGINE:"=!"
if defined OPT_ENGINE set "CFG_ENGINE=%OPT_ENGINE%"
if /I "%CFG_ENGINE%"=="llama.cpp" set "CFG_ENGINE=llamacpp"
if /I "%CFG_ENGINE%"=="llama-cpp" set "CFG_ENGINE=llamacpp"
if /I not "%CFG_ENGINE%"=="llamacpp" set "CFG_ENGINE=ollama"

set "SERVER_MODE=%CFG_SERVER%"
if defined OPT_SERVER set "SERVER_MODE=1"
if not "%SERVER_MODE%"=="1" set "SERVER_MODE=0"

:: Normalise numeric settings from .env (spaces/quotes/0 = auto).
set "CFG_OLLAMA_PORT=!CFG_OLLAMA_PORT: =!"
set "CFG_LLAMACPP_PORT=!CFG_LLAMACPP_PORT: =!"
set "CFG_LAN_CHAT_PORT=!CFG_LAN_CHAT_PORT: =!"
set "CFG_OLLAMA_NUM_PARALLEL=!CFG_OLLAMA_NUM_PARALLEL: =!"
set "CFG_OLLAMA_PORT=!CFG_OLLAMA_PORT:"=!"
set "CFG_LLAMACPP_PORT=!CFG_LLAMACPP_PORT:"=!"
set "CFG_LAN_CHAT_PORT=!CFG_LAN_CHAT_PORT:"=!"
set "CFG_OLLAMA_NUM_PARALLEL=!CFG_OLLAMA_NUM_PARALLEL:"=!"
if "%CFG_OLLAMA_PORT%"=="" set "CFG_OLLAMA_PORT=0"
if "%CFG_LLAMACPP_PORT%"=="" set "CFG_LLAMACPP_PORT=0"
if "%CFG_LAN_CHAT_PORT%"=="" set "CFG_LAN_CHAT_PORT=8090"
if "%CFG_OLLAMA_NUM_PARALLEL%"=="" set "CFG_OLLAMA_NUM_PARALLEL=1"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_OLLAMA_PORT%") do set "NUM=0"
if "%NUM%"=="0" set "CFG_OLLAMA_PORT=0"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_LLAMACPP_PORT%") do set "NUM=0"
if "%NUM%"=="0" set "CFG_LLAMACPP_PORT=0"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_LAN_CHAT_PORT%") do set "NUM=0"
if "%NUM%"=="0" set "CFG_LAN_CHAT_PORT=8090"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_OLLAMA_NUM_PARALLEL%") do set "NUM=0"
if "%NUM%"=="0" set "CFG_OLLAMA_NUM_PARALLEL=1"

set "ENGINE_LABEL=Ollama"
if /I "%CFG_ENGINE%"=="llamacpp" set "ENGINE_LABEL=llama.cpp"

:: -------------------------------------------------------
:: UPDATE MODE — refresh engines/UI without touching data
:: -------------------------------------------------------
if defined OPT_UPDATE (
    echo.
    echo Updating engines and UI ^(models and chats preserved^)...
    set "UPD_ARGS=-UpdateEngine"
    if /I "%OPT_UPDATE%"=="both" set "OPT_UPDATE=all"
    if /I not "%OPT_UPDATE%"=="all" set "UPD_ARGS=!UPD_ARGS! -Engine %OPT_UPDATE%"
    if defined OPT_YES set "UPD_ARGS=!UPD_ARGS! -Yes"
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-core.ps1" !UPD_ARGS!
    set "UPD_EXIT=%ERRORLEVEL%"
    if not defined OPT_YES pause
    exit /b %UPD_EXIT%
)

:: -------------------------------------------------------
:: IMPORTANT: All paths must point to USB, not the PC!
:: -------------------------------------------------------
set "OLLAMA_EXE=%~dp0ollama\ollama.exe"
set "LLAMA_EXE=%~dp0llamacpp\llama-server.exe"
set "APP_PATH=%~dp0anythingllm\AnythingLLM.exe"
set "ESC_APP_PATH=%APP_PATH:'=''%"
set "OLLAMA_MODELS=%~dp0ollama\data"
set "STORAGE_DIR=%~dp0anythingllm_data"
set "ANYTHINGLLM_PROFILE=%STORAGE_DIR%\anythingllm-desktop"
set "PID_FILE=%~dp0anythingllm_data\.session_pids"
set "APPDATA=%~dp0anythingllm_data"
set "LOCALAPPDATA=%~dp0anythingllm_data"

:: Validate the selected engine before starting background services
if /I "%CFG_ENGINE%"=="ollama" (
    if not exist "%OLLAMA_EXE%" (
        echo.
        echo ERROR: Ollama engine was not found at:
        echo   %OLLAMA_EXE%
        echo Run install.bat --engine=ollama to install it.
        echo.
        pause
        exit /b 1
    )
) else (
    if not exist "%LLAMA_EXE%" (
        echo.
        echo ERROR: llama-server was not found at:
        echo   %LLAMA_EXE%
        echo Run install.bat --engine=llamacpp to install it.
        echo.
        pause
        exit /b 1
    )
)

if not exist "%~dp0anythingllm_data" mkdir "%~dp0anythingllm_data" 2>nul
if not exist "%ANYTHINGLLM_PROFILE%" mkdir "%ANYTHINGLLM_PROFILE%" 2>nul
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

:: -------------------------------------------------------
:: MODEL SELECTION
:: -------------------------------------------------------
set "MODEL_NAME="
if defined OPT_MODEL set "MODEL_NAME=%OPT_MODEL%"
if not defined MODEL_NAME set "MODEL_NAME=%CFG_LLAMACPP_MODEL%"
if not defined MODEL_NAME (
    if exist "%~dp0models\installed-models.txt" (
        for /f "usebackq tokens=1 delims=|" %%m in ("%~dp0models\installed-models.txt") do (
            set "MODEL_NAME=%%m"
            goto :got_model
        )
    )
)
:got_model
if not defined MODEL_NAME set "MODEL_NAME=nemomix-local"
if /I "%MODEL_NAME%"=="nemomix-local_X" set "MODEL_NAME=nemomix-local"

set "MODEL_FILE="
if exist "%~dp0models\%MODEL_NAME%.gguf" set "MODEL_FILE=%MODEL_NAME%.gguf"
if not defined MODEL_FILE (
    if exist "%~dp0models\Modelfile-%MODEL_NAME%" (
        for /f "usebackq tokens=1,*" %%a in ("%~dp0models\Modelfile-%MODEL_NAME%") do (
            if /I "%%a"=="FROM" (
                set "MODEL_FILE=%%b"
                goto :got_file
            )
        )
    )
)
:got_file
if defined MODEL_FILE set "MODEL_FILE=!MODEL_FILE:./=!"
if defined MODEL_FILE set "MODEL_FILE=!MODEL_FILE:.\=!"
if not defined MODEL_FILE (
    for %%f in ("%~dp0models\*.gguf") do (
        set "MODEL_FILE=%%~nxf"
        goto :got_file2
    )
)
:got_file2

set "MODEL_PATH="
if defined MODEL_FILE if exist "%~dp0models\!MODEL_FILE!" set "MODEL_PATH=%~dp0models\!MODEL_FILE!"

if /I "%CFG_ENGINE%"=="llamacpp" (
    if not defined MODEL_PATH (
        echo.
        echo ERROR: No GGUF model found in "%~dp0models".
        echo Run install.bat to download a model first.
        echo.
        pause
        exit /b 1
    )
)

:: -------------------------------------------------------
:: PORT ALLOCATION — dynamic by default, fixed via .env
:: -------------------------------------------------------
set "ENGINE_PORT=%CFG_OLLAMA_PORT%"
if /I "%CFG_ENGINE%"=="llamacpp" set "ENGINE_PORT=%CFG_LLAMACPP_PORT%"
if "%ENGINE_PORT%"=="0" (
    call :free_port
    set "ENGINE_PORT=!FREE_PORT!"
)
if not defined ENGINE_PORT set "ENGINE_PORT=11434"
set "LAN_CHAT_PORT=%CFG_LAN_CHAT_PORT%"
if "%LAN_CHAT_PORT%"=="0" (
    call :free_port
    set "LAN_CHAT_PORT=!FREE_PORT!"
)

set "BIND_HOST=127.0.0.1"
if "%SERVER_MODE%"=="1" set "BIND_HOST=0.0.0.0"

echo [+] Engine: %ENGINE_LABEL%
echo [+] Model:  %MODEL_NAME%
if defined MODEL_FILE echo [+] GGUF:   %MODEL_FILE%
echo [+] Port:   %ENGINE_PORT%
echo [%date% %time%] Engine=%CFG_ENGINE% Model=%MODEL_NAME% Port=%ENGINE_PORT% >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: HARDWARE AUTO-TUNING
:: -------------------------------------------------------
set "HW_ACCEL=cpu"
set "HW_GPU_NAME="
set "HW_VRAM_GB=0"
set "HW_NGL=0"
set "HW_THREADS=4"
set "HW_CTX=4096"
set "HW_RAM_GB=0"
set "HW_ACCEL_NOTE=CPU only"
set "AUTO_TUNE=%CFG_AUTO_TUNE%"

if exist "%TOOLS%\hardware.ps1" (
    for /f "usebackq tokens=1,* delims==" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\hardware.ps1" -ModelPath "%MODEL_PATH%"`) do (
        if /I "%%a"=="PENDRIVE_ACCEL" set "HW_ACCEL=%%b"
        if /I "%%a"=="PENDRIVE_GPU_NAME" set "HW_GPU_NAME=%%b"
        if /I "%%a"=="PENDRIVE_VRAM_GB" set "HW_VRAM_GB=%%b"
        if /I "%%a"=="PENDRIVE_NGL" set "HW_NGL=%%b"
        if /I "%%a"=="PENDRIVE_THREADS" set "HW_THREADS=%%b"
        if /I "%%a"=="PENDRIVE_CTX" set "HW_CTX=%%b"
        if /I "%%a"=="PENDRIVE_RAM_GB" set "HW_RAM_GB=%%b"
        if /I "%%a"=="PENDRIVE_ACCEL_NOTE" set "HW_ACCEL_NOTE=%%b"
    )
)

:: User overrides in .env (numbers only; "auto" keeps detection)
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_LLAMACPP_NGL%") do set "NUM=0"
if "%NUM%"=="1" if not "%CFG_LLAMACPP_NGL%"=="" set "HW_NGL=%CFG_LLAMACPP_NGL%"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_LLAMACPP_THREADS%") do set "NUM=0"
if "%NUM%"=="1" if not "%CFG_LLAMACPP_THREADS%"=="" set "HW_THREADS=%CFG_LLAMACPP_THREADS%"
set "NUM=1"
for /f "delims=0123456789" %%x in ("%CFG_LLAMACPP_CTX%") do set "NUM=0"
if "%NUM%"=="1" if not "%CFG_LLAMACPP_CTX%"=="" set "HW_CTX=%CFG_LLAMACPP_CTX%"

echo [+] Acceleration: %HW_ACCEL_NOTE%
echo [+] Tuning: layers=%HW_NGL% threads=%HW_THREADS% ctx=%HW_CTX%
echo [%date% %time%] HW %HW_ACCEL% %HW_GPU_NAME% ngl=%HW_NGL% threads=%HW_THREADS% ctx=%HW_CTX% >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: START THE ENGINE
:: -------------------------------------------------------
echo.
echo Starting %ENGINE_LABEL% on %BIND_HOST%:%ENGINE_PORT%...
set "ENGINE_PID="
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\start-engine.ps1" -Engine %CFG_ENGINE% -UsbRoot "%USB_ARG%" -ModelPath "%MODEL_PATH%" -ModelAlias "%MODEL_NAME%" -Port %ENGINE_PORT% -BindHost %BIND_HOST% -Ngl %HW_NGL% -Ctx %HW_CTX% -Threads %HW_THREADS% -ExtraArgs "%CFG_LLAMACPP_EXTRA_ARGS%" -KeepAlive "%CFG_OLLAMA_KEEP_ALIVE%" -NumParallel %CFG_OLLAMA_NUM_PARALLEL% -LogFile "%LOG_DIR%\engine-%LOG_TS%.log"`) do set "ENGINE_PID=%%p"

if not defined ENGINE_PID (
    echo [ERROR] Could not start the engine. See:
    echo   %LOG_DIR%\engine-%LOG_TS%.log.err.log
    echo [%date% %time%] ERROR engine failed to start >> "%LOG_FILE%" 2>nul
    pause
    exit /b 1
)
echo %ENGINE_PID% > "%~dp0anythingllm_data\.session_pids"
echo [+] Engine PID: %ENGINE_PID%
echo [%date% %time%] Engine PID %ENGINE_PID% >> "%LOG_FILE%" 2>nul
powershell -NoProfile -Command "(Get-Process -Id %ENGINE_PID% -ErrorAction SilentlyContinue).PriorityClass = 'AboveNormal'" >nul 2>&1

:: -------------------------------------------------------
:: HEALTH CHECK
:: -------------------------------------------------------
set "HEALTH_URL=http://127.0.0.1:%ENGINE_PORT%/api/tags"
if /I "%CFG_ENGINE%"=="llamacpp" set "HEALTH_URL=http://127.0.0.1:%ENGINE_PORT%/health"
echo Waiting for %ENGINE_LABEL% to load the model...
powershell -NoProfile -Command "for($i=0; $i -lt 120; $i++){ try{ $r=Invoke-WebRequest -Uri '%HEALTH_URL%' -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200){ exit 0 } } catch { }; Start-Sleep -Seconds 1 }; exit 1" >nul 2>&1
if errorlevel 1 (
    echo [WARN] Engine did not become ready in 120s - continuing anyway...
    echo [%date% %time%] WARN engine not ready after 120s >> "%LOG_FILE%" 2>nul
) else (
    echo [+] %ENGINE_LABEL% is ready.
)

:: -------------------------------------------------------
:: CONFIGURE ANYTHINGLLM
:: -------------------------------------------------------
set "TOKEN_LIMIT=4096"
if exist "%TOOLS%\config-anythingllm.ps1" (
    set "CFG_ARGS=-Engine %CFG_ENGINE% -UsbRoot "%USB_ARG%" -Port %ENGINE_PORT% -Model "%MODEL_NAME%""
    if "%SERVER_MODE%"=="1" set "CFG_ARGS=!CFG_ARGS! -ServerMode -LanPort %LAN_CHAT_PORT%"
    for /f "usebackq tokens=*" %%t in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\config-anythingllm.ps1" !CFG_ARGS!`) do set "TOKEN_LIMIT=%%t"
)
echo [+] AnythingLLM configured: %CFG_ENGINE% @ 127.0.0.1:%ENGINE_PORT% ^(token_limit=%TOKEN_LIMIT%^)
echo [%date% %time%] AnythingLLM provider=%CFG_ENGINE% port=%ENGINE_PORT% >> "%LOG_FILE%" 2>nul

:: -------------------------------------------------------
:: LAN / QR MODE
:: -------------------------------------------------------
set "LAN_IP=127.0.0.1"
set "CHAT_PID="
set "LAN_URL="
if "%SERVER_MODE%"=="1" (
    for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "$a=Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue; $ip=$null; foreach($x in $a){ if($x.IPAddress -notlike '127.*' -and $x.IPAddress -notlike '169.254.*'){ $ip=$x.IPAddress; break } }; if(-not $ip){$ip='127.0.0.1'}; $ip"`) do set "LAN_IP=%%i"

    if /I "%CFG_ENGINE%"=="llamacpp" (
        set "LAN_URL=http://!LAN_IP!:%ENGINE_PORT%/"
    ) else (
        if exist "%TOOLS%\lan-chat.ps1" (
            for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\lan-chat.ps1" -Start -Port %LAN_CHAT_PORT% -OllamaUrl http://127.0.0.1:%ENGINE_PORT% -Model "%MODEL_NAME%" -LogFile "%LOG_DIR%\lan-chat-%LOG_TS%.log"`) do set "CHAT_PID=%%p"
            if defined CHAT_PID echo !CHAT_PID! >> "%PID_FILE%" 2>nul
            set "LAN_URL=http://!LAN_IP!:%LAN_CHAT_PORT%/"
        ) else (
            set "LAN_URL=http://!LAN_IP!:%ENGINE_PORT%/"
        )
    )

    echo.
    echo ===================================================
    echo   LAN / PHONE MODE
    echo ===================================================
    echo   Open on any device on this Wi-Fi:
    echo     !LAN_URL!
    echo   Engine API: http://!LAN_IP!:%ENGINE_PORT%
    echo   Model:      %MODEL_NAME%
    echo ===================================================
    echo.
    echo [%date% %time%] LAN URL !LAN_URL! IP !LAN_IP! >> "%LOG_FILE%" 2>nul
    if exist "%TOOLS%\qr.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%TOOLS%\qr.ps1" -Text "!LAN_URL!"
    )
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

:: -------------------------------------------------------
:: LAUNCH DESKTOP UI (skipped in headless server mode)
:: -------------------------------------------------------
if "%SERVER_MODE%"=="1" if not defined OPT_WITH_UI goto :server_running

if not exist "%APP_PATH%" (
    echo [WARN] AnythingLLM not found at %APP_PATH% - skipping desktop UI.
    echo [%date% %time%] WARN AnythingLLM missing >> "%LOG_FILE%" 2>nul
    goto :server_running
)

echo Starting AnythingLLM Interface...

:LaunchApp
:: Wipe only hardware-dependent Electron caches for portability.
set "ELECTRON_CACHE=%~dp0anythingllm_data\anythingllm-desktop"
if exist "%ELECTRON_CACHE%\GPUCache" rmdir /s /q "%ELECTRON_CACHE%\GPUCache" 2>nul
if exist "%ELECTRON_CACHE%\Cache" rmdir /s /q "%ELECTRON_CACHE%\Cache" 2>nul
if exist "%ELECTRON_CACHE%\Code Cache" rmdir /s /q "%ELECTRON_CACHE%\Code Cache" 2>nul
if exist "%ELECTRON_CACHE%\ShaderCache" rmdir /s /q "%ELECTRON_CACHE%\ShaderCache" 2>nul
if exist "%~dp0anythingllm_data\Cache" rmdir /s /q "%~dp0anythingllm_data\Cache" 2>nul
if exist "%~dp0anythingllm_data\GPUCache" rmdir /s /q "%~dp0anythingllm_data\GPUCache" 2>nul

pushd "%~dp0anythingllm"
start "" "AnythingLLM.exe" --user-data-dir="%~dp0anythingllm_data"
popd

:server_running
echo.
echo ===================================================
echo   SYSTEM ONLINE: Your AI is running from the USB!  
echo   Engine: %ENGINE_LABEL% @ http://127.0.0.1:%ENGINE_PORT%
echo   Model:  %MODEL_NAME% ^(token_limit=%TOKEN_LIMIT%^)
if "%SERVER_MODE%"=="1" echo   Phone:  !LAN_URL!
echo ===================================================
echo.
if "%SERVER_MODE%"=="1" (
    echo Keep this window open while your phone is connected.
) else (
    echo Use the AnythingLLM window to chat.
    echo Keep this black window open to keep the AI engine running!
)
echo.
echo Press any key to SHUT DOWN the AI safely...
echo.
pause

:: -------------------------------------------------------
:: CLEAN SHUTDOWN — kill only OUR PIDs
:: -------------------------------------------------------
set "PID_FILE=%~dp0anythingllm_data\.session_pids"
if exist "%PID_FILE%" (
    for /f "usebackq tokens=1" %%a in ("%PID_FILE%") do taskkill /PID %%a /T /F >nul 2>&1
    del "%PID_FILE%" 2>nul
)
if defined CHAT_PID taskkill /PID %CHAT_PID% /T /F >nul 2>&1
if defined ENGINE_PID taskkill /PID %ENGINE_PID% /T /F >nul 2>&1

:: Terminate AnythingLLM only from this USB path to avoid host instances
powershell -NoProfile -Command "Get-Process -Name AnythingLLM -ErrorAction SilentlyContinue ^| Where-Object { $_.Path -like '%ESC_APP_PATH%' -or $_.Path -like '%~dp0*' } ^| ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }" >nul 2>&1
echo [%date% %time%] Shutdown complete >> "%LOG_FILE%" 2>nul
echo.
echo AI Engine shut down. You may safely eject the USB.
timeout /t 3 >nul
endlocal
exit /b 0

:: -------------------------------------------------------
:: SUBROUTINES
:: -------------------------------------------------------
:free_port
set "FREE_PORT="
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$l=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); $p"`) do set "FREE_PORT=%%p"
if not defined FREE_PORT set "FREE_PORT=11434"
goto :eof

:show_help
echo.
echo PENDRIVE_X AI - Launcher usage:
echo.
echo   start-windows.bat                  Start with settings from .env
echo   start-windows.bat --server         Bind to the LAN and show a QR code
echo   start-windows.bat --lan            Same as --server
echo   start-windows.bat --headless       LAN mode without the desktop app
echo   start-windows.bat --engine=llamacpp  Force llama.cpp for this run
echo   start-windows.bat --engine=ollama    Force Ollama for this run
echo   start-windows.bat --model=qwen-local Use a specific model
echo   start-windows.bat --update-engine  Update engines/UI, then exit
echo   start-windows.bat --with-ui        Open desktop UI even in LAN mode
echo   start-windows.bat --help           Show this help
echo.
echo Settings live in: %~dp0.env
echo.
exit /b 0
