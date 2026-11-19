<#
remove-extra-local-users.ps1  -  6 November 2026

Leaves one person on the machine: fiodo. Removes every other non-built-in local account together with its
profile (C:\Users\<name> and the ProfileList key) and its scheduled tasks (for example \SoftLanding\<SID>\).

Kept on purpose:
  fiodo                      you (Microsoft account)
  ADMIN_fiodo                Administrator protection: the system-managed account every elevation runs as
  RID 500, 501, 503, 504     Administrator, Guest, DefaultAccount, WDAGUtilityAccount: built-in and disabled;
                             Windows refuses to delete the first three and recreates the fourth

  remove-extra-local-users.ps1           dry run: what would be removed
  remove-extra-local-users.ps1 -Apply    do it (one UAC prompt)

Undo: none needed for system accounts (Windows recreates WsiAccount if Web sign-in is used).
Recovery list and log: D:\data\sweeps\remove-extra-local-users-<time>\
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$OutDir   # internal: shared with the elevated re-launch
)
$ErrorActionPreference = 'Stop'

$Keep = 'fiodo', 'ADMIN_fiodo'

if (-not $OutDir) { $OutDir = 'D:\data\sweeps\remove-extra-local-users-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' }) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
function W([string]$Text) { Write-Host $Text; Add-Content -LiteralPath $log -Value $Text }
trap { W "ERROR: $($_.Exception.Message)"; exit 1 }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Apply -and -not $elevated) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-OutDir', $OutDir, '-Apply')
    try { $p = Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList }
    catch { Write-Host "Elevation did not start: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | Write-Host }
    exit $p.ExitCode
}

W "$(if ($Apply) { 'APPLY' } else { 'DRY RUN' })  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if (-not (Get-LocalUser -Name 'fiodo' -ErrorAction SilentlyContinue)) { throw "Account fiodo not found: the keep list is wrong, nothing removed." }

$users  = Get-LocalUser
$remove = @($users | Where-Object { [int]$_.SID.Value.Split('-')[-1] -ge 1000 -and $_.Name -notin $Keep })
foreach ($u in $users | Where-Object { $_ -notin $remove }) { W "keep    $($u.Name)" }
if (-not $remove) { W 'Nothing to remove.'; exit 0 }

$sched = New-Object -ComObject Schedule.Service
$sched.Connect()
# Task folders named after the SID (for example \SoftLanding\<SID>); empty ones are invisible to Get-ScheduledTask.
function Find-TaskDir($Folder, [string]$Name) {
    foreach ($f in $Folder.GetFolders(0)) { if ($f.Name -eq $Name) { $f.Path } else { Find-TaskDir $f $Name } }
}

$tasks = Get-ScheduledTask
$rows = foreach ($u in $remove) {
    $sid     = $u.SID.Value
    $prof    = Get-CimInstance Win32_UserProfile -Filter "SID='$sid'"
    $uTasks  = @($tasks | Where-Object { $_.TaskPath -like "*\$sid\*" -or $_.Principal.UserId -in $u.Name, $sid })
    $dirs    = @(Find-TaskDir $sched.GetFolder('\') $sid)
    W "remove  $($u.Name)  $sid  enabled=$($u.Enabled)  last logon=$($u.LastLogon)  ($($u.Description))"
    W "          profile: $(if ($prof) { $prof.LocalPath } else { 'none' })"
    foreach ($t in $uTasks) { W "          task:    $($t.TaskPath)$($t.TaskName)" }
    foreach ($d in $dirs) { W "          folder:  $d" }
    if ($prof.Loaded) { throw "Profile of $($u.Name) is loaded (account in use), nothing removed." }
    [pscustomobject]@{ User = $u; Sid = $sid; Profile = $prof; Tasks = $uTasks; Dirs = $dirs }
}
$rows | ForEach-Object { [pscustomobject]@{
    Name = $_.User.Name; SID = $_.Sid; Description = $_.User.Description; LastLogon = $_.User.LastLogon
    Profile = $_.Profile.LocalPath; Tasks = ($_.Tasks | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }) -join '; '; Folders = $_.Dirs -join '; ' } } |
    Export-Csv (Join-Path $OutDir 'removed.csv') -NoTypeInformation

if (-not $Apply) { W "Dry run only. Recovery list: $OutDir\removed.csv. Run again with -Apply."; exit 0 }

foreach ($r in $rows) {
    foreach ($t in $r.Tasks) { Unregister-ScheduledTask -TaskPath $t.TaskPath -TaskName $t.TaskName -Confirm:$false }
    # GetFolder rejects a trailing backslash (0x8007007B), so the parent is '\SoftLanding', and '\' for a top-level folder.
    foreach ($d in $r.Dirs) { $parent = $d.Substring(0, $d.LastIndexOf('\')); $sched.GetFolder($(if ($parent) { $parent } else { '\' })).DeleteFolder($r.Sid, 0) }
    if ($r.Profile) { $r.Profile | Remove-CimInstance }
    Remove-LocalUser -SID $r.Sid
    W "removed $($r.User.Name)"
}

# Self-check: the removed accounts, profiles and tasks are gone, fiodo is still there.
foreach ($r in $rows) {
    if (Get-LocalUser -SID $r.Sid -ErrorAction SilentlyContinue) { throw "$($r.User.Name) still exists." }
    if (Get-CimInstance Win32_UserProfile -Filter "SID='$($r.Sid)'") { throw "Profile of $($r.User.Name) still exists." }
    if (Get-ScheduledTask | Where-Object { $_.TaskPath -like "*\$($r.Sid)\*" }) { throw "Tasks of $($r.User.Name) still exist." }
    if (Find-TaskDir $sched.GetFolder('\') $r.Sid) { throw "Task folder of $($r.User.Name) still exists." }
}
if (-not (Get-LocalUser -Name 'fiodo' -ErrorAction SilentlyContinue)) { throw "fiodo is missing after the run." }
W "Check passed: local accounts now: $((Get-LocalUser).Name -join ', ')"
