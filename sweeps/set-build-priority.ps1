<#
set-build-priority.ps1  -  12 October 2026 (Go), 13 October 2026 (java.exe added; was set-go-build-priority.ps1)

Makes the Go toolchain and Java (Gradle daemon, workers, test forks, SpotBugs) yield to the foreground.
At 10:42 on 12 October 2026 one Go link of a large test binary (link.exe, 4.3 GB) drove the
machine to 100 % CPU (83 % kernel), 45 000 pages/s and a saturated disk for about 70 s; VS Code and
Chrome stalled behind it. At 10:56 on 13 October 2026 a Gradle build (two SpotBugs forks at 220-255 %
CPU) plus a Go link left 2.3 GB RAM free at 11 500 pages/s and the desktop stalled again.

Sets Image File Execution Options\<exe>\PerfOptions for those tools: CPU priority BelowNormal,
I/O priority Low, memory page priority Low. Windows applies these when the process starts, for
every caller (VS Code, Claude sessions, terminals, go-test). Test binaries started by go.exe
inherit BelowNormal. Builds still get all idle CPU and disk; they only lose when the foreground
wants them. IFEO matches by file name, so link.exe also covers an MSVC linker if one is installed,
and java.exe covers every console Java program; javaw.exe (GUI Java apps) is deliberately not listed.

  set-build-priority.ps1           dry run: current and target values per executable
  set-build-priority.ps1 -Apply    write the values (one UAC prompt)
  set-build-priority.ps1 -Remove   delete them again (one UAC prompt)

Log and previous values: D:\data\sweeps\set-build-priority-<time>\
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Remove,
    [string]$OutDir   # internal: shared with the elevated re-launch
)
$ErrorActionPreference = 'Stop'

$Root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
$Exes = 'go.exe', 'compile.exe', 'link.exe', 'asm.exe', 'cgo.exe', 'vet.exe', 'gopls.exe', 'java.exe'
# CpuPriorityClass 5 = BelowNormal, IoPriority 1 = Low, PagePriority 2 = MEMORY_PRIORITY_LOW
$Target = [ordered]@{ CpuPriorityClass = 5; IoPriority = 1; PagePriority = 2 }
$Want = ($Target.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' '

if ($Apply -and $Remove) { throw 'Pass -Apply or -Remove, not both.' }
$mode = if ($Apply) { 'APPLY' } elseif ($Remove) { 'REMOVE' } else { 'DRY RUN' }
if (-not $OutDir) { $OutDir = 'D:\data\sweeps\set-build-priority-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($mode -eq 'DRY RUN') { '-dryrun' } else { '' }) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
function W([string]$Text) { Write-Host $Text; Add-Content -LiteralPath $log -Value $Text }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($mode -ne 'DRY RUN' -and -not $elevated) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-OutDir', $OutDir, $(if ($Apply) { '-Apply' } else { '-Remove' }))
    try { $p = Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList }
    catch { Write-Host "Elevation did not start: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Write-Host }
    exit $p.ExitCode
}

function Get-State([string]$Exe) {
    $k = "$Root\$Exe\PerfOptions"
    $now = if (Test-Path $k) { Get-ItemProperty $k } else { $null }
    $parts = foreach ($n in $Target.Keys) { '{0}={1}' -f $n, $(if ($now -and $null -ne $now.$n) { $now.$n } else { '-' }) }
    [pscustomobject]@{ Exe = $Exe; Current = $parts -join ' ' }
}

W "set-build-priority  $mode  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Target: $Want"
$before = foreach ($e in $Exes) { Get-State $e }
$before | Export-Csv -LiteralPath (Join-Path $OutDir 'before.csv') -NoTypeInformation
foreach ($s in $before) {
    $set = $s.Current -match '=\d'
    $action = if ($Remove) { if ($set) { 'delete' } else { 'nothing to delete' } } elseif ($s.Current -eq $Want) { 'already set' } else { 'set' }
    W ('  {0,-12} {1,-50} -> {2}' -f $s.Exe, $s.Current, $action)
}
if ($mode -eq 'DRY RUN') { W 'Dry run: nothing changed. -Apply sets the values, -Remove deletes them.'; exit 0 }

$fail = 0
foreach ($e in $Exes) {
    $ek = "$Root\$e"; $pk = "$ek\PerfOptions"
    try {
        if ($Apply) {
            # Never New-Item -Force on a registry key: it wipes existing subkeys.
            if (-not (Test-Path $ek)) { $null = New-Item -Path $Root -Name $e }
            if (-not (Test-Path $pk)) { $null = New-Item -Path $ek -Name 'PerfOptions' }
            foreach ($n in $Target.Keys) { $null = New-ItemProperty -Path $pk -Name $n -Value $Target[$n] -PropertyType DWord -Force }
        }
        else {
            if (Test-Path $pk) { Remove-Item -Path $pk -Recurse -Confirm:$false }
            # Drop the executable's key too when nothing else is left in it.
            if ((Test-Path $ek) -and -not (Get-ChildItem $ek) -and -not (Get-Item $ek).Property) { Remove-Item -Path $ek -Confirm:$false }
        }
    }
    catch { $fail++; W "  [FAIL] $e : $($_.Exception.Message)" }
}

W 'After:'
foreach ($e in $Exes) { $s = Get-State $e; W ('  {0,-12} {1}' -f $s.Exe, $s.Current) }
W 'Applies to processes started from now on; running ones keep their priority.'
W "Log: $log"
exit [int]($fail -gt 0)
