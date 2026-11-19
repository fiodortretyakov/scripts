# clean-temp.ps1: deletes temp files that nothing can still use.
#
# Asked for on 12 November 2026 ("anything can be trimmed?"): %TEMP% held 12 GB, 9.4 GB of it scratch folders of
# finished Claude sessions (downloaded programs, throwaway repo clones, command outputs, logs). Storage Sense is on
# but only runs when the disk is low, so nothing clears them. Claude itself is not allowed to sweep other sessions'
# scratch folders, so this is yours to run. Dry run by default; not elevated; rerunnable any time.
#
#   D:\bin\sweeps\clean-temp.ps1           dry run: counts and sizes, changes nothing
#   D:\bin\sweeps\clean-temp.ps1 -Apply    deletes
#
# What it deletes (everything must ALSO be last written before the last boot, so no running program can hold it):
#   1. %TEMP%\claude\<project>\<session> folders with no write for 3 days. Kept: a session whose transcript was written
#      since the boot (still in use), and a session that holds documents (.pdf .docx .xlsx .pptx) outside cloned repos.
#   2. Every other %TEMP% entry with no write for 7 days. Kept: caches that are reused (WinGet, SnapdragonDrivers,
#      vscode-*, helm, .net).
# Files that are locked are skipped and counted. A summary goes to D:\data\sweeps\clean-temp-<time>\log.txt on -Apply.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Root = $env:TEMP,                    # for tests
    [datetime]$Boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime,   # for tests
    [string]$ConfigDir = $(if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { 'D:\config\claude' }),   # for tests
    [switch]$NoLog                                # for tests
)
$ErrorActionPreference = 'Stop'
$Root = $Root.TrimEnd('\')
$now = Get-Date
$cutSession = $now.AddDays(-3)
$cutOther = $now.AddDays(-7)
$keepNames = '^(claude|WinGet|SnapdragonDrivers|helm|\.net)$|^vscode-'
$docExt = '.pdf', '.docx', '.xlsx', '.pptx'
$lines = [System.Collections.Generic.List[string]]::new()
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c; $lines.Add($m) }
function Files([string]$path) { @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue) }
function Newest($files, $item) { if ($files.Count) { ($files | Measure-Object LastWriteTime -Maximum).Maximum } else { $item.LastWriteTime } }

Say "clean-temp  [$(if ($Apply) { 'APPLY' } else { 'DRY RUN' })]  $Root  (last boot $($Boot.ToString('d MMM HH:mm')))" Cyan

# Sessions whose transcript was written since the boot are still in use, whatever their temp folder says
$live = @{}
$projects = Join-Path $ConfigDir 'projects'
if (Test-Path -LiteralPath $projects) {
    Get-ChildItem -LiteralPath $projects -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $Boot } | ForEach-Object { $live[$_.BaseName] = $true }
}

# ---------------------------------------------------------------- 1. Claude session folders
$sessions = [System.Collections.Generic.List[object]]::new()
$keptLive = 0; $keptRecent = 0; $keptDocs = [System.Collections.Generic.List[string]]::new()
$claude = Join-Path $Root 'claude'
if (Test-Path -LiteralPath $claude) {
    foreach ($proj in Get-ChildItem -LiteralPath $claude -Directory -Force) {
        foreach ($s in Get-ChildItem -LiteralPath $proj.FullName -Directory -Force -ErrorAction SilentlyContinue) {
            $files = Files $s.FullName
            $newest = Newest $files $s
            if (-not ($newest -lt $Boot -and $newest -lt $cutSession)) { $keptRecent++; continue }
            if ($live[$s.Name]) { $keptLive++; continue }
            if ($files | Where-Object { $_.Extension -in $docExt -and $_.FullName -notmatch '\\(repos|node_modules|site-packages)\\' } | Select-Object -First 1) {
                $keptDocs.Add($s.FullName.Substring($Root.Length + 1)); continue
            }
            $sessions.Add([pscustomobject]@{ Path = $s.FullName; Bytes = [long](($files | Measure-Object Length -Sum).Sum); Newest = $newest })
        }
    }
}
$sBytes = [long](($sessions | Measure-Object Bytes -Sum).Sum)
Say ("1. Claude session folders to delete: {0} ({1:n2} GB). Kept: {2} written recently, {3} with a live transcript, {4} holding documents" -f $sessions.Count, ($sBytes / 1GB), $keptRecent, $keptLive, $keptDocs.Count)
$sessions | Sort-Object Bytes -Descending | Select-Object -First 5 | ForEach-Object { Say ("     {0,7:n0} MB  last write {1:d MMM}  {2}" -f ($_.Bytes / 1MB), $_.Newest, $_.Path.Substring($Root.Length + 1)) }
$keptDocs | ForEach-Object { Say "   kept (documents): $_" Yellow }

# ---------------------------------------------------------------- 2. other temp entries
$others = [System.Collections.Generic.List[object]]::new()
foreach ($e in Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notmatch $keepNames }) {
    if ($e.PSIsContainer) { $files = Files $e.FullName; $newest = Newest $files $e; $bytes = [long](($files | Measure-Object Length -Sum).Sum) }
    else { $newest = $e.LastWriteTime; $bytes = $e.Length }
    if ($newest -lt $cutOther -and $newest -lt $Boot) { $others.Add([pscustomobject]@{ Path = $e.FullName; Bytes = $bytes }) }
}
$oBytes = [long](($others | Measure-Object Bytes -Sum).Sum)
Say ("2. Other temp entries to delete (no write for 7 days): {0} ({1:n2} GB)" -f $others.Count, ($oBytes / 1GB))

if (-not $Apply) {
    Say ''
    Say ("DRY RUN: {0:n2} GB would be deleted. Nothing changed. Real run: D:\bin\sweeps\clean-temp.ps1 -Apply" -f (($sBytes + $oBytes) / 1GB)) Yellow
    exit 0
}

# ---------------------------------------------------------------- delete
$deleted = 0; $skipped = 0; $freed = [long]0
foreach ($x in @($sessions) + @($others)) {
    Remove-Item -LiteralPath $x.Path -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $x.Path) { $skipped++ } else { $deleted++; $freed += $x.Bytes }
}
if (Test-Path -LiteralPath $claude) {
    Get-ChildItem -LiteralPath $claude -Directory -Force | Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force | Select-Object -First 1) } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
}
Say ''
Say ("DONE: {0} entries deleted, {1:n2} GB freed; {2} skipped (locked or partly in use)" -f $deleted, ($freed / 1GB), $skipped) Green
if (-not $NoLog) {
    $out = "D:\data\sweeps\clean-temp-$($now.ToString('yyyy-MM-dd-HHmm'))"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    Set-Content -LiteralPath "$out\log.txt" -Value $lines -Encoding utf8
}
exit 0
