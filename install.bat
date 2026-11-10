@echo off
:: Disable command echoing to keep the console output clean and professional
setlocal enabledelayedexpansion

title PENDRIVE_X AI - Multi-Model Setup
:: Set the title of the console window

color 0B
:: Set the console color scheme: 0 = Black background, B = Light Aqua text

echo.
:: Print a blank line for spacing

echo ========================================================
echo           PENDRIVE_X AI - PORTABLE SETUP
echo ========================================================
echo.
echo    Welcome to PENDRIVE_X AI
echo.
echo    This will download and setup AI models on your USB.
echo.
echo    Features:
echo      * 6 Preset Models (Uncensored + Normal)
echo      * Custom GGUF Model Support
echo      * Dual engine: Ollama or llama.cpp
echo      * Fully Portable
echo.
echo    Recommended: 32GB USB Drive
echo    Internet needed for download.
echo.
echo    Usage:
echo      install.bat                          Interactive setup
echo      install.bat --engine=llamacpp        Use llama.cpp
echo      install.bat --models 1,3 --yes       Non-interactive
echo      install.bat --update-engine          Update engines/UI
echo ========================================================
echo.
:: Display the welcome banner, feature list, and requirements to the user

:: --------------------------------------------------------
:: ARGUMENT PARSING - translate --flags to PowerShell params
:: --------------------------------------------------------
set "PS_ARGS="
set "SKIP_PAUSE=0"

:parse
if "%~1"=="" goto :run
set "ARG=%~1"
if /I "%ARG%"=="--yes" (
    set "PS_ARGS=%PS_ARGS% -Yes"
    set "SKIP_PAUSE=1"
    shift
    goto :parse
)
if /I "%ARG%"=="-y" (
    set "PS_ARGS=%PS_ARGS% -Yes"
    set "SKIP_PAUSE=1"
    shift
    goto :parse
)
if /I "%ARG%"=="--help" (
    set "PS_ARGS=%PS_ARGS% -Help"
    set "SKIP_PAUSE=1"
    shift
    goto :parse
)
if /I "%ARG%"=="-h" (
    set "PS_ARGS=%PS_ARGS% -Help"
    set "SKIP_PAUSE=1"
    shift
    goto :parse
)
if /I "%ARG%"=="--update-engine" (
    set "PS_ARGS=%PS_ARGS% -UpdateEngine"
    set "SKIP_PAUSE=0"
    shift
    goto :parse
)
if /I "%ARG%"=="--update" (
    set "PS_ARGS=%PS_ARGS% -UpdateEngine"
    shift
    goto :parse
)
:: Compare prefixes with substring expansion so URLs containing & or | are safe.
if /I "!ARG:~0,16!"=="--update-engine=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "VAL=%%b"
    set "PS_ARGS=!PS_ARGS! -UpdateEngine"
    if not "!VAL!"=="" if /I not "!VAL!"=="all" set "PS_ARGS=!PS_ARGS! -Engine !VAL!"
    shift
    goto :parse
)
if /I "%ARG%"=="--engine" (
    set "PS_ARGS=%PS_ARGS% -Engine %~2"
    shift
    shift
    goto :parse
)
if /I "%ARG%"=="--models" (
    set "PS_ARGS=%PS_ARGS% -Models %~2"
    shift
    shift
    goto :parse
)
if /I "%ARG%"=="--custom-url" (
    set "PS_ARGS=%PS_ARGS% -CustomUrl "%~2""
    shift
    shift
    goto :parse
)
if /I "%ARG%"=="--custom-name" (
    set "PS_ARGS=%PS_ARGS% -CustomName "%~2""
    shift
    shift
    goto :parse
)

:: Handle --key=value forms without breaking URLs (no = inside URLs beyond query)
if /I "!ARG:~0,9!"=="--engine=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "PS_ARGS=%PS_ARGS% -Engine %%b"
    shift
    goto :parse
)
if /I "!ARG:~0,9!"=="--models=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "PS_ARGS=%PS_ARGS% -Models %%b"
    shift
    goto :parse
)
if /I "!ARG:~0,13!"=="--custom-url=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "VAL=%%b"
    set "PS_ARGS=%PS_ARGS% -CustomUrl "!VAL!""
    shift
    goto :parse
)
if /I "!ARG:~0,14!"=="--custom-name=" (
    for /f "tokens=1,* delims==" %%a in ("%ARG%") do set "VAL=%%b"
    set "PS_ARGS=%PS_ARGS% -CustomName "!VAL!""
    shift
    goto :parse
)

:: Pass anything else through unchanged (supports -Models, -Yes, ...)
set "PS_ARGS=%PS_ARGS% %ARG%"
shift
goto :parse

:run
if "%SKIP_PAUSE%"=="0" (
    pause
    :: Halt execution and wait for the user to press any key to continue
    echo.
    echo Starting setup...
    timeout /t 2 /nobreak >nul
) else (
    echo.
    echo Starting setup ^(non-interactive^)...
)

:: Inform the user that the automated setup process is beginning
powershell -ExecutionPolicy Bypass -File "%~dp0install-core.ps1" %PS_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"

if %EXIT_CODE% neq 0 (
    echo.
    echo ========================================================
    echo           SETUP INCOMPLETE OR ENCOUNTERED ERRORS
    echo ========================================================
    echo.
    echo Setup exited with code %EXIT_CODE%.
    echo Check the error messages above or in installer_data\logs\
    echo You can re-run install.bat to retry failed downloads.
    echo.
    echo ========================================================
    if "%SKIP_PAUSE%"=="0" pause
    exit /b %EXIT_CODE%
)

@REM Signing OFF IMF [Ethen Hunt] Code name ["Bravo Echo 11"]
:: Original author signature/comment
endlocal
exit /b 0
