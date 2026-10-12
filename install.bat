@echo off
:: Disable command echoing to keep the console output clean and professional

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
echo      * Fully Portable
echo.
echo    Recommended: 32GB USB Drive
echo    Internet needed for download.
echo.
echo ========================================================
echo.
:: Display the welcome banner, feature list, and requirements to the user

pause
:: Halt execution and wait for the user to press any key to continue

echo.
echo Starting setup...
:: Inform the user that the automated setup process is beginning

timeout /t 2 /nobreak >nul
:: Pause execution for 2 seconds to let the user read the message. 
:: /nobreak prevents the user from skipping the wait, and >nul hides the countdown timer.

powershell -ExecutionPolicy Bypass -File "%~dp0install-core.ps1"
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
    pause
    exit /b %EXIT_CODE%
)

@REM Signing OFF IMF [Ethen Hunt] Code name ["Bravo Echo 11"]
:: Original author signature/comment