<#
Prepares the laptop for Overcooked! All You Can Eat, Gothic 1 Remake, Risen and TUNIC "as before" (the 4 November 2026
wipe), everything EXCEPT Steam and the games themselves. Asked for on 6 November 2026 ("install everything except steam,
games itself"). Dry run by default; -Apply changes things. Runs as fiodo, no elevation (user profile, HKCU, D: only).

    D:\bin\sweeps\prepare-games-2026-11-06.ps1            dry run
    D:\bin\sweeps\prepare-games-2026-11-06.ps1 -Apply     do it (safe to re-run)

What it does:
  1. Save folders on D: and the junctions the games expect (same layout as the cancelled migrate-profile.ps1):
       %LOCALAPPDATA%\G1R                    -> D:\games\saves\G1R              (Gothic 1 Remake; the snapshot script reads it)
       %LOCALAPPDATA%\Risen                  -> D:\games\saves\Risen
       %USERPROFILE%\AppData\LocalLow\Team17 -> D:\games\saves\Team17           (Overcooked)
       %USERPROFILE%\AppData\LocalLow\Andrew Shouldice -> D:\games\saves\Andrew Shouldice   (TUNIC)
     A real folder already at a link path is merged into the D: target first (robocopy /E, then removed).
  2. Registry (HKCU, reg.exe import): per-exe GPU preferences, Overcooked PlayerPrefs, TUNIC PlayerPrefs from
     D:\drive\BackupPersonal\game-tweaks. The global DirectX line (DirectXUserGlobalSettings) is skipped when the current
     value differs from the 31 October export, so a later change of yours is not undone; the dry run shows both values.
  3. Gothic 1 Remake config pre-placed in D:\games\saves\G1R\Saved\Config\Windows (Engine.ini, GameUserSettings.ini,
     Input.ini + history\GOLDEN-2026-10-04); Engine.ini read-only (your 14 October order; GameUserSettings stays writable).
  4. Risen ConfigUser.xml pre-placed in D:\games\saves\Risen (5120x1440, FOV 100, 32:9 HUD fix).
  5. Downloads into D:\games\installers: MelonLoader.Installer.exe (GitHub LavaGang, latest), G1R-UE4SS.zip v0.4 (GitHub
     serioux1337/G1R-RE-UE4SS, the fork Gothic 1.1 needs), and the .NET 6.0.36 x64 runtime zip from Microsoft, checked
     against Microsoft's published SHA-512 and extracted to D:\games\dotnet6-x64 (hostfxr 6.0.36 x64, the path the
     restored Overcooked Loader.cfg points at).
  6. Staging copies for the moment the games are installed: D:\games\installers\overcooked\{Mods,UserData} (mod v3.13.0
     + Loader.cfg/MelonPreferences.cfg) and D:\games\installers\gothic\mod-edits (your edited mod files + rename script),
     D:\games\installers\risen (logo.ini, splash.bmp, focus fix).
Not done here (needs the game on disk): MelonLoader install, UE4SS unzip + rename, Nexus/World of Risen mod archives
(your logins), TUNIC byte patch (D:\bin\tunic_aspect.py), Risen logo/splash copy, Steam Input.
Log: D:\data\sweeps\prepare-games-2026-11-06-<time>\log.txt
#>
#Requires -Version 7.0
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from a normal (not elevated) PowerShell 7: everything here is user-scope.' }

$tweaks = 'D:\drive\BackupPersonal\game-tweaks'
$src = 'D:\src\ayce-ultrawide'
$games = 'D:\games'
$installers = Join-Path $games 'installers'
$dotnetDir = Join-Path $games 'dotnet6-x64'
$dotnetVer = '6.0.36'
$dotnetZipUrl = "https://builds.dotnet.microsoft.com/dotnet/Runtime/$dotnetVer/dotnet-runtime-$dotnetVer-win-x64.zip"
$dotnetSumUrl = "https://builds.dotnet.microsoft.com/dotnet/checksums/$dotnetVer-sha.txt"
$junctions = @(
    @{ Link = Join-Path $env:LOCALAPPDATA 'G1R';                         Target = Join-Path $games 'saves\G1R' }
    @{ Link = Join-Path $env:LOCALAPPDATA 'Risen';                       Target = Join-Path $games 'saves\Risen' }
    @{ Link = Join-Path $env:USERPROFILE 'AppData\LocalLow\Team17';      Target = Join-Path $games 'saves\Team17' }
    @{ Link = Join-Path $env:USERPROFILE 'AppData\LocalLow\Andrew Shouldice'; Target = Join-Path $games 'saves\Andrew Shouldice' }
)
$regFiles = @(
    @{ File = Join-Path $tweaks 'windows-gpu-preferences.reg'; Key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; GlobalName = 'DirectXUserGlobalSettings' }
    @{ File = Join-Path $tweaks 'overcooked\playerprefs.reg';  Key = 'HKCU:\Software\Team17\Overcooked All You Can Eat' }
    @{ File = Join-Path $tweaks 'tunic\playerprefs.reg';       Key = 'HKCU:\Software\Andrew Shouldice\Secret Legend' }
)
$gothicCfgSrc = Join-Path $tweaks 'gothic-1-remake\Config'
$gothicCfgDst = Join-Path $games 'saves\G1R\Saved\Config\Windows'
$risenCfgSrc = Join-Path $tweaks 'risen\ConfigUser.xml'
$risenCfgDst = Join-Path $games 'saves\Risen\ConfigUser.xml'

$mode = if ($Apply) { 'APPLY' } else { 'DRY RUN' }
$tag = if ($Apply) { '[do]   ' } else { '[would]' }
$OutDir = 'D:\data\sweeps\prepare-games-2026-11-06-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' })
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$log = Join-Path $OutDir 'log.txt'
$failed = 0
function W([string]$m, [string]$c = 'Gray') { Add-Content -LiteralPath $log -Value $m -Encoding utf8; Write-Host $m -ForegroundColor $c }
function Fail([string]$m) { W "  [FAIL]  $m" Red; $script:failed++ }
function Get-PeMachine([string]$path) { $fs = [IO.File]::OpenRead($path); try { $br = New-Object IO.BinaryReader($fs); $fs.Position = 0x3C; $fs.Position = $br.ReadInt32() + 4; return $br.ReadUInt16() } finally { $fs.Close() } }

W "prepare-games-2026-11-06  [$mode]  as $env:USERNAME  ->  $OutDir" Cyan
foreach ($must in $tweaks, $src, "$src\v3.13.0\OvercookedAYCE_Ultrawide_Mod.dll", $gothicCfgSrc, $risenCfgSrc) { if (-not (Test-Path -LiteralPath $must)) { throw "missing source: $must" } }

# ---- 1. folders and junctions
W '-- 1. Save folders and junctions'
foreach ($d in (Join-Path $games 'saves'), $installers, $dotnetDir) { if (-not (Test-Path -LiteralPath $d)) { W "  $tag create $d" Yellow; if ($Apply) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } }
foreach ($j in $junctions) {
    $item = Get-Item -LiteralPath $j.Link -Force -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction' -and (($item.Target -replace '\\$', '') -ieq $j.Target)) { W "  ok      $($j.Link) -> $($j.Target)" DarkGray; continue }
    if ($item -and $item.LinkType) { Fail "$($j.Link) is a $($item.LinkType) to $($item.Target), expected $($j.Target): fix by hand"; continue }
    if ($item) { W "  $tag merge the real folder $($j.Link) into $($j.Target), then replace it with the junction" Yellow }
    else { W "  $tag junction $($j.Link) -> $($j.Target)" Yellow }
    if (-not $Apply) { continue }
    New-Item -ItemType Directory -Path $j.Target -Force | Out-Null
    if ($item) {
        & robocopy.exe $j.Link $j.Target /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Fail "robocopy $($j.Link) -> $($j.Target) rc $LASTEXITCODE"; continue }
        Remove-Item -LiteralPath $j.Link -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $j.Link) -Force | Out-Null
    New-Item -ItemType Junction -Path $j.Link -Target $j.Target | Out-Null
    $chk = Get-Item -LiteralPath $j.Link -Force
    if ($chk.LinkType -eq 'Junction') { W "  [ok]    $($j.Link) -> $($j.Target)" Green } else { Fail "junction $($j.Link) not created" }
}

# ---- 2. registry
W '-- 2. Registry (HKCU)'
foreach ($r in $regFiles) {
    if (-not (Test-Path -LiteralPath $r.File)) { Fail "missing $($r.File)"; continue }
    $lines = Get-Content -LiteralPath $r.File
    $values = @($lines | Where-Object { $_ -match '^"' }).Count
    $toImport = $r.File
    if ($r.GlobalName) {
        $fileLine = $lines | Where-Object { $_ -like "`"$($r.GlobalName)`"=*" } | Select-Object -First 1
        $fileVal = if ($fileLine -match '^"[^"]+"="(.*)"$') { $Matches[1] } else { $null }
        $curVal = (Get-ItemProperty -Path $r.Key -Name $r.GlobalName -ErrorAction SilentlyContinue).($r.GlobalName)
        if ($fileVal -and $curVal -and ($curVal -ne $fileVal)) {
            W "  keep    $($r.GlobalName) as it is now: [$curVal]  (export had [$fileVal])" DarkGray
            $toImport = Join-Path $OutDir (Split-Path $r.File -Leaf)
            $lines | Where-Object { $_ -notlike "`"$($r.GlobalName)`"=*" } | Set-Content -LiteralPath $toImport -Encoding unicode
            $values--
        }
    }
    W "  $tag import $values values into $($r.Key)  (from $(Split-Path $r.File -Leaf))" Yellow
    if ($Apply) {
        & reg.exe import $toImport *> $null
        if ($LASTEXITCODE -eq 0) { W "  [ok]    imported $(Split-Path $r.File -Leaf)" Green } else { Fail "reg import $toImport rc $LASTEXITCODE" }
    }
}

# ---- 3. Gothic config
W '-- 3. Gothic 1 Remake config'
$gothicFiles = @('Engine.ini', 'GameUserSettings.ini', 'Input.ini')
W "  $tag copy $($gothicFiles -join ', ') + history\ -> $gothicCfgDst ; Engine.ini read-only" Yellow
if ($Apply) {
    New-Item -ItemType Directory -Path $gothicCfgDst -Force | Out-Null
    foreach ($f in $gothicFiles) {
        $dst = Join-Path $gothicCfgDst $f
        if (Test-Path -LiteralPath $dst) { Set-ItemProperty -LiteralPath $dst -Name IsReadOnly -Value $false }
        Copy-Item -LiteralPath (Join-Path $gothicCfgSrc $f) -Destination $dst -Force
    }
    & robocopy.exe (Join-Path $gothicCfgSrc 'history') (Join-Path $gothicCfgDst 'history') /E /NFL /NDL /NJH /NJS /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy history rc $LASTEXITCODE" }
    Set-ItemProperty -LiteralPath (Join-Path $gothicCfgDst 'Engine.ini') -Name IsReadOnly -Value $true
    W "  [ok]    $(@(Get-ChildItem $gothicCfgDst -Recurse -File).Count) files in $gothicCfgDst, Engine.ini read-only" Green
}

# ---- 4. Risen config
W '-- 4. Risen config'
W "  $tag copy ConfigUser.xml -> $risenCfgDst" Yellow
if ($Apply) { New-Item -ItemType Directory -Path (Split-Path $risenCfgDst) -Force | Out-Null; Copy-Item -LiteralPath $risenCfgSrc -Destination $risenCfgDst -Force; W "  [ok]    $risenCfgDst" Green }

# ---- 5. downloads
W '-- 5. Downloads'
$mlExe = Join-Path $installers 'MelonLoader.Installer.exe'
$ue4ssZip = Join-Path $installers 'G1R-UE4SS.zip'
$dotnetZip = Join-Path $installers "dotnet-runtime-$dotnetVer-win-x64.zip"
$fxr = Join-Path $dotnetDir "host\fxr\$dotnetVer\hostfxr.dll"
if (Test-Path -LiteralPath $mlExe) { W "  ok      $mlExe" DarkGray } else {
    W "  $tag gh release download LavaGang/MelonLoader.Installer (latest) MelonLoader.Installer.exe -> $installers" Yellow
    if ($Apply) { & gh release download --repo LavaGang/MelonLoader.Installer --pattern 'MelonLoader.Installer.exe' --dir $installers --clobber *> $null; if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $mlExe)) { W "  [ok]    $mlExe ($([math]::Round((Get-Item $mlExe).Length / 1MB, 1)) MB)" Green } else { Fail "MelonLoader installer download rc $LASTEXITCODE" } }
}
if (Test-Path -LiteralPath $ue4ssZip) { W "  ok      $ue4ssZip" DarkGray } else {
    W "  $tag gh release download serioux1337/G1R-RE-UE4SS v0.4 G1R-UE4SS.zip -> $installers" Yellow
    if ($Apply) { & gh release download v0.4 --repo serioux1337/G1R-RE-UE4SS --pattern 'G1R-UE4SS.zip' --dir $installers --clobber *> $null; if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $ue4ssZip)) { W "  [ok]    $ue4ssZip ($([math]::Round((Get-Item $ue4ssZip).Length / 1MB, 1)) MB)" Green } else { Fail "G1R-UE4SS.zip download rc $LASTEXITCODE" } }
}
if ((Test-Path -LiteralPath $fxr) -and ((Get-PeMachine $fxr) -eq 0x8664)) { W "  ok      $fxr (x64)" DarkGray } else {
    W "  $tag download $dotnetZipUrl, verify SHA-512 from $dotnetSumUrl, extract -> $dotnetDir" Yellow
    if (-not $Apply) {
        try { $h = Invoke-WebRequest -Uri $dotnetZipUrl -Method Head -UseBasicParsing; $len = "$($h.Headers['Content-Length'])"; W "          url answers $($h.StatusCode)$(if ($len) { ', ' + [math]::Round([int64]$len / 1MB, 1) + ' MB' })" DarkGray } catch { Fail "runtime url not reachable: $($_.Exception.Message)" }
    } else {
        try {
            Invoke-WebRequest -Uri $dotnetZipUrl -OutFile $dotnetZip -UseBasicParsing
            $sums = (Invoke-WebRequest -Uri $dotnetSumUrl -UseBasicParsing).Content
            $want = ($sums -split "`n" | Where-Object { $_ -match "dotnet-runtime-$dotnetVer-win-x64\.zip" } | Select-Object -First 1) -replace '\s.*$', ''
            $have = (Get-FileHash -LiteralPath $dotnetZip -Algorithm SHA512).Hash
            if (-not $want) { Fail 'published checksum not found; zip kept, not extracted' }
            elseif ($want.ToLower() -ne $have.ToLower()) { Fail "SHA-512 mismatch for $dotnetZip; not extracted" }
            else {
                Expand-Archive -LiteralPath $dotnetZip -DestinationPath $dotnetDir -Force
                if ((Test-Path -LiteralPath $fxr) -and ((Get-PeMachine $fxr) -eq 0x8664)) { W "  [ok]    $fxr (x64, SHA-512 verified)" Green } else { Fail "$fxr missing or not x64 after extraction" }
            }
        } catch { Fail "runtime download: $($_.Exception.Message)" }
    }
}

# ---- 6. staging for after the game installs
W '-- 6. Staging copies'
$stage = @(
    @{ From = "$src\v3.13.0";                              To = "$installers\overcooked\Mods";       Files = 'OvercookedAYCE_Ultrawide_Mod.dll', 'OvercookedAYCE_Ultrawide_Mod.pdb', 'OvercookedAYCE_Ultrawide_Mod.deps.json' }
    @{ From = "$tweaks\overcooked\UserData";               To = "$installers\overcooked\UserData";   Files = 'Loader.cfg', 'MelonPreferences.cfg' }
    @{ From = "$tweaks\gothic-1-remake\mod-edits";         To = "$installers\gothic\mod-edits";      Files = '*' }
    @{ From = "$tweaks\gothic-1-remake";                   To = "$installers\gothic";                Files = 'mods.txt' }
    @{ From = "$tweaks\risen";                             To = "$installers\risen";                 Files = 'logo.ini', 'splash.bmp', 'risen_focus_text_fix.py' }
)
foreach ($s in $stage) {
    W "  $tag $($s.From) [$($s.Files -join ', ')] -> $($s.To)" Yellow
    if ($Apply) { New-Item -ItemType Directory -Path $s.To -Force | Out-Null; foreach ($f in $s.Files) { Copy-Item -Path (Join-Path $s.From $f) -Destination $s.To -Force } }
}
if ($Apply) {
    $dll = "$installers\overcooked\Mods\OvercookedAYCE_Ultrawide_Mod.dll"
    $sha = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLower()
    if ($sha.StartsWith('d12545a2')) { W "  [ok]    staged mod dll sha256 $($sha.Substring(0, 12)) = pinned v3.13.0" Green } else { Fail "staged mod dll hash $sha is not the pinned v3.13.0 (d12545a2...)" }
    $cfg = Get-Content "$installers\overcooked\UserData\Loader.cfg" | Where-Object { $_ -match '^hostfxr_path_override' }
    if ($cfg -like "*$fxr*") { W "  [ok]    Loader.cfg points at $fxr" Green } else { Fail "Loader.cfg override is [$cfg], expected $fxr" }
}

W ''
if (-not $Apply) { W "DRY RUN: nothing changed$(if ($failed) { ", $failed check(s) FAILED above" }). Apply with: D:\bin\sweeps\prepare-games-2026-11-06.ps1 -Apply" Yellow; exit $(if ($failed) { 1 } else { 0 }) }
if ($failed) { W "FAILED or incomplete ($failed): see $log" Red; exit 1 }
W "DONE. Still needed once the games are installed: see the header. Log: $log" Green
