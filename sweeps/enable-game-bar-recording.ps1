#Requires -Version 7
<#
Turns Game Bar recording back on (13 November 2026, "can I record video using Game Bar in Doom Eternal?").

Recording was switched off by remove-xbox.ps1 on 23 October 2026 and kept off when Xbox came back on 4 November:
  HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR  AllowGameDVR = 0     (machine policy: blocks all Game Bar capture)
  HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR  AppCaptureEnabled = 0, AudioCaptureEnabled = 0
  HKCU\System\GameConfigStore  GameDVR_Enabled = 0
Apply sets AllowGameDVR = 1 (one UAC prompt), AppCaptureEnabled = 1, AudioCaptureEnabled = 1 (game sound in the
recording), GameDVR_Enabled = 1, and restarts Game Bar so it reads them. Background recording ("record what happened",
HistoricalCaptureEnabled) and the microphone stay OFF. Recordings go to D:\data\Videos\Captures.
-Undo puts all four back to 0.

Dry run (default):   & D:\bin\sweeps\enable-game-bar-recording.ps1
Apply:               & D:\bin\sweeps\enable-game-bar-recording.ps1 -Apply
Undo:                & D:\bin\sweeps\enable-game-bar-recording.ps1 -Undo
#>
param([switch]$Apply, [switch]$Undo)
$ErrorActionPreference = 'Stop'
$policyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
$userKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$storeKey = 'HKCU:\System\GameConfigStore'

function Show-State([string]$label) {
    $p = (Get-ItemProperty $policyKey -EA SilentlyContinue).AllowGameDVR
    $u = Get-ItemProperty $userKey -EA SilentlyContinue
    $s = Get-ItemProperty $storeKey -EA SilentlyContinue
    "$label  AllowGameDVR=$p  AppCaptureEnabled=$($u.AppCaptureEnabled)  AudioCaptureEnabled=$($u.AudioCaptureEnabled)  GameDVR_Enabled=$($s.GameDVR_Enabled)  HistoricalCaptureEnabled=$($u.HistoricalCaptureEnabled)  MicrophoneCaptureEnabled=$($u.MicrophoneCaptureEnabled)"
}

Show-State 'now:   '
if (-not $Apply -and -not $Undo) { 'Dry run. Run again with -Apply (or -Undo).'; return }
$value = if ($Apply) { 1 } else { 0 }

if ((Get-ItemProperty $policyKey -EA SilentlyContinue).AllowGameDVR -ne $value) {
    'Setting the machine policy (UAC prompt)'
    sudo pwsh -NoProfile -Command "New-Item -Path '$policyKey' -Force | Out-Null; Set-ItemProperty -Path '$policyKey' -Name AllowGameDVR -Value $value -Type DWord"
}
Set-ItemProperty $userKey -Name AppCaptureEnabled -Value $value -Type DWord
Set-ItemProperty $userKey -Name AudioCaptureEnabled -Value $value -Type DWord
Set-ItemProperty $storeKey -Name GameDVR_Enabled -Value $value -Type DWord
Get-Process GameBar, GameBarFTServer -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue

# sudo runs in "Force New Window" mode here: the elevated command finishes in its own window, so wait for it
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline -and (Get-ItemProperty $policyKey -EA SilentlyContinue).AllowGameDVR -ne $value) { Start-Sleep -Seconds 1 }
Show-State 'after: '
if ((Get-ItemProperty $policyKey -EA SilentlyContinue).AllowGameDVR -ne $value) { throw 'The machine policy did not change within 60 seconds (UAC prompt declined?).' }
'Done. Game Bar starts again the next time you open it (Win+G or the Stadia button).'
