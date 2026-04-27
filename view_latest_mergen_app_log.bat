@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM ============================================================
REM MERGEN Bilge - Latest Log Viewer
REM ============================================================

set "DRIVE=L:"
set "SHARE=\\rehisds\uygulamalar"
set "APP_REL=Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
set "APP_DIR=%DRIVE%\%APP_REL%"
set "MAPPED_BY_THIS_SCRIPT=0"

echo [INFO] Preparing log viewer...
echo.

net use %DRIVE% >nul 2>&1
if errorlevel 1 (
    echo [INFO] Mapping network share for log viewer...
    echo %SHARE%  --^>  %DRIVE%
    echo.

    net use %DRIVE% "%SHARE%" /persistent:no
    if errorlevel 1 goto ERR_MAP

    set "MAPPED_BY_THIS_SCRIPT=1"
)

if not exist "%APP_DIR%" goto ERR_APP_DIR
if not exist "%APP_DIR%\logs" goto ERR_LOG_DIR

pushd "%APP_DIR%"
if errorlevel 1 goto ERR_PUSHD

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

set "EXITCODE=%ERRORLEVEL%"
popd
goto FINISH


:ERR_MAP
echo [ERROR] Could not map network share:
echo %SHARE%
echo.
set "EXITCODE=1"
goto FINISH

:ERR_APP_DIR
echo [ERROR] App folder was not found:
echo %APP_DIR%
echo.
set "EXITCODE=1"
goto FINISH

:ERR_LOG_DIR
echo [ERROR] logs folder was not found:
echo %APP_DIR%\logs
echo.
set "EXITCODE=1"
goto FINISH

:ERR_PUSHD
echo [ERROR] Could not enter app folder:
echo %APP_DIR%
echo.
set "EXITCODE=1"
goto FINISH

:FINISH
if "%MAPPED_BY_THIS_SCRIPT%"=="1" (
    net use %DRIVE% /delete /y >nul 2>&1
)

echo.
echo [INFO] Log viewer exited with code: %EXITCODE%
echo.
pause
exit /b %EXITCODE%