<#
remove-windows-ai-workloads.ps1 - switch the Windows AI runtime off and remove its model packages (16 November 2026).

Click to Do and Recall are already off by policy (DisableClickToDo, DisableAIDataAnalysis), yet the AI runtime
starts at every boot: WorkloadsSessionHost (about 380 MB) runs although WSAIFabricSvc is Manual, because a
client starts the service on demand. The models arrive as WindowsWorkload.* packages (12 on 16 November 2026,
delivered with the 31 October and 11 November updates): content extraction, image search, settings model,
data analysis, tokenizers, WinML runtime, session manager.

  remove-windows-ai-workloads.ps1          dry run, no UAC: packages, service and AI host processes
  remove-windows-ai-workloads.ps1 -Apply   one UAC prompt: WSAIFabricSvc Disabled and stopped; every
                                           WindowsWorkload.* package removed for all users and deprovisioned

Lost: semantic (natural-language) search in Settings and File Explorer, AI actions in Photos and Paint.
Classic search stays. Not verified: whether any other in-box feature calls these packages.
Windows Update may deliver the packages again; with the service disabled they stay inert.
Undo (elevated): Set-Service WSAIFabricSvc -StartupType Manual; the packages return with Windows Update.
Log: D:\data\sweeps\remove-windows-ai-workloads-<time>\
#>
param(
    [switch]$Apply,
    [string]$OutDir   # internal: shared with the elevated re-launch
)
$ErrorActionPreference = 'Stop'
$Service = 'WSAIFabricSvc'
$Pattern = 'WindowsWorkload.*'
if (-not $OutDir) {
    $OutDir = 'D:\data\sweeps\remove-windows-ai-workloads-{0:yyyy-MM-dd-HHmmss}{1}' -f (Get-Date), $(if ($Apply) { '' } else { '-dryrun' })
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$LogFile = Join-Path $OutDir 'run.log'
function L([string]$m) { Add-Content -Path $LogFile -Value $m -Encoding utf8; Write-Output $m }
$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Get-Workloads {
    if ($elevated) { @(Get-AppxPackage -AllUsers -Name $Pattern) } else { @(Get-AppxPackage -Name $Pattern) }
}
function Show-State([string]$title) {
    L "--- $title ---"
    $s = Get-CimInstance Win32_Service -Filter "Name='$Service'"
    L "  service $Service`: $($s.State), $($s.StartMode)"
    $procs = @(Get-Process -Name 'Workloads*' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { L "  AI host processes: none" }
    $procs | ForEach-Object { L ("  process {0} pid {1}: {2} MB" -f $_.Name, $_.Id, [int]($_.WorkingSet64 / 1MB)) }
    $pk = Get-Workloads
    L "  $Pattern packages$(if (-not $elevated) { ' (this user)' }): $($pk.Count)"
    $pk | Sort-Object Name | ForEach-Object { L "    $($_.Name) $($_.Version)" }
}

if (-not $Apply) {
    L "DRY RUN $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Show-State 'now'
    L "-Apply would: set $Service to Disabled and stop it; remove every $Pattern package for all users; deprovision them."
    L "Run with -Apply to do it (one UAC prompt)."
    exit 0
}

if (-not $elevated) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Apply', '-OutDir', "`"$OutDir`"")
    try { $p = Start-Process "$PSHOME\pwsh.exe" -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList $argList }
    catch { Write-Output "Elevation cancelled: $($_.Exception.Message)"; exit 1 }
    if (Test-Path $LogFile) { Get-Content $LogFile }
    exit $p.ExitCode
}

$failed = 0
try {
    L "APPLY $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') as $(whoami)"
    Show-State 'before'

    L "--- service ---"
    try { Set-Service -Name $Service -StartupType Disabled; L "  $Service startup: Disabled" }
    catch {
        & sc.exe config $Service start= disabled | Out-Null
        if ($LASTEXITCODE -eq 0) { L "  $Service startup: Disabled (sc.exe)" } else { L "  FAILED to disable $Service`: $($_.Exception.Message)"; $failed++ }
    }
    try { Stop-Service -Name $Service -Force -ErrorAction Stop; L "  $Service stopped" }
    catch { L "  stop $Service`: $($_.Exception.Message)" }

    L "--- packages ---"
    # Models and data first, the shared runtime and the session manager last, so nothing is removed while a
    # package that depends on it is still installed.
    $rank = { param($n) if ($n -like '*.Data.*') { 0 } elseif ($n -like '*SessionManager*' -or $n -like '*.Manager.*') { 2 } else { 1 } }
    $pk = Get-Workloads | Sort-Object { & $rank $_.Name }, Name
    foreach ($p in $pk) {
        try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; L "  removed $($p.PackageFullName)" }
        catch { L "  FAILED $($p.PackageFullName): $($_.Exception.Message)"; $failed++ }
    }
    $prov = @(Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $Pattern })
    if ($prov.Count -eq 0) { L "  provisioned: none" }
    foreach ($p in $prov) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction Stop | Out-Null; L "  deprovisioned $($p.PackageName)" }
        catch { L "  FAILED deprovision $($p.PackageName): $($_.Exception.Message)"; $failed++ }
    }

    Start-Sleep -Seconds 5
    Show-State 'after'
    L "failures: $failed"
    exit $(if ($failed) { 1 } else { 0 })
} catch {
    L "FAILED: $($_.Exception.Message)"
    exit 1
}
