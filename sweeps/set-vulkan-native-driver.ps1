# set-vulkan-native-driver.ps1: makes every Vulkan program (Doom Eternal) use the native Qualcomm driver, never the
# Direct3D 12 translation layer.
#
# Asked for on 12 November 2026 ("how to force doom use correct render?"). Measured that day through the Vulkan loader:
#   a Vulkan program is offered three devices, in this order:
#     0  Qualcomm(R) Adreno(TM) X1-85 GPU                      native driver, Vulkan 1.4
#     1  Microsoft Direct3D12 (Qualcomm Adreno X1-85 GPU)      "Dozen": Vulkan translated to Direct3D 12, slower
#     2  Microsoft Direct3D12 (Microsoft Basic Render Driver)  software rendering on the CPU
#   Devices 1 and 2 come from the OpenCL, OpenGL and Vulkan Compatibility Pack (Microsoft.D3DMappingLayers). The
#   native one is first, so most games take it, but a game is free to pick another.
# The Vulkan loader (installed: 1.4.357) skips drivers named in VK_LOADER_DRIVERS_DISABLE. With *dzn* only the native
# device is left (tested). OpenGL and OpenCL programs are not affected; they do not go through the Vulkan loader.
#
#   D:\bin\sweeps\set-vulkan-native-driver.ps1           dry run: shows the devices now and with the setting
#   D:\bin\sweeps\set-vulkan-native-driver.ps1 -Apply    sets the machine variable. Run NOT elevated; one UAC prompt.
#   D:\bin\sweeps\set-vulkan-native-driver.ps1 -Undo     removes it again (one UAC prompt)
#
# Machine scope, like the other variables on this laptop. Programs started afterwards see it; restart Doom.
#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Undo,
    [switch]$MachinePhase,   # internal: set by the elevated re-launch
    [switch]$Enumerate       # internal: print the Vulkan devices of this process and exit
)
$ErrorActionPreference = 'Stop'
$name = 'VK_LOADER_DRIVERS_DISABLE'
$value = '*dzn*'
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# =============================================================================== device list of this process
if ($Enumerate) {
    Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class VulkanNativeDriverCheck {
  [StructLayout(LayoutKind.Sequential)] struct AppInfo { public int sType; public IntPtr pNext; public IntPtr pApplicationName; public uint applicationVersion; public IntPtr pEngineName; public uint engineVersion; public uint apiVersion; }
  [StructLayout(LayoutKind.Sequential)] struct CreateInfo { public int sType; public IntPtr pNext; public uint flags; public IntPtr pApplicationInfo; public uint enabledLayerCount; public IntPtr ppEnabledLayerNames; public uint enabledExtensionCount; public IntPtr ppEnabledExtensionNames; }
  [DllImport("vulkan-1.dll")] static extern int vkCreateInstance(ref CreateInfo ci, IntPtr alloc, out IntPtr instance);
  [DllImport("vulkan-1.dll")] static extern int vkEnumeratePhysicalDevices(IntPtr instance, ref uint count, [Out] IntPtr[] devices);
  [DllImport("vulkan-1.dll")] static extern void vkGetPhysicalDeviceProperties(IntPtr device, IntPtr props);
  [DllImport("vulkan-1.dll")] static extern void vkDestroyInstance(IntPtr instance, IntPtr alloc);
  public static string[] Devices() {
    var app = new AppInfo { sType = 0, apiVersion = (1u << 22) | (1u << 12) };
    IntPtr pApp = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(AppInfo))); Marshal.StructureToPtr(app, pApp, false);
    var ci = new CreateInfo { sType = 1, pApplicationInfo = pApp };
    IntPtr inst; int r = vkCreateInstance(ref ci, IntPtr.Zero, out inst);
    if (r != 0) { Marshal.FreeHGlobal(pApp); return new[] { "vkCreateInstance failed: " + r }; }
    uint n = 0; vkEnumeratePhysicalDevices(inst, ref n, null);
    var devs = new IntPtr[n]; vkEnumeratePhysicalDevices(inst, ref n, devs);
    var names = new string[n]; IntPtr props = Marshal.AllocHGlobal(2048); byte[] b = new byte[256];
    for (int i = 0; i < n; i++) {
      vkGetPhysicalDeviceProperties(devs[i], props);
      Marshal.Copy(props + 20, b, 0, 256); int z = Array.IndexOf(b, (byte)0);
      names[i] = Encoding.UTF8.GetString(b, 0, z < 0 ? 256 : z);
    }
    Marshal.FreeHGlobal(props); Marshal.FreeHGlobal(pApp); vkDestroyInstance(inst, IntPtr.Zero);
    return names;
  }
}
'@
    [VulkanNativeDriverCheck]::Devices()
    exit 0
}

# =============================================================================== MACHINE PART (elevated)
if ($MachinePhase) {
    if (-not $elevated) { throw 'The machine part must run elevated.' }
    if ($Undo) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Machine') }
    else { [Environment]::SetEnvironmentVariable($name, $value, 'Machine') }
    exit 0
}

# =============================================================================== USER PART (not elevated)
if ($elevated) { throw 'Run from a normal (not elevated) PowerShell 7 window: it asks for UAC itself.' }
function W([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
# The devices a NEW program would get with this value of the variable ($null = variable absent)
function Devices([string]$with) {
    $saved = $env:VK_LOADER_DRIVERS_DISABLE
    try {
        if ($with) { $env:VK_LOADER_DRIVERS_DISABLE = $with } else { Remove-Item Env:VK_LOADER_DRIVERS_DISABLE -ErrorAction SilentlyContinue }
        @(& "$PSHOME\pwsh.exe" -NoProfile -File $PSCommandPath -Enumerate)
    } finally { if ($null -eq $saved) { Remove-Item Env:VK_LOADER_DRIVERS_DISABLE -ErrorAction SilentlyContinue } else { $env:VK_LOADER_DRIVERS_DISABLE = $saved } }
}
function MachineValue { (Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').GetValue($name, $null) }
function UserHasTwin { (Get-Item 'HKCU:\Environment').GetValueNames() -contains $name }

$mode = if ($Undo) { 'UNDO' } elseif ($Apply) { 'APPLY' } else { 'DRY RUN' }
W "set-vulkan-native-driver  [$mode]  as $env:USERNAME" Cyan
$now = MachineValue
W "machine variable $name now: $(if ($null -eq $now) { '(not set)' } else { "'$now'" })$(if (UserHasTwin) { '; a user-scope copy exists and will be removed' })"
W 'devices a Vulkan program gets WITHOUT the setting:'
Devices $null | ForEach-Object -Begin { $i = 0 } -Process { W "  $i  $_"; $i++ }
W "devices WITH $name=$value`:"
$filtered = @(Devices $value)
$filtered | ForEach-Object -Begin { $i = 0 } -Process { W "  $i  $_" Green; $i++ }
$onlyNative = $filtered.Count -eq 1 -and $filtered[0] -like 'Qualcomm*'
if (-not $onlyNative) { W 'The setting does not leave exactly the native Qualcomm device; not applying.' Red; exit 1 }

if (-not $Apply -and -not $Undo) {
    W ''
    W 'DRY RUN: nothing changed. Apply with: D:\bin\sweeps\set-vulkan-native-driver.ps1 -Apply' Yellow
    exit 0
}

if (UserHasTwin) { Remove-ItemProperty -Path 'HKCU:\Environment' -Name $name }   # a user copy would shadow the machine value
$want = if ($Undo) { $null } else { $value }
if ((MachineValue) -ne $want) {
    W 'asking for elevation (UAC) ...' Cyan
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-MachinePhase')
    if ($Undo) { $argList += '-Undo' }
    try { Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList $argList }
    catch { W "[FAIL] the elevated part did not start: $($_.Exception.Message)" Red; exit 1 }
}
$after = MachineValue
if ($after -ne $want) { W "[FAIL] machine variable is $(if ($null -eq $after) { '(not set)' } else { "'$after'" })" Red; exit 1 }
if ($Undo) { W "DONE. $name is removed; Vulkan programs get all three devices again." Green; exit 0 }
W "DONE. $name=$value is set for the machine." Green
W 'Close Doom if it is running and start it again. Programs that were already open keep the old setting until restarted.'
exit 0
