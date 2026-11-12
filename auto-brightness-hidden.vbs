' Launches auto-brightness.ps1 with no visible console window.
' Needed because the task must run in the interactive session (dxva2/DDC cannot see
' monitors from session 0), and powershell.exe -WindowStyle Hidden still flashes.
Set sh = CreateObject("WScript.Shell")
' 2026-09-14: wait, and propagate the script's exit code.
' With bWaitOnReturn = False this wrapper returned the instant it launched, so the task's
' LastTaskResult only ever recorded that wscript started - a run that failed outright still
' reported 0x0. It also meant ExecutionTimeLimit and MultipleInstances never applied, because
' Task Scheduler considered the task finished immediately. The per-task limits were raised to
' match real run times before this change; lower them again and a healthy run gets killed.
rc = sh.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""D:\bin\auto-brightness.ps1""", 0, True)
WScript.Quit rc
