@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM Always use the folder where this .bat file is located.
REM This avoids UNC path, server-name, Turkish-character, and shortcut "Start in" problems.
set "APP_DIR=%~dp0"

echo [INFO] Script file:
echo %~f0
echo.

echo [INFO] App folder:
echo %APP_DIR%
echo.

pushd "%APP_DIR%."
if errorlevel 1 (
    echo [ERROR] Could not enter repository folder:
    echo %APP_DIR%
    echo.
    echo [DIAGNOSTIC] Please check that this folder is reachable from this VM/user:
    echo %APP_DIR%
    pause
    exit /b 1
)

echo [INFO] Current folder:
cd
echo.

REM Keep your actual R/Shiny launch command below this line.
REM Example:
REM "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" -e "shiny::runApp('.', host='0.0.0.0', port=3838)"

set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%