@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM ============================================================
REM MERGEN Bilge - Production Launcher
REM ============================================================

set "APP_DIR=%~dp0"

REM ============================================================
REM Disable console QuickEdit Mode (prevents accidental freezes)
REM ------------------------------------------------------------
REM When QuickEdit is on (Windows default), clicking inside this
REM console enters selection mode and SUSPENDS the single-threaded
REM Shiny app on its next stdout write -> every connected user's
REM screen freezes until the selection is cleared (pressing Enter
REM flushes the buffered output and resumes the app). Disabling
REM QuickEdit on this console stops that intermittent freeze.
REM Best-effort: failure must not block startup, so the exit code
REM is intentionally ignored.
REM ============================================================

if exist "%APP_DIR%tools\disable_console_quickedit.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%APP_DIR%tools\disable_console_quickedit.ps1" 2>nul
)

echo [INFO] Script file:
echo %~f0
echo.

echo [INFO] App folder:
echo %APP_DIR%
echo.

REM ============================================================
REM Enter application folder
REM ============================================================

pushd "%APP_DIR%"
if errorlevel 1 goto ERR_APP_DIR

echo [INFO] Current folder:
cd
echo.

REM ============================================================
REM Dynamically detect newest installed R under C:\Program Files\R
REM ============================================================

set "RSCRIPT_EXE="

REM Optional manual override.
REM Example:
REM set MERGEN_RSCRIPT=C:\Program Files\R\R-4.5.1\bin\Rscript.exe

if defined MERGEN_RSCRIPT (
    if exist "%MERGEN_RSCRIPT%" (
        set "RSCRIPT_EXE=%MERGEN_RSCRIPT%"
    )
)

if "%RSCRIPT_EXE%"=="" (
    for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$root='C:\Program Files\R'; $found = Get-ChildItem -Path $root -Directory -Filter 'R-*' -ErrorAction SilentlyContinue | ForEach-Object { $verText = $_.Name -replace '^R-',''; try { $ver = [version]$verText; $rscript = Join-Path $_.FullName 'bin\Rscript.exe'; if (Test-Path $rscript) { [pscustomobject]@{ Version = $ver; Path = $rscript } } } catch {} } | Sort-Object Version -Descending | Select-Object -First 1; if ($found) { $found.Path }"') do (
        set "RSCRIPT_EXE=%%I"
    )
)

if "%RSCRIPT_EXE%"=="" (
    where Rscript.exe >nul 2>&1
    if not errorlevel 1 (
        set "RSCRIPT_EXE=Rscript.exe"
    )
)

if "%RSCRIPT_EXE%"=="" goto ERR_RSCRIPT_NOT_FOUND

echo [INFO] Rscript:
echo %RSCRIPT_EXE%
echo.

REM ============================================================
REM Production environment settings
REM ============================================================

set "SSO_ENABLED=TRUE"

REM run_mergen_prod.R uses these.
set "MERGEN_HOST=0.0.0.0"
set "MERGEN_PORT=8009"

REM Backward compatibility.
set "SHINY_HOST=%MERGEN_HOST%"
set "SHINY_PORT=%MERGEN_PORT%"

echo [INFO] SSO_ENABLED=%SSO_ENABLED%
echo [INFO] MERGEN_HOST=%MERGEN_HOST%
echo [INFO] MERGEN_PORT=%MERGEN_PORT%
echo.

REM ============================================================
REM R diagnostics
REM ============================================================

echo [INFO] R session diagnostics:
"%RSCRIPT_EXE%" -e "cat('R.home = ', R.home(), '\n', sep=''); cat('R.version = ', R.version.string, '\n', sep=''); cat('R_LIBS_USER = ', Sys.getenv('R_LIBS_USER'), '\n', sep=''); cat('Library paths:\n'); print(.libPaths())"

set "R_DIAG_CODE=%ERRORLEVEL%"
if not "%R_DIAG_CODE%"=="0" goto ERR_R_DIAG

echo.

REM ============================================================
REM Check startup files
REM ============================================================

if not exist "run_mergen_prod.R" goto ERR_NO_RUN_PROD_R
if not exist "app.R" goto ERR_NO_APP_R

REM ============================================================
REM Package installation diagnostic
REM ============================================================

echo [INFO] Checking required package installation from this Rscript session...

"%RSCRIPT_EXE%" -e "pkgs <- c('arrow','duckdb','fastmatch','pdftools','pool','shinyBS','stringdist','writexl','av'); ip <- rownames(installed.packages()); miss <- setdiff(pkgs, ip); if (length(miss)) { cat('Missing installed packages from this Rscript session:\n'); cat(paste(miss, collapse=', '), '\n'); quit(status=10) } else { cat('All required packages are installed and visible in the active R library paths.\n') }"

set "PKG_CHECK_CODE=%ERRORLEVEL%"
if not "%PKG_CHECK_CODE%"=="0" goto ERR_PKG_CHECK

echo.

REM ============================================================
REM Start MERGEN Bilge through production R launcher
REM ------------------------------------------------------------
REM The app's stdout/stderr are redirected to a LOG FILE so the
REM interactive console is never in R's write path. This makes it
REM impossible for any console state (accidental text selection,
REM Ctrl+S pause, scroll, focus loss) to block the single-threaded
REM Shiny event loop and freeze every connected user. Writing to a
REM file also makes stdout block-buffered instead of tied to console
REM rendering. The app's own rotating file logger
REM (logs\mergen_YYYYMMDD.log) is unaffected, and the read-only live
REM viewer opened below tails it for visibility.
REM ============================================================

if not exist "logs" mkdir "logs"

REM Pre-create today's daily log so the live viewer can attach at once.
REM cwd is the app folder (earlier pushd), so a relative path is safe and
REM avoids passing the Turkish app path as a PowerShell argument.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$f = Join-Path 'logs' ('mergen_' + (Get-Date -Format 'yyyyMMdd') + '.log'); if (-not (Test-Path -LiteralPath $f)) { New-Item -ItemType File -Path $f -Force | Out-Null }" 2>nul

REM Open the read-only live log viewer in its own window. It tails
REM logs\mergen_*.log (written by the app's file appender), so it can
REM never block the app that is writing the logs.
if exist "view_latest_mergen_app_log.bat" (
    start "MERGEN Bilge - Canli Log" "view_latest_mergen_app_log.bat"
)

echo [INFO] Starting MERGEN Bilge production app through run_mergen_prod.R...
echo [INFO] App console output goes to the log file below, NOT this window:
echo %APP_DIR%logs\run_mergen_prod_console.log
echo [INFO] Live application logs open in the separate window titled:
echo MERGEN Bilge - Canli Log
echo [INFO] This window reports the exit code when the app stops.
echo.

"%RSCRIPT_EXE%" --encoding=UTF-8 "run_mergen_prod.R" >> "logs\run_mergen_prod_console.log" 2>&1

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge exited with code: %EXITCODE%
echo.

goto FINISH


REM ============================================================
REM Error handlers
REM ============================================================

:ERR_APP_DIR
echo [ERROR] Could not enter repository folder:
echo %APP_DIR%
echo.
set "EXITCODE=1"
goto FINISH_NO_POPD

:ERR_RSCRIPT_NOT_FOUND
echo [ERROR] Rscript.exe could not be found.
echo.
echo [DIAGNOSTIC] Expected something like:
echo C:\Program Files\R\R-4.5.1\bin\Rscript.exe
echo.
set "EXITCODE=1"
goto FINISH

:ERR_R_DIAG
echo.
echo [ERROR] R diagnostics failed. Exit code: %R_DIAG_CODE%
echo.
set "EXITCODE=%R_DIAG_CODE%"
goto FINISH

:ERR_NO_RUN_PROD_R
echo [ERROR] run_mergen_prod.R was not found in:
cd
echo.
set "EXITCODE=1"
goto FINISH

:ERR_NO_APP_R
echo [ERROR] app.R was not found in:
cd
echo.
set "EXITCODE=1"
goto FINISH

:ERR_PKG_CHECK
echo.
echo [ERROR] Package diagnostic failed. Exit code: %PKG_CHECK_CODE%
echo.
echo [DIAGNOSTIC] The Rscript path is:
echo %RSCRIPT_EXE%
echo.
echo [DIAGNOSTIC] Compare the library paths printed above with the library paths in RStudio.
echo In RStudio on the VM, run:
echo R.home()
echo file.path(R.home("bin"), "Rscript.exe")
echo .libPaths()
echo.
set "EXITCODE=%PKG_CHECK_CODE%"
goto FINISH


REM ============================================================
REM Finish
REM ============================================================

:FINISH
popd

:FINISH_NO_POPD
echo.
echo [INFO] Final launcher exit code: %EXITCODE%
echo.
pause
exit /b %EXITCODE%