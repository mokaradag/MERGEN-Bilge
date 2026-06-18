@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM ============================================================
REM MERGEN Bilge - Production Launcher
REM ============================================================

set "APP_DIR=%~dp0"

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
REM Daily console log capture
REM ============================================================

set "MERGEN_LOG_DIR=%APP_DIR%logs"

if not exist "%MERGEN_LOG_DIR%" (
    mkdir "%MERGEN_LOG_DIR%" >nul 2>&1
)

if not exist "%MERGEN_LOG_DIR%" goto ERR_LOG_DIR

set "MERGEN_LOG_DATE="
for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format yyyyMMdd"') do (
    set "MERGEN_LOG_DATE=%%I"
)

if "%MERGEN_LOG_DATE%"=="" goto ERR_LOG_DATE

set "MERGEN_CONSOLE_LOG=%MERGEN_LOG_DIR%\mergen_%MERGEN_LOG_DATE%.log"

echo ============================================================>> "%MERGEN_CONSOLE_LOG%"
echo MERGEN Bilge launcher started: %DATE% %TIME%>> "%MERGEN_CONSOLE_LOG%"
echo Script: %~f0>> "%MERGEN_CONSOLE_LOG%"
echo App folder: %APP_DIR%>> "%MERGEN_CONSOLE_LOG%"
echo ============================================================>> "%MERGEN_CONSOLE_LOG%"
echo.>> "%MERGEN_CONSOLE_LOG%"

echo [INFO] Daily console log:
echo %MERGEN_CONSOLE_LOG%
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
REM ============================================================

echo [INFO] Starting MERGEN Bilge production app through run_mergen_prod.R...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& { param([string]$RscriptExe, [string]$RunScript, [string]$LogFile) & $RscriptExe $RunScript 2>&1 | Tee-Object -FilePath $LogFile -Append; exit $LASTEXITCODE }" "%RSCRIPT_EXE%" "run_mergen_prod.R" "%MERGEN_CONSOLE_LOG%"

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

:ERR_LOG_DIR
echo [ERROR] Log folder could not be created or reached:
echo %MERGEN_LOG_DIR%
echo.
set "EXITCODE=1"
goto FINISH

:ERR_LOG_DATE
echo [ERROR] Could not resolve today's date for the mergen_YYYYMMDD.log file.
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