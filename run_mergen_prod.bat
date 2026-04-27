@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

REM ============================================================
REM MERGEN Bilge - Production Launcher
REM ============================================================
REM This script is expected to be launched from a mapped drive,
REM for example:
REM M:\Primavera\PYB\04 - Geliştirme\MERGEN Bilge\run_mergen_prod.bat
REM
REM The local VM launcher should map:
REM \\rehisds\uygulamalar  -->  M:
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
if errorlevel 1 (
    echo [ERROR] Could not enter repository folder:
    echo %APP_DIR%
    echo.
    echo [DIAGNOSTIC] This usually means the script was launched directly from a UNC path
    echo or the network path is not accessible for this VM/user.
    echo.
    pause
    exit /b 1
)

echo [INFO] Current folder:
cd
echo.

REM ============================================================
REM Dynamically detect newest installed R under C:\Program Files\R
REM ============================================================

set "RSCRIPT_EXE="

REM Optional manual override.
REM If this environment variable exists and points to Rscript.exe, it wins.
if defined MERGEN_RSCRIPT (
    if exist "%MERGEN_RSCRIPT%" (
        set "RSCRIPT_EXE=%MERGEN_RSCRIPT%"
    )
)

REM Detect latest R version dynamically, for example R-4.5.1, R-4.6.0, etc.
if "%RSCRIPT_EXE%"=="" (
    for /f "delims=" %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$root='C:\Program Files\R'; $found = Get-ChildItem -Path $root -Directory -Filter 'R-*' -ErrorAction SilentlyContinue | ForEach-Object { $verText = $_.Name -replace '^R-',''; try { $ver = [version]$verText; $rscript = Join-Path $_.FullName 'bin\Rscript.exe'; if (Test-Path $rscript) { [pscustomobject]@{ Version = $ver; Path = $rscript } } } catch {} } | Sort-Object Version -Descending | Select-Object -First 1; if ($found) { $found.Path }"') do (
        set "RSCRIPT_EXE=%%I"
    )
)

REM Fallback to PATH only if no Program Files R installation was found.
if "%RSCRIPT_EXE%"=="" (
    where Rscript.exe >nul 2>&1
    if not errorlevel 1 (
        set "RSCRIPT_EXE=Rscript.exe"
    )
)

if "%RSCRIPT_EXE%"=="" (
    echo [ERROR] Rscript.exe could not be found.
    echo.
    echo [DIAGNOSTIC] Expected something like:
    echo   C:\Program Files\R\R-4.5.1\bin\Rscript.exe
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

REM run_mergen_prod.R uses MERGEN_HOST and MERGEN_PORT.
set "MERGEN_HOST=0.0.0.0"
set "MERGEN_PORT=3838"

REM Keep these too for backward compatibility with older launch paths.
set "SHINY_HOST=%MERGEN_HOST%"
set "SHINY_PORT=%MERGEN_PORT%"

echo [INFO] SSO_ENABLED=%SSO_ENABLED%
echo [INFO] MERGEN_HOST=%MERGEN_HOST%
echo [INFO] MERGEN_PORT=%MERGEN_PORT%
echo.

REM ============================================================
REM Diagnostics: show which R and library paths this batch uses
REM ============================================================

echo [INFO] R session diagnostics:
"%RSCRIPT_EXE%" -e "cat('R.home() = ', R.home(), '\n', sep=''); cat('R.version = ', R.version.string, '\n', sep=''); cat('R_LIBS_USER = ', Sys.getenv('R_LIBS_USER'), '\n', sep=''); cat('.libPaths() =\n'); print(.libPaths())"
echo.

REM ============================================================
REM Check startup script
REM ============================================================

if not exist "run_mergen_prod.R" (
    echo [ERROR] run_mergen_prod.R was not found in the current folder:
    cd
    echo.
    popd
    pause
    exit /b 1
)

if not exist "app.R" (
    echo [ERROR] app.R was not found in the current folder:
    cd
    echo.
    popd
    pause
    exit /b 1
)

REM ============================================================
REM Optional package visibility diagnostic
REM ============================================================

echo [INFO] Checking required package visibility from this Rscript session...
"%RSCRIPT_EXE%" -e "pkgs <- c('arrow','duckdb','fastmatch','pdftools','pool','shinyBS','stringdist','writexl','av'); miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly=TRUE)]; if (length(miss)) { cat('Missing from this Rscript session:\n'); cat(paste(miss, collapse=', '), '\n'); quit(status=10) } else { cat('All required packages are visible.\n') }"

if errorlevel 10 (
    echo.
    echo [ERROR] Some packages are still not visible to the Rscript session launched by this .bat.
    echo.
    echo [DIAGNOSTIC] Compare the .libPaths() printed above with the .libPaths()
    echo from the RStudio session where the app works.
    echo.
    echo In RStudio on the VM, run:
    echo   R.home()
    echo   file.path(R.home("bin"), "Rscript.exe")
    echo   .libPaths()
    echo.
    echo If the Rscript path is correct but .libPaths() is different, then the app is
    echo being launched under a different user/library context.
    echo.
    popd
    pause
    exit /b 1
)

echo.

REM ============================================================
REM Start MERGEN Bilge through the production R launcher
REM ============================================================

echo [INFO] Starting MERGEN Bilge production app through run_mergen_prod.R...
echo.

"%RSCRIPT_EXE%" "run_mergen_prod.R"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge exited with code: %EXITCODE%
echo.

popd

pause
exit /b %EXITCODE%