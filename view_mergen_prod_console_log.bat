@echo off
setlocal EnableExtensions

REM ==============================================================================
REM Dosya Yolu: view_mergen_prod_console_log.bat
REM Aciklama: PowerShell tabanli console log izleyicisini baslatir.
REM
REM IMPORTANT:
REM - Keep this BAT in the app root folder.
REM - Do NOT copy this BAT to Desktop.
REM - Put only a Desktop shortcut to this BAT.
REM - Turkish UI text is printed by the UTF-8 PowerShell script, not by CMD.
REM ==============================================================================

pushd "%~dp0"
if errorlevel 1 (
    echo.
    echo [ERROR] Could not enter script folder:
    echo %~dp0
    echo.
    pause
    exit /b 1
)

if not exist "run_mergen_prod.R" (
    echo.
    echo [ERROR] This BAT is not running from the MERGEN Bilge app root.
    echo Current folder:
    echo %CD%
    echo.
    echo Fix:
    echo Keep the real BAT in the app root folder.
    echo Put only a shortcut to the BAT on Desktop.
    echo.
    pause
    popd
    exit /b 1
)

if not exist "view_mergen_prod_console_log.ps1" (
    echo.
    echo [ERROR] Missing file:
    echo %CD%\view_mergen_prod_console_log.ps1
    echo.
    pause
    popd
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\view_mergen_prod_console_log.ps1"

popd
exit /b %ERRORLEVEL%