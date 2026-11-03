$ErrorActionPreference = 'Stop'
$inputReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
$job = $null
$code = 125
try {
    $config = ConvertFrom-Json -InputObject ($inputReader.ReadLine())
    Add-Type -Path $config.jobSource
    if (!$config.executable -or !$config.cwd) { throw 'Invalid launch' }
    $job = [MergenBrowserJob]::new([string]$config.executable, [string[]]$config.args, [string]$config.cwd)
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
    $job.Stop(5000)
    # Dogal hata cikisi, temiz agactan bagimsiz olarak hata kalir.
    if ($code -ne 124) {
        if ($job.Stopped) { $code = 0 } else { $code = $job.ExitCode }
    }
} catch {
    # Ham istisna argv, profil veya origin sizdirabilir.
    [Console]::Error.WriteLine('Owned browser launch or cleanup could not be verified.')
    if ($code -ne 124) { $code = 125 }
} finally {
    if ($null -ne $job) { $job.Dispose() }
}
exit $code
