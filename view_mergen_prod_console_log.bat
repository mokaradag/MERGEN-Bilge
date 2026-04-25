@echo off
setlocal EnableExtensions

REM ==============================================================================
REM Dosya Yolu: view_mergen_prod_console_log.bat
REM Açıklama: MERGEN Bilge üretim console log dosyasını canlı izler.
REM
REM Not:
REM - Bu dosya loga yazmaz, yalnızca okur.
REM - App çalışırken güvenle açık tutulabilir.
REM - UNC path için pushd kullanılır.
REM ==============================================================================

chcp 65001 >nul

pushd "%~dp0"
if errorlevel 1 (
    echo.
    echo [ERROR] Could not enter repository folder:
    echo %~dp0
    echo.
    pause
    exit /b 1
)

set "LOG_FILE=%CD%\logs\run_mergen_prod_console.log"

if not exist "%LOG_FILE%" (
    echo.
    echo [ERROR] Log file not found:
    echo %LOG_FILE%
    echo.
    echo Start MERGEN Bilge first by running:
    echo run_mergen_prod.bat
    echo.
    pause
    popd
    exit /b 1
)

echo.
echo Watching MERGEN Bilge production console log:
echo %LOG_FILE%
echo.
echo Press CTRL+C to stop watching. This will NOT stop the app.
echo ------------------------------------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$path = '%LOG_FILE%';" ^
  "Get-Content -LiteralPath $path -Tail 120 -Wait"

popd
exit /b 0