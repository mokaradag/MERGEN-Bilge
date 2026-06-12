# ==============================================================================
# Dosya Yolu: tools/run_repo_rscript.ps1
# Açıklama:
#   Windows VM üzerinde repo içindeki herhangi bir R betiğini UNC yol sorunu
#   yaşamadan çalıştırır. PowerShell UNC dizininde durabilir; bu sarmalayıcı
#   cmd pushd ile UNC yolu geçici sürücü harfine bağlar ve Rscript'i oradan
#   çalıştırır.
# ==============================================================================

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Script,

  [string]$RepoRoot = "",

  [switch]$Vanilla
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

$ScriptForCmd = $Script.Replace('"', '""')

$RscriptArgs = ""
if ($Vanilla) {
  $RscriptArgs = "--vanilla "
}

$CmdLine = @"
setlocal EnableDelayedExpansion
pushd "$RepoRootForCmd"
set "PUSHD_RC=!ERRORLEVEL!"
if not "!PUSHD_RC!"=="0" exit /b !PUSHD_RC!
Rscript $RscriptArgs"$ScriptForCmd"
set "RSCRIPT_RC=!ERRORLEVEL!"
popd
exit /b !RSCRIPT_RC!
"@

& cmd.exe /d /v:on /s /c $CmdLine

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}