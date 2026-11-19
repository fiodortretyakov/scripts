<#
set-claude-effort-default.ps1  -  4 November 2026

Every new Claude Code session starts at xhigh effort: his request of 4 November 2026.

Since 14 October 2026 the machine variable CLAUDE_CODE_EFFORT_LEVEL=max has overridden settings.json in
every session, and /effort is "Not applied" while it is set. Removing it hands the default back to
D:\config\claude\settings.json, which already holds "effortLevel": "xhigh" and modelSettings xhigh for
Opus 5, Opus 5.5 and Fable 5.1. /effort max still raises a single session. settings.json cannot hold
"max": its effortLevel enum stops at xhigh and silently drops anything else.

  set-claude-effort-default.ps1           dry run: the variable per scope and the settings values
  set-claude-effort-default.ps1 -Apply    remove the machine variable (one UAC prompt)
  set-claude-effort-default.ps1 -Revert   machine CLAUDE_CODE_EFFORT_LEVEL=max again (one UAC prompt)

Both also delete a user-scope twin, which would shadow the machine value. Sessions see the change only
after ALL VS Code windows are closed and VS Code is started again.
Log: D:\data\sweeps\set-claude-effort-default-<time>\
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Revert,
    [switch]$Child,   # internal: the elevated re-launch
    [string]$OutDir   # internal: shared with the elevated re-launch
)
$ErrorActionPreference = 'Stop'

if ($Apply -and $Revert) { throw 'Pass -Apply or -Revert, not both.' }
$mode = if ($Apply) { 'APPLY' } elseif ($Revert) { 'REVERT' } else { 'DRY RUN' }
if (-not $OutDir) { $OutDir = 'D:\data\sweeps\set-claude-effort-default-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($mode -eq 'DRY RUN') { '-dryrun' } else { '' }) }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
function W([string]$Text) { Write-Host $Text; Add-Content -LiteralPath $log -Value $Text }

$name     = 'CLAUDE_CODE_EFFORT_LEVEL'
$machKey  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$userKey  = 'HKCU:\Environment'
$settings = 'D:\config\claude\settings.json'
$target   = if ($Revert) { 'max' } else { $null }   # $null = no machine variable
# Delete with [NullString]::Value, never $null: pwsh 7.6.9 on .NET 10 passes $null as '' and SetEnvironmentVariable
# then writes an EMPTY value that shadows the other scope (tested 4 November 2026). It broadcasts WM_SETTINGCHANGE.
$setTo    = if ($Revert) { 'max' } else { [NullString]::Value }
function Show($V) { if ($null -eq $V) { '<absent>' } else { "'$V'" } }
function Get-Scope([string]$Key) { $k = Get-Item -LiteralPath $Key; if ($k.GetValueNames() -contains $name) { [string]$k.GetValue($name) } }

# Elevated child, ADMIN_fiodo under Administrator protection: the machine value only (its HKCU is not his).
if ($Child) {
    try {
        [Environment]::SetEnvironmentVariable($name, $setTo, 'Machine')
        W "  machine        now $(Show (Get-Scope $machKey))  (elevated as $([Environment]::UserName))"
        exit 0
    } catch { W "  [FAIL] machine: $($_.Exception.Message)"; exit 1 }
}

$mach = Get-Scope $machKey
$user = Get-Scope $userKey
$cfg  = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json
$per  = if ($cfg.modelSettings) { @($cfg.modelSettings.PSObject.Properties | ForEach-Object { "$($_.Name) $(Show $_.Value.effortLevel)" }) -join ', ' } else { 'none' }

W "set-claude-effort-default  $mode  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "  $name"
W "    machine      $(Show $mach)  ->  $(Show $target)$(if ($mach -eq $target) { '  (already)' })"
W "    user         $(Show $user)$(if ($null -ne $user) { '  (shadows the machine value; -Apply and -Revert delete it)' })"
W "    this shell   $(Show $env:CLAUDE_CODE_EFFORT_LEVEL)  (read when the shell started; running sessions keep theirs)"
W "  settings.json  effortLevel $(Show $cfg.effortLevel); modelSettings: $per"
if ($mode -eq 'DRY RUN') { W 'Dry run: nothing changed. -Apply removes the machine variable (one UAC prompt); -Revert sets it to max again.'; exit 0 }
if ($Apply -and $cfg.effortLevel -ne 'xhigh') { W "[STOP] settings.json effortLevel is $(Show $cfg.effortLevel), not 'xhigh': without the variable new sessions would start at the model default."; exit 1 }

if ($mach -ne $target) {
    $seen = @(Get-Content -LiteralPath $log).Count
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Child', '-OutDir', $OutDir, $(if ($Apply) { '-Apply' } else { '-Revert' }))
    try { $null = Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList }
    catch { W "  [FAIL] elevation did not start: $($_.Exception.Message)"; exit 1 }
    Get-Content -LiteralPath $log | Select-Object -Skip $seen | Write-Host
}

# As him: delete a stray user-scope twin and broadcast WM_SETTINGCHANGE from his own session as well.
[Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'User')
$now     = Get-Scope $machKey
$userNow = Get-Scope $userKey
$ok      = ($now -eq $target) -and ($null -eq $userNow)
W "  machine        now $(Show $now)  $(if ($now -eq $target) { 'ok' } else { '[FAIL]' })"
W "  user           now $(Show $userNow)  $(if ($null -eq $userNow) { 'ok' } else { '[FAIL]' })"
if ($ok) { W "Close ALL VS Code windows, then start VS Code: new sessions start at $(if ($Apply) { 'xhigh (settings.json)' } else { 'max' })." }
W "Log: $log"
exit $(if ($ok) { 0 } else { 1 })
