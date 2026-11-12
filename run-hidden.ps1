# run-hidden.ps1: runs a program for a scheduled task with no window, and hands its exit code to Task Scheduler.
#
# Task action (one line):
#   C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
#       -File D:\bin\run-hidden.ps1 <program.exe> <arguments>
#
# Why conhost: a console program started by Task Scheduler in the desktop session gets a console window.
# "pwsh -WindowStyle Hidden" hides it only after it was shown, and that flash takes the foreground from a full-screen
# game. "conhost --headless" gives the program a console without any window. It replaced the wscript/VBScript wrappers
# (*-hidden.vbs) in November 2026, because Microsoft is retiring VBScript.
#
# Why this script: conhost always exits with 0, so a failed run would look healthy in Task Scheduler. When the program
# fails, this script ends the conhost above it with the program's exit code; that code becomes the task's last result.
# conhost also stays alive until the program ends, so the task's time limit and "do not start a second copy" apply.
#
# <program.exe> must be an executable, not a .ps1: start a script as "pwsh.exe -File script.ps1", so that its exit code
# means what it means on a command line. Works in Windows PowerShell 5.1 and PowerShell 7.
$program, $rest = $args
$rc = 1
try {
    $global:LASTEXITCODE = $null
    & $program @rest
    if ($null -ne $LASTEXITCODE) { $rc = $LASTEXITCODE }
} catch { $rc = 1 }   # the program did not start

if ($rc -ne 0) {
    $me = Get-CimInstance Win32_Process -Filter "ProcessId = $PID"
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId = $($me.ParentProcessId)"
    if ($parent.Name -eq 'conhost.exe') {
        $code = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$rc), 0)
        $null = Invoke-CimMethod -InputObject $parent -MethodName Terminate -Arguments @{ Reason = $code }
    }
}
exit $rc
