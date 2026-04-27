# ==============================================================================
# MERGEN Bilge Production Launcher Self-Test
# File: C:\MergenLauncher\test_mergen_prod_launcher.ps1
# ==============================================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

$Share = "\\rehisds\uygulamalar"
$Drive = "T:"
$AppRel = "Primavera\PYB\04 - Geliştirme\MERGEN Bilge"
$ExpectedPort = 8009

$RequiredPackages = @(
    "arrow",
    "duckdb",
    "fastmatch",
    "pdftools",
    "pool",
    "shinyBS",
    "stringdist",
    "writexl",
    "av"
)

$RequiredEnvVars = @(
    "DB_DSN",
    "LOCAL_LLM_ENDPOINT"
)

$LauncherDir = "C:\MergenLauncher"
$LogDir = Join-Path $LauncherDir "test_logs"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogDir "mergen_launcher_selftest_$Timestamp.log"

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
$MappedByThisScript = $false

function Write-Line {
    param([string]$Text = "")
    Write-Host $Text
    Add-Content -Path $LogFile -Value $Text -Encoding UTF8
}

function Pass {
    param([string]$Text)
    Write-Line "[PASS] $Text"
}

function Warn {
    param([string]$Text)
    $Warnings.Add($Text) | Out-Null
    Write-Line "[WARN] $Text"
}

function Fail {
    param([string]$Text)
    $Failures.Add($Text) | Out-Null
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

Write-Line "============================================================"
Write-Line "MERGEN Bilge Production Launcher Self-Test"
Write-Line "Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Line "Log file: $LogFile"
Write-Line "============================================================"

# ------------------------------------------------------------------------------
# 1. Map network share to test drive
# ------------------------------------------------------------------------------

Test-Step "Network share mapping" {
    Write-Line "Share: $Share"
    Write-Line "Drive: $Drive"

    & net.exe use $Drive /delete /y | Out-Null 2>&1

    $mapOutput = & net.exe use $Drive $Share /persistent:no 2>&1
    Add-Content -Path $LogFile -Value ($mapOutput | Out-String) -Encoding UTF8

    if ($LASTEXITCODE -ne 0) {
        throw "Could not map $Share to $Drive. net use exit code: $LASTEXITCODE"
    }

    $MappedByThisScript = $true

    if (-not (Test-Path "$Drive\")) {
        throw "Mapped drive is not accessible: $Drive\"
    }

    Pass "Network share mapped successfully."
}

$AppDir = Join-Path "$Drive\" $AppRel
$RunBat = Join-Path $AppDir "run_mergen_prod.bat"
$RunR = Join-Path $AppDir "run_mergen_prod.R"
$AppR = Join-Path $AppDir "app.R"
$LogViewerBat = Join-Path $AppDir "view_latest_mergen_app_log.bat"

# ------------------------------------------------------------------------------
# 2. Check app folder and required files
# ------------------------------------------------------------------------------

Test-Step "Application folder and required files" {
    Write-Line "AppDir: $AppDir"

    if (-not (Test-Path $AppDir)) {
        throw "Application folder not found: $AppDir"
    }

    $requiredFiles = @(
        $RunBat,
        $RunR,
        $AppR
    )

    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            throw "Required file missing: $file"
        }
        Pass "Found: $file"
    }

    if (Test-Path $LogViewerBat) {
        Pass "Found: $LogViewerBat"
    }
    else {
        Warn "Log viewer file not found: $LogViewerBat"
    }
}

# ------------------------------------------------------------------------------
# 3. Static checks for run_mergen_prod.bat
# ------------------------------------------------------------------------------

Test-Step "run_mergen_prod.bat static safety checks" {
    $bat = Get-Content -LiteralPath $RunBat -Raw -Encoding UTF8

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

    $dangerousEchoLines = Select-String -LiteralPath $RunBat -Pattern '^\s*echo .*[()]' -Encoding UTF8
    if ($dangerousEchoLines) {
        Warn "Potentially risky echo lines with parentheses were found. These can break CMD inside IF blocks."
        foreach ($line in $dangerousEchoLines) {
            Write-Line "       Line $($line.LineNumber): $($line.Line)"
        }
    }
    else {
        Pass "No risky echo lines with parentheses found."
    }
}

# ------------------------------------------------------------------------------
# 4. Static checks for view_latest_mergen_app_log.bat
# ------------------------------------------------------------------------------

Test-Step "view_latest_mergen_app_log.bat static safety checks" {
    if (-not (Test-Path $LogViewerBat)) {
        Warn "Skipping log viewer checks because file does not exist."
        return
    }

    $bat = Get-Content -LiteralPath $LogViewerBat -Raw -Encoding UTF8

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

# ------------------------------------------------------------------------------
# 5. Detect newest installed R
# ------------------------------------------------------------------------------

$Rscript = $null

Test-Step "Dynamic Rscript detection" {
    $RRoot = "C:\Program Files\R"

    if (-not (Test-Path $RRoot)) {
        throw "R root folder not found: $RRoot"
    }

    $found = Get-ChildItem -Path $RRoot -Directory -Filter "R-*" |
        ForEach-Object {
            $verText = $_.Name -replace '^R-', ''
            try {
                $ver = [version]$verText
                $candidate = Join-Path $_.FullName "bin\Rscript.exe"
                if (Test-Path $candidate) {
                    [pscustomobject]@{
                        Version = $ver
                        Path = $candidate
                    }
                }
            }
            catch {
                # Ignore folders that are not valid R version folders.
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

# ------------------------------------------------------------------------------
# 6. R diagnostics
# ------------------------------------------------------------------------------

Test-Step "R diagnostics and library paths" {
    $cmd = @"
cat('R.home = ', R.home(), '\n', sep='')
cat('R.version = ', R.version.string, '\n', sep='')
cat('R_LIBS_USER = ', Sys.getenv('R_LIBS_USER'), '\n', sep='')
cat('Library paths:\n')
print(.libPaths())
"@

    $output = & $Rscript -e $cmd 2>&1
    Add-Content -Path $LogFile -Value ($output | Out-String) -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        throw "R diagnostics failed. Exit code: $LASTEXITCODE"
    }

    Pass "R diagnostics completed successfully."
}

# ------------------------------------------------------------------------------
# 7. Required R package installation check
# ------------------------------------------------------------------------------

Test-Step "Required R package visibility" {
    $pkgList = ($RequiredPackages | ForEach-Object { '"' + $_ + '"' }) -join ", "

    $cmd = @"
pkgs <- c($pkgList)
ip <- rownames(installed.packages())
miss <- setdiff(pkgs, ip)
if (length(miss)) {
  cat('Missing installed packages:\n')
  cat(paste(miss, collapse = ', '), '\n')
  quit(status = 10)
}
cat('All required packages are installed and visible.\n')
"@

    $output = & $Rscript -e $cmd 2>&1
    Add-Content -Path $LogFile -Value ($output | Out-String) -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        throw "Required package check failed. Exit code: $LASTEXITCODE"
    }

    Pass "All required R packages are visible."
}

# ------------------------------------------------------------------------------
# 8. R syntax parse checks
# ------------------------------------------------------------------------------

Test-Step "R startup file parse checks" {
    Push-Location $AppDir

    try {
        $cmd = @"
parse(file = 'run_mergen_prod.R')
parse(file = 'app.R')
cat('R startup files parsed successfully.\n')
"@

        $output = & $Rscript -e $cmd 2>&1
        Add-Content -Path $LogFile -Value ($output | Out-String) -Encoding UTF8
        $output | ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "R parse check failed. Exit code: $LASTEXITCODE"
        }

        Pass "run_mergen_prod.R and app.R parsed successfully."
    }
    finally {
        Pop-Location
    }
}

# ------------------------------------------------------------------------------
# 9. .Renviron and required environment variables
# ------------------------------------------------------------------------------

Test-Step ".Renviron and required environment variables" {
    Push-Location $AppDir

    try {
        $envList = ($RequiredEnvVars | ForEach-Object { '"' + $_ + '"' }) -join ", "

        $cmd = @"
renv <- file.path(getwd(), '.Renviron')
if (file.exists(renv)) {
  readRenviron(renv)
  cat('.Renviron loaded from: ', renv, '\n', sep = '')
} else {
  cat('.Renviron not found. Checking system/user environment only.\n')
}
required <- c($envList)
missing <- required[!nzchar(Sys.getenv(required, unset = ''))]
if (length(missing)) {
  cat('Missing required environment variables:\n')
  cat(paste(missing, collapse = ', '), '\n')
  quit(status = 10)
}
cat('Required environment variables are available.\n')
"@

        $output = & $Rscript -e $cmd 2>&1
        Add-Content -Path $LogFile -Value ($output | Out-String) -Encoding UTF8
        $output | ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "Environment variable check failed. Exit code: $LASTEXITCODE"
        }

        Pass "Required environment variables are available."
    }
    finally {
        Pop-Location
    }
}

# ------------------------------------------------------------------------------
# 10. Port check
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------

Write-Line ""
Write-Line "------------------------------------------------------------"
Write-Line "[CLEANUP]"
Write-Line "------------------------------------------------------------"

if ($MappedByThisScript) {
    & net.exe use $Drive /delete /y | Out-Null 2>&1
    Write-Line "Unmapped test drive: $Drive"
}

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------

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