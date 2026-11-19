<#
Uninstalls the Epic Games Launcher and removes what its uninstaller leaves behind: registry keys, the Epic Online
Services it installs next to itself, its autostart, firewall rules, data folders and shortcuts.
Asked for on 6 November 2026 (not installed yet that day). Dry run by default. Run as fiodo from PowerShell 7, NOT
elevated; -Apply asks for UAC once (machine part runs as ADMIN_fiodo, user part stays fiodo).

    D:\bin\sweeps\uninstall-epic-games-launcher.ps1            dry run: lists everything found, changes nothing, no UAC
    D:\bin\sweeps\uninstall-epic-games-launcher.ps1 -Apply     uninstalls, removes the leftovers, verifies

  1  MSIs (elevated): every Uninstall entry published by Epic Games, Inc. (the launcher's WiX MSI and the Epic Online
     Services MSI): msiexec /x {ProductCode} /qn /norestart. Running launcher processes are closed first.
  2  Services whose binary lives under an Epic Games folder (elevated): stopped and deleted if an MSI left them.
  3  Registry, machine (elevated): HKLM\SOFTWARE\Epic Games, HKLM\SOFTWARE\EpicGames and their WOW6432Node twins,
     HKLM\SOFTWARE\Classes\com.epicgames.* (URL protocols), HKLM\SOFTWARE\Classes\Applications\EpicGamesLauncher.exe,
     HKLM Run values pointing into Epic Games, Uninstall entries the MSIs left behind.
  4  Registry, user (fiodo): HKCU\Software\Epic Games, HKCU\Software\EpicGames, HKCU\Software\Classes\com.epicgames.*,
     HKCU\Software\Classes\Applications\EpicGamesLauncher.exe, HKCU Run value EpicGamesLauncher (its autostart),
     user-scope Uninstall entries by Epic Games.
  5  Firewall rules whose program is under Epic Games (elevated).
  6  Folders and shortcuts: C:\Program Files (x86)\Epic Games\Launcher and \Epic Online Services, C:\ProgramData\Epic,
     %LOCALAPPDATA%\EpicGamesLauncher, %LOCALAPPDATA%\EpicOnlineServices*, %LOCALAPPDATA%\UnrealEngineLauncher,
     Start menu and desktop shortcuts. GAME folders under C:\Program Files (x86)\Epic Games are listed and KEPT;
     the folder itself goes only when empty.
Every registry key is exported to <log folder>\reg\*.reg before removal (recovery: double-click the .reg file).
Log: D:\data\sweeps\uninstall-epic-games-launcher-<time>\log.txt. Re-running is safe: it reports what is left.
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$MachinePhase,   # internal: set by the elevated re-launch
    [string]$OutDir          # internal: log folder shared by both parts
)
$ErrorActionPreference = 'Stop'
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$epicRoot = 'C:\Program Files (x86)\Epic Games'
$launcherProcs = 'EpicGamesLauncher', 'EpicWebHelper', 'EpicOnlineServices', 'EpicOnlineServicesHost', 'EpicOnlineServicesUserHelper', 'EOSOverlayRenderer-Win64-Shipping', 'EOSOverlayRenderer-Win32-Shipping'

# ------------------------------------------------------------------------------------------------ discovery (both parts)
function Found([string]$scope, [string]$kind, [string]$path, [string]$note = '') {
    [pscustomobject]@{ Scope = $scope; Kind = $kind; Path = $path; Note = $note }
}
function FindAll {
    $items = [System.Collections.Generic.List[object]]::new()
    # MSI / ARP entries
    $arp = @(
        @{ hive = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'machine' },
        @{ hive = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'machine' },
        @{ hive = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'user' }
    )
    foreach ($a in $arp) {
        Get-ChildItem -Path $a.hive -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ($p.Publisher -like 'Epic Games*' -or $p.DisplayName -like 'Epic Games Launcher*' -or $p.DisplayName -like 'Epic Online Services*') {
                $isMsi = ($_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') -or ($p.UninstallString -match 'msiexec')
                $code = if ($_.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') { $_.PSChildName } elseif ($p.UninstallString -match '(\{[0-9A-Fa-f-]{36}\})') { $Matches[1] } else { '' }
                $items.Add((Found $a.scope $(if ($isMsi -and $code) { 'msi' } else { 'arpkey' }) $_.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '') "$($p.DisplayName) $($p.DisplayVersion) $code"))
            }
        }
    }
    # services
    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName -like '*\Epic Games\*' -or $_.PathName -like '*EpicOnlineServices*' } | ForEach-Object {
        $items.Add((Found 'machine' 'service' $_.Name "$($_.State), $($_.PathName)"))
    }
    # registry keys
    $keys = @(
        @{ k = 'HKLM:\SOFTWARE\Epic Games'; s = 'machine' }, @{ k = 'HKLM:\SOFTWARE\WOW6432Node\Epic Games'; s = 'machine' },
        @{ k = 'HKLM:\SOFTWARE\EpicGames'; s = 'machine' }, @{ k = 'HKLM:\SOFTWARE\WOW6432Node\EpicGames'; s = 'machine' },
        @{ k = 'HKLM:\SOFTWARE\Classes\Applications\EpicGamesLauncher.exe'; s = 'machine' },
        @{ k = 'HKCU:\Software\Epic Games'; s = 'user' }, @{ k = 'HKCU:\Software\EpicGames'; s = 'user' },
        @{ k = 'HKCU:\Software\Classes\Applications\EpicGamesLauncher.exe'; s = 'user' }
    )
    foreach ($e in $keys) { if (Test-Path -LiteralPath $e.k) { $items.Add((Found $e.s 'regkey' $e.k)) } }
    foreach ($c in @(@{ k = 'HKLM:\SOFTWARE\Classes'; s = 'machine' }, @{ k = 'HKCU:\Software\Classes'; s = 'user' })) {
        Get-ChildItem -Path $c.k -Name -ErrorAction SilentlyContinue | Where-Object { $_ -like 'com.epicgames.*' } | ForEach-Object {
            $items.Add((Found $c.s 'regkey' "$($c.k)\$_" 'URL protocol'))
        }
    }
    # Run values (autostart)
    foreach ($r in @(@{ k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; s = 'machine' }, @{ k = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; s = 'machine' }, @{ k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; s = 'user' })) {
        $p = Get-ItemProperty -LiteralPath $r.k -ErrorAction SilentlyContinue
        if ($p) { $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' -and ("$($_.Value)" -like '*Epic Games*' -or $_.Name -like 'EpicGamesLauncher*') } | ForEach-Object { $items.Add((Found $r.s 'regvalue' "$($r.k)::$($_.Name)" "$($_.Value)")) } }
    }
    # firewall rules
    try {
        Get-NetFirewallApplicationFilter -ErrorAction Stop | Where-Object { $_.Program -like '*\Epic Games\*' } | Get-NetFirewallRule -ErrorAction SilentlyContinue | ForEach-Object {
            $items.Add((Found 'machine' 'fwrule' $_.Name "$($_.DisplayName) [$($_.Direction) $($_.Action) $($_.Profile)]"))
        }
    } catch { }
    # folders and shortcuts
    foreach ($d in @("$epicRoot\Launcher", "$epicRoot\Epic Online Services", 'C:\ProgramData\Epic')) { if (Test-Path -LiteralPath $d) { $items.Add((Found 'machine' 'folder' $d)) } }
    Get-ChildItem -Path $env:LOCALAPPDATA -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(EpicGamesLauncher|EpicOnlineServices.*|UnrealEngineLauncher)$' } | ForEach-Object { $items.Add((Found 'user' 'folder' $_.FullName)) }
    foreach ($f in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Epic Games Launcher.lnk", "$env:Public\Desktop\Epic Games Launcher.lnk")) { if (Test-Path -LiteralPath $f) { $items.Add((Found 'machine' 'file' $f)) } }
    foreach ($f in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Epic Games Launcher.lnk", "$env:USERPROFILE\Desktop\Epic Games Launcher.lnk")) { if (Test-Path -LiteralPath $f) { $items.Add((Found 'user' 'file' $f)) } }
    if (Test-Path -LiteralPath $epicRoot) {
        $games = Get-ChildItem -LiteralPath $epicRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'Launcher', 'Epic Online Services' }
        foreach ($g in $games) { $items.Add((Found 'machine' 'game' $g.FullName 'KEPT: game folder, uninstall games from the launcher first if you want them gone')) }
        $items.Add((Found 'machine' 'rootfolder' $epicRoot 'removed only when empty'))
    }
    return , $items
}

function ExportKey([string]$key, [string]$dir) {
    $native = $key -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
    $file = Join-Path $dir (($native -replace '[\\:*?"<>|]', '_') + '.reg')
    & reg.exe export $native $file /y *> $null
    return $file
}

# ================================================================================ MACHINE PART (elevated, ADMIN_fiodo)
if ($MachinePhase) {
    if (-not $elevated) { throw 'The machine part must run elevated.' }
    $log = Join-Path $OutDir 'log.txt'
    $regDir = Join-Path $OutDir 'reg'
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    function M([string]$m) { Add-Content -LiteralPath $log -Value "  (elevated) $m" -Encoding utf8 }
    $rc = 0
    $items = FindAll | Where-Object Scope -eq 'machine'
    foreach ($s in ($items | Where-Object Kind -eq 'service')) {
        try { Stop-Service -Name $s.Path -Force -ErrorAction SilentlyContinue; M "stopped service $($s.Path)" } catch { M "[warn] stop $($s.Path): $($_.Exception.Message)" }
    }
    foreach ($m in ($items | Where-Object Kind -eq 'msi')) {
        $code = ($m.Note -split ' ')[-1]
        $p = Start-Process msiexec.exe -ArgumentList @('/x', $code, '/qn', '/norestart') -Wait -PassThru
        if ($p.ExitCode -in 0, 1605, 3010) { M "msiexec /x $code -> $($p.ExitCode) ($($m.Note))" } else { M "[FAIL] msiexec /x $code -> $($p.ExitCode) ($($m.Note))"; $rc = 1 }
    }
    # re-discover: the MSIs took their own keys, services and files with them
    $items = FindAll | Where-Object Scope -eq 'machine'
    foreach ($s in ($items | Where-Object Kind -eq 'service')) {
        & sc.exe delete $s.Path *> $null; M "sc delete $($s.Path) -> $LASTEXITCODE"
    }
    foreach ($k in ($items | Where-Object Kind -in 'regkey', 'arpkey')) {
        try { $f = ExportKey $k.Path $regDir; Remove-Item -LiteralPath $k.Path -Recurse -Force; M "removed key $($k.Path) (export $f)" }
        catch { M "[FAIL] key $($k.Path): $($_.Exception.Message)"; $rc = 1 }
    }
    foreach ($v in ($items | Where-Object Kind -eq 'regvalue')) {
        $key, $name = $v.Path -split '::', 2
        try { $f = ExportKey $key $regDir; Remove-ItemProperty -LiteralPath $key -Name $name -Force; M "removed value $($v.Path) (export $f)" }
        catch { M "[FAIL] value $($v.Path): $($_.Exception.Message)"; $rc = 1 }
    }
    foreach ($r in ($items | Where-Object Kind -eq 'fwrule')) {
        try { Remove-NetFirewallRule -Name $r.Path -ErrorAction Stop; M "removed firewall rule $($r.Note)" } catch { M "[FAIL] firewall rule $($r.Path): $($_.Exception.Message)"; $rc = 1 }
    }
    foreach ($d in ($items | Where-Object Kind -in 'folder', 'file')) {
        try { Remove-Item -LiteralPath $d.Path -Recurse -Force; M "removed $($d.Path)" } catch { M "[FAIL] $($d.Path): $($_.Exception.Message)"; $rc = 1 }
    }
    if ((Test-Path -LiteralPath $epicRoot) -and -not (Get-ChildItem -LiteralPath $epicRoot -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $epicRoot -Force; M "removed empty $epicRoot"
    }
    exit $rc
}

# ================================================================================ USER PART (fiodo, not elevated)
if ($elevated) { throw 'Run from a normal (not elevated) PowerShell 7: the user part must run as fiodo, the machine part asks for UAC itself.' }
$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
if (-not $OutDir) { $OutDir = 'D:\data\sweeps\uninstall-epic-games-launcher-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' }) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
$regDir = Join-Path $OutDir 'reg'
New-Item -ItemType Directory -Path $regDir -Force | Out-Null
$script:failed = 0
function W([string]$m, [string]$c = 'Gray') { Add-Content -LiteralPath $log -Value $m -Encoding utf8; Write-Host $m -ForegroundColor $c }

W "uninstall-epic-games-launcher  [$mode]  as $env:USERNAME  ->  $OutDir" Cyan
$items = FindAll
if (-not $items.Count) { W 'Nothing found: no Epic Games Launcher, Epic Online Services, registry keys, rules, folders or shortcuts.' Green; exit 0 }

W "Found $($items.Count) item(s):"
$items | Sort-Object Scope, Kind, Path | ForEach-Object {
    $tag = if ($_.Kind -in 'game', 'rootfolder') { '[keep] ' } elseif ($Apply) { '[remove]' } else { '[would] ' }
    W ("  {0} {1,-7} {2,-9} {3}  {4}" -f $tag, $_.Scope, $_.Kind, $_.Path, $_.Note) $(if ($_.Kind -in 'game', 'rootfolder') { 'DarkGray' } else { 'Yellow' })
}
if (-not $Apply) {
    W ''
    W "DRY RUN: nothing changed. Apply with: D:\bin\sweeps\uninstall-epic-games-launcher.ps1 -Apply" Yellow
    exit 0
}

# close the launcher and its helpers (user processes)
Get-Process -Name $launcherProcs -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill(); W "  closed $($_.Name) (pid $($_.Id))" } catch { } }
Start-Sleep -Seconds 2

$machineWork = @($items | Where-Object { $_.Scope -eq 'machine' -and $_.Kind -notin 'game', 'rootfolder' })
if ($machineWork.Count) {
    W "  asking for elevation (UAC) for $($machineWork.Count) machine item(s) ..." Cyan
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-MachinePhase', '-OutDir', $OutDir)
    try { Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList $argList }
    catch { W "  [FAIL]  machine part did not start: $($_.Exception.Message)" Red; $script:failed++ }
    Get-Content -LiteralPath $log | Where-Object { $_ -like '  (elevated)*' } | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
}

# user items (fiodo's hive and profile)
foreach ($k in ($items | Where-Object { $_.Scope -eq 'user' -and $_.Kind -in 'regkey', 'arpkey' })) {
    try { $f = ExportKey $k.Path $regDir; Remove-Item -LiteralPath $k.Path -Recurse -Force; W "  [ok]    removed key $($k.Path) (export $f)" Green }
    catch { W "  [FAIL]  key $($k.Path): $($_.Exception.Message)" Red; $script:failed++ }
}
foreach ($v in ($items | Where-Object { $_.Scope -eq 'user' -and $_.Kind -eq 'regvalue' })) {
    $key, $name = $v.Path -split '::', 2
    try { $f = ExportKey $key $regDir; Remove-ItemProperty -LiteralPath $key -Name $name -Force; W "  [ok]    removed value $($v.Path) (export $f)" Green }
    catch { W "  [FAIL]  value $($v.Path): $($_.Exception.Message)" Red; $script:failed++ }
}
foreach ($d in ($items | Where-Object { $_.Scope -eq 'user' -and $_.Kind -in 'folder', 'file' })) {
    try { Remove-Item -LiteralPath $d.Path -Recurse -Force; W "  [ok]    removed $($d.Path)" Green }
    catch { W "  [FAIL]  $($d.Path): $($_.Exception.Message)" Red; $script:failed++ }
}

# verification
$left = @(FindAll | Where-Object Kind -notin 'game', 'rootfolder')
W ''
if ($left.Count) { $left | ForEach-Object { W "  [left]  $($_.Scope) $($_.Kind) $($_.Path)  $($_.Note)" Red }; $script:failed++ }
if ($script:failed) { W "FAILED or incomplete: see $log (registry exports in $regDir)" Red; exit 1 }
W "DONE. Everything of the Epic Games Launcher is gone; registry exports for recovery are in $regDir" Green
