@echo off
setlocal EnableExtensions

REM ==============================================================================
REM Dosya Yolu: view_latest_mergen_app_log.bat
REM Açıklama: logs klasöründeki en güncel mergen_*.log dosyasını canlı izler.
REM
REM Not:
REM - Bu dosya loga yazmaz, yalnızca okur.
REM - Uygulama çalışırken güvenle açık tutulabilir.
REM - Türkçe karakterler için PowerShell tarafında UTF-8 okuma zorlanır.
REM - UNC path için pushd kullanılır.
REM ==============================================================================

chcp 65001 >nul

pushd "%~dp0"
if errorlevel 1 (
    echo.
    echo [HATA] Repo klasörüne geçilemedi:
    echo %~dp0
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false);" ^
  "$OutputEncoding = New-Object System.Text.UTF8Encoding($false);" ^
  "$logDir = Join-Path (Get-Location) 'logs';" ^
  "$latest = Get-ChildItem -LiteralPath $logDir -Filter 'mergen_*.log' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1;" ^
  "if (-not $latest) { Write-Host '[HATA] logs klasöründe mergen_*.log dosyası bulunamadı:' $logDir; pause; exit 1 }" ^
  "Write-Host '';" ^
  "Write-Host 'En güncel MERGEN uygulama logu izleniyor:';" ^
  "Write-Host $latest.FullName;" ^
  "Write-Host '';" ^
  "Write-Host 'İzlemeyi durdurmak için CTRL+C tuşlarına basın. Bu işlem uygulamayı durdurmaz.';" ^
  "Write-Host '------------------------------------------------------------';" ^
  "Get-Content -LiteralPath $latest.FullName -Encoding UTF8 -Tail 120 -Wait"

popd
exit /b 0