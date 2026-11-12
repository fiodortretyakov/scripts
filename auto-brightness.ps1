<#
Ambient-light-driven brightness for the Samsung Odyssey G95NC over DDC/CI.

MUST run under Windows PowerShell 5.1 (powershell.exe) -- it needs WinRT for the
ambient light sensor. PowerShell 7 has no WinRT projection.

  auto-brightness.ps1              # read light, set brightness, log
  auto-brightness.ps1 -WhatIf      # show what it would do, change nothing
  auto-brightness.ps1 -Calibrate 8 # "in THIS light I want 8/50" -> re-anchors the curve
  auto-brightness.ps1 -Show        # current lux + mapping table

Why write-only: the G95NC reports garbage for VCP 0x10 current value (253 against
max=50) but honours writes. So the last value we set is tracked in a state file
rather than read back from the monitor.

Since 2026-09-29 the target is computed from a smoothed lux (log-domain moving average
across runs, ~8 min time constant, see Get-SmoothedLux) with a deadband of 2, so a passing
cloud no longer steps the monitor 7 -> 15 -> 7 within minutes. -Calibrate still anchors on
the live reading.
#>
[CmdletBinding()]
param(
    [switch]$WhatIf,
    [int]$Calibrate = -1,
    [switch]$Show,
    [int]$Min = 0,
    [int]$Max = 40,
    [int]$Deadband = 2,        # was 1 until 2026-09-29; pairs with the lux smoothing below
    [double]$Gamma = -1,       # -1 = keep whatever is stored; 1.0 = no dimming
    [int]$Contrast = -1,       # -1 = keep whatever is stored; VCP 0x12, 0-50 on the G95NC
    [double]$NightGamma = -1,  # gamma at or below -NightLux; blends up to -Gamma at the anchor lux
    [int]$NightContrast = -1,  # same for contrast
    [double]$NightLux = -1,    # lux at or below which the night values apply in full
    [string]$ExternalOnly = '', # on | off: turn the internal panel off whenever the G95NC is attached
    [string]$Sweep = '',        # on | off: kill leaked agent processes and abandoned Claude sessions every run
    [double]$IdleSessionHours = -1, # a Claude session whose process tree shows no CPU for this long is killed; 0 disables
    [switch]$SweepNow           # run only the sweep (honours -WhatIf) and exit
)
if ($ExternalOnly -and $ExternalOnly -notin 'on', 'off') { throw "-ExternalOnly takes 'on' or 'off'" }
if ($Sweep -and $Sweep -notin 'on', 'off') { throw "-Sweep takes 'on' or 'off'" }

$ErrorActionPreference = 'Stop'

# Fires every five minutes. A run that outlives its task (stopped at the time limit) is not tracked by the
# scheduler's MultipleInstances setting, so without this lock a stalled run would just get relaunched.
if (-not ($Show -or $Calibrate -ge 0 -or $SweepNow)) {
    . (Join-Path $PSScriptRoot 'single-instance.ps1')
    if (-not (Enter-SingleInstance 'auto-brightness')) { return }
}

$stateDir  = Join-Path 'D:\config' 'auto-brightness'
$stateFile = Join-Path $stateDir 'state.json'
$logFile   = Join-Path $stateDir 'auto-brightness.log'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

function Write-Log([string]$m) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Verbose $line
    # keep the log from growing forever
    if ((Get-Item $logFile).Length -gt 200KB) {
        $keep = Get-Content $logFile -Tail 500
        Set-Content -Path $logFile -Value $keep -Encoding utf8
    }
}

# One merge helper for every state write, so a field only one path knows about (the night
# profile, the external-only flag) survives the writes made by the other paths.
function Update-StateFields([hashtable]$fields) {
    $st = New-Object psobject
    if (Test-Path $stateFile) {
        $raw = Get-Content $stateFile -Raw
        if ($raw -and $raw.Trim()) { $st = $raw | ConvertFrom-Json }
    }
    foreach ($k in $fields.Keys) { $st | Add-Member -NotePropertyName $k -NotePropertyValue $fields[$k] -Force }
    $st | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding utf8
    return $st
}

$settings = @{}
if ($NightGamma -ge 0)    { $settings.nightGamma = $NightGamma }
if ($NightContrast -ge 0) { $settings.nightContrast = $NightContrast }
if ($NightLux -ge 0)      { $settings.nightLux = $NightLux }
if ($ExternalOnly)        { $settings.externalOnly = ($ExternalOnly -eq 'on') }
if ($Sweep)               { $settings.sweepAgents = ($Sweep -eq 'on') }
if ($IdleSessionHours -ge 0) { $settings.idleSessionHours = $IdleSessionHours }
if ($settings.Count -gt 0 -and -not $WhatIf) { [void](Update-StateFields $settings) }

$nightGammaStored = -1.0; $nightContrastStored = -1; $nightLuxStored = 10.0; $externalOnlyStored = $false
$sweepAgentsStored = $true; $idleSessionHoursStored = 3.0
if (Test-Path $stateFile) {
    $sN = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($null -ne $sN.nightGamma)    { $nightGammaStored    = [double]$sN.nightGamma }
    if ($null -ne $sN.nightContrast) { $nightContrastStored = [int]$sN.nightContrast }
    if ($null -ne $sN.nightLux)      { $nightLuxStored      = [double]$sN.nightLux }
    if ($null -ne $sN.externalOnly)  { $externalOnlyStored  = [bool]$sN.externalOnly }
    if ($null -ne $sN.sweepAgents)   { $sweepAgentsStored   = [bool]$sN.sweepAgents }
    if ($null -ne $sN.idleSessionHours) { $idleSessionHoursStored = [double]$sN.idleSessionHours }
}
if ($NightGamma -ge 0)    { $nightGammaStored = $NightGamma }
if ($NightContrast -ge 0) { $nightContrastStored = $NightContrast }
if ($NightLux -ge 0)      { $nightLuxStored = $NightLux }
if ($ExternalOnly)        { $externalOnlyStored = ($ExternalOnly -eq 'on') }
if ($Sweep)               { $sweepAgentsStored = ($Sweep -eq 'on') }
if ($IdleSessionHours -ge 0) { $idleSessionHoursStored = $IdleSessionHours }

# ---------- ambient light ----------
function Get-Lux {
    [void][Windows.Devices.Sensors.LightSensor, Windows.Devices.Sensors, ContentType = WindowsRuntime]
    $als = [Windows.Devices.Sensors.LightSensor]::GetDefault()
    if ($null -eq $als) { throw 'no ambient light sensor available' }
    # Average a few samples; the sensor's MinimumReportInterval is 250 ms.
    # Kept deliberately small: this runs every 5 min and the sleeps dominated the run
    # cost (4x300ms = 1.2 s of a 2.2 s run). Three samples still smooths sensor jitter,
    # and the deadband absorbs the rest. One pinned core is what spins the fan here.
    $vals = @()
    foreach ($i in 1..3) {
        $r = $als.GetCurrentReading()
        if ($r) { $vals += [double]$r.IlluminanceInLux }
        if ($i -lt 3) { Start-Sleep -Milliseconds 250 }
    }
    if ($vals.Count -eq 0) { throw 'sensor returned no readings' }
    return [math]::Round(($vals | Measure-Object -Average).Average, 1)
}

# ---------- lux -> brightness ----------
# Log curve through an anchor point, because perceived brightness is logarithmic.
# Default anchor: 256 lux (normal indoor) -> 3/50, matching the level this user runs.
# An anchor below this is meaningless and mathematically fatal: the curve takes
# Log10(anchorLux), so an anchor of 0 lux yields -Infinity, the target becomes Infinity,
# and the cast to int throws -- which silently kills the 2-min task on every run.
# Calibrating in a dark room is the easy way to hit this.
$MIN_ANCHOR_LUX = 20.0

function Get-Anchor {
    if (Test-Path $stateFile) {
        $s = Get-Content $stateFile -Raw | ConvertFrom-Json
        # Must be $null-tested, not truthy-tested: an anchorBrightness of 0 is a valid
        # calibration but is falsy, which silently reverted to the default anchor.
        if ($null -ne $s.anchorLux -and $null -ne $s.anchorBrightness) {
            $ax = [double]$s.anchorLux
            if ($ax -lt $MIN_ANCHOR_LUX) { $ax = $MIN_ANCHOR_LUX }   # repair a bad stored anchor
            return @{ Lux = $ax; B = [double]$s.anchorBrightness }
        }
    }
    return @{ Lux = 256.0; B = 3.0 }
}

function Get-TargetBrightness([double]$lux, $anchor) {
    if ($lux -lt 1) { $lux = 1 }
    # +9 brightness steps per decade of light. Was 5.0 until 2026-09-07: five was too flat at
    # the bright end -- an anchor of 435 lux -> 12/50 left direct sunlight at only 19/50 and a
    # sunlit 2000 lux room at 15/50, which reads as dark. Nine holds the anchor exactly and
    # lifts only the ends: 2000 lux -> 18/50, 10000 lux -> 24/50. Evenings drop a little
    # (100 lux: 9 -> 6), which is the intended trade.
    $stepsPerDecade = 9.0
    $t = $anchor.B + $stepsPerDecade * ([math]::Log10($lux) - [math]::Log10($anchor.Lux))
    $t = [int][math]::Round($t)
    if ($t -lt $Min) { $t = $Min }
    if ($t -gt $Max) { $t = $Max }
    return $t
}

# ---------- external-only guard ----------
# The internal panel is Windows-managed (adaptive brightness, ACM, CABC); no automation
# may touch it. Everything below targets the G95NC only.
$INTERNAL_PANEL_ID = 'DISPLAY\SHP1577'
function Test-ExternalAttached {
    $mons = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    foreach ($m in $mons) {
        if ($m.Active -and $m.InstanceName -notlike "$INTERNAL_PANEL_ID*") { return $true }
    }
    return $false
}

# Compiled C# helpers are cached as DLLs next to the state file, keyed by a hash of their source
# (asked for 2 October 2026): Add-Type -TypeDefinition started csc.exe on every run. A changed source
# gets a new hash, and the stale build of that helper is removed. Any failure falls back to compiling.
function Add-CachedType([string]$name, [string]$source) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source))[0..7] | ForEach-Object { $_.ToString('x2') })
    $dll = Join-Path $stateDir "$name-$hash.dll"
    try {
        if (-not (Test-Path $dll)) {
            Get-ChildItem $stateDir -Filter "$name-*.dll" -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
            Add-Type -TypeDefinition $source -OutputAssembly $dll -OutputType Library -ErrorAction Stop
        }
        Add-Type -Path $dll -ErrorAction Stop
    } catch {
        Remove-Item $dll -ErrorAction SilentlyContinue
        Add-Type -TypeDefinition $source
    }
}

# ---------- DDC ----------
Add-CachedType 'ddc' @'
using System;
using System.Runtime.InteropServices;
public static class AB {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PM { public IntPtr h; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string desc; }
    public delegate bool E(IntPtr h, IntPtr hdc, IntPtr r, IntPtr d);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr r, E cb, IntPtr d);
    [DllImport("dxva2.dll")] public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, ref uint c);
    [DllImport("dxva2.dll")] public static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint c, [Out] PM[] a);
    [DllImport("dxva2.dll")] public static extern bool DestroyPhysicalMonitors(uint c, [In] PM[] a);
    [DllImport("dxva2.dll")] public static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte c, IntPtr t, ref uint cur, ref uint max);
    [DllImport("dxva2.dll")] public static extern bool SetVCPFeature(IntPtr h, byte c, uint v);
    [StructLayout(LayoutKind.Sequential)]
    public struct PATH_INFO {
        public uint srcAdapterLow; public int srcAdapterHigh; public uint srcId; public uint srcModeIdx; public uint srcStatus;
        public uint tgtAdapterLow; public int tgtAdapterHigh; public uint tgtId; public uint tgtModeIdx;
        public uint outputTechnology; public uint rotation; public uint scaling;
        public uint refreshNum; public uint refreshDen; public uint scanLineOrdering;
        public uint targetAvailable; public uint tgtStatus; public uint flags;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct MODE_BLOB { public uint a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p; }
    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint f, out uint np, out uint nm);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint f, ref uint np, [In,Out] PATH_INFO[] p, ref uint nm, [In,Out] MODE_BLOB[] m, IntPtr i);
}
'@

# ---------- external-only topology ----------
# 2026-08-26: the internal panel ignores every brightness request while docked (pinned bright,
# slider dead), so the user wants it OFF whenever the G95NC is attached. Windows falls back to
# the internal panel by itself when the G95NC is unplugged, so only the attach case needs a
# hand. WmiMonitorID.Active stays True for a panel that is out of the topology; the active
# DisplayConfig paths are the only signal that flips.
function Test-InternalActive {
    [uint32]$np = 0; [uint32]$nm = 0
    if ([AB]::GetDisplayConfigBufferSizes(2, [ref]$np, [ref]$nm) -ne 0 -or $np -eq 0) { return $false }
    $paths = New-Object 'AB+PATH_INFO[]' $np
    $modes = New-Object 'AB+MODE_BLOB[]' $nm
    if ([AB]::QueryDisplayConfig(2, [ref]$np, $paths, [ref]$nm, $modes, [IntPtr]::Zero) -ne 0) { return $false }
    foreach ($i in 0..($np - 1)) {
        if ([uint32]$paths[$i].outputTechnology -eq [uint32]2147483648) { return $true }
    }
    return $false
}

# Re-assert contrast (VCP 0x12). It lives in the monitor's own memory, so it normally
# persists -- but an HDR toggle or a factory reset drops it, and then the dim profile is
# silently half-applied. Cheap to re-send, so send it every run.
function Set-DdcContrast([int]$value) {
    if ($value -lt 0) { return $null }
    $handles = New-Object System.Collections.ArrayList
    $cb = [AB+E] { param($h, $hdc, $r, $d) [void]$handles.Add($h); return $true }
    [void][AB]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, $cb, [IntPtr]::Zero)
    $done = $null
    foreach ($hm in $handles) {
        [uint32]$n = 0
        if (-not [AB]::GetNumberOfPhysicalMonitorsFromHMONITOR($hm, [ref]$n) -or $n -eq 0) { continue }
        $arr = New-Object 'AB+PM[]' $n
        if (-not [AB]::GetPhysicalMonitorsFromHMONITOR($hm, $n, $arr)) { continue }
        try {
            foreach ($pm in $arr) {
                if ($pm.desc -match 'Surface') { continue }
                [uint32]$cur = 0; [uint32]$max = 0
                if (-not [AB]::GetVCPFeatureAndVCPFeatureReply($pm.h, [byte]0x12, [IntPtr]::Zero, [ref]$cur, [ref]$max)) { continue }
                if ($max -lt 1 -or $max -gt 255) { continue }
                $v = $value; if ($v -gt $max) { $v = [int]$max }
                if (-not $WhatIf) { [void][AB]::SetVCPFeature($pm.h, [byte]0x12, [uint32]$v) }
                $done = "$($pm.desc) contrast -> $v/$max"
            }
        } finally { [void][AB]::DestroyPhysicalMonitors($n, $arr) }
    }
    return $done
}

function Set-DdcBrightness([int]$value) {
    $handles = New-Object System.Collections.ArrayList
    $cb = [AB+E] { param($h, $hdc, $r, $d) [void]$handles.Add($h); return $true }
    [void][AB]::EnumDisplayMonitors([IntPtr]::Zero, [IntPtr]::Zero, $cb, [IntPtr]::Zero)

    $applied = @()
    foreach ($hm in $handles) {
        [uint32]$n = 0
        if (-not [AB]::GetNumberOfPhysicalMonitorsFromHMONITOR($hm, [ref]$n) -or $n -eq 0) { continue }
        $arr = New-Object 'AB+PM[]' $n
        if (-not [AB]::GetPhysicalMonitorsFromHMONITOR($hm, $n, $arr)) { continue }
        try {
            foreach ($pm in $arr) {
                if ($pm.desc -match 'Surface') { continue }
                [uint32]$cur = 0; [uint32]$max = 0
                # only monitors that answer VCP 0x10 at all; the internal panel does not
                if (-not [AB]::GetVCPFeatureAndVCPFeatureReply($pm.h, [byte]0x10, [IntPtr]::Zero, [ref]$cur, [ref]$max)) { continue }
                if ($max -lt 1 -or $max -gt 255) { continue }
                $v = $value
                if ($v -gt $max) { $v = [int]$max }
                if (-not $WhatIf) { [void][AB]::SetVCPFeature($pm.h, [byte]0x10, [uint32]$v) }
                $applied += ('{0} -> {1}/{2}' -f $pm.desc, $v, $max)
            }
        } finally { [void][AB]::DestroyPhysicalMonitors($n, $arr) }
    }
    return $applied
}

# ---------- charger health ----------
# Earned the hard way 2026-08-12: a failing charger delivering 12.5 W instead of ~39 W
# silently brownout-throttled the firmware and looked exactly like a dead display panel
# (backlight pinned, gamma inert, HDR greyed out, DDC locked). Nothing warned about it.
# Cheap to check on a heartbeat that already runs.
function Test-ChargerHealth {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $pw = [System.Windows.Forms.SystemInformation]::PowerStatus
        $bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop
        if ($pw.PowerLineStatus -ne 'Online') { return $null }          # on battery, nothing to judge
        $pct = [int]($pw.BatteryLifePercent * 100)
        # Only meaningful while actually drawing charge. Smart Charging parks at 80%
        # and legitimately reports 0 W, so do not cry wolf there.
        if (-not $bs.Charging -or $bs.ChargeRate -le 0) { return $null }
        if ($pct -ge 78) { return $null }
        if ($bs.ChargeRate -lt 20000) {
            return "WARNING: charging at only $([math]::Round($bs.ChargeRate/1000,1)) W at $pct% - expected ~39 W. Suspect a failing charger/cable/dock. A brownout here fakes display and brightness faults."
        }
    } catch { }
    return $null
}
$chargerWarning = Test-ChargerHealth
if ($chargerWarning) { Write-Log $chargerWarning; Write-Output $chargerWarning }

# ---------- IDE file-watcher watchdog ----------
# The Antigravity IDE @parcel/watcher NodeService process has repeatedly pinned a full core
# indefinitely, which is THE cause of fan noise on this chassis. Detect it by comparing
# cumulative CPU between runs -- costs no extra time, because this task already fires
# every ~5 min (~2 min until 2 October 2026). A single cumulative snapshot cannot see it; only a rate can.
#
# 2026-09-17: the detector now also FIXES it. Measured on the 17 September instance:
#   - the culprit thread is inside @parcel/watcher 2.5.1's windows backend, re-arming
#     ReadDirectoryChangesW ~200k times a second with ZERO read I/O; it is a native busy
#     loop, not tree scanning, so no files.watcherExclude entry can prevent it (VS Code
#     turns every '**/x/**' glob into a regex parcel applies AFTER the kernel delivered
#     the event -- see @parcel/watcher/wrapper.js normalizeOptions).
#   - it survives forever: 299 CPU-minutes on one process, cleared only by a restart.
#   - the IDE respawns the watcher itself. workbench.desktop.main.js constructs the
#     universal watcher client with { restartOnError: true } and MAX_RESTARTS = 5, so
#     killing the utility process raises ETERM -> onError -> restart(), and every watch
#     request is re-issued. Killing it is therefore self-healing, not destructive.
# Safety rails, in order of importance:
#   1. Only ever kill a process with watcher.node actually loaded. The renderer and the
#      extension host legitimately burn a core during a build or an agent run; the file
#      watcher never does.
#   2. Require a sustained sample over the threshold, so a real burst of watcher work after a
#      big checkout is not mistaken for the spin. Two ~2-min samples (~4 min) until 2 October
#      2026; since the task moved to every 5 min, one sample already spans 5 min.
#   3. At most 3 kills per rolling 24 h. The IDE's own restart budget is 5 PER WINDOW and
#      only a window reload resets it; spending all 5 would leave file watching dead and
#      silent. After the budget is gone the watchdog stops killing and says to reload.
$IdeWatcherCpuPct   = 70
$IdeWatcherStrikes  = 1
$IdeWatcherMaxKills = 3

# Definitive identification: the file watcher is the only IDE process that loads
# @parcel/watcher's native module. Name and command line cannot tell the NodeService
# utility processes apart -- the extension host and the watcher share both.
function Test-IsIdeFileWatcher([int]$procId) {
    try {
        $p = Get-Process -Id $procId -ErrorAction Stop
        foreach ($m in $p.Modules) {
            if ($m.FileName -like '*@parcel*watcher*') { return $true }
        }
    } catch { }
    return $false
}

# Rail 3 counts only the watchdog's own kills, but every watcher death spends the IDE's budget, and
# @parcel/watcher also crashes by itself (0xC0000005). On 1 October 2026 it crashed five times, so the
# watchdog's 14:05 kill was the sixth death in that window: the IDE gave up, and Source Control,
# Explorer and new worktrees stopped refreshing until a reload. Read what each window has spent from
# its own logs. A reload appends to the same window folder, so only lines after the last workbench
# load count. Marker: "Started local extension host", logged on every window load (also on a rare
# extension-host-only restart, which can only under-count; a death is then caught by the toast and reload).
# 2 October 2026: moved from Antigravity to VS Code 1.140 (process 'Code', logs %APPDATA%\Code\logs,
# same MAX_RESTARTS = 5, its own @parcel/watcher build). The history above was measured on Antigravity.
$IdeWatcherMaxRestarts = 5   # MAX_RESTARTS in workbench.desktop.main.js
function Get-IdeWatcherBudget {
    # VSCODE_APPDATA since 8 October 2026 (migrate-prep.ps1)
    $session = Get-ChildItem (Join-Path 'D:\config\vscode\appdata' 'Code\logs') -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'window*\renderer.log') } |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $session) { return $null }
    $worst = $null
    foreach ($w in Get-ChildItem $session.FullName -Directory -Filter 'window*') {
        $loadAt = [datetime]::MinValue
        $load = Select-String -Path (Join-Path $w.FullName 'renderer.log') -Pattern 'Started local extension host' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($load) { $loadAt = [datetime]$load.Line.Substring(0, 23) }
        $restarts = 0; $deadAt = $null
        $fw = Join-Path $w.FullName 'fileWatcher.log'
        if (Test-Path $fw) {
            foreach ($m in Select-String -Path $fw -Pattern '\[File Watcher \(universal\)\] (restarting watcher|gave up)') {
                $t = [datetime]$m.Line.Substring(0, 23)
                if ($t -lt $loadAt) { continue }
                if ($m.Line -match 'gave up') { $deadAt = $t } else { $restarts++ }
            }
        }
        if (-not $worst -or (-not $worst.DeadAt -and ($deadAt -or $restarts -gt $worst.Restarts))) {
            $worst = @{ Window = $w.Name; Restarts = $restarts; DeadAt = $deadAt }
        }
    }
    return $worst
}

function Test-IdeWatcher($prev) {
    $nowT = Get-Date
    $cur = @{}
    foreach ($p in (Get-Process 'Code' -ErrorAction SilentlyContinue)) {
        try { $cur["p$($p.Id)"] = [double]$p.CPU } catch {}
    }

    # carry the kill log forward, dropping anything older than 24 h
    $kills = @()
    if ($prev -and $prev.kills) {
        foreach ($t in $prev.kills) {
            try { if (((Get-Date) - [datetime]$t).TotalHours -lt 24) { $kills += [datetime]$t } } catch {}
        }
    }

    $warn     = $null
    $strikes  = @{}
    $budget   = $null
    if ($cur.Count) { $budget = Get-IdeWatcherBudget }
    if ($prev -and $prev.at) {
        $dt = ($nowT - [datetime]$prev.at).TotalSeconds
        if ($dt -gt 45 -and $dt -lt 900) {
            foreach ($k in $cur.Keys) {
                $old = $prev.procs.$k
                if ($null -eq $old) { continue }
                $pct = [math]::Round((($cur[$k] - [double]$old) / $dt) * 100, 1)
                if ($pct -le $IdeWatcherCpuPct) { continue }

                $procId = [int]$k.Substring(1)
                if (-not (Test-IsIdeFileWatcher $procId)) {
                    # a busy renderer or extension host: report, never touch
                    $warn = "NOTE: VS Code $procId burned $pct% of one core for the last $([int]$dt)s, but it is not the file watcher - left alone."
                    continue
                }

                $n = 1
                if ($prev.strikes -and $prev.strikes.$k) { $n = [int]$prev.strikes.$k + 1 }
                $strikes[$k] = $n

                if ($n -lt $IdeWatcherStrikes) {
                    $warn = "WARNING: VS Code file watcher $procId has burned $pct% of one core for the last $([int]$dt)s (strike $n of $IdeWatcherStrikes) - the @parcel/watcher spin. Killing it on the next sample if it persists."
                    continue
                }
                if ($kills.Count -ge $IdeWatcherMaxKills) {
                    $warn = "WARNING: VS Code file watcher $procId is spinning at $pct% again, but $($kills.Count) kills already happened in the last 24 h. NOT killing it - reload the window (Developer: Reload Window) to reset the IDE's own 5-restart budget."
                    continue
                }
                if ($budget -and $budget.Restarts -ge $IdeWatcherMaxRestarts - 1) {
                    $warn = "WARNING: VS Code file watcher $procId is spinning at $pct%, but $($budget.Window) has already restarted it $($budget.Restarts) of $IdeWatcherMaxRestarts times. NOT killing it - one more death and the IDE stops watching files. Reload the window (Developer: Reload Window)."
                    continue
                }
                try {
                    Stop-Process -Id $procId -Force -ErrorAction Stop
                    $kills += $nowT
                    $strikes.Remove($k)
                    $warn = "FIXED: killed spinning VS Code file watcher $procId ($pct% of one core for $([int]$dt)s). The IDE respawns it and re-issues every watch request. Kill $($kills.Count) of $IdeWatcherMaxKills in 24 h."
                } catch {
                    $warn = "WARNING: could not kill spinning VS Code file watcher ${procId}: $($_.Exception.Message)"
                }
            }
        }
    }
    $deadAt = $null
    if ($budget -and $budget.DeadAt) {
        $deadAt = $budget.DeadAt.ToString('o')
        $warn = "WARNING: VS Code file watching has been DEAD in $($budget.Window) since $($budget.DeadAt.ToString('d MMMM HH:mm')) (the IDE gave up after $IdeWatcherMaxRestarts restarts): Source Control, Explorer and new worktrees do not refresh. Reload the window (Developer: Reload Window)."
    }
    return @{
        procs   = $cur
        at      = $nowT.ToString('o')
        warning = $warn
        strikes = $strikes
        kills   = @($kills | ForEach-Object { $_.ToString('o') })
        deadAt  = $deadAt
    }
}

# Asked for 2 October 2026: the dead-watcher warning only reached the log, so the 1 October death
# went unnoticed for a day. One toast per death, not one per run. Windows PowerShell 5.1
# (this task's host) can load the WinRT toast API directly; the AUMID is Windows PowerShell's own.
function Show-Toast([string]$title, [string]$body) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $esc = [System.Security.SecurityElement]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast duration='long'><visual><binding template='ToastGeneric'><text>$($esc::Escape($title))</text><text>$($esc::Escape($body))</text></binding></visual></toast>")
        $aumid = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($aumid).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
        Write-Log "NOTIFIED: $title"
    } catch { Write-Log "WARNING: toast failed: $($_.Exception.Message)" }
}

$prevIde = $null; $prevIdle = $null
if (Test-Path $stateFile) {
    $sIde = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($sIde.ideCpu) { $prevIde = $sIde.ideCpu }
    if ($sIde.claudeIdle) { $prevIdle = $sIde.claudeIdle }
}
$ideCheck = Test-IdeWatcher $prevIde
if ($ideCheck.warning) { Write-Log $ideCheck.warning; Write-Output $ideCheck.warning }
$deadNotified = $null
if ($prevIde -and $prevIde.deadNotified) { $deadNotified = ([datetime]$prevIde.deadNotified).ToString('o') }
if ($ideCheck.deadAt -and $ideCheck.deadAt -ne $deadNotified) {
    Show-Toast 'IDE file watching is dead' ("VS Code gave up restarting its file watcher at {0}. Source Control, Explorer and new worktrees no longer refresh. Run Developer: Reload Window." -f ([datetime]$ideCheck.deadAt).ToString('HH:mm'))
    $deadNotified = $ideCheck.deadAt
}
$reloadRequested = $null
if ($prevIde -and $prevIde.reloadRequested) { $reloadRequested = ([datetime]$prevIde.reloadRequested).ToString('o') }
$ideCpuState = @{ procs = $ideCheck.procs; at = $ideCheck.at; strikes = $ideCheck.strikes; kills = $ideCheck.kills; deadNotified = $deadNotified; reloadRequested = $reloadRequested }

# ---------- leaked / abandoned agent process sweep ----------
# Asked for 2026-08-26 ("add to automation close orphan claude sessions too"). Two rules:
#  * ORPHAN: an agent process whose parent is gone -- a Claude session, its gopls, or a Bash-tool
#    child (find/grep/tail/head/bash/actionlint). Nothing will ever read its output again -- reaped only past a 15 min age floor, because Claude Code detaches live background work whose parent exits immediately.
#  * IDLE: a claude.exe whose whole process tree has grown < 1 CPU-second for $idleSessionHoursStored
#    hours. The transcript is on disk and resumable; only the live context goes.
# git fsmonitor--daemon is detached by design and never in the list. taskkill /T /F, not
# Stop-Process: the msys binaries ignore Stop-Process and it takes the children too.
$SWEEP_ACTIVE_CORE_PCT = 2.0
$SWEEP_ORPHAN_NAMES = @('claude.exe', 'gopls.exe', 'find.exe', 'grep.exe', 'tail.exe', 'head.exe', 'bash.exe', 'actionlint.exe')
function Get-TreeCpuSeconds([int]$rootId, $byId, $kids) {
    $sum = 0.0
    $stack = New-Object System.Collections.Stack
    $stack.Push($rootId)
    while ($stack.Count -gt 0) {
        $id = [int]$stack.Pop()
        $p = $byId[$id]
        if ($p) { $sum += ($p.KernelModeTime + $p.UserModeTime) / 10000000.0 }
        if ($kids.ContainsKey($id)) { foreach ($k in $kids[$id]) { $stack.Push([int]$k) } }
    }
    return $sum
}
function Invoke-AgentSweep($prevIdle, [double]$idleHours) {
    $lines = New-Object System.Collections.ArrayList
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $byId = @{}; $kids = @{}
    foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
    foreach ($p in $all) {
        $pp = [int]$p.ParentProcessId
        if (-not $kids.ContainsKey($pp)) { $kids[$pp] = New-Object System.Collections.ArrayList }
        [void]$kids[$pp].Add([int]$p.ProcessId)
    }
    function Kill-Tree($p, [string]$why) {
        $mb = [math]::Round($p.WorkingSetSize / 1MB)
        if ($WhatIf) { [void]$lines.Add(("WOULD KILL {0} pid {1} ({2} MB): {3}" -f $p.Name, $p.ProcessId, $mb, $why)); return }
        & (Join-Path $env:WINDIR 'System32\taskkill.exe') /PID $p.ProcessId /T /F 2>&1 | Out-Null
        Start-Sleep -Milliseconds 400
        $alive = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
        $tail = if ($alive) { ' -- STILL ALIVE after taskkill' } else { '' }
        [void]$lines.Add(("KILLED {0} pid {1} ({2} MB): {3}{4}" -f $p.Name, $p.ProcessId, $mb, $why, $tail))
    }
    $me = $PID
    foreach ($p in $all) {
        if ($SWEEP_ORPHAN_NAMES -notcontains $p.Name) { continue }
        if ([int]$p.ProcessId -eq $me) { continue }
        if ($byId.ContainsKey([int]$p.ParentProcessId)) { continue }
        # Age floor, added 2026-09-02: Claude Code detaches Bash-tool background work on
        # purpose -- the parent bash exits at once while the harness keeps reading the
        # child's output FILE, so "parent gone" alone is not "abandoned". The sweep shot
        # three such processes under two minutes old out from under a live session today.
        # A real leak is still reaped, just 15 minutes later; MSYS fork storms survive
        # that long only if they are real.
        if ($p.CreationDate -gt (Get-Date).AddMinutes(-15)) { continue }
        Kill-Tree $p ("orphan, parent {0} is gone, started {1}" -f $p.ParentProcessId, $p.CreationDate.ToString('HH:mm'))
    }
    $nowT = Get-Date
    $state = @{}
    foreach ($p in $all) {
        if ($p.Name -ne 'claude.exe' -or -not $byId.ContainsKey([int]$p.ParentProcessId)) { continue }
        $key = "p$($p.ProcessId)"
        $cpu = Get-TreeCpuSeconds ([int]$p.ProcessId) $byId $kids
        $started = $p.CreationDate.ToString('o')
        $prev = $null
        if ($prevIdle) { $prev = $prevIdle.$key }
        $lastActive = $nowT
        if ($prev -and $prev.started -eq $started) {
            $lastActive = [datetime]$prev.lastActive
            # An idle IDE session still burns 0.4-0.9 % of a core (measured 2 October 2026: 0.38-0.92
            # CPU-s per 100 s), so the old fixed 1 CPU-second per ~2-min sample kept all 18 open
            # sessions "active" forever. Active now means above $SWEEP_ACTIVE_CORE_PCT of one core since
            # the last sample. After a gap (standby, skipped runs) a rate is diluted, so the old
            # 1-second rule still applies there: the change can only make the sweep kill later, never sooner.
            $delta = $cpu - [double]$prev.cpu
            $dt = 300.0
            if ($prev.at) { $dt = ($nowT - [datetime]$prev.at).TotalSeconds }
            if (($dt -gt 900 -and $delta -ge 1.0) -or ($dt -gt 0 -and $delta / $dt * 100 -ge $SWEEP_ACTIVE_CORE_PCT)) { $lastActive = $nowT }
        }
        $idleH = ($nowT - $lastActive).TotalHours
        if ($idleHours -gt 0 -and $idleH -ge $idleHours) {
            Kill-Tree $p ("idle session, no CPU in its process tree for {0:N1} h (limit {1} h), started {2}" -f $idleH, $idleHours, $p.CreationDate.ToString('HH:mm'))
            continue
        }
        $state[$key] = @{ cpu = [math]::Round($cpu, 1); lastActive = $lastActive.ToString('o'); started = $started; at = $nowT.ToString('o') }
    }
    return @{ idle = $state; lines = @($lines) }
}
if (($sweepAgentsStored -or $SweepNow) -and -not $Show -and $Calibrate -lt 0) {
    $sweepResult = Invoke-AgentSweep $prevIdle $idleSessionHoursStored
    foreach ($l in $sweepResult.lines) { Write-Log "sweep: $l"; Write-Output "sweep: $l" }
    if (-not $WhatIf) { [void](Update-StateFields @{ claudeIdle = $sweepResult.idle }) }
    if ($SweepNow) {
        Write-Output ("sweep done: {0} action(s); tracking {1} live Claude session(s); idle limit {2} h" -f $sweepResult.lines.Count, $sweepResult.idle.Count, $idleSessionHoursStored)
        return
    }
}

# ---------- IDE window auto-reload ----------
# Chosen 2 October 2026 over notification-only. Once the IDE has given up on its file watcher, ask the
# local extension in D:\bin\ide-reload-extension to run Developer: Reload Window, the only thing that
# resets the watcher. A reload restarts the extension host and ends every Claude session in the IDE,
# so it waits until no session has been active for 15 min (the sweep's 2 %-of-a-core rule) and the
# keyboard and mouse have been idle for 10 min. One request per death; the toast covers the wait.
# The task runs Interactive in his session, so GetLastInputInfo sees his real input.
function Get-InputIdleMinutes {
    try {
        if (-not ('InputIdle' -as [type])) {
            Add-CachedType 'inputidle' @"
using System; using System.Runtime.InteropServices;
public static class InputIdle {
  [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
  public static double Minutes() { var i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(i); if (!GetLastInputInfo(ref i)) return -1; return unchecked((uint)Environment.TickCount - i.dwTime) / 60000.0; }
}
"@
        }
        return [InputIdle]::Minutes()
    } catch { return -1 }
}
if ($ideCheck.deadAt -and $ideCpuState.reloadRequested -ne $ideCheck.deadAt -and $sweepResult -and -not $WhatIf) {
    $inputIdle = Get-InputIdleMinutes
    $active = @($sweepResult.idle.Values | Where-Object { ((Get-Date) - [datetime]$_.lastActive).TotalMinutes -lt 15 })
    if ($inputIdle -ge 10 -and $active.Count -eq 0) {
        Set-Content -Path (Join-Path 'D:\config' 'auto-brightness\ide-reload-request') -Value (Get-Date).ToString('o')
        $ideCpuState.reloadRequested = $ideCheck.deadAt
        Write-Log ("FIXED: requested an IDE window reload (file watcher dead since {0}; input idle {1:N0} min; no Claude session active for 15 min)." -f ([datetime]$ideCheck.deadAt).ToString('d MMMM HH:mm'), $inputIdle)
    } else {
        Write-Log ("NOTE: IDE auto-reload waits: input idle {0:N1} of 10 min, {1} Claude session(s) active in the last 15 min." -f $inputIdle, $active.Count)
    }
}

if (-not $Show -and -not (Test-ExternalAttached)) {
    $msg = 'no external display attached; internal panel is Windows-managed, nothing to do'
    $lastLine = if (Test-Path $logFile) { Get-Content $logFile -Tail 1 } else { '' }
    if ($lastLine -notlike "*$msg") { Write-Log $msg }
    # Keep the IDE watchdog's CPU baseline moving while undocked, or its rate check goes blind.
    if (-not $WhatIf -and (Test-Path $stateFile)) {
        [void](Update-StateFields @{ ideCpu = $ideCpuState; lastRun = (Get-Date).ToString('o') })
    }
    Write-Output $msg
    return
}

if ($externalOnlyStored -and -not $Show -and -not $WhatIf -and (Test-InternalActive)) {
    Start-Process -FilePath (Join-Path $env:WINDIR 'System32\DisplaySwitch.exe') -ArgumentList '/external' -Wait
    Start-Sleep -Seconds 3
    Write-Log 'G95NC attached and the internal panel was active -> DisplaySwitch /external (internal panel off; auto-brightness.ps1 -ExternalOnly off stops this)'
}

# ---------- lux smoothing ----------
# 2026-09-29: the sensor is honest but the sky is not. Passing clouds moved the live reading
# 90 -> 920 lux within minutes and the G95NC stepped 7 -> 15 -> 7 with it, every two minutes,
# which is exactly the kind of brightness flicker that tires the eyes. An exponential moving
# average across runs with an ~8 min time constant follows a real change within a few runs
# (a 300 -> 900 lux step is fully applied in ~15 min) but a 4-minute cloud never leaves the
# deadband. Averaged in the log domain because brightness perception is logarithmic. After a
# gap of more than 30 min (standby, undocked) the average restarts from the live reading, so
# waking into different light is applied at once.
$LuxSmoothingSeconds           = 480.0
$LuxSmoothingResetAfterSeconds = 1800.0
function Get-SmoothedLux([double]$raw) {
    $prevEma = $null; $prevAt = $null
    if (Test-Path $stateFile) {
        $sL = Get-Content $stateFile -Raw | ConvertFrom-Json
        if ($null -ne $sL.luxEma -and $sL.luxEmaAt) {
            $prevEma = [double]$sL.luxEma
            try { $prevAt = [datetime]$sL.luxEmaAt } catch { $prevAt = $null }
        }
    }
    $ema = $raw
    if ($null -ne $prevEma -and $prevAt) {
        $dt = ((Get-Date) - $prevAt).TotalSeconds
        if ($dt -gt 0 -and $dt -lt $LuxSmoothingResetAfterSeconds) {
            $alpha = 1.0 - [math]::Exp(-$dt / $LuxSmoothingSeconds)
            $lp = [math]::Log10([math]::Max($prevEma, 1.0))
            $lr = [math]::Log10([math]::Max($raw, 1.0))
            $ema = [math]::Pow(10.0, $lp + $alpha * ($lr - $lp))
        }
    }
    $ema = [math]::Round($ema, 1)
    if (-not $WhatIf) { [void](Update-StateFields @{ luxEma = $ema; luxEmaAt = (Get-Date).ToString('o') }) }
    return $ema
}

# ---------- main ----------
$luxRaw = Get-Lux
$lux    = Get-SmoothedLux $luxRaw
$anchor = Get-Anchor

# Read stored gamma/contrast BEFORE the -Calibrate branch. They used to be read after it,
# so calibrating returned early with $storedContrast still -1 and wiped the stored
# contrast out of state.json.
$storedGamma = 1.0
$storedContrast = -1
if (Test-Path $stateFile) {
    $s0 = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($null -ne $s0.gammaLevel)    { $storedGamma = [double]$s0.gammaLevel }
    if ($null -ne $s0.contrastLevel) { $storedContrast = [int]$s0.contrastLevel }
}
if ($Gamma -ge 0)    { $storedGamma = $Gamma }
if ($Contrast -ge 0) { $storedContrast = $Contrast }

if ($Calibrate -ge 0) {
    # Anchor on the live reading, not the smoothed one: "in THIS light I want N/50". The
    # average restarts from it too, so the new anchor is not fought by stale history.
    $lux = $luxRaw
    if (-not $WhatIf) { [void](Update-StateFields @{ luxEma = $luxRaw; luxEmaAt = (Get-Date).ToString('o') }) }
    # Never anchor in the dark -- see $MIN_ANCHOR_LUX. Keep the previous anchor lux
    # instead of writing a fatal one; the brightness level still takes effect.
    if ($lux -lt $MIN_ANCHOR_LUX) {
        $keep = $anchor.Lux
        Write-Log ("REFUSED to anchor at {0} lux (too dark, min {1}); keeping anchor lux {2} and just setting {3}/50" -f $lux, $MIN_ANCHOR_LUX, $keep, $Calibrate)
        Write-Output ("Too dark to calibrate ({0} lux). Kept the existing anchor of {1} lux and set brightness {2}/50." -f $lux, $keep, $Calibrate)
        Write-Output "Re-run -Calibrate in your normal working light to move the anchor."
        $lux = $keep
    }
    [void](Update-StateFields @{ anchorLux = $lux; anchorBrightness = $Calibrate; lastSet = $Calibrate; lastRun = (Get-Date).ToString('o'); gammaLevel = $storedGamma; contrastLevel = $storedContrast; ideCpu = $ideCpuState })
    [void](Set-DdcBrightness $Calibrate)
    Write-Log ("CALIBRATED: {0} lux is now anchored to {1}/50" -f $lux, $Calibrate)
    Write-Output ("Calibrated: at {0} lux, brightness {1}/50 is now the reference point." -f $lux, $Calibrate)
    return
}

$target = Get-TargetBrightness $lux $anchor

# ---------- night blend ----------
# DDC brightness bottoms out at 0/50 and the G95NC is still too bright in a dark room, so
# contrast and gamma slide as well: the stored (day) values at the anchor lux, the night values
# at or below $nightLuxStored, log-linear in between. A stored gamma of 1.0 means "no software
# dimming" (the gaming profile) and switches the blend off entirely.
function Get-NightBlend([double]$l) {
    if ($l -lt 1) { $l = 1 }
    $lo = [math]::Log10([math]::Max($nightLuxStored, 1.0)); $hi = [math]::Log10($anchor.Lux)
    if ($hi -le $lo) { return 0.0 }
    $b = ($hi - [math]::Log10($l)) / ($hi - $lo)
    if ($b -lt 0) { $b = 0.0 }
    if ($b -gt 1) { $b = 1.0 }
    return $b
}
$effGamma = $storedGamma; $effContrast = $storedContrast; $blend = 0.0
if ($storedGamma -lt 1.0) {
    $blend = Get-NightBlend $lux
    if ($nightGammaStored -ge 0 -and $nightGammaStored -lt $storedGamma) {
        $effGamma = [math]::Round($storedGamma - ($storedGamma - $nightGammaStored) * $blend, 2)
    }
    if ($storedContrast -ge 0 -and $nightContrastStored -ge 0 -and $nightContrastStored -lt $storedContrast) {
        $effContrast = [int][math]::Round($storedContrast - ($storedContrast - $nightContrastStored) * $blend)
    }
}

if ($Show) {
    Write-Output ("current light : {0} lux smoothed (live {1} lux; the target follows the smoothed value)" -f $lux, $luxRaw)
    Write-Output ("anchor        : {0} lux -> {1}/50" -f $anchor.Lux, $anchor.B)
    Write-Output ("target now    : {0}/50   (clamped to {1}..{2})" -f $target, $Min, $Max)
    Write-Output ("day profile   : contrast {0}/50, gamma {1}" -f $storedContrast, $storedGamma)
    if ($nightGammaStored -ge 0 -or $nightContrastStored -ge 0) {
        Write-Output ("night profile : contrast {0}/50, gamma {1} at <= {2} lux" -f $nightContrastStored, $nightGammaStored, $nightLuxStored)
        Write-Output ("blend now     : {0:P0} night -> contrast {1}/50, gamma {2}" -f $blend, $effContrast, $effGamma)
    }
    Write-Output ("external-only : {0}" -f $(if ($externalOnlyStored) { 'on (internal panel off while the G95NC is attached)' } else { 'off' }))
    Write-Output ("agent sweep   : {0}, idle Claude sessions killed after {1} h" -f $(if ($sweepAgentsStored) { 'on' } else { 'off' }), $idleSessionHoursStored)
    Write-Output ""
    Write-Output "mapping preview:"
    foreach ($l in 10, 50, 100, 256, 500, 1000, 3000, 10000) {
        Write-Output ("  {0,6} lux -> {1,2}/50" -f $l, (Get-TargetBrightness $l $anchor))
    }
    return
}

$last = $null
if (Test-Path $stateFile) {
    $s = Get-Content $stateFile -Raw | ConvertFrom-Json
    if ($null -ne $s.lastSet) { $last = [int]$s.lastSet }
}

if ($effContrast -ge 0) {
    $c = Set-DdcContrast $effContrast
    if ($c) { Write-Verbose $c }
}

# Re-assert the gamma dim every run. It is lost on reboot and fullscreen games can
# clear it, so re-applying here makes it self-healing. Runs before the deadband
# early-return so gamma is restored even when brightness needs no change.
if ($storedGamma -lt 1.0 -and -not $WhatIf) {
    try {
        $sd = Join-Path (Split-Path $PSCommandPath -Parent) 'screen-dim.ps1'
        if (Test-Path $sd) { & $sd -Monitor 'G95NC' -Level $effGamma | Out-Null }
    } catch {
        # The G95NC is unplugged most of the time, and screen-dim throws "no display matched" for
        # that. Logging it as a failure every 2 min was 720 noise lines a day - exactly the kind of
        # constant red that hid a genuinely broken `gh pr list` in the worktree pruner for days.
        if ($_.Exception.Message -match 'no display matched') {
            Write-Verbose 'gamma re-apply skipped: G95NC not attached'
        } else {
            Write-Log "gamma re-apply failed: $($_.Exception.Message)"
        }
    }
}

if ($null -ne $last -and [math]::Abs($target - $last) -le $Deadband) {
    # Still persist state here: this early-return is the common path, and skipping the
    # write meant a newly-passed -Gamma was never saved.
    # Re-send brightness even inside the deadband. Brightness is WRITE-ONLY on this
    # monitor (reads return garbage 253), so if anything external changed it we cannot
    # detect that -- and skipping the write left it stuck at the foreign value. The
    # deadband is only meant to stop the *target* flapping as lux jitters, not to skip
    # re-asserting the level we own.
    if (-not $WhatIf) {
        [void](Set-DdcBrightness $last)
        [void](Update-StateFields @{ anchorLux = $anchor.Lux; anchorBrightness = $anchor.B; lastSet = $last; lastRun = (Get-Date).ToString('o'); gammaLevel = $storedGamma; contrastLevel = $storedContrast; ideCpu = $ideCpuState })
    }
    Write-Log ("{0} lux (live {6}) -> target {1}/50; last was {2}, within deadband {3}, no change (gamma {4}, contrast {5})" -f $lux, $target, $last, $Deadband, $effGamma, $effContrast, $luxRaw)
    Write-Output ("{0} lux -> {1}/50 (unchanged, within deadband; gamma {2}, contrast {3})" -f $lux, $target, $effGamma, $effContrast)
    return
}

$applied = Set-DdcBrightness $target
if ($applied.Count -eq 0) {
    # 2026-09-29: one run in ~700 got no DDC answer with the G95NC attached; the monitor simply
    # did not reply in time. One retry after 1.5 s costs nothing on this rare path.
    Start-Sleep -Milliseconds 1500
    $applied = Set-DdcBrightness $target
}
$verb = if ($WhatIf) { 'WOULD SET' } else { 'SET' }
if ($applied.Count -eq 0) {
    Write-Log ("{0} lux (live {2}) -> target {1}/50 but NO DDC-capable monitor answered, even after a retry" -f $lux, $target, $luxRaw)
    Write-Output "no DDC-capable monitor found"
    return
}

if (-not $WhatIf) {
    [void](Update-StateFields @{ anchorLux = $anchor.Lux; anchorBrightness = $anchor.B; lastSet = $target; lastRun = (Get-Date).ToString('o'); gammaLevel = $storedGamma; contrastLevel = $storedContrast; ideCpu = $ideCpuState })
}
Write-Log ("{0} lux (live {6}) -> {1} {2}/50  [{3}]  (gamma {4}, contrast {5})" -f $lux, $verb, $target, ($applied -join '; '), $effGamma, $effContrast, $luxRaw)
Write-Output ("{0} lux -> {1} {2}/50 (gamma {3}, contrast {4})" -f $lux, $verb, $target, $effGamma, $effContrast)
foreach ($a in $applied) { Write-Output ("   {0}" -f $a) }




