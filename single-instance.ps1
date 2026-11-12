<#
Single-instance lock for the scheduled helper scripts. Dot-source it, then:

    . "$PSScriptRoot\single-instance.ps1"
    if (-not (Enter-SingleInstance 'auto-brightness')) { return }

Why this exists (2026-08-21): the tasks were launched through a hidden wrapper that did not
wait for the script. The Task Scheduler therefore saw the task finish at once, so
**`MultipleInstances IgnoreNew` did not apply to the PowerShell process at all**. The launcher
waits now (`run-hidden.ps1`), but a script that is still running after its task was stopped at
the time limit is not tracked either, so the lock stays.

That is harmless while each run takes ~1 s. It stopped being harmless when the first-ever
Defender full scan started: `hdr-auto` (1/min, deleted 2026-09-08) and `auto-brightness`
(1/2 min) stopped
completing, kept being launched, and **27 orphaned processes accumulated in 31 minutes**,
driving the run queue past 130 on a 12-core box. The pile-up then made everything else on the
machine slower, which is exactly the interruption these tasks are supposed to avoid.

A missed run costs one minute here, so exiting immediately is always the right answer -
never wait for the lock.
#>

# Held for the life of the process. Must stay referenced or the GC releases the mutex early.
$script:SingleInstanceMutexes = @()

function Enter-SingleInstance {
  param([Parameter(Mandatory)][string]$Name)

  # Local\ rather than Global\: these are per-user helpers and Global\ needs privileges the
  # Limited-runlevel tasks do not have.
  $m = New-Object System.Threading.Mutex($false, "Local\fiodo-helper-$Name")
  try {
    # AbandonedMutexException means a previous holder died without releasing - we now own it.
    $got = $m.WaitOne(0)
  }
  catch [System.Threading.AbandonedMutexException] { $got = $true }
  catch { return $true }   # Never let the lock itself be the reason a helper stops working.

  if ($got) { $script:SingleInstanceMutexes += $m; return $true }
  $m.Dispose()
  $false
}
