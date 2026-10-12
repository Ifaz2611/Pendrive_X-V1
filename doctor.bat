@echo off
title Pendrive_X Doctor
color 0E
echo ===================================================
echo   Pendrive_X Doctor — Diagnostics
echo ===================================================
set "USB_ROOT=%~dp0"
echo USB: %USB_ROOT%
echo.

:: FS check
powershell -NoProfile -Command "$d='%~d0'; try { $v=Get-CimInstance Win32_LogicalDisk -Filter ('DeviceID=''{0}''' -f $d) -ErrorAction Stop; Write-Host ('FS: {0} | Free: {1} GB | Total: {2} GB' -f $v.FileSystem, [math]::Round($v.FreeSpace/1GB,1), [math]::Round($v.Size/1GB,1)) } catch { Write-Host 'FS & Space: unknown' }"

:: RAM
powershell -NoProfile -Command "try { $m=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; Write-Host ('RAM: {0} GB' -f [math]::Round($m.TotalPhysicalMemory/1GB,1)) } catch { Write-Host 'RAM GB: unknown' }"

:: Installed models
if exist "%USB_ROOT%models\installed-models.txt" (
  echo.
  echo Installed models:
  type "%USB_ROOT%models\installed-models.txt"
) else (
  echo No installed-models.txt
)

:: GGUF size check
echo.
echo GGUF files:
dir "%USB_ROOT%models\*.gguf" 2>nul || echo  (none found)

:: Ollama binary
if exist "%USB_ROOT%ollama\ollama.exe" (echo Ollama: FOUND) else (echo Ollama: MISSING — run install.bat)

:: AnythingLLM
if exist "%USB_ROOT%anythingllm\AnythingLLM.exe" (echo AnythingLLM: FOUND) else (echo AnythingLLM: MISSING)

:: .env
echo.
echo .env:
if exist "%USB_ROOT%anythingllm_data\storage\.env" (type "%USB_ROOT%anythingllm_data\storage\.env") else (echo   [none])

:: Port 11434 busy?
powershell -NoProfile -Command "try { $s=New-Object System.Net.Sockets.TcpClient; $s.Connect('127.0.0.1', 11434); Write-Host 'Port 11434: IN USE (host Ollama may be running)'; $s.Dispose() } catch { Write-Host 'Port 11434: free' }" 2>nul

echo.
echo Logs: %USB_ROOT%installer_data\logs\ , %USB_ROOT%anythingllm_data\logs\
if exist "%USB_ROOT%installer_data\logs" dir "%USB_ROOT%installer_data\logs" /b
if exist "%USB_ROOT%anythingllm_data\logs" dir "%USB_ROOT%anythingllm_data\logs" /b
echo.
pause
