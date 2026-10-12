@echo off
setlocal enabledelayedexpansion
title PENDRIVE_X AI Launcher Pro v0.07 - JAMES BOND EDITION [HARDENED]
color 0B

:: ═══════════════════════════════════════════════════════════════
:: 1. RUTAS Y VARIABLES DE ENTORNO (Blindaje Total)
:: ═══════════════════════════════════════════════════════════════
set "USB_ROOT=%~dp0"
set "DATA_DIR=%USB_ROOT%anythingllm_data"
set "OLLAMA_DIR=%USB_ROOT%ollama"
set "OLLAMA_MODELS=%OLLAMA_DIR%\data"
set "MODELS_DIR=%USB_ROOT%models"

:: Path virtualization: fuerza todo hacia el USB
set "USERPROFILE=%DATA_DIR%"
set "APPDATA=%DATA_DIR%"
set "LOCALAPPDATA=%DATA_DIR%"
set "TEMP=%DATA_DIR%\temp"
set "TMP=%DATA_DIR%\temp"

if not exist "%DATA_DIR%\temp" mkdir "%DATA_DIR%\temp" 2>nul

:: FAT32 guard (like preflight-check.sh:484)
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$d='%~d0'; try{$v=Get-CimInstance -ClassName Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d) -ErrorAction Stop; $v.FileSystem} catch {''}"`) do set "FS_TYPE=%%a"
if /I "%FS_TYPE%"=="FAT32" (
    echo [ERROR] FAT32 no soportado / FAT32 not supported — Reformatea como exFAT ^(Format as exFAT^).
    pause & endlocal & exit /b 1
)

:: Logging
set "LOG_DIR=%DATA_DIR%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

echo ===================================================
echo     SISTEMA IA PORTABLE - JAMES BOND EDITION v0.07
echo     PORTABLE AI SYSTEM - JAMES BOND EDITION v0.07 ^(EN/ES^)
echo ===================================================

:: ═══════════════════════════════════════════════════════════════
:: 2. VERIFICACION DE ESPACIO EN DISCO (Locale-Independent)
:: ═══════════════════════════════════════════════════════════════
set "FREE_MB=-1"
for /f "usebackq tokens=*" %%a in (`powershell -NoProfile -Command "$d='%~d0'; try { $vol=Get-CimInstance -ClassName Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d) -ErrorAction Stop; if($vol -and $vol.FreeSpace -ne $null){[math]::Round($vol.FreeSpace/1MB,0)}else{-1} } catch {-1}"`) do set "FREE_MB=%%a"
if not defined FREE_MB set "FREE_MB=-1"

:: Guard against empty or non-numeric FREE_MB before numeric compare
set "FREE_MB_NUM=0"
for /f "delims=0123456789-" %%x in ("%FREE_MB%") do set "FREE_MB_NUM=1"
if "%FREE_MB_NUM%"=="1" set "FREE_MB=-1"

if %FREE_MB% LSS 500 (
    if %FREE_MB% GTR 0 (
        echo [!] ADVERTENCIA: Solo %FREE_MB% MB libres en el USB.
    ) else (
        echo [!] ADVERTENCIA: No se pudo verificar espacio libre.
    )
    echo     Esto puede corromper tus chats. Libera al menos 500 MB.
    pause
)

:: ═══════════════════════════════════════════════════════════════
:: 3. LECTURA DEL MODELO POR DEFECTO
:: ═══════════════════════════════════════════════════════════════
set "DEFAULT_MODEL=nemomix-local"
if exist "%MODELS_DIR%\installed-models.txt" (
    for /f "usebackq tokens=1 delims=|" %%a in ("%MODELS_DIR%\installed-models.txt") do (
        set "DEFAULT_MODEL=%%a"
        goto :GotModel
    )
)
:GotModel

:: ═══════════════════════════════════════════════════════════════
:: 4. LIMPIEZA DE CACHES ELECTRON (Evita errores JS al cambiar de PC/GPU)
:: ═══════════════════════════════════════════════════════════════
set "ANYTHINGLLM_CACHE=%DATA_DIR%\anythingllm-desktop"
if exist "%ANYTHINGLLM_CACHE%" (
    rmdir /S /Q "%ANYTHINGLLM_CACHE%\GPUCache" 2>nul
    rmdir /S /Q "%ANYTHINGLLM_CACHE%\Cache" 2>nul
    rmdir /S /Q "%ANYTHINGLLM_CACHE%\Code Cache" 2>nul
    rmdir /S /Q "%ANYTHINGLLM_CACHE%\ShaderCache" 2>nul
)

:: ═══════════════════════════════════════════════════════════════
:: 5. BUSCAR PUERTO LIBRE (Evita colision con Ollama del host)
:: ═══════════════════════════════════════════════════════════════
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$l=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0); $l.Start(); $p=$l.LocalEndpoint.Port; $l.Stop(); $p"`) do set "OLLAMA_PORT=%%p"
set "OLLAMA_HOST=127.0.0.1:%OLLAMA_PORT%"
echo [+] Puerto Ollama dinamico asignado: %OLLAMA_PORT%

:: ═══════════════════════════════════════════════════════════════
:: 6. LIMPIAR SESION ANTERIOR (Solo nuestros PIDs, NUNCA el host)
:: ═══════════════════════════════════════════════════════════════
set "PID_FILE=%DATA_DIR%\.session_pids"
if exist "%PID_FILE%" (
    for /f "tokens=1,2" %%a in (%PID_FILE%) do (
        if not "%%a"=="" if not "%%a"=="0" taskkill /PID %%a /T /F >nul 2>&1
        if not "%%b"=="" if not "%%b"=="0" taskkill /PID %%b /T /F >nul 2>&1
    )
    del "%PID_FILE%" 2>nul
)

:: ═══════════════════════════════════════════════════════════════
:: 7. LANZAR MOTOR OLLAMA (con prioridad y captura de PID)
:: ═══════════════════════════════════════════════════════════════
echo [+] Iniciando motor Ollama en %OLLAMA_HOST%...
if not exist "%OLLAMA_DIR%\ollama.exe" (
    echo [ERROR] No se encuentra ollama.exe en %OLLAMA_DIR%
    pause & exit /b 1
)
if not exist "%USB_ROOT%anythingllm\AnythingLLM.exe" (
    echo [ERROR] No se encuentra AnythingLLM.exe en %USB_ROOT%anythingllm
    pause & exit /b 1
)

:: Lanzar via PowerShell para capturar PID de forma fiable (con escape de comillas simples)
set "ESC_OLLAMA_EXE=%OLLAMA_DIR:'=''%\ollama.exe"
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$proc=Start-Process -FilePath '%ESC_OLLAMA_EXE%' -ArgumentList 'serve' -WindowStyle Hidden -PassThru; $proc.Id"`) do set "OLLAMA_PID=%%p"

if not defined OLLAMA_PID (
    echo [ERROR] No se pudo iniciar Ollama o capturar su PID.
    pause & exit /b 1
)

:: Subir prioridad a AboveNormal (best-effort, no requiere admin)
powershell -NoProfile -Command "(Get-Process -Id %OLLAMA_PID% -ErrorAction SilentlyContinue).PriorityClass = 'AboveNormal'" >nul 2>&1

:: ═══════════════════════════════════════════════════════════════
:: 8. HEALTHCHECK (Polling via PowerShell, mas robusto que curl)
:: ═══════════════════════════════════════════════════════════════
set /a "attempts=0"
echo | set /p "=Esperando motor"
:WaitForOllama
set /a "attempts+=1"
if %attempts% GEQ 40 (
    echo.
    echo [ERROR] Timeout esperando Ollama en puerto %OLLAMA_PORT%.
    echo         El motor no respondio. Revisa firewall o reinstala.
    taskkill /PID %OLLAMA_PID% /F /T >nul 2>&1
    pause & exit /b 1
)

powershell -NoProfile -Command "try { Invoke-RestMethod -Uri 'http://%OLLAMA_HOST%/api/tags' -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo. [OK] Motor activo.
    goto :OllamaReady
)
echo | set /p "=."
timeout /t 1 /nobreak >nul
goto :WaitForOllama
:OllamaReady

:: ═══════════════════════════════════════════════════════════════
:: 9. CONFIGURAR ANYTHINGLLM (.env — preserve custom model and token limit)
:: ═══════════════════════════════════════════════════════════════
if not exist "%DATA_DIR%\storage" mkdir "%DATA_DIR%\storage" 2>nul
set "ENV_FILE=%DATA_DIR%\storage\.env"
set "TOKEN_LIMIT=4096"
set "SAVED_MODEL="
if exist "%ENV_FILE%" (
    for /f "usebackq tokens=1,2 delims==" %%a in ("%ENV_FILE%") do (
        if /I "%%a"=="OLLAMA_MODEL_TOKEN_LIMIT" set "TOKEN_LIMIT=%%b"
        if /I "%%a"=="OLLAMA_MODEL_PREF" if not "%%b"=="" set "SAVED_MODEL=%%b"
    )
)
if defined SAVED_MODEL set "DEFAULT_MODEL=%SAVED_MODEL%"
:: Validate token limit is numeric, fallback to 4096
for /f "delims=0123456789" %%x in ("%TOKEN_LIMIT%") do set "TOKEN_LIMIT=4096"

(
    echo LLM_PROVIDER=ollama
    echo OLLAMA_BASE_PATH=http://%OLLAMA_HOST%
    echo OLLAMA_MODEL_PREF=%DEFAULT_MODEL%
    echo OLLAMA_MODEL_TOKEN_LIMIT=%TOKEN_LIMIT%
    echo EMBEDDING_ENGINE=native
    echo VECTOR_DB=lancedb
) > "%ENV_FILE%"

echo [+] AnythingLLM configurado: %DEFAULT_MODEL% @ %OLLAMA_HOST% (token_limit=%TOKEN_LIMIT%)

:: ═══════════════════════════════════════════════════════════════
:: 10. LANZAR ANYTHINGLLM (Modo Privacidad Maxima)
:: ═══════════════════════════════════════════════════════════════
echo [+] Lanzando interfaz con proteccion de datos...
pushd "%USB_ROOT%anythingllm"

set "LLM_ARGS=--user-data-dir="%DATA_DIR%" --no-sandbox --disable-gpu-shader-disk-cache --disable-software-rasterizer --disable-dev-shm-usage --disable-metrics --disable-breakpad"
start "" /Abovenormal "AnythingLLM.exe" %LLM_ARGS%

popd

:: Capturar PID de AnythingLLM (esperar a que aparezca en el sistema)
timeout /t 2 /nobreak >nul
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "$proc=Get-Process 'AnythingLLM' -ErrorAction SilentlyContinue | Select-Object -First 1; if($proc){$proc.Id}else{0}"`) do set "ANYTHINGLLM_PID=%%p"

:: Guardar PIDs para cierre limpio en la proxima ejecucion
if defined OLLAMA_PID (
    if defined ANYTHINGLLM_PID if not "%ANYTHINGLLM_PID%"=="0" (
        echo %OLLAMA_PID% %ANYTHINGLLM_PID% > "%PID_FILE%"
    ) else (
        echo %OLLAMA_PID% 0 > "%PID_FILE%"
    )
)

echo.
echo ===================================================
echo     SISTEMA ACTIVO - SESION ULTRA-SEGURA
echo     Ollama API: http://%OLLAMA_HOST%
echo     Modelo:     %DEFAULT_MODEL%
echo ===================================================
echo.
echo [i] Manten esta ventana abierta.
echo [i] Presiona cualquier tecla para cerrar de forma segura.
pause

:: ═══════════════════════════════════════════════════════════════
:: 11. CIERRE DE SEGURIDAD MILITAR (Solo nuestros procesos)
:: ═══════════════════════════════════════════════════════════════
echo [+] Cerrando sistemas y sincronizando...

:: Cierre graceful primero, luego forzado
if defined ANYTHINGLLM_PID if not "%ANYTHINGLLM_PID%"=="0" (
    taskkill /PID %ANYTHINGLLM_PID% /T >nul 2>&1
    timeout /t 2 /nobreak >nul
    taskkill /PID %ANYTHINGLLM_PID% /F /T >nul 2>&1
)

if defined OLLAMA_PID (
    taskkill /PID %OLLAMA_PID% /T >nul 2>&1
    timeout /t 3 /nobreak >nul
    taskkill /PID %OLLAMA_PID% /F /T >nul 2>&1
)

:: Fallback extremo pero SEGURO: solo si el exe esta en NUESTRA ruta USB
for /f "usebackq tokens=*" %%p in (`powershell -NoProfile -Command "Get-Process ollama -ErrorAction SilentlyContinue | Where-Object {$_.Path -eq '%ESC_OLLAMA_EXE%'} | Select-Object -ExpandProperty Id -First 1"`) do (
    if not "%%p"=="" taskkill /PID %%p /F /T >nul 2>&1
)

:: Sincronizacion forzada de cache de escritura
set "ESC_DATA_DIR=%DATA_DIR:'=''%"
powershell -NoProfile -Command "[System.IO.File]::Create('%ESC_DATA_DIR%\sync.tmp').Dispose(); Remove-Item '%ESC_DATA_DIR%\sync.tmp' -ErrorAction SilentlyContinue" >nul 2>&1
ipconfig /flushdns >nul

:: Limpiar archivo de sesion
if exist "%PID_FILE%" del "%PID_FILE%" 2>nul

echo [EXITO] Puedes retirar el USB. / You may safely eject the USB.
timeout /t 3
endlocal
exit /b 0