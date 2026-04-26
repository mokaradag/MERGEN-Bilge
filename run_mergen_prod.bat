@echo off
setlocal EnableExtensions

REM ==============================================================================
REM Dosya Yolu: run_mergen_prod.bat
REM Aciklama: MERGEN Bilge uretim baslatma komutu.
REM
REM Not:
REM - Repo UNC/network path uzerindeyse cd /d kullanmayin.
REM - pushd, UNC yolu gecici bir surucu harfine map eder.
REM - Rscript yolu gerekirse asagida sabitlenmelidir.
REM ==============================================================================

REM ------------------------------------------------------------------------------
REM 0) Konsol kod sayfasi
REM ------------------------------------------------------------------------------

chcp 65001 >nul

REM ------------------------------------------------------------------------------
REM 1) Repo klasorune gec
REM    UNC path icin cd /d guvenilir degildir; pushd kullanilir.
REM ------------------------------------------------------------------------------

pushd "%~dp0"
if errorlevel 1 (
    echo.
    echo [ERROR] Could not enter repository folder:
    echo %~dp0
    echo.
    pause
    exit /b 1
)

REM ------------------------------------------------------------------------------
REM 2) Uretim host/port varsayilanlari
REM ------------------------------------------------------------------------------

if "%MERGEN_HOST%"=="" set "MERGEN_HOST=0.0.0.0"
if "%MERGEN_PORT%"=="" set "MERGEN_PORT=8009"

REM ------------------------------------------------------------------------------
REM 3) Rscript yolu
REM
REM ONEMLI:
REM - RStudio/interactive R baska, Rscript baska R kurulumunu kullaniyorsa
REM   paketler gorunmeyebilir.
REM - Bu nedenle production icin Rscript yolunu mumkunse sabitleyin.
REM - R 4.5.1 kullaniyorsaniz asagidaki yol dogru olmalidir.
REM ------------------------------------------------------------------------------

if "%RSCRIPT%"=="" set "RSCRIPT=C:\Program Files\R\R-4.5.1\bin\Rscript.exe"

REM Eger yukaridaki Rscript yoksa PATH uzerindeki Rscript'e dus.
if not exist "%RSCRIPT%" (
    echo [WARN] Fixed Rscript path not found:
    echo        %RSCRIPT%
    echo [WARN] Falling back to Rscript from PATH.
    set "RSCRIPT=Rscript"
)

REM ------------------------------------------------------------------------------
REM 4) Istege bagli sabit R paket kutuphanesi
REM
REM Paketleri ozel bir production library altina kurduysaniz asagidaki satiri
REM acip kendi yolunuza gore duzenleyin.
REM
REM Ornek:
REM set "R_LIBS_USER=D:\MERGEN_R_LIBS\R-4.5.1"
REM ------------------------------------------------------------------------------

REM set "R_LIBS_USER=D:\MERGEN_R_LIBS\R-4.5.1"

if not "%R_LIBS_USER%"=="" (
    if not exist "%R_LIBS_USER%" mkdir "%R_LIBS_USER%" >nul 2>nul
)

REM ------------------------------------------------------------------------------
REM 5) Log klasoru ve log dosyasi
REM ------------------------------------------------------------------------------

if not exist "logs" mkdir "logs"

set "RUN_LOG=logs\run_mergen_prod_console.log"
set "PREFLIGHT_R=logs\run_mergen_prod_preflight.R"

echo ============================================================ > "%RUN_LOG%"
echo MERGEN Bilge production startup >> "%RUN_LOG%"
echo Date: %DATE% %TIME% >> "%RUN_LOG%"
echo Working directory: %CD% >> "%RUN_LOG%"
echo Host: %MERGEN_HOST% >> "%RUN_LOG%"
echo Port: %MERGEN_PORT% >> "%RUN_LOG%"
echo Rscript: %RSCRIPT% >> "%RUN_LOG%"
echo R_LIBS_USER: %R_LIBS_USER% >> "%RUN_LOG%"
echo ============================================================ >> "%RUN_LOG%"
echo. >> "%RUN_LOG%"

REM ------------------------------------------------------------------------------
REM 6) Rscript var mi kontrol et
REM ------------------------------------------------------------------------------

if exist "%RSCRIPT%" goto RSCRIPT_OK

where "%RSCRIPT%" >nul 2>nul
if errorlevel 1 (
    echo.
    echo [ERROR] Rscript was not found.
    echo Current RSCRIPT value:
    echo %RSCRIPT%
    echo.
    echo Fix:
    echo   Edit run_mergen_prod.bat and set RSCRIPT to the real Rscript.exe path.
    echo   Example:
    echo   set "RSCRIPT=C:\Program Files\R\R-4.5.1\bin\Rscript.exe"
    echo.
    echo Full log:
    echo %CD%\%RUN_LOG%
    echo [ERROR] Rscript was not found: %RSCRIPT% >> "%RUN_LOG%"
    pause
    popd
    exit /b 1
)

:RSCRIPT_OK

REM ------------------------------------------------------------------------------
REM 7) R paket preflight script'i olustur
REM ------------------------------------------------------------------------------

> "%PREFLIGHT_R%" echo options(encoding = "UTF-8")
>> "%PREFLIGHT_R%" echo cat("R.version.string:\n")
>> "%PREFLIGHT_R%" echo cat(R.version.string, "\n\n")
>> "%PREFLIGHT_R%" echo cat(".libPaths():\n")
>> "%PREFLIGHT_R%" echo print(.libPaths())
>> "%PREFLIGHT_R%" echo cat("\n")
>> "%PREFLIGHT_R%" echo source("R/config_packages.R", encoding = "UTF-8")
>> "%PREFLIGHT_R%" echo cat("\nPackage preflight OK.\n")

REM ------------------------------------------------------------------------------
REM 8) Rscript ve paket preflight
REM ------------------------------------------------------------------------------

echo Running Rscript/package preflight...
echo Running Rscript/package preflight... >> "%RUN_LOG%"
echo. >> "%RUN_LOG%"

"%RSCRIPT%" "%CD%\%PREFLIGHT_R%" 1>> "%RUN_LOG%" 2>>&1

set "PREFLIGHT_EXIT=%ERRORLEVEL%"

if not "%PREFLIGHT_EXIT%"=="0" (
    echo.
    echo [ERROR] R package preflight failed. Exit code: %PREFLIGHT_EXIT%
    echo.
    echo Last log lines:
    echo ------------------------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%CD%\%RUN_LOG%' -Tail 120"
    echo ------------------------------------------------------------
    echo.
    echo Full log:
    echo %CD%\%RUN_LOG%
    echo.
    pause
    popd
    exit /b %PREFLIGHT_EXIT%
)

REM ------------------------------------------------------------------------------
REM 9) Uretim baslatma
REM ------------------------------------------------------------------------------

echo.
echo Starting MERGEN Bilge...
echo Repo: %CD%
echo Log : %CD%\%RUN_LOG%
echo.

echo. >> "%RUN_LOG%"
echo Starting run_mergen_prod.R... >> "%RUN_LOG%"
echo. >> "%RUN_LOG%"

"%RSCRIPT%" "%CD%\run_mergen_prod.R" 1>> "%RUN_LOG%" 2>>&1

set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo [ERROR] MERGEN Bilge failed to start. Exit code: %EXIT_CODE%
    echo.
    echo Last log lines:
    echo ------------------------------------------------------------
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%CD%\%RUN_LOG%' -Tail 120"
    echo ------------------------------------------------------------
    echo.
    echo Full log:
    echo %CD%\%RUN_LOG%
    echo.
    pause
    popd
    exit /b %EXIT_CODE%
)

REM Normalde Shiny calisiyorsa bu noktaya ancak uygulama kapandiginda gelinir.
echo.
echo MERGEN Bilge stopped. Exit code: %EXIT_CODE%
echo Full log:
echo %CD%\%RUN_LOG%
echo.
pause

popd
exit /b 0
