$ErrorActionPreference = 'Stop'
# Kisitli dil modu (AppLocker/WDAC) C# derlemesini engeller; ayri kodla bildirilir.
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { exit 126 }
$job = $null
$code = 125
$stage = 'input'
try {
    # Gecersiz UTF-8 sessizce U+FFFD olmaz; bozuk yol 'input' asamasinda reddedilir.
    $inputReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false, $true))
    $config = ConvertFrom-Json -InputObject ($inputReader.ReadLine())
    if (!$config.executable -or !$config.cwd -or !$config.jobSource) { throw 'Invalid launch' }
    $stage = 'compile'
    Add-Type -LiteralPath $config.jobSource
    $stage = 'launch'
    $job = [MergenBrowserJob]::new([string]$config.executable, [string[]]$config.args, [string]$config.cwd)
    $stage = 'wait'
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $request = $inputReader.ReadLineAsync()
    while ($null -eq $job.ExitCode) {
        if ($request.IsCompleted) {
            if ($request.Result -eq 'stop') { break }
            if ($null -ne $request.Result) { throw 'Invalid control' }
        }
        if ($timer.ElapsedMilliseconds -ge $config.timeoutMs) { $code = 124; break }
        Start-Sleep -Milliseconds 10
    }
    $stage = 'cleanup'
    $job.Stop(5000)
    # Dogal hata cikisi, temiz agactan bagimsiz olarak hata kalir.
    if ($code -ne 124) {
        if ($job.Stopped) { $code = 0 } else { $code = $job.ExitCode }
    }
} catch {
    # Ham istisna argv, profil veya origin sizdirabilir; yalniz sabit asama ve Win32 kodu yazilir.
    if ($stage -eq 'launch' -and ('MergenBrowserJob' -as [type])) {
        $launchStage = [MergenBrowserJob]::LastStage
        if ($launchStage) { $stage = $launchStage }
    }
    $win32 = ''
    $inner = $_.Exception
    while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
    if ($inner -is [ComponentModel.Win32Exception]) { $win32 = ' win32=' + [string]$inner.NativeErrorCode }
    [Console]::Error.WriteLine('Owned browser launch or cleanup could not be verified.')
    [Console]::Error.WriteLine('MERGEN_OWNED_BROWSER_STAGE=' + $stage + $win32)
    if ($code -ne 124) { $code = 125 }
} finally {
    if ($null -ne $job) { $job.Dispose() }
}
exit $code
