#Requires -RunAsAdministrator
<#
Confines .NET 6 to a private folder so the machine-wide EOL package can be removed.

    melonloader-portable-net6.ps1                  # stage the runtime + point both games at it
    melonloader-portable-net6.ps1 -Revert          # clear the overrides, go back to machine-wide
    melonloader-portable-net6.ps1 -RemoveMachine   # uninstall Microsoft.DotNet.Runtime.6, after testing

WHY, AND WHY THE OBVIOUS ROUTE IS WRONG

Goal: get "Microsoft.DotNet.Runtime.6 (x64), EOL November 2024" off the installed-packages
list. Two routes were tried and both are dead ends:

  ARM64          impossible. Overcooked is a pure x64 PE (machine 0x8664) running under Prism;
                 MelonLoader injects via version.dll into that process, and every DLL in an
                 x64 process must be x64. Verified at byte level.
  .NET 8         tried, failed. hostfxr loaded 8.0.30 correctly, then:
                   System.AccessViolationException at HarmonyLib.Harmony..ctor
                   at MelonLoader.Core.Initialize()
                 HarmonyLib 2.10.2 and MonoMod patch CLR internals and are not .NET 8 safe.
                 LavaGang's rollForward=LatestMinor pin is load-bearing, not caution.

And simply uninstalling .NET 6 does NOT remove .NET 6. version.dll contains the UTF-16
strings "PortableDotnet", "dotnet6.windows" and "6.0.25": with no local runtime the bootstrap
DOWNLOADS 6.0.25 - an even older EOL build - over the network, into the game folder, managed
by nothing. Strictly worse than what we have.

THE ACTUAL ANSWER

MelonLoader documents an override, in this game's own UserData\Loader.cfg:

    # Manually defines the HostFXR path to use for DotNet Initialization.
    # Equivalent to the '--melonloader.hostfxr' launch option
    hostfxr_path_override = ""

So: copy the 6.0.36 runtime out of C:\Program Files\dotnet\x64 into a private folder, point
every MelonLoader install at that hostfxr.dll, and the machine-wide package becomes
removable. The EOL runtime still exists but is scoped to one directory used by two games
instead of registered system-wide - and because it is a copy of 6.0.36, it is NEWER than the
6.0.25 the fallback would have fetched.

DESTINATION CHOICE

D:\games\dotnet6-x64, not <GAME>\dotnet, for three reasons: one copy serves both
MelonLoader installs instead of two 68 MB copies; it survives a Steam verify-integrity, which
can delete unrecognised files from a game folder; and it needs no elevation to maintain later.

hostfxr resolves the shared framework by walking up from its own location, so the standard
layout is reproduced exactly: <root>\host\fxr\6.0.36\hostfxr.dll and
<root>\shared\Microsoft.NETCore.App\6.0.36\.
#>
[CmdletBinding()]
param(
    [switch]$Revert,
    [switch]$RemoveMachine,
    [string]$Dest = 'D:\games\dotnet6-x64'
)

$ErrorActionPreference = 'Continue'
$log = "$env:LOCALAPPDATA\Temp\claude\melonloader-portable-net6.log"
New-Item -ItemType Directory -Path (Split-Path $log) -Force | Out-Null
Start-Transcript -Path $log -Force | Out-Null

function Head($t) { Write-Host ""; Write-Host "===== $t" -ForegroundColor Cyan }
function OK($t)   { Write-Host "  $t" -ForegroundColor Green }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Red }
function Note($t) { Write-Host "  $t" -ForegroundColor Yellow }
function Die($t)  { Bad "ABORT: $t"; Stop-Transcript | Out-Null; Write-Host ''; Write-Host 'Press Enter.' -ForegroundColor Cyan; [void](Read-Host); exit 1 }

$src     = 'C:\Program Files\dotnet\x64'
$ver     = '6.0.36'
$fxr     = Join-Path $Dest "host\fxr\$ver\hostfxr.dll"
$backups = 'D:\games\backups\melonloader'

# Every MelonLoader install - missing one means it silently breaks later.
function Get-LoaderConfigs {
    $roots = @(
        "${env:ProgramFiles(x86)}\Steam\steamapps\common",
        "$env:ProgramFiles\Steam\steamapps\common",
        "$env:ProgramFiles\Epic Games",
        'C:\XboxGames'
    ) | Where-Object { $_ -and (Test-Path $_) }
    foreach ($r in $roots) {
        foreach ($g in (Get-ChildItem $r -Directory -ErrorAction SilentlyContinue)) {
            if (-not (Test-Path (Join-Path $g.FullName 'MelonLoader'))) { continue }
            $cfg = Join-Path $g.FullName 'UserData\Loader.cfg'
            $cur = ''
            if (Test-Path $cfg) {
                $m = Select-String -Path $cfg -Pattern '^\s*hostfxr_path_override\s*=\s*"(.*)"' -ErrorAction SilentlyContinue |
                     Select-Object -First 1
                if ($m) { $cur = $m.Matches[0].Groups[1].Value }
            }
            [pscustomobject]@{
                Game     = $g.Name
                Cfg      = $cfg
                Exists   = Test-Path $cfg
                Override = $cur
            }
        }
    }
}

function Set-Override([string]$cfgPath, [string]$value) {
    # Regex-replace the single line. Do NOT parse-and-rewrite: Loader.cfg is TOML carrying
    # ~40 explanatory comments that a round-trip through a serialiser would destroy.
    $raw = Get-Content $cfgPath -Raw
    $escaped = $value -replace '\\', '\\'          # TOML basic string needs doubled backslashes
    $new = [regex]::Replace($raw,
        '(?m)^(\s*hostfxr_path_override\s*=\s*)"[^"]*"',
        ('${1}"' + $escaped.Replace('$', '$$') + '"'))
    if ($new -eq $raw) { return $false }
    Set-Content -Path $cfgPath -Value $new -Encoding UTF8 -NoNewline
    return $true
}

Head 'MelonLoader installs found'
$all = @(Get-LoaderConfigs)
if (-not $all) { Die 'no MelonLoader installs found' }
foreach ($c in $all) {
    Write-Host ("  {0,-26} Loader.cfg={1,-5} override={2}" -f $c.Game, $c.Exists, $(if ($c.Override) { $c.Override } else { '<empty>' }))
}

# ============================================================ revert

if ($Revert) {
    Head 'Clearing hostfxr overrides - back to the machine-wide runtime'
    foreach ($c in $all) {
        if (-not $c.Exists) { Note "$($c.Game): no Loader.cfg"; continue }
        if (-not $c.Override) { Note "$($c.Game): already empty"; continue }
        if (Set-Override $c.Cfg '') { OK "$($c.Game): override cleared" } else { Bad "$($c.Game): line not found" }
    }
    Write-Host ""
    Get-LoaderConfigs | ForEach-Object { Write-Host ("    {0,-26} {1}" -f $_.Game, $(if ($_.Override) { $_.Override } else { '<empty>' })) }
    Note ''
    Note "Machine-wide .NET 6 must be installed for this to work:"
    Note '  winget install --id Microsoft.DotNet.Runtime.6 --architecture x64 --scope machine'
    Note "The private copy at $Dest can stay or be deleted."
    Stop-Transcript | Out-Null; Write-Host ''; Write-Host 'Press Enter.' -ForegroundColor Cyan; [void](Read-Host); exit 0
}

# ============================================================ remove machine-wide

if ($RemoveMachine) {
    Head 'Removing the machine-wide .NET 6 x64 package'

    if (-not (Test-Path $fxr)) { Die "private runtime missing at $fxr - run without switches first" }
    OK "private hostfxr present: $fxr"

    $bad = $all | Where-Object { $_.Override -ne $fxr }
    if ($bad) {
        Bad 'these installs are not pointing at the private runtime:'
        $bad | ForEach-Object { Bad ("    {0}: {1}" -f $_.Game, $(if ($_.Override) { $_.Override } else { '<empty>' })) }
        Die 'run without switches first so every install is overridden'
    }
    OK 'every MelonLoader install points at the private runtime'

    # Proof it actually WORKED, not just that the config says so.
    $ocLog = "${env:ProgramFiles(x86)}\Steam\steamapps\common\Overcooked! All You Can Eat\MelonLoader\Latest.log"
    if (-not (Test-Path $ocLog)) { Die 'no MelonLoader log - launch the game first' }
    $cfgTime = (Get-Item ($all | Where-Object Game -match 'Overcooked' | Select-Object -First 1).Cfg).LastWriteTime
    $logTime = (Get-Item $ocLog).LastWriteTime
    Write-Host "  Loader.cfg changed : $cfgTime"
    Write-Host "  Latest.log written : $logTime"
    if ($logTime -lt $cfgTime) { Die 'the log predates the override - launch the game once, then re-run' }

    $head = Get-Content $ocLog -TotalCount 6
    $head | ForEach-Object { Write-Host "    $_" }
    if (($head | Out-String) -notmatch [regex]::Escape($Dest)) {
        Bad 'the log does not show MelonLoader loading hostfxr from the private folder.'
        Die 'not removing the machine-wide runtime until the override is proven to work'
    }
    OK 'confirmed: MelonLoader loaded hostfxr from the private folder'

    Write-Host ""
    $r = Read-Host "  Type YES to uninstall Microsoft.DotNet.Runtime.6 (x64)"
    if ($r -ne 'YES') { Die 'not confirmed' }

    winget uninstall --id Microsoft.DotNet.Runtime.6 --disable-interactivity 2>&1 | ForEach-Object { Write-Host "    $_" }
    Write-Host "  winget exit: $LASTEXITCODE"

    Write-Host ""
    Write-Host "  machine x64 runtimes remaining:"
    if (Test-Path "$src\dotnet.exe") { & "$src\dotnet.exe" --list-runtimes 2>&1 | ForEach-Object { Write-Host "    $_" } }
    else { Write-Host "    (x64 root gone entirely)" }
    winget list --disable-interactivity 2>$null | Select-String 'DotNet' | ForEach-Object { Write-Host "    $($_.Line)" }
    Write-Host ""
    Note 'Launch Overcooked once more to confirm it still works with no machine-wide .NET 6.'
    Note "If it breaks: melonloader-portable-net6.ps1 -Revert, then reinstall the package."
    Stop-Transcript | Out-Null; Write-Host ''; Write-Host 'Press Enter.' -ForegroundColor Cyan; [void](Read-Host); exit 0
}

# ============================================================ 1. stage the runtime

Head "1. Staging .NET $ver x64 into $Dest"

$running = Get-Process -Name 'Overcooked All You Can Eat', 'VampireSurvivors' -ErrorAction SilentlyContinue
if ($running) { Die "close the game first: $($running.ProcessName -join ', ')" }

foreach ($need in "$src\host\fxr\$ver\hostfxr.dll", "$src\shared\Microsoft.NETCore.App\$ver") {
    if (-not (Test-Path $need)) { Die "source missing: $need - is Microsoft.DotNet.Runtime.6 x64 installed?" }
}
OK "source runtime present under $src"

New-Item -ItemType Directory -Path $Dest -Force | Out-Null
foreach ($pair in @(
    @{ From = "$src\host\fxr\$ver";                    To = "$Dest\host\fxr\$ver" }
    @{ From = "$src\shared\Microsoft.NETCore.App\$ver"; To = "$Dest\shared\Microsoft.NETCore.App\$ver" }
)) {
    New-Item -ItemType Directory -Path $pair.To -Force | Out-Null
    & robocopy $pair.From $pair.To /MIR /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    $rc = $LASTEXITCODE; $global:LASTEXITCODE = 0
    if ($rc -ge 8) { Die "robocopy $($pair.From) exited $rc" }
    $n = (Get-ChildItem $pair.To -Recurse -File).Count
    OK ("copied {0,4} files -> {1}" -f $n, $pair.To)
}
Copy-Item "$src\dotnet.exe" $Dest -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $fxr)) { Die "staging failed - $fxr not present" }

# Confirm the copy is genuinely x64, not something odd.
$fs = [IO.File]::OpenRead($fxr); $br = New-Object IO.BinaryReader($fs)
$fs.Position = 0x3C; $peOff = $br.ReadInt32(); $fs.Position = $peOff + 4
$machine = $br.ReadUInt16(); $br.Close(); $fs.Close()
$arch = switch ($machine) { 0xAA64 { 'ARM64' } 0x8664 { 'x64' } 0x14C { 'x86' } default { "0x{0:X}" -f $machine } }
Write-Host "  staged hostfxr.dll PE machine: $arch"
if ($arch -ne 'x64') { Die "staged hostfxr is $arch, must be x64 to load into the emulated game process" }
OK 'staged runtime is x64'

$m = Get-ChildItem $Dest -Recurse -File | Measure-Object Length -Sum
Write-Host ("  total staged: {0} files, {1:N1} MB" -f $m.Count, ($m.Sum / 1MB))

# ============================================================ 2. point every install at it

Head '2. Setting hostfxr_path_override'

New-Item -ItemType Directory -Path $backups -Force | Out-Null
$stamp = Join-Path $backups ('loadercfg-' + (Get-Item $fxr).LastWriteTime.ToString('yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $stamp -Force | Out-Null

foreach ($c in $all) {
    if (-not $c.Exists) { Note "$($c.Game): no Loader.cfg - MelonLoader writes it on first run, re-run this after"; continue }
    Copy-Item $c.Cfg (Join-Path $stamp ("{0}-Loader.cfg" -f ($c.Game -replace '[^\w.-]', '_'))) -Force
    if (Set-Override $c.Cfg $fxr) { OK "$($c.Game): override set" }
    else { Bad "$($c.Game): hostfxr_path_override line not found in Loader.cfg" }
}
Write-Host ""
Write-Host "  state now:"
Get-LoaderConfigs | ForEach-Object { Write-Host ("    {0,-26} {1}" -f $_.Game, $(if ($_.Override) { $_.Override } else { '<empty>' })) }
Note "backups: $stamp"

Head 'NEXT'
Note '1. Launch Overcooked. Confirm the Ultrawide mod still fills 5120x1440.'
Note '2. Check line 1 of the log names the PRIVATE folder, not C:\Program Files\dotnet\x64:'
Write-Host ""
Write-Host "     Get-Content '${env:ProgramFiles(x86)}\Steam\steamapps\common\Overcooked! All You Can Eat\MelonLoader\Latest.log' -TotalCount 6" -ForegroundColor White
Write-Host ""
Note '3. If it works:  melonloader-portable-net6.ps1 -RemoveMachine'
Note '   If it breaks: melonloader-portable-net6.ps1 -Revert'
Write-Host ""
Note 'The machine-wide package is untouched until step 3, so this is fully reversible.'
Write-Host "  Log: $log"

Stop-Transcript | Out-Null
Write-Host ""
Write-Host "Done. Press Enter to close." -ForegroundColor Cyan
[void](Read-Host)
