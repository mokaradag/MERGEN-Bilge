@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "DRIVE=M:"
set "SHARE=\\rehisds\uygulamalar"
set "APP_REL=Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
set "APP_BAT=%DRIVE%\%APP_REL%\run_mergen_prod.bat"
set "APP_LOG_DIR=%DRIVE%\%APP_REL%\logs"

for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyyMMdd"') do set "MERGEN_LOG_DATE=%%I"
if not defined MERGEN_LOG_DATE set "MERGEN_LOG_DATE=unknown"
set "MERGEN_APP_LOG=%APP_LOG_DIR%\mergen_%MERGEN_LOG_DATE%.log"

echo [INFO] Mapping network share...
echo %SHARE%  --^>  %DRIVE%
echo.

net use %DRIVE% /delete /y >nul 2>&1

net use %DRIVE% "%SHARE%" /persistent:no
if errorlevel 1 (
    echo [ERROR] Could not map network share:
    echo %SHARE%
    echo.
    pause
    exit /b 1
)

echo [INFO] Checking app script:
echo %APP_BAT%
echo.

if not exist "%APP_BAT%" (
    echo [ERROR] App script was not found:
    echo %APP_BAT%
    echo.
    net use %DRIVE% /delete /y >nul 2>&1
    pause
    exit /b 1
)

echo [INFO] Starting MERGEN Bilge...
echo.

if not exist "%APP_LOG_DIR%" mkdir "%APP_LOG_DIR%" >nul 2>&1

echo [INFO] Daily console log file:
echo %MERGEN_APP_LOG%
echo.

set "MERGEN_APP_BAT=%APP_BAT%"
set "MERGEN_EXTERNAL_CONSOLE_TEE=TRUE"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $log = $env:MERGEN_APP_LOG; $bat = $env:MERGEN_APP_BAT; New-Item -ItemType Directory -Path (Split-Path -Parent $log) -Force | Out-Null; $q = [char]34; $cmd = 'call ' + $q + $bat + $q; & cmd.exe /d /c $cmd 2>&1 | Tee-Object -FilePath $log -Append; exit $LASTEXITCODE"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge launcher returned exit code: %EXITCODE%
echo.

net use %DRIVE% /delete /y >nul 2>&1

echo [INFO] Network drive unmapped.
echo.

pause
exit /b %EXITCODE%