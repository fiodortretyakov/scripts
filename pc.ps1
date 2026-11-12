<#
One control surface for this machine. Thin dispatcher -- every underlying script keeps
working standalone, so deleting this file breaks nothing.

  pc.ps1 status                        everything at a glance
  pc.ps1 dim -Profile work             apply a named display profile
  pc.ps1 dim -Brightness 0 -Contrast 20 -Gamma 0.55
  pc.ps1 charger                       charger health
  pc.ps1 tasks                         the scheduled automations

The 'game' subcommand and the HDR status readout were removed on 2026-09-08 together with
hdr-auto.ps1, which owned the auto-HDR toggle AND the keep-awake hold.

The 'hdr' and 'audio' subcommands were removed on 6 October 2026 together with hdr.ps1 and
audio-spatial.ps1: HDR is toggled in Settings, and Windows applies the spatial format per
endpoint on its own.

Handles the PS5.1-vs-PS7 split: auto-brightness needs WinRT (5.1 only), the rest is
happy in either.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status','dim','charger','tasks','profiles','panelreset','sweep')]
    [string]$Command = 'status',
    [switch]$Preview,

    [string]$Profile,
    [int]$Brightness = -1,
    [int]$Contrast   = -1,
    [double]$Gamma   = -1
)

$bin = Split-Path $PSCommandPath -Parent
$ps5 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

# Named display profiles. Add SDR/HDR variants here after calibration.
$Profiles = @{
    'work'    = @{ Brightness = 12; Contrast = 40; Gamma = 0.90; Note = 'settled 2026-08-14 daylight profile (anchor 435 lux)' }
    'medium'  = @{ Brightness = 0;  Contrast = 30; Gamma = 0.70; Note = 'middle ground' }
    'bright'  = @{ Brightness = 3;  Contrast = 40; Gamma = 0.85; Note = 'closest to a normal picture' }
    'gaming'  = @{ Brightness = 10; Contrast = 50; Gamma = 1.00; Note = 'no software dimming; pair with HDR on' }
}

function Invoke-Ps5($script, $argList) { & $ps5 -NoProfile -ExecutionPolicy Bypass -File (Join-Path $bin $script) @argList }

function Show-Charger {
    Add-Type -AssemblyName System.Windows.Forms
    $pw = [System.Windows.Forms.SystemInformation]::PowerStatus
    $bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue
    $pct = [int]($pw.BatteryLifePercent * 100)
    $w = if ($bs) { [math]::Round($bs.ChargeRate / 1000, 1) } else { '?' }
    Write-Output ("  power     : {0}   battery {1}%   {2}" -f $pw.PowerLineStatus, $pct, $pw.BatteryChargeStatus)
    Write-Output ("  charging  : {0} W" -f $w)
    if ($pw.PowerLineStatus -eq 'Online' -and $bs -and $bs.Charging -and $bs.ChargeRate -gt 0 -and $pct -lt 78 -and $bs.ChargeRate -lt 20000) {
        Write-Output "  WARNING   : only $w W at $pct% - expected ~39 W. Suspect a failing charger/cable/dock."
        Write-Output "              A brownout here fakes display and brightness faults."
    } elseif ($pct -ge 78 -and $bs -and $bs.ChargeRate -lt 1000) {
        Write-Output "  note      : 0 W at $pct% is Smart Charging parking at 80%, not a fault."
    }
}

function Show-Displays {
    $st = Join-Path 'D:\config' 'auto-brightness\state.json'
    if (Test-Path $st) {
        $s = Get-Content $st -Raw | ConvertFrom-Json
        Write-Output ("  profile   : brightness {0}/50, contrast {1}/50, gamma {2}" -f $s.lastSet, $s.contrastLevel, $s.gammaLevel)
        Write-Output ("  anchor    : {0} lux -> {1}/50" -f $s.anchorLux, $s.anchorBrightness)
        if ($null -ne $s.nightGamma) { Write-Output ("  night     : contrast {0}/50, gamma {1} at <= {2} lux (blends up to the day profile at the anchor)" -f $s.nightContrast, $s.nightGamma, $s.nightLux) }
        Write-Output ("  ext-only  : {0}   (auto-brightness.ps1 -ExternalOnly on|off)" -f $(if ($s.externalOnly) { 'on - internal panel off while the G95NC is attached' } else { 'off' }))
        $sw = if ($null -eq $s.sweepAgents -or $s.sweepAgents) { 'on' } else { 'off' }
        $ih = if ($null -ne $s.idleSessionHours) { $s.idleSessionHours } else { 3 }
        $tracked = if ($s.claudeIdle) { @($s.claudeIdle.PSObject.Properties).Count } else { 0 }
        Write-Output ("  sweep     : {0}, {1} live Claude session(s) tracked, idle ones killed after {2} h   (pc.ps1 sweep [-Preview])" -f $sw, $tracked, $ih)
    }
}

function Show-Tasks {
    $svc = New-Object -ComObject Schedule.Service; $svc.Connect(); $f = $svc.GetFolder('\')
    foreach ($n in 'Auto brightness G95NC','Daily winget upgrade') {
        try {
            $t = $f.GetTask("\$n")
            $ok = if ($t.LastTaskResult -eq 0) { 'ok' } elseif ($t.LastTaskResult -eq 267011) { 'not yet run' } else { "result $($t.LastTaskResult)" }
            Write-Output ("  {0,-24} {1,-12} next {2}" -f $t.Name, $ok, $t.NextRunTime)
        } catch { Write-Output ("  {0,-24} NOT REGISTERED" -f $n) }
    }
}

switch ($Command) {

    'profiles' {
        Write-Output "named display profiles:"
        foreach ($k in $Profiles.Keys | Sort-Object) {
            $p = $Profiles[$k]
            Write-Output ("  {0,-8} brightness {1,2}/50  contrast {2,2}/50  gamma {3,-5}  {4}" -f $k, $p.Brightness, $p.Contrast, $p.Gamma, $p.Note)
        }
    }

    'dim' {
        if ($Profile) {
            if (-not $Profiles.ContainsKey($Profile)) { throw "unknown profile '$Profile'. Try: $($Profiles.Keys -join ', ')" }
            $p = $Profiles[$Profile]
            $Brightness = $p.Brightness; $Contrast = $p.Contrast; $Gamma = $p.Gamma
            Write-Output "applying profile '$Profile' ($($p.Note))"
        }
        if ($Brightness -lt 0 -and $Contrast -lt 0 -and $Gamma -lt 0) { throw "give -Profile, or at least one of -Brightness/-Contrast/-Gamma" }
        $a = @()
        if ($Brightness -ge 0) { $a += @('-Calibrate', $Brightness) }
        if ($Contrast   -ge 0) { $a += @('-Contrast',  $Contrast) }
        if ($Gamma      -ge 0) { $a += @('-Gamma',     $Gamma) }
        Invoke-Ps5 'auto-brightness.ps1' $a
        Write-Output "stored - the 2-min task will keep re-asserting this."
    }

    'charger' { Write-Output "charger:"; Show-Charger }

    # Kill leaked agent processes and abandoned Claude sessions now (the 2-min task does the same
    # every run). -Preview lists what would go without killing anything.
    'sweep' {
        $a = @('-SweepNow'); if ($Preview) { $a += '-WhatIf' }
        Invoke-Ps5 'auto-brightness.ps1' $a
    }

    # Internal panel pinned bright with a dead slider (2026-08-26): taking the panel out of the
    # topology and back power-cycles it, and the backlight followed the slider again right after.
    # Manual only, and only makes sense with the G95NC attached.
    'panelreset' {
        $ds = Join-Path $env:WINDIR 'System32\DisplaySwitch.exe'
        Write-Output "internal panel off (external only) ..."
        Start-Process -FilePath $ds -ArgumentList '/external' -Wait
        Start-Sleep -Seconds 6
        Write-Output "and back on (extend) ..."
        Start-Process -FilePath $ds -ArgumentList '/extend' -Wait
        Start-Sleep -Seconds 3
        Write-Output "now move the brightness slider; if the panel still ignores it, hold the power button ~20 s (forced restart)."
    }

    'tasks'   { Write-Output "scheduled automations:"; Show-Tasks }

    'status'  {
        Write-Output ""
        Write-Output "DISPLAYS"; Show-Displays
        Write-Output ""
        Write-Output "POWER";    Show-Charger
        Write-Output ""
        Write-Output "AUTOMATIONS"; Show-Tasks
        Write-Output ""
    }
}
