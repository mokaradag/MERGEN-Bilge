@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "C:\MergenLauncher\test_mergen_prod_launcher.ps1"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] Self-test exited with code: %EXITCODE%
echo.

pause
exit /b %EXITCODE%