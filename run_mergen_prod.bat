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
if errorlevel 1 (
    echo [ERROR] Could not enter repository folder:
    echo %APP_DIR%
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

if "%RSCRIPT_EXE%"=="" (
    echo [ERROR] Rscript.exe could not be found.
    echo.
    pause
    popd
    exit /b 1
)

echo [INFO] Rscript:
echo %RSCRIPT_EXE%
echo.

REM ============================================================
REM Production environment settings
REM ============================================================

set "SSO_ENABLED=TRUE"

REM run_mergen_prod.R uses these.
set "MERGEN_HOST=0.0.0.0"
set "MERGEN_PORT=3838"

REM Keep these for older paths too.
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
"%RSCRIPT_EXE%" -e "cat('R.home() = ', R.home(), '\n', sep=''); cat('R.version = ', R.version.string, '\n', sep=''); cat('R_LIBS_USER = ', Sys.getenv('R_LIBS_USER'), '\n', sep=''); cat('.libPaths() =\n'); print(.libPaths())"

set "R_DIAG_CODE=%ERRORLEVEL%"
if not "%R_DIAG_CODE%"=="0" (
    echo.
    echo [ERROR] R diagnostics failed. Exit code: %R_DIAG_CODE%
    echo.
    pause
    popd
    exit /b %R_DIAG_CODE%
)

echo.

REM ============================================================
REM Check startup files
REM ============================================================

if not exist "run_mergen_prod.R" (
    echo [ERROR] run_mergen_prod.R was not found in:
    cd
    echo.
    pause
    popd
    exit /b 1
)

if not exist "app.R" (
    echo [ERROR] app.R was not found in:
    cd
    echo.
    pause
    popd
    exit /b 1
)

REM ============================================================
REM Package installation diagnostic
REM ============================================================
REM Use installed.packages() here instead of requireNamespace().
REM requireNamespace() loads package DLLs and can fail/hang/crash before
REM giving us a readable message. app.R can still do the deeper runtime check.
REM ============================================================

echo [INFO] Checking required package installation from this Rscript session...

"%RSCRIPT_EXE%" -e "pkgs <- c('arrow','duckdb','fastmatch','pdftools','pool','shinyBS','stringdist','writexl','av'); ip <- rownames(installed.packages()); miss <- setdiff(pkgs, ip); if (length(miss)) { cat('Missing installed packages from this Rscript session:\n'); cat(paste(miss, collapse=', '), '\n'); quit(status=10) } else { cat('All required packages are installed and visible in .libPaths().\n') }"

set "PKG_CHECK_CODE=%ERRORLEVEL%"

if not "%PKG_CHECK_CODE%"=="0" (
    echo.
    echo [ERROR] Package diagnostic failed. Exit code: %PKG_CHECK_CODE%
    echo.
    echo [DIAGNOSTIC] The Rscript path is:
    echo %RSCRIPT_EXE%
    echo.
    echo [DIAGNOSTIC] If packages are installed in RStudio but not visible here,
    echo compare .libPaths() from this console with .libPaths() in RStudio.
    echo.
    pause
    popd
    exit /b %PKG_CHECK_CODE%
)

echo.

REM ============================================================
REM Start MERGEN Bilge through production R launcher
REM ============================================================

echo [INFO] Starting MERGEN Bilge production app through run_mergen_prod.R...
echo.

"%RSCRIPT_EXE%" "run_mergen_prod.R"

set "EXITCODE=%ERRORLEVEL%"

echo.
echo [INFO] MERGEN Bilge exited with code: %EXITCODE%
echo.

pause
popd
exit /b %EXITCODE%