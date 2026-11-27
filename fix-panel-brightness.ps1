<#
.SYNOPSIS
  Recovers the Surface internal panel backlight when it stays at maximum after a restart, and records why.

.DESCRIPTION
  Manual tool: it creates no scheduled task and changes no display setting.

  Background: the panel's timing controller (TCON) is configured only by the initialisation that the
  Surface panel driver runs after each "display on". When that run fails or is skipped, the backlight
  ignores Windows until the next display on. This script repeats a clean display off/on cycle until
  the brightness responds, and traces both Surface display drivers so that each run records what the
  drivers did.

  Flow: one UAC prompt (the driver trace needs it; cancel it or pass -NoTrace to run without a trace),
  then, in the elevated window: baseline brightness test, display cycles (off, wake, test, question)
  and, on request, a panel driver restart.

  Output in D:\data\panel-brightness\<time>\: run.log (summary and timeline), <phase>.etl (raw trace),
  events-<phase>.txt (decoded trace).

.PARAMETER Target
  Brightness (0-100) to leave the panel at. Default: the current Windows value, or 40 when that is below 20.
.PARAMETER MaxCycles
  Display off/on cycles to try. 0 = baseline trace only.
.PARAMETER OffSeconds
  Display-off time of the first two cycles; each later cycle adds 2 s, up to 12 s.
.PARAMETER NoTrace
  No elevation and no driver trace.
.PARAMETER SelfTest
  No questions: baseline, one cycle, and a create/remove check of the boot logger.
.PARAMETER ArmBootTrace
  Records the next boot with a one-shot ETW boot logger. The next normal run collects it and removes the logger.
.PARAMETER DisarmBootTrace
  Removes the boot logger without collecting.
.PARAMETER AtLogon
  Used by the logon task: waits 20 s for the desktop, traces only until two runs with the fault are recorded,
  and keeps the window open when the brightness is still stuck.
.PARAMETER Decode
  Decodes an existing .etl of these drivers and prints its timeline.

.EXAMPLE
  fix-panel-brightness.ps1
  fix-panel-brightness.ps1 -Target 40 -MaxCycles 5
  fix-panel-brightness.ps1 -ArmBootTrace
  fix-panel-brightness.ps1 -Decode D:\data\panel-brightness\20261127-120000\cycle-1.etl
#>
[CmdletBinding()]
param(
    [ValidateRange(-1, 100)][int]$Target = -1,
    [ValidateRange(0, 50)][int]$MaxCycles = 15,
    [ValidateRange(2, 12)][int]$OffSeconds = 4,
    [switch]$NoTrace,
    [switch]$SelfTest,
    [switch]$ArmBootTrace,
    [switch]$DisarmBootTrace,
    [switch]$AtLogon,
    [string]$Decode,
    [Parameter(DontShow)][string]$RunDir,     # set by the unelevated parent for the elevated child
    [Parameter(DontShow)][string]$UserSid     # the invoking user, for the ACL grant on the run folder
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$DataRoot = 'D:\data\panel-brightness'
$Session = 'PanelBrightnessFix'
$BootSession = 'PanelBrightnessBoot'
$BootKey = "HKLM:\SYSTEM\CurrentControlSet\Control\WMI\Autologger\$BootSession"
$BootFile = Join-Path $env:SystemRoot "System32\LogFiles\WMI\$BootSession.etl"   # D: (ReFS) may mount too late for a boot logger
$Providers = @(
    '{D97BE1A9-8A9E-4869-AC15-7B26EF7C686E}'   # SurfacePanelDriver, WPP
    '{20CEE194-C7E5-4A49-A04D-15A5CFCED4D6}'   # SurfaceDisplayHardwareDriver (TCON), WPP
    '{06BB8F33-7631-449F-A023-8FB431222751}'   # Microsoft.Surface.Display.Prod, TraceLogging
    '{3D53356D-424B-496A-A094-2154D8D2B304}'   # Microsoft-Surface-SurfacePanelDriver, manifest
    '{C55D6B1B-9B7E-47AA-9305-0D73C2C257D2}'   # Microsoft-Surface-SurfaceDisplayHardware, manifest
)

# WPP message table: '<first 8 hex digits of the source file GUID>:<message id>' = label.
# {0} {1} {2} = the first three 32-bit payload values, {3} = the payload text.
# Read from the call sites of the driver versions in $TableFor; other versions may number differently.
$TableFor = @{ 'SurfacePanelDriver.dll' = '3.0.247.0'; 'SurfaceDisplayHardwareDriver.dll' = '2.2.50.0' }
$Messages = [ordered]@{
    '81bf24c1:13'  = 'panel state: {3}'
    '796363c9:35'  = 'panel state: display flag OFF'
    '796363c9:36'  = 'panel state: display flag on'
    '796363c9:37'  = 'panel state: CABC on'
    '796363c9:38'  = 'panel state: CABC off'
    '796363c9:40'  = 'panel state: HDR on'
    '796363c9:41'  = 'panel state: HDR off'
    '796363c9:48'  = 'panel state: GetBacklight FAILED, status 0x{0:X8}'
    '796363c9:49'  = 'panel state: cached backlight {0} millinits'
    '2c5b9761:10'  = 'panel: DISPLAY OFF'
    '2c5b9761:11'  = 'panel: DISPLAY ON'
    '2c5b9761:13'  = 'panel: TCON initialisation queued'
    '2c5b9761:14'  = 'panel: waiting for the running initialisation (monitor off)'
    '2c5b9761:15'  = 'panel: initialisation started'
    '2c5b9761:16'  = 'panel: display is off, initialisation abandoned'
    '2c5b9761:17'  = 'panel: initialisation finished'
    '2c5b9761:18'  = 'panel: FAILED to initialise the display hardware, status 0x{0:X8}'
    '2c5b9761:19'  = 'panel: display hardware driver unreachable'
    '2c5b9761:21'  = 'panel: unable to initialise brightness for the display hardware'
    '2c5b9761:22'  = 'panel: backlight optimisation level = {3}'
    '2c5b9761:26'  = 'panel: FAILED to send the HDR status'
    '2c5b9761:80'  = 'panel: FAILED to send the HDR status'
    '2c5b9761:81'  = 'panel: cached brightness is not valid'
    '2c5b9761:106' = 'panel: device power up (D0 entry)'
    '2c5b9761:112' = 'panel: device power down (D0 exit)'
    'abd0ef80:17'  = 'panel: SKIPPED a TCON command, the driver believes the display is off'
    'abd0ef80:18'  = 'panel: TCON driver interface not available, command dropped'
    'abd0ef80:203' = 'panel: TCON driver interface not available'
    '55461b8d:25'  = 'panel: brightness {0} millinits sent to the GPU driver, status 0x{2:X8}'
    '55461b8d:15'  = 'panel: brightness request ignored (difference {0} <= {1} millinits)'
    '17926504:10'  = 'tcon:  DISPLAY OFF'
    '17926504:11'  = 'tcon:  DISPLAY ON'
    '6ae6f5ec:11'  = 'tcon:  command {0} received'
    '6ae6f5ec:12'  = 'tcon:  display is off, command not processed'
    '6ae6f5ec:55'  = 'tcon:  initialising the TCON hardware'
    '6e67aa05:38'  = 'tcon:  TCON status 0x{0:X}'
    '6e67aa05:40'  = 'tcon:  TCON is still loading'
    '6e67aa05:41'  = 'tcon:  TCON is ready'
    '6e67aa05:42'  = 'tcon:  unknown TCON status'
    '6e67aa05:13'  = 'tcon:  unknown TCON status 0x{0:X}'
    '6e67aa05:29'  = 'tcon:  enabling the colour pipeline'
    '6e67aa05:43'  = 'tcon:  colour pipeline enabled'
    '6e67aa05:20'  = 'tcon:  global dimming disabled'
    '6e67aa05:14'  = 'tcon:  CABC disabled'
    'b82cc08d:20'  = 'tcon:  I2C write FAILED, status 0x{0:X8}'
    '6de7a770:14'  = 'tcon:  {3}'
}
$CommandNames = @{ 23 = 'initialise the TCON'; 28 = 'backlight optimisation level'; 29 = 'HDR status' }
$StateGroups = @{ '796363c9:35' = 'flag'; '796363c9:36' = 'flag'; '796363c9:37' = 'cabc'; '796363c9:38' = 'cabc'; '796363c9:40' = 'hdr'; '796363c9:41' = 'hdr' }

if (-not ('PanelBrightnessFixV2.Etl' -as [type])) {
    Add-Type -IgnoreWarnings -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace PanelBrightnessFixV2 {
    public static class Native {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct REASON_CONTEXT { public uint Version; public uint Flags; [MarshalAs(UnmanagedType.LPWStr)] public string Reason; public IntPtr Pad1; public IntPtr Pad2; }
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr PowerCreateRequest(ref REASON_CONTEXT context);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool PowerSetRequest(IntPtr handle, int type);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool PowerClearRequest(IntPtr handle, int type);
        [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
        [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

        // SystemRequired (1) + ExecutionRequired (3): keeps this process running while the display is off.
        public static IntPtr KeepAwake(string reason) {
            var context = new REASON_CONTEXT { Version = 0, Flags = 1, Reason = reason };
            IntPtr handle = PowerCreateRequest(ref context);
            if (handle == IntPtr.Zero || handle == new IntPtr(-1)) return IntPtr.Zero;
            PowerSetRequest(handle, 1); PowerSetRequest(handle, 3);
            return handle;
        }
        public static void Release(IntPtr handle) {
            if (handle != IntPtr.Zero) { PowerClearRequest(handle, 1); PowerClearRequest(handle, 3); }
        }
        // WM_SYSCOMMAND / SC_MONITORPOWER / 2 to ONE window. HWND_BROADCAST makes every window repeat it,
        // which turns the display off a second time in the middle of the driver's initialisation.
        public static bool DisplayOff() {
            IntPtr window = GetShellWindow();
            if (window == IntPtr.Zero) window = GetForegroundWindow();
            return window != IntPtr.Zero && PostMessage(window, 0x0112, new IntPtr(0xF170), new IntPtr(2));
        }
        public static void Wake(int method) {
            if (method == 0) { mouse_event(1, 1, 0, 0, UIntPtr.Zero); mouse_event(1, -1, 0, 0, UIntPtr.Zero); }
            else if (method == 1) { keybd_event(0x7E, 0, 0, UIntPtr.Zero); keybd_event(0x7E, 0, 2, UIntPtr.Zero); }   // F15
            else { IntPtr window = GetShellWindow(); if (window != IntPtr.Zero) PostMessage(window, 0x0112, new IntPtr(0xF170), new IntPtr(-1)); }
        }
        // Relative waits (Start-Sleep, Thread.Sleep) stop counting while the display is off (Modern Standby).
        public static void SpinFor(int milliseconds) {
            var clock = System.Diagnostics.Stopwatch.StartNew();
            while (clock.ElapsedMilliseconds < milliseconds) System.Threading.Thread.SpinWait(20000);
        }
    }

    public sealed class Row { public DateTime Time; public string Key; public uint A; public uint B; public uint C; public string Text; }
    public sealed class TraceData { public int Total; public List<Row> Rows = new List<Row>(); }

    // Reads an .etl without TMF or manifest: provider GUID, event id and raw payload are enough for WPP.
    public static class Etl {
        [StructLayout(LayoutKind.Sequential)]
        public struct EVENT_DESCRIPTOR { public ushort Id; public byte Version; public byte Channel; public byte Level; public byte Opcode; public ushort Task; public ulong Keyword; }
        [StructLayout(LayoutKind.Sequential)]
        public struct EVENT_HEADER { public ushort Size; public ushort HeaderType; public ushort Flags; public ushort EventProperty; public uint ThreadId; public uint ProcessId; public long TimeStamp; public Guid ProviderId; public EVENT_DESCRIPTOR Descriptor; public ulong ProcessorTime; public Guid ActivityId; }
        [StructLayout(LayoutKind.Sequential)]
        public struct EVENT_RECORD { public EVENT_HEADER Header; public uint BufferContext; public ushort ExtendedDataCount; public ushort UserDataLength; public IntPtr ExtendedData; public IntPtr UserData; public IntPtr UserContext; }
        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        public delegate void EventRecordCallback(ref EVENT_RECORD record);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "OpenTraceW")] static extern ulong OpenTrace(IntPtr logfile);
        [DllImport("advapi32.dll", SetLastError = true)] static extern uint ProcessTrace(ulong[] handles, uint count, IntPtr start, IntPtr end);
        [DllImport("advapi32.dll", SetLastError = true)] static extern uint CloseTrace(ulong handle);

        static bool IsText(byte c) { return (c >= 0x20 && c < 0x7f) || c == 9 || c == 10 || c == 13; }
        static char Clean(byte c) { return (c == 9 || c == 10 || c == 13) ? ' ' : (char)c; }
        static string Printable(byte[] b) {
            var parts = new List<string>();
            var sb = new StringBuilder();
            int i = 0;
            while (i < b.Length) {
                int j = i; sb.Clear();
                while (j + 1 < b.Length && b[j + 1] == 0 && IsText(b[j])) { sb.Append(Clean(b[j])); j += 2; }
                if (sb.Length >= 3) { parts.Add(sb.ToString().Trim()); i = j; continue; }
                j = i; sb.Clear();
                while (j < b.Length && IsText(b[j])) { sb.Append(Clean(b[j])); j++; }
                if (sb.Length >= 3) { parts.Add(sb.ToString().Trim()); i = j; continue; }
                i++;
            }
            return string.Join(" | ", parts);
        }

        // Writes one line per event to outFile and returns the events whose key is in 'keys'.
        public static TraceData Read(string path, string outFile, HashSet<string> keys, Dictionary<string, string> texts) {
            var result = new TraceData();
            Exception failure = null;
            using (var writer = new StreamWriter(outFile, false, new UTF8Encoding(false))) {
                EventRecordCallback callback = (ref EVENT_RECORD r) => {
                    try {
                        result.Total++;
                        byte[] data = new byte[r.UserDataLength];
                        if (data.Length > 0 && r.UserData != IntPtr.Zero) Marshal.Copy(r.UserData, data, 0, data.Length);
                        string text = Printable(data);
                        string meta = "";
                        for (int k = 0; k < r.ExtendedDataCount; k++) {
                            IntPtr item = IntPtr.Add(r.ExtendedData, k * 16);
                            ushort type = (ushort)Marshal.ReadInt16(item, 2);
                            ushort size = (ushort)Marshal.ReadInt16(item, 6);
                            IntPtr pointer = Marshal.ReadIntPtr(item, 8);
                            if (type == 11 && size > 0 && pointer != IntPtr.Zero) {   // TraceLogging schema: event and field names
                                byte[] schema = new byte[size];
                                Marshal.Copy(pointer, schema, 0, size);
                                meta = "[" + Printable(schema) + "] ";
                            }
                        }
                        string hex = (data.Length > 0 && (data.Length <= 16 || text.Length == 0))
                            ? BitConverter.ToString(data, 0, Math.Min(data.Length, 32)).Replace("-", "") + " " : "";
                        string guid8 = r.Header.ProviderId.ToString().Substring(0, 8);
                        string key = guid8 + ":" + r.Header.Descriptor.Id;
                        DateTime time = DateTime.FromFileTimeUtc(r.Header.TimeStamp).ToLocalTime();
                        string format = null;
                        if (texts != null) texts.TryGetValue(key, out format);
                        writer.WriteLine("{0:HH:mm:ss.fffffff} p={1} t={2} g={3} id={4} n={5} {6}{7}{8}{9}", time, r.Header.ProcessId, r.Header.ThreadId,
                            guid8, r.Header.Descriptor.Id, data.Length, meta, hex, text, format != null ? "  ;; " + format : "");
                        if (keys != null && keys.Contains(key)) {
                            var row = new Row { Time = time, Key = key, Text = text };
                            if (data.Length >= 4) row.A = BitConverter.ToUInt32(data, 0);
                            if (data.Length >= 8) row.B = BitConverter.ToUInt32(data, 4);
                            if (data.Length >= 12) row.C = BitConverter.ToUInt32(data, 8);
                            result.Rows.Add(row);
                        }
                    } catch (Exception e) { if (failure == null) failure = e; }
                };
                // EVENT_TRACE_LOGFILEW: LogFileName at 0, ProcessTraceMode at 28 (EVENT_RECORD mode), EventRecordCallback at 424.
                IntPtr logfile = Marshal.AllocHGlobal(448);
                for (int i = 0; i < 448; i++) Marshal.WriteByte(logfile, i, 0);
                IntPtr name = Marshal.StringToHGlobalUni(path);
                try {
                    Marshal.WriteIntPtr(logfile, 0, name);
                    Marshal.WriteInt32(logfile, 28, 0x10000000);
                    Marshal.WriteIntPtr(logfile, 424, Marshal.GetFunctionPointerForDelegate(callback));
                    ulong handle = OpenTrace(logfile);
                    if (handle == ulong.MaxValue) throw new Win32Exception(Marshal.GetLastWin32Error());
                    uint status = ProcessTrace(new[] { handle }, 1, IntPtr.Zero, IntPtr.Zero);
                    CloseTrace(handle);
                    if (status != 0) throw new Win32Exception((int)status);
                } finally {
                    GC.KeepAlive(callback);
                    Marshal.FreeHGlobal(name);
                    Marshal.FreeHGlobal(logfile);
                }
            }
            if (failure != null) throw failure;
            return result;
        }
    }
}
'@
}
$Native = [PanelBrightnessFixV2.Native]

$LogFile = ''
$TraceOff = $true
$TraceOn = $false
$Level = 0
$Result = 3
$WakeNeedsUser = $false

function Write-Log([string]$Text, [switch]$Detail) {
    $line = '{0:HH:mm:ss} {1}{2}' -f (Get-Date), $(if ($Detail) { '  | ' } else { '' }), $Text
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line }
    if (-not $Detail) { Write-Host $Text }
}

# ---------------------------------------------------------------- trace decoding

$KeySet = [System.Collections.Generic.HashSet[string]]::new()
foreach ($key in $Messages.Keys) { [void]$KeySet.Add($key) }

# Optional: full format strings from D:\data\panel-brightness\decode\map-*.txt annotate the events files.
# Row: <guid8><' ' or '~'><id> <format>; '~' = the GUID was inferred, so the row is shown with a '~'.
$FormatTexts = [System.Collections.Generic.Dictionary[string, string]]::new()
$sure = @{}; $inferred = @{}
foreach ($file in @(Get-ChildItem -Path (Join-Path $DataRoot 'decode\map-*.txt') -ErrorAction SilentlyContinue)) {
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
        if ($line -match '^([0-9a-f]{8})([ ~])\s*(\d+) (.+)$') {
            $key = '{0}:{1}' -f $Matches[1], $Matches[3]
            $bag = if ($Matches[2] -eq ' ') { $sure } else { $inferred }
            if ($bag.ContainsKey($key)) { $bag[$key] = $null } else { $bag[$key] = $Matches[4] }   # ambiguous rows are dropped
        }
    }
}
foreach ($key in $sure.Keys) { if ($null -ne $sure[$key]) { $FormatTexts[$key] = $sure[$key] } }
foreach ($key in $inferred.Keys) { if ($null -ne $inferred[$key] -and -not $sure.ContainsKey($key)) { $FormatTexts[$key] = '~' + $inferred[$key] } }

function Get-Timeline($Rows, [int]$Max) {
    $seen = @{}; $written = 0; $hidden = 0
    foreach ($row in $Rows) {
        $text = $Messages[$row.Key] -f $row.A, $row.B, $row.C, $row.Text
        if ($row.Key -eq '6ae6f5ec:11') { $name = $CommandNames[[int]$row.A]; if ($name) { $text += " ($name)" } }
        if ($row.Key -like '796363c9:*' -or $row.Key -like '81bf24c1:*') {      # state dump: repeated on every provider enable
            $group = $StateGroups[$row.Key] ?? $row.Key
            if ($seen[$group] -eq $text) { continue }
            $seen[$group] = $text
        }
        if ($written -ge $Max) { $hidden++; continue }
        '{0:HH:mm:ss.fff} {1}' -f $row.Time, $text
        $written++
    }
    if ($hidden) { "... $hidden more key events: see the events file" }
}

function Get-TraceSummary($Rows) {
    $count = @{}; $command = @{}
    $sent = 0; $rejected = 0; $flag = ''
    foreach ($row in $Rows) {
        $count[$row.Key] = 1 + [int]$count[$row.Key]
        switch ($row.Key) {
            '6ae6f5ec:11' { $id = [int]$row.A; $command[$id] = 1 + [int]$command[$id] }
            '55461b8d:25' { $sent++; if ($row.C -ne 0) { $rejected++ } }
            '796363c9:35' { $flag = 'OFF' }
            '796363c9:36' { $flag = 'on' }
        }
    }
    $on = [int]$count['2c5b9761:11']; $off = [int]$count['2c5b9761:10']
    $init = [int]$command[23]; $optimisation = [int]$command[28]; $hdr = [int]$command[29]
    $ready = [int]$count['6e67aa05:41']; $busy = [int]$count['6e67aa05:40']; $i2c = [int]$count['b82cc08d:20']
    $skipped = [int]$count['abd0ef80:17']
    $missing = [int]$count['abd0ef80:18'] + [int]$count['abd0ef80:203']
    $ignored = [int]$count['55461b8d:15']
    $failures = 0
    foreach ($key in '2c5b9761:18', '2c5b9761:19', '2c5b9761:21', '2c5b9761:26', '2c5b9761:80', '2c5b9761:81', '796363c9:48') { $failures += [int]$count[$key] }
    $initOk = $on -ge 1 -and $ready -ge 1 -and $optimisation -ge 1 -and $hdr -ge 1 -and $skipped -eq 0 -and $missing -eq 0

    $parts = @()
    if ($flag) { $parts += "driver display flag $flag" }
    if ($on -or $off) {
        $parts += "display off x$off, on x$on"
        $parts += "TCON initialisation $(if ($initOk) { 'complete' } else { 'NOT complete' }) (runs $init, ready $ready, busy polls $busy, tunings $optimisation+$hdr)"
    }
    $parts += "brightness sent to the GPU driver x$sent$(if ($rejected) { " ($rejected REJECTED)" })"
    if ($ignored) { $parts += "ignored x$ignored" }

    $problems = @()
    if ($flag -eq 'OFF') { $problems += 'the panel driver believes the display is OFF' }
    if ($skipped) { $problems += "the panel driver skipped $skipped TCON command(s) because it believed the display was off" }
    if ($missing) { $problems += "the TCON driver interface was not available $missing time(s)" }
    if ($on -and -not $init) { $problems += 'display on, but no TCON initialisation ran' }
    if ($init -and -not $ready) { $problems += 'the TCON never reported ready' }
    if ($i2c) { $problems += "$i2c I2C error(s) while talking to the TCON" }
    if ($failures) { $problems += "$failures driver failure message(s): see the timeline" }
    if ($rejected) { $problems += 'the GPU driver rejected a brightness value' }

    [pscustomobject]@{ Line = ($parts -join '; '); Problems = $problems; InitOk = $initOk }
}

# ---------------------------------------------------------------- trace sessions

function Start-PanelTrace([string]$Name) {
    if ($script:TraceOff) { return }
    $etl = Join-Path $RunDir "$Name.etl"
    & logman.exe stop $Session -ets *> $null
    $first = $true
    foreach ($guid in $Providers) {
        if ($first) { $out = & logman.exe start $Session -ets -o $etl -bs 256 -nb 32 128 -p $guid '0xffffffffffffffff' '0xff' 2>&1 }
        else { $out = & logman.exe update trace $Session -ets -p $guid '0xffffffffffffffff' '0xff' 2>&1 }
        if ($LASTEXITCODE -ne 0) {
            Write-Log "trace: provider $guid not enabled (exit $LASTEXITCODE): $((($out | Out-String).Trim() -split "`r?`n")[-1])" -Detail
            if ($first) { $script:TraceOff = $true; Write-Log 'The driver trace could not start; continuing without it.'; return }
        }
        $first = $false
    }
    $script:TraceOn = $true
}

function Stop-PanelTrace {
    if (-not $script:TraceOn) { return }
    & logman.exe stop $Session -ets *> $null
    $script:TraceOn = $false
}

# Stops the trace, decodes <Name>.etl, writes the timeline to the log and prints the summary.
function Complete-Phase([string]$Name, [string]$Note, [int]$MaxTimeline = 150) {
    Stop-PanelTrace
    Write-Log "${Name}: $Note"
    $etl = Join-Path $RunDir "$Name.etl"
    if (-not (Test-Path -LiteralPath $etl)) { return $null }
    try { $data = [PanelBrightnessFixV2.Etl]::Read($etl, (Join-Path $RunDir "events-$Name.txt"), $KeySet, $FormatTexts) }
    catch { Write-Log "  trace not decoded: $($_.Exception.Message)"; return $null }
    foreach ($line in @(Get-Timeline $data.Rows $MaxTimeline)) { Write-Log $line -Detail }
    $summary = Get-TraceSummary $data.Rows
    Write-Log "  trace ($($data.Total) events): $($summary.Line)"
    foreach ($problem in $summary.Problems) { Write-Log "  ! $problem" }
    return $summary
}

# ---------------------------------------------------------------- boot logger (one-shot)

function Enable-BootTrace {
    & logman.exe delete "autosession\$BootSession" *> $null
    $first = $true
    foreach ($guid in $Providers) {
        if ($first) { $out = & logman.exe create trace "autosession\$BootSession" -o $BootFile -bs 256 -nb 32 128 -max 200 -p $guid '0xffffffffffffffff' '0xff' 2>&1 }
        else { $out = & logman.exe update trace "autosession\$BootSession" -p $guid '0xffffffffffffffff' '0xff' 2>&1 }
        if ($LASTEXITCODE -ne 0) { throw "logman failed for $guid (exit $LASTEXITCODE): $(($out | Out-String).Trim())" }
        $first = $false
    }
}

function Disable-BootTrace {
    & logman.exe stop $BootSession -ets *> $null
    & logman.exe delete "autosession\$BootSession" *> $null
    if (Test-Path -LiteralPath $BootKey) { Remove-Item -LiteralPath $BootKey -Recurse -Force }
    Get-ChildItem -Path ($BootFile -replace '\.etl$', '*.etl') -ErrorAction SilentlyContinue | Remove-Item -Force
}

# After a restart with the boot logger armed: collects the boot trace and removes the logger.
function Save-BootTrace {
    if (-not (Test-Path -LiteralPath $BootKey)) { return }
    & logman.exe query $BootSession -ets *> $null
    if ($LASTEXITCODE -ne 0) { Write-Log 'Boot trace: armed, but its session is not running (no restart since it was armed). It stays armed.'; return }
    & logman.exe stop $BootSession -ets *> $null
    $file = Get-ChildItem -Path ($BootFile -replace '\.etl$', '*.etl') -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($file) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $RunDir 'boot.etl')
        [void](Complete-Phase 'boot' "trace of the last boot ($([math]::Round($file.Length / 1MB)) MB)" 400)
    } else { Write-Log "Boot trace: the session ran, but no file matches $BootFile." }
    Disable-BootTrace
    Write-Log 'Boot trace: collected; the boot logger is removed.'
}

function Test-BootLogger {
    if (Test-Path -LiteralPath $BootKey) { Write-Log 'boot logger check: skipped, a boot trace is armed'; return }
    Enable-BootTrace
    $subKeys = @(Get-ChildItem -LiteralPath $BootKey)
    & reg.exe query ($BootKey -replace '^HKLM:\\', 'HKLM\') /s *> (Join-Path $RunDir 'boot-logger.txt')
    Disable-BootTrace
    Write-Log "boot logger check: created with $($subKeys.Count) providers; removed: $(-not (Test-Path -LiteralPath $BootKey))"
}

# ---------------------------------------------------------------- brightness and display

function Get-Panel {
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Set-PanelLevel([int]$Percent) {
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods | Select-Object -First 1 |
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]0; Brightness = [byte]$Percent } | Out-Null
}

# Visible test: dark for a moment, then the target level.
function Test-Brightness {
    try {
        Set-PanelLevel 0
        Start-Sleep -Milliseconds 1500
        Set-PanelLevel $script:Level
        Start-Sleep -Milliseconds 1000
    } catch { Write-Log "brightness test failed: $($_.Exception.Message)" }
}

function Get-StandbyEvent([int]$Id, [datetime]$Since) {
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = $Id; StartTime = $Since } -ErrorAction SilentlyContinue |
        Sort-Object TimeCreated | Select-Object -First 1
}

function Show-Countdown([int]$Cycle, [int]$Seconds) {
    if ($script:WakeNeedsUser) { Write-Host "Cycle ${Cycle}: the screens go dark. Press Shift after about $Seconds s of darkness." -ForegroundColor Cyan }
    else {
        Write-Host "Cycle ${Cycle}: the screens go dark for about $Seconds s and return by themselves." -ForegroundColor Cyan
        Write-Host "Hands off the keyboard, mouse and touchpad. If it stays dark longer than $($Seconds + 12) s, press Shift." -ForegroundColor Cyan
    }
    for ($left = $(if ($Cycle -eq 1) { 6 } else { 3 }); $left -ge 1; $left--) { Write-Host -NoNewline "$left "; Start-Sleep -Seconds 1 }
    Write-Host ''
}

# One display off/on. Returns a description: off time, what woke the display, the reason Windows logged.
function Invoke-DisplayCycle([int]$Seconds) {
    $since = (Get-Date).AddSeconds(-1)
    if (-not $Native::DisplayOff()) { return 'the display-off message was not delivered' }
    $Native::SpinFor($Seconds * 1000)
    $methods = 'mouse move', 'F15 key', 'monitor-on message'
    $sleepEvent = Get-StandbyEvent 506 $since
    if (-not $sleepEvent) {
        foreach ($index in 0..2) { $Native::Wake($index) }
        return 'Windows logged no standby entry; display state unknown'
    }
    $wakeEvent = Get-StandbyEvent 507 $since
    $by = if ($wakeEvent) { 'early' } else { '' }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($round = 0; -not $wakeEvent -and $clock.Elapsed.TotalSeconds -lt 120; $round++) {
        for ($index = 0; $index -lt $methods.Count -and -not $wakeEvent; $index++) {
            $Native::Wake($index)
            $poll = [Diagnostics.Stopwatch]::StartNew()
            while (-not $wakeEvent -and $poll.ElapsedMilliseconds -lt 2500) {
                $Native::SpinFor(200)
                $wakeEvent = Get-StandbyEvent 507 $since
            }
            if ($wakeEvent) { $by = if ($round -eq 0) { $methods[$index] } else { 'input' } }
        }
    }
    if (-not $wakeEvent) { $script:WakeNeedsUser = $true; return 'display off; no wake detected within 120 s' }
    $offFor = ($wakeEvent.TimeCreated - $sleepEvent.TimeCreated).TotalSeconds
    $reason = if ("$($wakeEvent.Message)" -match 'Reason:\s*(.+)') { $Matches[1].Trim() } else { 'unknown' }
    if ($by -eq 'input' -or ($by -eq 'early' -and $offFor -gt $Seconds + 3)) { $script:WakeNeedsUser = $true }
    $who = switch ($by) {
        'early' { 'woke before the script tried' }
        'input' { 'the injected wake failed, woke by input' }
        default { "woke by the injected $by" }
    }
    return ('display off {0:n1} s; {1}; Windows wake reason: {2}' -f $offFor, $who, $reason)
}

function Read-Answer([string]$Question) {
    if ($SelfTest) { return '' }
    $answer = "$(Read-Host $Question)".Trim().ToLowerInvariant()
    Write-Log "answer: '$answer'" -Detail
    return $answer
}

function Write-Environment {
    $os = Get-CimInstance Win32_OperatingSystem
    $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $monitors = @(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorID -ErrorAction SilentlyContinue | ForEach-Object { ($_.InstanceName -split '\\')[1] })
    $earlier = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 506; StartTime = $os.LastBootUpTime } -ErrorAction SilentlyContinue).Count
    Write-Log ('system: build {0}.{1}, booted {2:yyyy-MM-dd HH:mm:ss} ({3:n0} min ago), display-off events since boot: {4}' -f $version.CurrentBuild, $version.UBR, $os.LastBootUpTime, ((Get-Date) - $os.LastBootUpTime).TotalMinutes, $earlier) -Detail
    Write-Log ('power: {0}; monitors: {1}; elevated: {2}; trace: {3}' -f $(if ($battery) { "battery status $($battery.BatteryStatus) (2 = AC), $($battery.EstimatedChargeRemaining) %" } else { 'no battery' }), ($monitors -join ', '), $elevated, (-not $script:TraceOff)) -Detail
    foreach ($pattern in 'surfacepaneldriver.inf_*\SurfacePanelDriver.dll', 'surfacedisplayhardwaredriver.inf_*\SurfaceDisplayHardwareDriver.dll', 'qcdx8380.inf_*\qcdxkm8380.sys') {
        $found = @(Get-ChildItem -Path (Join-Path $env:SystemRoot "System32\DriverStore\FileRepository\$pattern") -ErrorAction SilentlyContinue)
        $versions = @($found | ForEach-Object { $_.VersionInfo.FileVersionRaw.ToString() } | Sort-Object -Unique)
        $leaf = Split-Path $pattern -Leaf
        Write-Log "driver: $leaf $($versions -join ', ')" -Detail
        if ($TableFor.ContainsKey($leaf) -and $versions -notcontains $TableFor[$leaf]) {
            Write-Log "Note: the message table was read from $leaf $($TableFor[$leaf]); timeline labels may be wrong for this version. The raw trace stays valid."
        }
    }
}

# ---------------------------------------------------------------- recovery flow

function Invoke-Recovery {
    $panel = Get-Panel
    if (-not $panel) { throw 'No internal panel: WmiMonitorBrightness has no instance.' }
    $current = [int]$panel.CurrentBrightness
    $script:Level = if ($Target -ge 0) { $Target } elseif ($current -lt 20) { 40 } else { $current }
    $cycles = if ($SelfTest) { 1 } else { $MaxCycles }
    Write-Log "Panel $(($panel.InstanceName -split '\\')[1]): Windows reports $current %, target $script:Level %, up to $cycles cycle(s)."

    Start-PanelTrace 'baseline'
    Start-Sleep -Milliseconds 1500
    Test-Brightness
    [void](Complete-Phase 'baseline' 'brightness test before any cycle')
    switch (Read-Answer 'Did the screen go dark for a moment? [y = brightness works / Enter = no / q = quit]') {
        'y' { Write-Log 'RESULT: brightness already responds; nothing to fix.'; $script:Result = 0; return }
        'q' { Write-Log 'RESULT: stopped.'; $script:Result = 2; return }
    }

    for ($cycle = 1; $cycle -le $cycles; $cycle++) {
        $seconds = [Math]::Min(12, $OffSeconds + 2 * [Math]::Max(0, $cycle - 2))
        Show-Countdown $cycle $seconds
        Start-PanelTrace "cycle-$cycle"
        $note = Invoke-DisplayCycle $seconds
        Start-Sleep -Seconds 3      # the driver's initialisation after display on takes about 2 s
        Test-Brightness
        [void](Complete-Phase "cycle-$cycle" $note)
        $answer = Read-Answer 'Did the screen go dark for a moment? [y = fixed / Enter = next cycle / r = restart the panel driver / q = quit]'
        if ($answer -eq 'r') {
            Write-Host 'Restarting the panel driver; windows may move between screens.'
            Start-PanelTrace "restart-$cycle"
            $device = $panel.InstanceName -replace '_\d+$'
            if ($elevated) { & pnputil.exe /restart-device $device *> $null; $code = $LASTEXITCODE }
            else { $code = (Start-Process pnputil.exe -Verb RunAs -Wait -PassThru -ArgumentList '/restart-device', "`"$device`"").ExitCode }
            Start-Sleep -Seconds 5
            Test-Brightness
            [void](Complete-Phase "restart-$cycle" "panel driver restart, pnputil exit code $code")
            $answer = Read-Answer 'Did the screen go dark for a moment? [y = fixed / Enter = next cycle / q = quit]'
        }
        if ($answer -eq 'y') { Write-Log "RESULT: fixed in cycle $cycle (display off $seconds s). Brightness $script:Level %."; $script:Result = 0; return }
        if ($answer -eq 'q') { Write-Log 'RESULT: stopped.'; $script:Result = 2; return }
    }
    if ($SelfTest) { Write-Log 'RESULT: self-test finished.'; $script:Result = 0 }
    else { Write-Log "RESULT: still stuck after $cycles cycle(s)."; $script:Result = 1 }
}

# ---------------------------------------------------------------- main

if ($Decode) {
    $etl = (Resolve-Path -LiteralPath $Decode).ProviderPath
    $data = [PanelBrightnessFixV2.Etl]::Read($etl, "$etl.events.txt", $KeySet, $FormatTexts)
    Get-Timeline $data.Rows 100000
    $summary = Get-TraceSummary $data.Rows
    "trace ($($data.Total) events): $($summary.Line)"
    foreach ($problem in $summary.Problems) { "! $problem" }
    "decoded events: $etl.events.txt"
    return
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$mode = if ($ArmBootTrace) { 'arm' } elseif ($DisarmBootTrace) { 'disarm' } else { 'fix' }
$isParent = -not $RunDir
if ($AtLogon -and $isParent) {
    Write-Host 'Panel brightness check after sign-in: starts in 20 s. Close this window to skip it.' -ForegroundColor Cyan
    Start-Sleep -Seconds 20      # let the desktop and the display drivers settle after sign-in
    # Two traced runs that met the fault are enough for the diagnosis; later logons skip the UAC prompt.
    $traced = @(Get-ChildItem -LiteralPath $DataRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'baseline.etl')) -and
            (Select-String -LiteralPath (Join-Path $_.FullName 'run.log') -Pattern 'RESULT: (fixed in cycle|still stuck)' -Quiet -ErrorAction SilentlyContinue)
        }).Count
    if ($traced -ge 2) { $NoTrace = [switch]$true }
}
if ($isParent) { $RunDir = Join-Path $DataRoot (Get-Date -Format 'yyyyMMdd-HHmmss') }
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
$LogFile = Join-Path $RunDir 'run.log'

if ($isParent -and -not $elevated -and ($mode -ne 'fix' -or -not $NoTrace)) {
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-RunDir', "`"$RunDir`"", '-UserSid', $identity.User.Value)
    foreach ($name in $PSBoundParameters.Keys) {
        $value = $PSBoundParameters[$name]
        if ($value -is [switch]) { if ($value) { $arguments += "-$name" } } else { $arguments += "-$name", "`"$value`"" }
    }
    Write-Host 'Opening the elevated window (UAC prompt). Cancel the prompt to run without the driver trace.'
    $child = $null
    try { $child = Start-Process pwsh -Verb RunAs -Wait -PassThru -ArgumentList $arguments } catch { Write-Host "No elevation: $($_.Exception.Message)" }
    if ($child) {
        $lines = @(if (Test-Path -LiteralPath $LogFile) { Get-Content -LiteralPath $LogFile })
        $lines | Where-Object { $_ -notmatch '^\S+   \| ' }
        $code = if (($lines -join "`n") -match '(?m)\| exit code (\d+)\s*$') { [int]$Matches[1] } else { 3 }
        Write-Host "Full log: $LogFile"
        if ($AtLogon -and $code -ne 0) { [void](Read-Host 'Press Enter to close') }
        exit $code
    }
    if ($mode -ne 'fix') { exit 3 }
}

$TraceOff = [bool]$NoTrace -or -not $elevated
$request = [IntPtr]::Zero
try {
    switch ($mode) {
        'arm' {
            Enable-BootTrace
            Write-Log 'Boot trace armed: it records the next boot. Run this script after the restart to collect it; it then removes itself.'
            $Result = 0
        }
        'disarm' { Disable-BootTrace; Write-Log 'Boot trace removed.'; $Result = 0 }
        default {
            Write-Environment
            if ($elevated) { Save-BootTrace }
            if ($SelfTest -and $elevated) { Test-BootLogger }
            $request = $Native::KeepAwake('Panel brightness recovery')
            Invoke-Recovery
        }
    }
} catch {
    Write-Log "ERROR at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
    $Result = 3
} finally {
    Stop-PanelTrace
    $Native::Release($request)
    Write-Log "exit code $Result" -Detail
    if ($elevated -and $UserSid) { & icacls.exe $RunDir /grant "*${UserSid}:(OI)(CI)M" /T /C /Q *> $null }
}
if ($isParent) { Write-Host "Full log: $LogFile" }
if ($AtLogon -and $isParent -and $Result -ne 0) { [void](Read-Host 'Press Enter to close') }
exit $Result
