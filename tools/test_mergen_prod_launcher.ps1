param(
    [string]$RepoRoot,
    [string]$ExpectedPort = "8009"
)

$ErrorActionPreference = "Stop"

[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        Fail $Message
    }
    Write-Ok $Message
}

function Assert-FileExists {
    param([string]$Path)
    Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) "File exists: $Path"
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    Assert-True ([regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) $Message
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    Assert-True (-not [regex]::IsMatch($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) $Message
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)

Write-Host "============================================================"
Write-Host "MERGEN Bilge production launcher regression smoke test"
Write-Host "============================================================"
Write-Info "Repo root     : $RepoRoot"
Write-Info "Expected port : $ExpectedPort"
Write-Host ""

Assert-True (Test-Path -LiteralPath $RepoRoot -PathType Container) "Repo root is reachable"

$runBat = Join-Path $RepoRoot "run_mergen_prod.bat"
$runR = Join-Path $RepoRoot "run_mergen_prod.R"
$appR = Join-Path $RepoRoot "app.R"
$logBat = Join-Path $RepoRoot "view_latest_mergen_app_log.bat"

Assert-FileExists $runBat
Assert-FileExists $runR
Assert-FileExists $appR
Assert-FileExists $logBat

Write-Host ""
Write-Info "Static checks for run_mergen_prod.bat"

$runBatText = Get-Content -LiteralPath $runBat -Raw -Encoding UTF8

Assert-Contains $runBatText 'set\s+"MERGEN_HOST=0\.0\.0\.0"' "run_mergen_prod.bat sets MERGEN_HOST=0.0.0.0"
Assert-Contains $runBatText ('set\s+"MERGEN_PORT=' + [regex]::Escape($ExpectedPort) + '"') "run_mergen_prod.bat sets MERGEN_PORT=$ExpectedPort"
Assert-Contains $runBatText 'Get-ChildItem\s+-Path\s+\$root\s+-Directory\s+-Filter\s+''R-\*''' "run_mergen_prod.bat dynamically detects newest R-* under Program Files"
Assert-Contains $runBatText 'Rscript\.exe' "run_mergen_prod.bat uses Rscript.exe"
Assert-Contains $runBatText '"%RSCRIPT_EXE%"\s+"run_mergen_prod\.R"' "run_mergen_prod.bat starts run_mergen_prod.R rather than directly calling shiny::runApp"
Assert-Contains $runBatText 'mergen_%LOG_DATE%\.log' "run_mergen_prod.bat creates daily mergen_yyyymmdd.log files"
Assert-Contains $runBatText 'Tee-Object\s+-FilePath\s+\$log\s+-Append' "run_mergen_prod.bat mirrors console output into the daily log"
Assert-Contains $runBatText 'MERGEN_LOG_WRAPPED' "run_mergen_prod.bat guards the logging wrapper against recursion"
Assert-Contains $runBatText 'goto\s+ERR_APP_DIR' "run_mergen_prod.bat uses goto-based error handling for app folder failures"
Assert-Contains $runBatText 'goto\s+ERR_PKG_CHECK' "run_mergen_prod.bat uses goto-based error handling for package-check failures"
Assert-NotContains $runBatText 'pushd\s+"%APP_DIR%\."' "run_mergen_prod.bat does not use the risky pushd \"%APP_DIR%.\" pattern"
Assert-NotContains $runBatText 'shiny::runApp\s*\(' "run_mergen_prod.bat does not bypass run_mergen_prod.R with direct shiny::runApp"
Assert-NotContains $runBatText 'Compare\s+the\s+\.libPaths\(\)\s+printed\s+above\s+with\s+the\s+\.libPaths\(\)' "run_mergen_prod.bat avoids the old CMD parser-breaking echo line with .libPaths()"
Assert-NotContains $runBatText 'if\s+errorlevel\s+10\s*\(' "run_mergen_prod.bat avoids the old fragile IF ERRORLEVEL block style"

Write-Host ""
Write-Info "Static checks for view_latest_mergen_app_log.bat"

$logBatText = Get-Content -LiteralPath $logBat -Raw -Encoding UTF8

Assert-Contains $logBatText 'set\s+"SHARE=\\\\rehisds\\uygulamalar"' "log viewer maps the expected network share"
Assert-Contains $logBatText 'net\s+use' "log viewer uses net use mapping instead of relying on UNC current directory"
Assert-Contains $logBatText 'MAPPED_BY_THIS_SCRIPT' "log viewer tracks whether it created the mapped drive"
Assert-NotContains $logBatText 'pushd\s+"%~dp0"' "log viewer does not pushd directly into its own UNC path"

Write-Host ""
Write-Info "Dynamic R detection check"

$rRoot = "C:\Program Files\R"
Assert-True (Test-Path -LiteralPath $rRoot -PathType Container) "R installation root exists: $rRoot"

$rInstall = Get-ChildItem -Path $rRoot -Directory -Filter "R-*" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $verText = $_.Name -replace '^R-', ''
        try {
            $ver = [version]$verText
            $rscript = Join-Path $_.FullName "bin\Rscript.exe"
            if (Test-Path -LiteralPath $rscript -PathType Leaf) {
                [pscustomobject]@{
                    Version = $ver
                    Path = $rscript
                }
            }
        } catch {
            # Ignore non-standard R-* folders.
        }
    } |
    Sort-Object Version -Descending |
    Select-Object -First 1

Assert-True ($null -ne $rInstall) "Newest Rscript.exe was detected dynamically under C:\Program Files\R"
$rscriptExe = $rInstall.Path
Write-Info "Detected Rscript: $rscriptExe"

Write-Host ""
Write-Info "R session diagnostics from detected Rscript"

& $rscriptExe -e "cat('R.home = ', R.home(), '\n', sep=''); cat('R.version = ', R.version.string, '\n', sep=''); cat('R_LIBS_USER = ', Sys.getenv('R_LIBS_USER'), '\n', sep=''); cat('Library paths:\n'); print(.libPaths())"
if ($LASTEXITCODE -ne 0) {
    Fail "R diagnostics failed with exit code $LASTEXITCODE"
}
Write-Ok "R diagnostics command completed"

Write-Host ""
Write-Info "Required package visibility check"

$requiredPackages = @(
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

$pkgExpr = @"
pkgs <- c('$($requiredPackages -join "','")')
ip <- rownames(installed.packages())
miss <- setdiff(pkgs, ip)
if (length(miss)) {
  cat('Missing installed packages from this Rscript session:\n')
  cat(paste(miss, collapse=', '), '\n')
  quit(status=10)
}
cat('All required packages are installed and visible in the active R library paths.\n')
"@

& $rscriptExe -e $pkgExpr
if ($LASTEXITCODE -ne 0) {
    Fail "Required package visibility check failed with exit code $LASTEXITCODE"
}
Write-Ok "Required packages are visible to the same Rscript that the launcher will use"

Write-Host ""
Write-Info "Production startup file sanity check"

$runRText = Get-Content -LiteralPath $runR -Raw -Encoding UTF8
Assert-Contains $runRText 'run_mergen_app\s*\(' "run_mergen_prod.R starts the app through run_mergen_app()"
Assert-Contains $runRText 'readRenviron\s*\(' "run_mergen_prod.R loads .Renviron explicitly"
Assert-Contains $runRText 'MERGEN_PORT' "run_mergen_prod.R reads MERGEN_PORT"

Write-Host ""
Write-Host "============================================================"
Write-Host "[PASS] Production launcher smoke test completed successfully."
Write-Host "============================================================"
exit 0
