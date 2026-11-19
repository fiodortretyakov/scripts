#Requires -Version 7
<#
.SYNOPSIS
Builds one VS Code workspace with a main folder and every git repository under a second folder.

.DESCRIPTION
Dry run by default: it prints the folders and writes nothing.
  -Apply   writes the workspace file (folders are replaced; settings already in the file are kept).
  -Open    opens the workspace in a NEW window. The current window keeps running.
  -Reuse   opens it in the CURRENT window. That reloads the window and ends everything running in it,
           including a Claude session and its background work.

The main folder (-WorkRoot) comes first so that Claude sessions keep it as their working folder. Without
-WorkRoot the first folder of the existing workspace file stays the main folder.
Keep the workspace file outside folders in which other tools rewrite workspace files.

.EXAMPLE
.\code-workspace.ps1 -WorkRoot D:\work
.\code-workspace.ps1 -Apply
.\code-workspace.ps1 -Apply -Open
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Open,
    [switch]$Reuse,
    [string]$WorkRoot,
    [string]$PersonalRoot = 'D:\src',
    [string]$WorkspaceFile = 'D:\config\vscode\code.code-workspace'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Open -and $Reuse) { throw 'Use -Open (new window) or -Reuse (current window), not both.' }
$existing = $null
if (Test-Path -LiteralPath $WorkspaceFile) {
    $existing = Get-Content -LiteralPath $WorkspaceFile -Raw | ConvertFrom-Json -AsHashtable
}
if (-not $WorkRoot) {
    $first = if ($existing -and $existing.Contains('folders')) { @($existing['folders']) | Select-Object -First 1 }
    if (-not $first) { throw "Pass -WorkRoot: $WorkspaceFile has no first folder to keep." }
    $WorkRoot = $first['path']
}
if (-not (Test-Path -LiteralPath $WorkRoot)) { throw "Work folder not found: $WorkRoot" }
if (-not (Test-Path -LiteralPath $PersonalRoot)) { throw "Personal folder not found: $PersonalRoot" }

$folders = [System.Collections.Generic.List[string]]::new()
$folders.Add($WorkRoot)
$skipped = [System.Collections.Generic.List[string]]::new()
foreach ($dir in (Get-ChildItem -LiteralPath $PersonalRoot -Directory | Sort-Object Name)) {
    if (Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) { $folders.Add($dir.FullName) }
    else { $skipped.Add($dir.FullName) }
}

$doc = [ordered]@{}
if ($existing) {
    foreach ($key in $existing.Keys) {
        if ($key -ne 'folders') { $doc[$key] = $existing[$key] }
    }
}
if (-not $doc.Contains('settings')) {
    $doc['settings'] = [ordered]@{
        'git.ignoreLimitWarning' = $true
        'search.exclude'         = [ordered]@{ '**/.godot' = $true }
        'files.watcherExclude'   = [ordered]@{ '**/.godot/**' = $true }
    }
}
$folderEntries = @(foreach ($f in $folders) { [ordered]@{ path = $f } })
$doc.Insert(0, 'folders', $folderEntries)
$json = ($doc | ConvertTo-Json -Depth 20) + "`n"

$state = if ($existing) { 'update' } else { 'new' }
"Workspace file: $WorkspaceFile ($state)"
'Folders:'
foreach ($f in $folders) { "  $f" }
foreach ($s in $skipped) { "  skipped, not a git repository: $s" }

if (-not $Apply) {
    'DRY RUN: nothing written. Run again with -Apply.'
    if ($Open -or $Reuse) { 'Not opened: -Open and -Reuse need -Apply.' }
    return
}

$parent = Split-Path -Parent $WorkspaceFile
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
Set-Content -LiteralPath $WorkspaceFile -Value $json -NoNewline
"WRITTEN: $WorkspaceFile"

if ($Open -or $Reuse) {
    $code = (Get-Command code -ErrorAction Stop).Source
    if ($Reuse) {
        'Opening in the CURRENT window: it reloads and ends what runs in it.'
        & $code -r $WorkspaceFile
    }
    else {
        'Opening in a new window.'
        & $code -n $WorkspaceFile
    }
}
