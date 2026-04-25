@echo off
setlocal

REM ==============================================================================
REM Dosya Yolu: run_mergen_prod.bat
REM Açıklama: MERGEN Bilge üretim başlatma komutu.
REM ==============================================================================

cd /d "%~dp0"

REM İsteğe bağlı üretim portu/host ayarı.
if "%MERGEN_HOST%"=="" set MERGEN_HOST=0.0.0.0
if "%MERGEN_PORT%"=="" set MERGEN_PORT=8009

REM Rscript PATH içinde değilse aşağıdaki satırı kendi R kurulum yoluna göre açın:
REM set "RSCRIPT=C:\Program Files\R\R-4.5.1\bin\Rscript.exe"

if "%RSCRIPT%"=="" set "RSCRIPT=Rscript"

"%RSCRIPT%" "%~dp0run_mergen_prod.R"

endlocal