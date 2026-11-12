<#
Software dimming via the GDI gamma ramp, per display.

  screen-dim.ps1                            # list displays
  screen-dim.ps1 -Monitor G95NC -Level 0.5  # dim by monitor-name substring
  screen-dim.ps1 -Gdi '\\.\DISPLAY2' -Level 0.5
  screen-dim.ps1 -Monitor G95NC -Reset

External monitors only, in SDR. The internal Surface panel is always excluded: it is
Windows-managed (adaptive brightness, ACM), and its OEM calibration pipeline owns the
hardware LUT anyway, so ramps never reached it (proven with a hard-red ramp).

Gamma is independent of backlight, so this stacks on top of DDC brightness -- useful
once DDC brightness is already at 0.

Resets on reboot; fullscreen games can clear it.
#>
param(
    [string]$Monitor,
    [string]$Gdi,
    [double]$Level = 0.6,
    [switch]$Reset,
    [switch]$Read      # report the current ramp without changing it
)
$ErrorActionPreference = 'Stop'
if ($Reset) { $Level = 1.0 }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SD2 {
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
    [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] public static extern int GetRaw(IntPtr p);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateDCW(string drv, string dev, string port, IntPtr dm);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr h);
    [DllImport("gdi32.dll")] public static extern bool SetDeviceGammaRamp(IntPtr h, ushort[] r);
    [DllImport("gdi32.dll")] public static extern bool GetDeviceGammaRamp(IntPtr h, ushort[] r);
}
'@

[uint32]$np=0; [uint32]$nm=0
$null = [SD2]::GetDisplayConfigBufferSizes(2, [ref]$np, [ref]$nm)
$paths = New-Object 'SD2+PATH_INFO[]' $np
$modes = New-Object 'SD2+MODE_BLOB[]' $nm
$null = [SD2]::QueryDisplayConfig(2, [ref]$np, $paths, [ref]$nm, $modes, [IntPtr]::Zero)

function Pkt($p, [int]$t, [int]$s, [bool]$src) {
    $b = [Runtime.InteropServices.Marshal]::AllocHGlobal($s)
    for ($o=0; $o -lt $s; $o+=4) { [Runtime.InteropServices.Marshal]::WriteInt32($b,$o,0) }
    [Runtime.InteropServices.Marshal]::WriteInt32($b,0,$t)
    [Runtime.InteropServices.Marshal]::WriteInt32($b,4,$s)
    if ($src) {
        [Runtime.InteropServices.Marshal]::WriteInt32($b,8,[int]$p.srcAdapterLow)
        [Runtime.InteropServices.Marshal]::WriteInt32($b,12,$p.srcAdapterHigh)
        [Runtime.InteropServices.Marshal]::WriteInt32($b,16,[int]$p.srcId)
    } else {
        [Runtime.InteropServices.Marshal]::WriteInt32($b,8,[int]$p.tgtAdapterLow)
        [Runtime.InteropServices.Marshal]::WriteInt32($b,12,$p.tgtAdapterHigh)
        [Runtime.InteropServices.Marshal]::WriteInt32($b,16,[int]$p.tgtId)
    }
    return $b
}

$displays = @()
foreach ($i in 0..($np-1)) {
    $p = $paths[$i]
    $b = Pkt $p 1 84 $true
    $gdiName = $null
    try { if ([SD2]::GetRaw($b) -eq 0) { $gdiName = [Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($b,20)) } } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($b) }
    $b = Pkt $p 2 420 $false
    $monName = '?'
    try { if ([SD2]::GetRaw($b) -eq 0) { $monName = [Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($b,36)) } } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($b) }
    $isInt = ([uint32]$p.outputTechnology -eq [uint32]2147483648)
    if ($gdiName) { $displays += [pscustomobject]@{ Gdi = $gdiName; Monitor = $monName; Internal = $isInt } }
}

if (-not $Monitor -and -not $Gdi) {
    Write-Output "attached displays:"
    foreach ($d in $displays) {
        $note = if ($d.Internal) { '  <- internal: excluded, Windows-managed' } else { '' }
        Write-Output ("  {0,-14} {1,-20} internal={2}{3}" -f $d.Gdi, $d.Monitor, $d.Internal, $note)
    }
    Write-Output ""
    Write-Output "usage: screen-dim.ps1 -Monitor G95NC -Level 0.5    |    -Reset"
    return
}

$targets = @()
if ($Gdi)     { $targets = $displays | Where-Object { $_.Gdi -eq $Gdi } }
elseif ($Monitor) { $targets = $displays | Where-Object { $_.Monitor -like "*$Monitor*" } }
if (-not $targets) { throw "no display matched (have: $(($displays | ForEach-Object { "$($_.Gdi)=$($_.Monitor)" }) -join ', '))" }
$targets = @($targets | Where-Object { -not $_.Internal })
if (-not $targets) { throw 'only the internal panel matched; it is excluded (Windows-managed)' }

$ramp = New-Object 'uint16[]' 768
for ($i = 0; $i -lt 256; $i++) {
    $v = [int][math]::Round($i * 257 * $Level)
    if ($v -gt 65535) { $v = 65535 }
    if ($v -lt 0) { $v = 0 }
    # [uint16] not [ushort]: 'ushort' is a PS7-only type accelerator and this script is
    # invoked from auto-brightness.ps1 under Windows PowerShell 5.1.
    $ramp[$i] = [uint16]$v; $ramp[$i+256] = [uint16]$v; $ramp[$i+512] = [uint16]$v
}

foreach ($t in $targets) {
    $hdc = [SD2]::CreateDCW('DISPLAY', $t.Gdi, $null, [IntPtr]::Zero)
    if ($hdc -eq [IntPtr]::Zero) { Write-Output ("  {0}: CreateDC FAILED" -f $t.Gdi); continue }
    if ($Read) {
        try {
            $chk = New-Object 'uint16[]' 768
            [void][SD2]::GetDeviceGammaRamp($hdc, $chk)
            $eff = [math]::Round($chk[128] / 32896.0, 3)
            Write-Output ("  {0,-14} {1,-20} current ramp[128]={2} => effective level ~{3}" -f $t.Gdi, $t.Monitor, $chk[128], $eff)
        } finally { [void][SD2]::DeleteDC($hdc) }
        continue
    }
    try {
        $ok  = [SD2]::SetDeviceGammaRamp($hdc, $ramp)
        $chk = New-Object 'uint16[]' 768
        [void][SD2]::GetDeviceGammaRamp($hdc, $chk)
        Write-Output ("  {0,-14} {1,-20} level={2}  set={3}  readback[128]={4} (normal 32896)" -f $t.Gdi, $t.Monitor, $Level, $ok, $chk[128])    } finally { [void][SD2]::DeleteDC($hdc) }
}

