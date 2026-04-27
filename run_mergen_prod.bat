@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM ============================================================
REM MERGEN Bilge - Production Launcher
REM ============================================================
REM This script must preferably be launched from a mapped drive,
REM for example:
REM M:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge\run_mergen_prod.bat
REM
REM Do NOT use shortcut "Start in" as a UNC path.
REM If the app is on a network share, use a local launcher that maps:
REM \\rehisds\uygulamalar  -->  M:
REM ============================================================

set "APP_DIR=%~dp0"

echo [INFO] Script file:
echo %~f0
echo.

echo [INFO] App folder:
echo %APP_DIR%
echo.

REM Enter the application folder.
REM Do not use "%APP_DIR%." here; it can break on UNC/network paths.
pushd "%APP_DIR%"
if errorlevel 1 (
    echo [ERROR] Could not enter repository folder:
    echo %APP_DIR%
    echo.
    echo [DIAGNOSTIC] This usually means one of the following:
    echo   1. The script was launched directly from a UNC path.
    echo   2. The shortcut "Start in" field points to a UNC path.
    echo   3. The network path is not accessible for this VM/user.
    echo   4. The folder name contains a character/path mismatch.
    echo.
    echo [DIAGNOSTIC] Recommended solution:
    echo   Launch this script through a local VM launcher that maps the share to a drive letter.
    echo.
    pause
    exit /b 1
)

echo [INFO] Current folder:
cd
echo.

REM ============================================================
REM R executable detection
REM ============================================================

set "RSCRIPT_EXE="

if exist "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" (
    set "RSCRIPT_EXE=C:\Program Files\R\R-4.4.2\bin\Rscript.exe"
) else if exist "C:\Program Files\R\R-4.4.1\bin\Rscript.exe" (
    set "RSCRIPT_EXE=C:\Program Files\R\R-4.4.1\bin\Rscript.exe"
) else if exist "C:\Program Files\R\R-4.3.3\bin\Rscript.exe" (
    set "RSCRIPT_EXE=C:\Program Files\R\R-4.3.3\bin\Rscript.exe"
) else (
    where Rscript.exe >nul 2>&1
    if not errorlevel 1 (
        set "RSCRIPT_EXE=Rscript.exe"
    )
)

if "%RSCRIPT_EXE%"=="" (
    echo [ERROR] Rscript.exe could not be found.
    echo.
    echo [DIAGNOSTIC] Please check your R installation path.
    echo Example:
    echo   C:\Program Files\R\R-4.4.2\bin\Rscript.exe
    echo.
    popd
    pause
    exit /b 1
)

echo [INFO] Rscript:
echo %RSCRIPT_EXE%
echo.

REM ============================================================
REM Production environment settings
REM ============================================================

set "SSO_ENABLED=TRUE"
set "SHINY_HOST=0.0.0.0"
set "SHINY_PORT=3838"

echo [INFO] SSO_ENABLED=%SSO_ENABLED%
echo [INFO] SHINY_HOST=%SHINY_HOST%
echo [INFO] SHINY_PORT=%SHINY_PORT%
echo.

REM ============================================================
REM Start MERGEN Bilge
REM ============================================================

if not exist "app.R" (
    echo [ERROR] app.R was not found in the current folder:
    cd
    echo.
    popd
    pause
    exit /b 1
)

echo [INFO] Starting MERGEN Bilge production app...
echo.

"%RSCRIPT_EXE%" -e "options(shiny.host=Sys.getenv('SHINY_HOST','0.0.0.0'), shiny.port=as.integer(Sys.getenv('SHINY_PORT','3838'))); shiny::runApp('.', launch.browser=FALSE)"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge exited with code: %EXITCODE%
echo.

popd

pause
exit /b %EXITCODE%