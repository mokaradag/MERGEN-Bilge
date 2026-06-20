# ==============================================================================
# tools/disable_console_quickedit.ps1
# Purpose: Disable the Windows console "QuickEdit Mode" for the CURRENT console.
#
# Why this matters for MERGEN Bilge production:
#   When QuickEdit Mode is enabled (the Windows default), clicking inside the
#   console window that runs the Shiny app puts the console into selection/mark
#   mode. While in that mode, ANY process attached to the console BLOCKS on its
#   next write to the screen buffer. The MERGEN Bilge R/Shiny process is single
#   threaded, so a blocked stdout write freezes the whole event loop -> every
#   connected user's screen freezes. Pressing Enter / Esc / clicking again exits
#   mark mode, the buffered output flushes all at once, and the app resumes.
#   That is exactly the intermittent "app frozen for no reason, unfreezes when I
#   click the cmd window" symptom on the on-prem VM.
#
#   Clearing ENABLE_QUICK_EDIT_MODE (and setting ENABLE_EXTENDED_FLAGS so the
#   change takes effect) on the shared console input handle prevents accidental
#   selections from suspending the app. The change is a property of the console
#   object, so it persists for the cmd session and the Rscript launched after.
#
# Safety: This is best-effort and must NEVER break startup. On any failure it
#   prints a warning and exits 0. ASCII-only on purpose (Windows/VM safe).
# ==============================================================================

$ErrorActionPreference = 'SilentlyContinue'

try {
    $signature = @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@

    $consoleApi = Add-Type -Name 'MergenConsoleApi' -Namespace 'Mergen' `
        -MemberDefinition $signature -PassThru -ErrorAction Stop

    # STD_INPUT_HANDLE = -10
    $stdInHandle = $consoleApi::GetStdHandle(-10)

    # GetConsoleMode fails for a null/invalid handle (e.g. no real console),
    # which is our skip signal; no need for a separate INVALID_HANDLE compare.
    if ($stdInHandle -eq [IntPtr]::Zero) {
        Write-Host '[QUICKEDIT] No console input handle; skipping (non-interactive session).'
        exit 0
    }

    $mode = [uint32]0
    if (-not $consoleApi::GetConsoleMode($stdInHandle, [ref]$mode)) {
        Write-Host '[QUICKEDIT] GetConsoleMode failed; skipping (no interactive console).'
        exit 0
    }

    # Use explicit uint32 masks to avoid signed-int bitwise edge cases.
    # ~ENABLE_QUICK_EDIT_MODE (0x0040) = 0xFFFFFFBF ; ENABLE_EXTENDED_FLAGS = 0x0080
    $clearQuickEdit = [uint32]0xFFFFFFBF
    $extendedFlags  = [uint32]0x00000080

    # Clear QuickEdit, set Extended flags so the mode change is honored.
    $newMode = [uint32](([uint32]$mode -band $clearQuickEdit) -bor $extendedFlags)

    if ($consoleApi::SetConsoleMode($stdInHandle, $newMode)) {
        Write-Host '[QUICKEDIT] Console QuickEdit Mode disabled (prevents accidental freeze).'
    } else {
        Write-Host '[QUICKEDIT] SetConsoleMode failed; QuickEdit unchanged.'
    }
}
catch {
    Write-Host ('[QUICKEDIT] Could not adjust console mode: ' + $_.Exception.Message)
}

exit 0
