$ErrorActionPreference = "Stop"

$launcherBat = $env:MERGEN_LAUNCHER_BAT
$launcherDir = $env:MERGEN_LAUNCHER_DIR

if ([string]::IsNullOrWhiteSpace($launcherBat)) {
    throw "MERGEN_LAUNCHER_BAT is not set."
}

if ([string]::IsNullOrWhiteSpace($launcherDir)) {
    throw "MERGEN_LAUNCHER_DIR is not set."
}

$logDir = Join-Path $launcherDir "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$date = Get-Date -Format "yyyyMMdd"
$logFile = Join-Path $logDir ("mergen_{0}.log" -f $date)

Write-Host "[INFO] Daily console log file: $logFile"

$cmd = 'call "' + $launcherBat + '"'
& $env:ComSpec /d /c $cmd 2>&1 | Tee-Object -FilePath $logFile -Append
$exitCode = $LASTEXITCODE

exit $exitCode
