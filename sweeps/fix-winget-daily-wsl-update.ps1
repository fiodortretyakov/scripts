<#
fix-winget-daily-wsl-update.ps1 - let the daily winget task keep WSL up to date (16 November 2026).

Why: winget's Microsoft.WSL package is an MSIX installer. Under Administrator protection the elevated
machine phase of winget-daily.ps1 runs as ADMIN_fiodo, whose winget never matches the per-user MSIX,
and fiodo's own `winget upgrade --id Microsoft.WSL` fails with 0x80073d28 (administrator privileges
required). WSL stayed at 2.7.13 from late October while 2.7.14 and 3.0.5 shipped.

  fix-winget-daily-wsl-update.ps1          dry run, no UAC: the helper's verdict for this machine and
                                           the block that would be added to winget-daily.ps1
  fix-winget-daily-wsl-update.ps1 -Apply   one UAC prompt: back up winget-daily.ps1, write update-wsl.ps1
                                           next to it, add the call, parse-check both (restore on error),
                                           then run the helper once elevated, which updates WSL now
                                           unless a container or a wsl.exe is running

Log and backup: D:\data\sweeps\fix-winget-daily-wsl-update-<time>\
Undo (elevated): copy winget-daily.ps1 from that folder back to C:\ProgramData\fiodo-tasks and delete
C:\ProgramData\fiodo-tasks\update-wsl.ps1.
#>
param(
    [switch]$Apply,
    [string]$OutDir   # internal: shared with the elevated re-launch
)
$ErrorActionPreference = 'Stop'
$TaskDir = 'C:\ProgramData\fiodo-tasks'
$Daily   = Join-Path $TaskDir 'winget-daily.ps1'
$Helper  = Join-Path $TaskDir 'update-wsl.ps1'
$Anchor  = '# ---- ARM64 regression check'
$Marker  = 'update-wsl.ps1'
if (-not $OutDir) {
    $OutDir = 'D:\data\sweeps\fix-winget-daily-wsl-update-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' })
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$LogFile = Join-Path $OutDir 'run.log'
function L([string]$m) { Add-Content -Path $LogFile -Value $m -Encoding utf8; Write-Output $m }

# ---- the helper: Windows PowerShell 5.1 compatible, ASCII only ---------------------------------
$HelperText = @'
<#
update-wsl.ps1 - called by winget-daily.ps1 in the elevated machine phase; prints one line per event.

winget's Microsoft.WSL package is an MSIX, registered per user: the machine phase (ADMIN_fiodo) never
lists its upgrades, and fiodo's unelevated winget fails with 0x80073d28.
`wsl --update --web-download` installs the GitHub release for the whole machine. The installed version
comes from `wsl --version`: WSL 3.0 dropped the "Windows Subsystem for Linux" uninstall entry.
Added 16 November 2026 by D:\bin\sweeps\fix-winget-daily-wsl-update.ps1.

An update stops every distro, dockerd included, so it waits while a container runs or a wsl.exe is
open, and the "Start WSL engine" task starts the engine again afterwards.
Exit code: 0 = current, updated or deferred; 1 = failed.
#>
param([string]$WingetExe, [switch]$DryRun)
$env:WSL_UTF8 = '1'

function Get-WslVersion {
    $line = & "$env:SystemRoot\System32\wsl.exe" --version 2>$null | Select-Object -First 1
    if ("$line" -match '(\d+\.\d+\.\d+(?:\.\d+)?)') { try { return [version]$Matches[1] } catch { } }
    return $null
}
# [version]'3.0.5' has Revision -1 and would compare lower than '3.0.5.0'.
function Get-Normal([version]$v) { New-Object Version $v.Major, $v.Minor, ([Math]::Max($v.Build, 0)), ([Math]::Max($v.Revision, 0)) }

$installed = Get-WslVersion
if (-not $installed) { 'WSL: wsl --version gave no version, nothing done'; exit 1 }

if (-not $WingetExe) {
    $c = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($c) { $WingetExe = $c.Source }
}
$latestText = $null
if ($WingetExe) {
    $show = & $WingetExe show --id Microsoft.WSL --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String
    if ($show -match '(?m)^Version:\s*(\S+)') { $latestText = $Matches[1] }
}
$latest = $null
if ($latestText) { try { $latest = [version]$latestText } catch { } }
if (-not $latest) { "WSL: $installed installed; could not read the latest version from winget"; exit 1 }
if ((Get-Normal $installed) -ge (Get-Normal $latest)) { "WSL: $installed (current)"; exit 0 }

$busy = @()
$open = @(Get-Process -Name wsl -ErrorAction SilentlyContinue)
if ($open.Count -gt 0) { $busy += "$($open.Count) wsl.exe open" }
$docker = Get-Command docker.exe -ErrorAction SilentlyContinue
if ($docker) {
    $ids = @(& $docker.Source ps -q 2>$null | Where-Object { $_ })
    if ($LASTEXITCODE -eq 0 -and $ids.Count -gt 0) { $busy += "$($ids.Count) container(s) running" }
}
if ($busy.Count -gt 0) { "WSL: $installed -> $latestText pending, deferred: $($busy -join ', ')"; exit 0 }
if ($DryRun) { "WSL: $installed -> $latestText, would run wsl --update --web-download, then start the 'Start WSL engine' task"; exit 0 }

$out = @(& "$env:SystemRoot\System32\wsl.exe" --update --web-download 2>&1 | ForEach-Object { ("$_" -replace "`0", '').Trim() } | Where-Object { $_ })
$code = $LASTEXITCODE
# The MSI may finish after wsl.exe returns: wait up to 2 minutes for the new version.
$after = Get-WslVersion
for ($i = 0; $i -lt 24 -and $after -and (Get-Normal $after) -le (Get-Normal $installed); $i++) { Start-Sleep -Seconds 5; $after = Get-WslVersion }

$engine = 'started'
try { Start-ScheduledTask -TaskName 'Start WSL engine' -ErrorAction Stop } catch { $engine = "not started: $($_.Exception.Message)" }
$dockerState = 'no docker CLI'
if ($docker) {
    $dockerState = 'not reachable after 60 s'
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        & $docker.Source version --format '{{.Server.Version}}' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $dockerState = 'reachable'; break }
    }
}
if ($after -and (Get-Normal $after) -gt (Get-Normal $installed)) {
    "WSL: $installed -> $after updated (wsl --update exit $code); engine $engine; docker $dockerState"
    exit 0
}
"WSL: update FAILED, still $after (wsl --update exit $code): $(($out | Select-Object -Last 2) -join ' | '); engine $engine"
exit 1
'@

# ---- the call added to winget-daily.ps1, right before the ARM64 check --------------------------
$Hook = @'
# ---- WSL (machine phase) -------------------------------------------------------
# Microsoft.WSL is an MSIX package, registered per user: this phase (ADMIN_fiodo) never lists its
# upgrades and fiodo's unelevated winget fails with 0x80073d28. update-wsl.ps1 compares the machine-wide
# MSI with winget's latest and runs wsl --update itself, deferred while containers run (16 November 2026).
if ($IsMachine -and -not $SkipUpgrade) {
    W "--- WSL ---"
    try { & (Join-Path $PSScriptRoot 'update-wsl.ps1') -WingetExe $WingetExe 2>&1 | ForEach-Object { W "  $_" } }
    catch { W "  WSL: $($_.Exception.Message)" }
}

'@

function Test-Parse([string]$path) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    return @($errs)
}

$text = [IO.File]::ReadAllText($Daily)
$hooked = $text.Contains($Marker)
$anchorCount = ([regex]::Matches($text, [regex]::Escape($Anchor))).Count

if (-not $Apply) {
    L "DRY RUN $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $tmp = Join-Path $OutDir 'update-wsl.ps1'
    [IO.File]::WriteAllText($tmp, $HelperText)
    $errs = Test-Parse $tmp
    L "helper parse errors: $($errs.Count)"
    L "helper verdict (Windows PowerShell 5.1, as the task runs it):"
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $tmp -DryRun | ForEach-Object { L "  $_" }
    L "winget-daily.ps1: anchor found $anchorCount time(s); already hooked: $hooked"
    L "would write $Helper and insert before '$Anchor':"
    $Hook.TrimEnd() -split "`r?`n" | ForEach-Object { L "  | $_" }
    L "Run with -Apply to do it (one UAC prompt)."
    exit 0
}

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Apply', '-OutDir', "`"$OutDir`"")
    try { $p = Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList }
    catch { Write-Output "Elevation cancelled: $($_.Exception.Message)"; exit 1 }
    if (Test-Path $LogFile) { Get-Content $LogFile }
    exit $p.ExitCode
}

try {
    L "APPLY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') as $(whoami)"
    if ($anchorCount -ne 1 -and -not $hooked) { L "STOP: anchor '$Anchor' found $anchorCount times, expected 1"; exit 1 }
    Copy-Item $Daily (Join-Path $OutDir 'winget-daily.ps1')
    if (Test-Path $Helper) { Copy-Item $Helper (Join-Path $OutDir 'update-wsl.ps1.before') }
    L "backup: $OutDir\winget-daily.ps1"

    [IO.File]::WriteAllText($Helper, $HelperText)
    if ($hooked) {
        L "winget-daily.ps1 already calls update-wsl.ps1: left as it is"
    } else {
        $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $i = $text.IndexOf($Anchor)
        $new = $text.Substring(0, $i) + (($Hook -split "`r?`n") -join $nl) + $text.Substring($i)
        [IO.File]::WriteAllText($Daily, $new)
        L "winget-daily.ps1: WSL block inserted before the ARM64 check"
    }
    $bad = @(Test-Parse $Helper) + @(Test-Parse $Daily)
    if ($bad.Count -gt 0) {
        $bad | ForEach-Object { L "  parse error: $($_.Extent.File):$($_.Extent.StartLineNumber) $($_.Message)" }
        Copy-Item (Join-Path $OutDir 'winget-daily.ps1') $Daily -Force
        Remove-Item $Helper -Force
        L "STOP: parse errors, winget-daily.ps1 restored and update-wsl.ps1 removed"
        exit 1
    }
    L "parse check: both files clean"

    L "test run (elevated, Windows PowerShell 5.1, as the task runs it):"
    $winget = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    $wingetArg = if (Test-Path $winget) { @('-WingetExe', $winget) } else { @() }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $Helper @wingetArg | ForEach-Object { L "  $_" }
    L "test exit code: $LASTEXITCODE"
    exit $LASTEXITCODE
} catch {
    L "FAILED: $($_.Exception.Message)"
    exit 1
}
