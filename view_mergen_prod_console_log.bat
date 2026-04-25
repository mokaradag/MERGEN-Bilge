@echo off
setlocal EnableExtensions

REM ==============================================================================
REM Dosya Yolu: view_mergen_prod_console_log.bat
REM Açıklama: MERGEN Bilge üretim console log dosyasını canlı izler.
REM
REM Not:
REM - Bu dosya loga yazmaz, yalnızca okur.
REM - Startup / Rscript / stdout / stderr çıktısını gösterir.
REM - Normal runtime app logları için view_latest_mergen_app_log.bat kullanılır.
REM - Türkçe karakterler için PowerShell tarafında UTF-8 okuma zorlanır.
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
echo Normal runtime app logs are in logs\mergen_YYYYMMDD.log
echo ------------------------------------------------------------
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false);" ^
  "$OutputEncoding = New-Object System.Text.UTF8Encoding($false);" ^
  "$path = '%LOG_FILE%';" ^
  "Get-Content -LiteralPath $path -Encoding UTF8 -Tail 120 -Wait"

popd
exit /b 0