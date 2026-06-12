# ==============================================================================
# Dosya Yolu: tools/run_repo_test_file.ps1
# Açıklama:
#   Windows VM üzerinde tek bir testthat dosyasını UNC yol ve helper yükleme
#   sorunları yaşamadan çalıştırır. PowerShell UNC dizininde durabilir; bu
#   sarmalayıcı cmd pushd ile repo yolunu geçici sürücü harfine bağlar,
#   helper_bootstrap.R dosyasını yükler ve sonra hedef test dosyasını
#   testthat::test_file ile çalıştırır.
# ==============================================================================

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$TestFile,

  [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
}

# UNC yol PowerShell içinde çalışır, ancak CMD/Rscript alt süreçleri UNC
# çalışma dizinini desteklemez. cmd pushd UNC yolu geçici sürücü harfine
# bağlar; böylece göreli repo yolları doğru kökten çözülür.
$RepoRootForCmd = $RepoRoot.ToString().TrimEnd('\')
$RepoRootForCmd = $RepoRootForCmd.Replace('"', '""')

$TestFileForR = $TestFile.Replace("\", "/")
$TestFileForR = $TestFileForR.Replace("'", "\\'")

$RCode = @"
library(testthat)
source('tests/testthat/helper_bootstrap.R', encoding = 'UTF-8')
testthat::local_edition(3)
testthat::test_file('$TestFileForR', reporter = 'summary')
"@

$RCodeForCmd = $RCode.Replace('"', '\"')

$CmdLine = @"
setlocal EnableDelayedExpansion
pushd "$RepoRootForCmd"
set "PUSHD_RC=!ERRORLEVEL!"
if not "!PUSHD_RC!"=="0" exit /b !PUSHD_RC!
Rscript -e "$RCodeForCmd"
set "TEST_RC=!ERRORLEVEL!"
popd
exit /b !TEST_RC!
"@

& cmd.exe /d /v:on /s /c $CmdLine

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}