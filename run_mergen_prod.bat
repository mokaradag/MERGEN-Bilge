@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "APP_DIR=\\rehisas\uygulamalar\Primavera\PYB\04 - Gelistirme\MERGEN Bilge"

pushd "%APP_DIR%"
if errorlevel 1 (
    echo [ERROR] Could not enter repository folder:
    echo %APP_DIR%
    pause
    exit /b 1
)

echo [INFO] Current folder:
cd

REM Burada mevcut R/Shiny calistirma komutunuz olacak.
REM Ornek:
REM "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" -e "shiny::runApp('.', host='0.0.0.0', port=3838)"

set "EXITCODE=%ERRORLEVEL%"

popd

exit /b %EXITCODE%