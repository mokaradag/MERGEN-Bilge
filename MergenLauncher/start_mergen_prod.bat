@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "DRIVE=M:"
set "SHARE=\\rehisds\uygulamalar"
set "APP_REL=Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
set "APP_BAT=%DRIVE%\%APP_REL%\run_mergen_prod.bat"

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

call "%APP_BAT%"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge launcher returned exit code: %EXITCODE%
echo.

net use %DRIVE% /delete /y >nul 2>&1

echo [INFO] Network drive unmapped.
echo.

pause
exit /b %EXITCODE%