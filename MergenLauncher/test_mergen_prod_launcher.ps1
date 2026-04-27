$ErrorActionPreference = "Stop"

# ASCII-only MERGEN launcher self-test.
# This script avoids Turkish path literals and avoids fragile R -e quoting.

$Share = "\\rehisds\uygulamalar"
$Drive = "T:"
$SearchRootRel = "Primavera\PYB"
$ExpectedAppFolderName = "MERGEN Bilge"
$ExpectedPort = 8009

$RequiredPackagesCsv = "arrow,duckdb,fastmatch,pdftools,pool,shinyBS,stringdist,writexl,av"
$RequiredEnvVarsCsv = "DB_DSN,LOCAL_LLM_ENDPOINT"

$LauncherDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $LauncherDir) {
    $LauncherDir = "C:\MergenLauncher"
}

$LogDir = Join-Path $LauncherDir "test_logs"
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "mergen_launcher_selftest_$Timestamp.log"

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]

$MappedByThisScript = $false
$AppDir = $null
$RunBat = $null
$RunR = $null
$AppR = $null
$LogViewerBat = $null
$Rscript = $null

function Write-Line {
    param([string]$Text = "")
    Write-Host $Text
    Add-Content -LiteralPath $LogFile -Value $Text -Encoding UTF8
}

function Pass {
    param([string]$Text)
    Write-Line "[PASS] $Text"
}

function Warn {
    param([string]$Text)
    $script:Warnings.Add($Text) | Out-Null
    Write-Line "[WARN] $Text"
}

function Fail {
    param([string]$Text)
    $script:Failures.Add($Text) | Out-Null
    Write-Line "[FAIL] $Text"
}

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )

    Write-Line ""
    Write-Line "------------------------------------------------------------"
    Write-Line "[TEST] $Name"
    Write-Line "------------------------------------------------------------"

    try {
        & $Body
    }
    catch {
        Fail "$Name failed: $($_.Exception.Message)"
    }
}

function Invoke-RScriptFile {
    param(
        [string]$RCode
    )

    $TempR = Join-Path $env:TEMP ("mergen_selftest_" + [guid]::NewGuid().ToString("N") + ".R")

    try {
        Set-Content -LiteralPath $TempR -Value $RCode -Encoding ASCII
        $output = & $script:Rscript $TempR 2>&1
        Add-Content -LiteralPath $LogFile -Value ($output | Out-String) -Encoding UTF8
        $output | ForEach-Object { Write-Host $_ }
        return $LASTEXITCODE
    }
    finally {
        if (Test-Path -LiteralPath $TempR) {
            Remove-Item -LiteralPath $TempR -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Line "============================================================"
Write-Line "MERGEN Bilge Production Launcher Self-Test"
Write-Line "Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Line "Log file: $LogFile"
Write-Line "============================================================"

Test-Step "Network share mapping" {
    Write-Line "Share: $Share"
    Write-Line "Drive: $Drive"

    & net.exe use $Drive /delete /y | Out-Null 2>&1

    $mapOutput = & net.exe use $Drive $Share /persistent:no 2>&1
    Add-Content -LiteralPath $LogFile -Value ($mapOutput | Out-String) -Encoding UTF8

    if ($LASTEXITCODE -ne 0) {
        throw "Could not map $Share to $Drive. net use exit code: $LASTEXITCODE"
    }

    $script:MappedByThisScript = $true

    if (-not (Test-Path -LiteralPath "$Drive\")) {
        throw "Mapped drive is not accessible: $Drive\"
    }

    Pass "Network share mapped successfully."
}

Test-Step "Discover MERGEN Bilge app folder" {
    $SearchRoot = Join-Path "$Drive\" $SearchRootRel

    Write-Line "Search root: $SearchRoot"

    if (-not (Test-Path -LiteralPath $SearchRoot)) {
        throw "Search root not found: $SearchRoot"
    }

    $allCandidates = Get-ChildItem -LiteralPath $SearchRoot -Recurse -Filter "run_mergen_prod.bat" -File -ErrorAction SilentlyContinue

    if (-not $allCandidates -or $allCandidates.Count -eq 0) {
        throw "No run_mergen_prod.bat file found under $SearchRoot"
    }

    $candidates = $allCandidates | Where-Object {
        $parent = Split-Path -Parent $_.FullName
        $leaf = Split-Path -Leaf $parent
        $leaf -eq $ExpectedAppFolderName
    } | Sort-Object FullName

    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-Line "Found run_mergen_prod.bat files, but none under folder named '$ExpectedAppFolderName'. Candidates:"
        foreach ($item in ($allCandidates | Select-Object -First 30)) {
            Write-Line "  $($item.FullName)"
        }
        throw "MERGEN Bilge app folder could not be discovered."
    }

    if ($candidates.Count -gt 1) {
        Warn "Multiple candidates found. Using the first one."
        foreach ($item in $candidates) {
            Write-Line "  Candidate: $($item.FullName)"
        }
    }

    $script:RunBat = $candidates[0].FullName
    $script:AppDir = Split-Path -Parent $script:RunBat
    $script:RunR = Join-Path $script:AppDir "run_mergen_prod.R"
    $script:AppR = Join-Path $script:AppDir "app.R"
    $script:LogViewerBat = Join-Path $script:AppDir "view_latest_mergen_app_log.bat"

    Write-Line "Discovered AppDir:"
    Write-Line $script:AppDir

    Pass "MERGEN Bilge app folder discovered successfully."
}

Test-Step "Application folder and required files" {
    if (-not (Test-Path -LiteralPath $script:AppDir)) {
        throw "Application folder not found: $script:AppDir"
    }

    foreach ($file in @($script:RunBat, $script:RunR, $script:AppR)) {
        if (-not (Test-Path -LiteralPath $file)) {
            throw "Required file missing: $file"
        }
        Pass "Found: $file"
    }

    if (Test-Path -LiteralPath $script:LogViewerBat) {
        Pass "Found: $script:LogViewerBat"
    }
    else {
        Warn "Log viewer file not found: $script:LogViewerBat"
    }
}

Test-Step "run_mergen_prod.bat static safety checks" {
    $bat = Get-Content -LiteralPath $script:RunBat -Raw

    if ($bat -match 'pushd\s+"%APP_DIR%\."') {
        Fail 'Unsafe pattern found: pushd "%APP_DIR%."'
    }
    else {
        Pass 'Unsafe pattern not found: pushd "%APP_DIR%."'
    }

    if ($bat -match 'set\s+"MERGEN_PORT=8009"') {
        Pass "MERGEN_PORT is set to 8009."
    }
    else {
        Fail "MERGEN_PORT is not set to 8009 in run_mergen_prod.bat."
    }

    if ($bat -match 'run_mergen_prod\.R') {
        Pass "run_mergen_prod.bat starts through run_mergen_prod.R."
    }
    else {
        Fail "run_mergen_prod.bat does not appear to start run_mergen_prod.R."
    }

    if ($bat -match 'shiny::runApp') {
        Warn "run_mergen_prod.bat still contains shiny::runApp directly. Prefer run_mergen_prod.R."
    }
    else {
        Pass "No direct shiny::runApp call found in run_mergen_prod.bat."
    }
}

Test-Step "view_latest_mergen_app_log.bat static safety checks" {
    if (-not (Test-Path -LiteralPath $script:LogViewerBat)) {
        Warn "Skipping log viewer checks because file does not exist."
        return
    }

    $bat = Get-Content -LiteralPath $script:LogViewerBat -Raw

    if ($bat -match 'pushd\s+"%~dp0"') {
        Fail 'Log viewer still uses UNC-sensitive pattern: pushd "%~dp0"'
    }
    else {
        Pass 'Log viewer does not use UNC-sensitive pushd "%~dp0" pattern.'
    }

    if ($bat -match 'net use') {
        Pass "Log viewer appears to use mapped-drive logic."
    }
    else {
        Warn "Log viewer does not appear to map the network share itself."
    }
}

Test-Step "Dynamic Rscript detection" {
    $RRoot = "C:\Program Files\R"

    if (-not (Test-Path -LiteralPath $RRoot)) {
        throw "R root folder not found: $RRoot"
    }

    $found = Get-ChildItem -LiteralPath $RRoot -Directory -Filter "R-*" |
        ForEach-Object {
            $verText = $_.Name -replace '^R-', ''
            try {
                $ver = [version]$verText
                $candidate = Join-Path $_.FullName "bin\Rscript.exe"
                if (Test-Path -LiteralPath $candidate) {
                    [pscustomobject]@{
                        Version = $ver
                        Path = $candidate
                    }
                }
            }
            catch {
            }
        } |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $found) {
        throw "No valid Rscript.exe found under $RRoot"
    }

    $script:Rscript = $found.Path

    Write-Line "Detected Rscript: $script:Rscript"
    Pass "Newest Rscript detected successfully."
}

Test-Step "R diagnostics and library paths" {
    $rcode = @'
cat("R.home = ", R.home(), "\n", sep = "")
cat("R.version = ", R.version.string, "\n", sep = "")
cat("R_LIBS_USER = ", Sys.getenv("R_LIBS_USER"), "\n", sep = "")
cat("Library paths:\n")
print(.libPaths())
'@

    $code = Invoke-RScriptFile $rcode

    if ($code -ne 0) {
        throw "R diagnostics failed. Exit code: $code"
    }

    Pass "R diagnostics completed successfully."
}

Test-Step "Required R package visibility" {
    $env:MERGEN_TEST_REQUIRED_PACKAGES = $RequiredPackagesCsv

    $rcode = @'
pkgs <- strsplit(Sys.getenv("MERGEN_TEST_REQUIRED_PACKAGES"), ",", fixed = TRUE)[[1]]
pkgs <- trimws(pkgs)
ip <- rownames(installed.packages())
miss <- setdiff(pkgs, ip)

if (length(miss)) {
  cat("Missing installed packages:\n")
  cat(paste(miss, collapse = ", "), "\n")
  quit(status = 10)
}

cat("All required packages are installed and visible.\n")
'@

    $code = Invoke-RScriptFile $rcode

    if ($code -ne 0) {
        throw "Required package check failed. Exit code: $code"
    }

    Pass "All required R packages are visible."
}

Test-Step "R startup file parse checks" {
    Push-Location -LiteralPath $script:AppDir

    try {
        $rcode = @'
parse(file = "run_mergen_prod.R")
parse(file = "app.R")
cat("R startup files parsed successfully.\n")
'@

        $code = Invoke-RScriptFile $rcode

        if ($code -ne 0) {
            throw "R parse check failed. Exit code: $code"
        }

        Pass "run_mergen_prod.R and app.R parsed successfully."
    }
    finally {
        Pop-Location
    }
}

Test-Step ".Renviron and required environment variables" {
    Push-Location -LiteralPath $script:AppDir

    try {
        $env:MERGEN_TEST_REQUIRED_ENV_VARS = $RequiredEnvVarsCsv

        $rcode = @'
renv <- file.path(getwd(), ".Renviron")

if (file.exists(renv)) {
  readRenviron(renv)
  cat(".Renviron loaded from: ", renv, "\n", sep = "")
} else {
  cat(".Renviron not found. Checking system/user environment only.\n")
}

required <- strsplit(Sys.getenv("MERGEN_TEST_REQUIRED_ENV_VARS"), ",", fixed = TRUE)[[1]]
required <- trimws(required)

missing <- required[!nzchar(Sys.getenv(required, unset = ""))]

if (length(missing)) {
  cat("Missing required environment variables:\n")
  cat(paste(missing, collapse = ", "), "\n")
  quit(status = 10)
}

cat("Required environment variables are available.\n")
'@

        $code = Invoke-RScriptFile $rcode

        if ($code -ne 0) {
            throw "Environment variable check failed. Exit code: $code"
        }

        Pass "Required environment variables are available."
    }
    finally {
        Pop-Location
    }
}

Test-Step "Port 8009 check" {
    $listeners = Get-NetTCPConnection -LocalPort $ExpectedPort -State Listen -ErrorAction SilentlyContinue

    if ($listeners) {
        Warn "Port $ExpectedPort is already listening. This is OK if MERGEN Bilge is already running."

        foreach ($listener in $listeners) {
            Write-Line "       LocalAddress=$($listener.LocalAddress), OwningProcess=$($listener.OwningProcess)"
        }

        try {
            $url = "http://127.0.0.1:$ExpectedPort/"
            Write-Line "Trying HTTP check: $url"
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            Pass "HTTP check succeeded. Status code: $($response.StatusCode)"
        }
        catch {
            Warn "Port is listening, but HTTP check failed: $($_.Exception.Message)"
        }
    }
    else {
        Pass "Port $ExpectedPort is currently free. This is normal before starting the app."
    }
}

Write-Line ""
Write-Line "------------------------------------------------------------"
Write-Line "[CLEANUP]"
Write-Line "------------------------------------------------------------"

if ($MappedByThisScript) {
    & net.exe use $Drive /delete /y | Out-Null 2>&1
    Write-Line "Unmapped test drive: $Drive"
}

Write-Line ""
Write-Line "============================================================"
Write-Line "SELF-TEST SUMMARY"
Write-Line "============================================================"

Write-Line "Failures: $($Failures.Count)"
foreach ($f in $Failures) {
    Write-Line "  - $f"
}

Write-Line "Warnings: $($Warnings.Count)"
foreach ($w in $Warnings) {
    Write-Line "  - $w"
}

Write-Line ""
Write-Line "Log file:"
Write-Line $LogFile
Write-Line ""

if ($Failures.Count -gt 0) {
    Write-Line "[RESULT] FAILED"
    exit 1
}
else {
    Write-Line "[RESULT] PASSED"
    exit 0
}