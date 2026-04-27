@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "LAUNCHER_DIR=%~dp0"
set "PS1_FILE=%LAUNCHER_DIR%test_mergen_prod_launcher.ps1"

if not exist "%PS1_FILE%" (
    echo [ERROR] PowerShell test script was not found:
    echo %PS1_FILE%
    echo.
    pause
    exit /b 1
)

echo [INFO] Using PowerShell test script:
echo %PS1_FILE%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1_FILE%"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] Self-test exited with code: %EXITCODE%
echo.

pause
exit /b %EXITCODE%