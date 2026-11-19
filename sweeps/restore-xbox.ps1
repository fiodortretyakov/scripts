<#
.SYNOPSIS
  Undoes the machine-wide parts of the 23 October 2026 Xbox removal that block Microsoft Store games
  (Doom Eternal): Xbox sign-in and achievements, cloud saves, multiplayer, and Game Bar opening.
.DESCRIPTION
  Dry run by default: prints what would change. -Apply asks for UAC once, applies in an elevated child,
  then verifies from this session. Recovery data goes to D:\data\sweeps\restore-xbox-<stamp>\.

  Restores:
    XblAuthManager  Disabled -> Manual   Xbox sign-in, achievements
    XblGameSave     Disabled -> Manual   Xbox cloud saves
    XboxNetApiSvc   Disabled -> Manual   Xbox multiplayer networking
    HKLM ms-gamebar, ms-gamebarservices, ms-gamingoverlay: remove the shell\open\command -> systray.exe
    redirect so Game Bar opens (Win+G, achievement pop-ups).
    \Microsoft\XblGameSave\XblGameSaveTask: the in-box cloud-save sync on standby entry. The XML below is the
    <taskScheduler> block of the component manifest Windows-Gaming-XboxLive-Storage-Service-Component
    10.0.26100.8115 (C:\Windows\WinSxS\Manifests\arm64_windows-gaming-xbox..e-service-component_31bf3856ad364e35_
    10.0.26100.8115_none_ef489fc763dae69f.manifest), decoded 4 November 2026, plus version="1.2".

  Left as is on purpose (not needed for the game):
    XboxGipSvc (Xbox-brand controllers only), AllowGameDVR=0 (screen recording only),
    Deprovisioned entries, Xbox app (not wanted).
#>
param([switch]$Apply, [switch]$Elevated, [string]$OutDir)

$ErrorActionPreference = 'Stop'
$services = 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc'
$protocols = 'ms-gamebar', 'ms-gamebarservices', 'ms-gamingoverlay'
$taskPath = '\Microsoft\XblGameSave\'
$taskName = 'XblGameSaveTask'
$taskXml = @'
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Microsoft</Author>
    <Description>XblGameSave Standby Task</Description>
    <URI>\Microsoft\XblGameSave\XblGameSaveTask</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="LocalSystem">
      <UserId>S-1-5-18</UserId>
    </Principal>
  </Principals>
  <Triggers>
    <IdleTrigger id="XblGameSave Check on CS Entry">
      <Enabled>false</Enabled>
    </IdleTrigger>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>true</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>true</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>true</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="LocalSystem">
    <Exec>
      <Command>%windir%\System32\XblGameSaveTask.exe</Command>
      <Arguments>standby</Arguments>
    </Exec>
  </Actions>
</Task>
'@

function Test-TaskPresent {
    if (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue) { return $true }
    Test-Path "C:\Windows\System32\Tasks$taskPath$taskName"
}

function Get-Plan {
    foreach ($s in $services) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.StartType -eq 'Disabled') {
            [pscustomobject]@{ Kind = 'Service'; Target = $s; Before = 'Disabled'; After = 'Manual' }
        }
    }
    foreach ($p in $protocols) {
        $cmd = "HKLM:\SOFTWARE\Classes\$p\shell\open\command"
        if ((Test-Path $cmd) -and ((Get-Item $cmd).GetValue('') -match 'systray\.exe')) {
            [pscustomobject]@{ Kind = 'Redirect'; Target = "HKLM:\SOFTWARE\Classes\$p\shell"; Before = 'systray.exe'; After = 'removed' }
        }
    }
    if (-not (Test-TaskPresent)) {
        [pscustomobject]@{ Kind = 'Task'; Target = "$taskPath$taskName"; Before = 'absent'; After = 'registered (in-box XML)' }
    }
}

function Invoke-Plan([object[]]$Plan, [string]$Dir) {
    $log = Join-Path $Dir 'apply.log'
    foreach ($i in $Plan) {
        switch ($i.Kind) {
            'Service' {
                Set-Service -Name $i.Target -StartupType Manual
            }
            'Redirect' {
                $name = ($i.Target -split '\\')[-2]
                & reg.exe export ($i.Target -replace '^HKLM:\\', 'HKLM\') (Join-Path $Dir "$name-shell.reg") /y | Out-Null
                Remove-Item -Path $i.Target -Recurse -Force
            }
            'Task' {
                Set-Content -Path (Join-Path $Dir "$taskName.xml") -Value $taskXml -Encoding utf8
                $null = Register-ScheduledTask -Xml $taskXml -TaskPath $taskPath -TaskName $taskName
                $state = (Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName).State
                "$(Get-Date -Format s) Task state after register: $state" | Add-Content -Path $log
            }
        }
        "$(Get-Date -Format s) $($i.Kind) $($i.Target): $($i.Before) -> $($i.After)" | Add-Content -Path $log
    }
}

if ($Elevated) {
    try {
        Invoke-Plan -Plan @(Get-Plan) -Dir $OutDir
        'OK' | Set-Content -Path (Join-Path $OutDir 'result.txt')
    } catch {
        "FAILED: $_" | Set-Content -Path (Join-Path $OutDir 'result.txt')
    }
    return
}

$plan = @(Get-Plan)
if ($plan.Count -eq 0) { 'Nothing to restore: services, Game Bar protocols and the save task are already back.'; return }
$plan | Format-Table -AutoSize | Out-String -Width 200
if (-not $Apply) { "DRY RUN: $($plan.Count) changes. Apply with: & D:\bin\sweeps\restore-xbox.ps1 -Apply"; return }

$dir = "D:\data\sweeps\restore-xbox-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$plan | Export-Csv -Path (Join-Path $dir 'plan.csv') -NoTypeInformation

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    & $PSCommandPath -Elevated -OutDir $dir
} else {
    $pwsh = (Get-Process -Id $PID).Path
    Start-Process -FilePath $pwsh -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Elevated', '-OutDir', "`"$dir`"")
}

Get-Content -Path (Join-Path $dir 'apply.log') -ErrorAction SilentlyContinue
"Elevated run: $(Get-Content -Path (Join-Path $dir 'result.txt') -ErrorAction SilentlyContinue)"
$left = @(Get-Plan)
if ($left.Count -eq 0) { "VERIFIED: all $($plan.Count) changes applied. Recovery files: $dir" }
else { 'STILL PENDING:'; $left | Format-Table -AutoSize | Out-String -Width 200 }
