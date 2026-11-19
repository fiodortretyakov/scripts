<#
Removes ONLY the Add/Remove Programs registry keys (the "Uninstall" keys) of the Epic Games Launcher and Epic Online
Services: the entries that Windows "Installed apps" and `winget list` read. No files, services or other keys are touched.
Use it when the launcher is already gone (folder deleted, MSI uninstall failed) and the entries linger.
Asked for on 6 November 2026. Dry run by default. Run as fiodo from PowerShell 7, NOT elevated; -Apply asks for UAC
once for the HKLM keys (HKCU keys go without it). Every key is exported to <log folder>\reg\*.reg before deletion
(double-click the .reg file to restore it).

    D:\bin\sweeps\remove-epic-uninstall-keys.ps1            dry run: lists the matching keys, changes nothing
    D:\bin\sweeps\remove-epic-uninstall-keys.ps1 -Apply     deletes them

Searched: HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, its WOW6432Node twin (32-bit view, where the Epic
MSIs register) and HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall. A key matches when its DisplayName or
Publisher starts with "Epic Games" or "Epic Online Services"; -Match '<regex>' replaces that pattern.
Log: D:\data\sweeps\remove-epic-uninstall-keys-<time>\log.txt. Re-running is safe: it reports what is left.
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Match = '^(Epic Games|Epic Online Services)',
    [switch]$MachinePhase,   # internal: set by the elevated re-launch
    [string]$OutDir          # internal: log folder shared by both parts
)
$ErrorActionPreference = 'Stop'
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hives = @(
    @{ hive = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'machine' },
    @{ hive = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'machine' },
    @{ hive = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'; scope = 'user' }
)

function FindKeys {
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($h in $hives) {
        Get-ChildItem -Path $h.hive -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ("$($p.DisplayName)" -match $Match -or "$($p.Publisher)" -match $Match) {
                $found.Add([pscustomobject]@{
                        Scope  = $h.scope
                        Path   = $_.PSPath                                                          # provider path, for Remove-Item
                        Native = $_.PSPath.Replace('Microsoft.PowerShell.Core\Registry::', '')      # HKEY_...\..., for reg.exe and display
                        Name   = "$($p.DisplayName) $($p.DisplayVersion)".Trim()
                        Pub    = "$($p.Publisher)"
                    })
            }
        }
    }
    return , $found
}
function ExportKey([string]$native, [string]$dir) {
    $file = Join-Path $dir (($native -replace '[\\:*?"<>|]', '_') + '.reg')
    & reg.exe export $native $file /y *> $null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $file)) { throw "reg export of $native failed, key not removed" }
    return $file
}

# ================================================================================ MACHINE PART (elevated, ADMIN_fiodo)
if ($MachinePhase) {
    if (-not $elevated) { throw 'The machine part must run elevated.' }
    $log = Join-Path $OutDir 'log.txt'
    $regDir = Join-Path $OutDir 'reg'
    New-Item -ItemType Directory -Path $regDir -Force | Out-Null
    $rc = 0
    foreach ($k in (FindKeys | Where-Object Scope -eq 'machine')) {
        try { $f = ExportKey $k.Native $regDir; Remove-Item -LiteralPath $k.Path -Recurse -Force; Add-Content -LiteralPath $log -Value "  (elevated) removed $($k.Native)  [$($k.Name)]  export $f" -Encoding utf8 }
        catch { Add-Content -LiteralPath $log -Value "  (elevated) [FAIL] $($k.Native): $($_.Exception.Message)" -Encoding utf8; $rc = 1 }
    }
    exit $rc
}

# ================================================================================ USER PART (fiodo, not elevated)
if ($elevated) { throw 'Run from a normal (not elevated) PowerShell 7: HKCU must be fiodo''s hive; the HKLM part asks for UAC itself.' }
$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
if (-not $OutDir) { $OutDir = 'D:\data\sweeps\remove-epic-uninstall-keys-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' }) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
$regDir = Join-Path $OutDir 'reg'
New-Item -ItemType Directory -Path $regDir -Force | Out-Null
$failed = 0
function W([string]$m, [string]$c = 'Gray') { Add-Content -LiteralPath $log -Value $m -Encoding utf8; Write-Host $m -ForegroundColor $c }

W "remove-epic-uninstall-keys  [$mode]  as $env:USERNAME  match '$Match'  ->  $OutDir" Cyan
$keys = FindKeys
if (-not $keys.Count) { W 'Nothing found: no Uninstall key matches.' Green; exit 0 }
W "Found $($keys.Count) key(s):"
foreach ($k in $keys) { W ("  {0} {1,-7} {2}  [{3}; {4}]" -f $(if ($Apply) { '[remove]' } else { '[would] ' }), $k.Scope, $k.Native, $k.Name, $k.Pub) Yellow }
if (-not $Apply) { W ''; W 'DRY RUN: nothing changed. Apply with: D:\bin\sweeps\remove-epic-uninstall-keys.ps1 -Apply' Yellow; exit 0 }

if (@($keys | Where-Object Scope -eq 'machine').Count) {
    W '  asking for elevation (UAC) for the HKLM keys ...' Cyan
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-MachinePhase', '-OutDir', $OutDir, '-Match', $Match)
    try { Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList $argList }
    catch { W "  [FAIL]  machine part did not start: $($_.Exception.Message)" Red; $failed++ }
    Get-Content -LiteralPath $log | Where-Object { $_ -like '  (elevated)*' } | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
}
foreach ($k in ($keys | Where-Object Scope -eq 'user')) {
    try { $f = ExportKey $k.Native $regDir; Remove-Item -LiteralPath $k.Path -Recurse -Force; W "  [ok]    removed $($k.Native)  [$($k.Name)]  export $f" Green }
    catch { W "  [FAIL]  $($k.Native): $($_.Exception.Message)" Red; $failed++ }
}

$left = FindKeys
W ''
if ($left.Count) { foreach ($k in $left) { W "  [left]  $($k.Scope) $($k.Native)  [$($k.Name)]" Red }; $failed++ }
if ($failed) { W "FAILED or incomplete: see $log (exports in $regDir)" Red; exit 1 }
W "DONE. The Uninstall keys are gone; .reg exports for recovery are in $regDir" Green
