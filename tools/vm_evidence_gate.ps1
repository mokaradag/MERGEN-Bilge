# ==============================================================================
# Dosya Yolu: tools/vm_evidence_gate.ps1
# Açıklama:
#   Windows VM üzerinde tests/scripts/run_vm_evidence_gate.R kanıt kapısını
#   PowerShell ile güvenli ve tekrarlanabilir şekilde çalıştırır.
# ==============================================================================

param(
  [string]$Profile = "vm",
  [string]$RepoRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
}

$env:MERGEN_EVIDENCE_PROFILE = $Profile

if ([string]::IsNullOrWhiteSpace($env:SSO_ENABLED)) {
  $env:SSO_ENABLED = "TRUE"
}

if ([string]::IsNullOrWhiteSpace($env:DB_CLIENT_ENCODING)) {
  $env:DB_CLIENT_ENCODING = "WINDOWS-1254"
}

if ([string]::IsNullOrWhiteSpace($env:DB_NAME_ENCODING)) {
  $env:DB_NAME_ENCODING = "WINDOWS-1254"
}

if ([string]::IsNullOrWhiteSpace($env:MERGEN_PORT)) {
  $env:MERGEN_PORT = "8009"
}

# UNC yol PowerShell icinde calisir, ancak CMD/Rscript alt surecleri UNC
# calisma dizinini desteklemez. cmd pushd UNC yolu gecici surucu harfine
# baglar; boylece goreli tests\scripts yolu dogru kokten cozulur.
$RepoRootForCmd = $RepoRoot.ToString().TrimEnd('\')
$RepoRootForCmd = $RepoRootForCmd.Replace('"', '""')

$CmdLine = @"
setlocal EnableDelayedExpansion
pushd "$RepoRootForCmd"
set "PUSHD_RC=!ERRORLEVEL!"
if not "!PUSHD_RC!"=="0" exit /b !PUSHD_RC!
Rscript --vanilla tests\scripts\run_vm_evidence_gate.R
set "GATE_RC=!ERRORLEVEL!"
popd
exit /b !GATE_RC!
"@

& cmd.exe /d /v:on /s /c $CmdLine

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}