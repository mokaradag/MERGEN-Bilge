# ==============================================================================
# Dosya Yolu: view_mergen_prod_console_log.ps1
# Açıklama: MERGEN Bilge üretim console log dosyasını canlı izler.
#
# Not:
# - Bu dosya loga yazmaz, yalnızca okur.
# - Başlatma / Rscript / stdout / stderr çıktısını gösterir.
# - Normal uygulama çalışma zamanı logları için view_latest_mergen_app_log.bat
#   kullanılmalıdır.
# - Türkçe karakterler için PowerShell tarafında UTF-8 okuma/yazma zorlanır.
# ==============================================================================

$ErrorActionPreference = "Stop"

[Console]::InputEncoding  = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $scriptDir

if (-not (Test-Path -LiteralPath (Join-Path $scriptDir "run_mergen_prod.R"))) {
  Write-Host ""
  Write-Host "[HATA] Bu izleyici MERGEN Bilge uygulama kökünden çalışmıyor."
  Write-Host "Geçerli klasör:"
  Write-Host $scriptDir
  Write-Host ""
  Write-Host "Çözüm:"
  Write-Host "Gerçek BAT ve PS1 dosyalarını uygulama kökünde tutun."
  Write-Host "Masaüstüne yalnızca kısayol koyun; BAT dosyasını Masaüstüne kopyalamayın."
  Write-Host ""
  pause
  exit 1
}

$logFile = Join-Path $scriptDir "logs\run_mergen_prod_console.log"

if (-not (Test-Path -LiteralPath $logFile)) {
  Write-Host ""
  Write-Host "[HATA] Log dosyası bulunamadı:"
  Write-Host $logFile
  Write-Host ""
  Write-Host "Önce MERGEN Bilge uygulamasını başlatın:"
  Write-Host "run_mergen_prod.bat"
  Write-Host ""
  pause
  exit 1
}

Write-Host ""
Write-Host "MERGEN Bilge üretim console log dosyası izleniyor:"
Write-Host $logFile
Write-Host ""
Write-Host "İzlemeyi durdurmak için CTRL+C tuşlarına basın. Bu işlem uygulamayı durdurmaz."
Write-Host "Normal uygulama çalışma zamanı logları logs\mergen_YYYYMMDD.log dosyasındadır."
Write-Host "Bunun için view_latest_mergen_app_log.bat dosyasını kullanın."
Write-Host "------------------------------------------------------------"
Write-Host ""

Get-Content -LiteralPath $logFile -Encoding UTF8 -Tail 120 -Wait