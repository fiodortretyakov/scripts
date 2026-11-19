# Starts PowerShellEditorServices in stdio mode for Claude Code (plugin pwsh-tuned@local).
# PSES and PSScriptAnalyzer come from the newest VS Code PowerShell extension (ms-vscode.powershell), resolved at
# every start so extension updates keep working. Logs: %LOCALAPPDATA%\pwsh-tuned\logs\<start time>-<PID>, kept 7 days.
$ErrorActionPreference = 'Stop'

$extensionsRoot = Join-Path $env:USERPROFILE '.vscode\extensions'
$extension = Get-ChildItem -LiteralPath $extensionsRoot -Directory -Filter 'ms-vscode.powershell-*' |
    Where-Object { $_.Name -match '^ms-vscode\.powershell-\d+\.\d+\.\d+$' } |
    Sort-Object { [version]($_.Name -replace '^ms-vscode\.powershell-', '') } -Descending |
    Select-Object -First 1
if (-not $extension) {
    [Console]::Error.WriteLine("pwsh-tuned: no ms-vscode.powershell-* folder under $extensionsRoot")
    exit 1
}
$modulesPath = Join-Path $extension.FullName 'modules'

$logsRoot = Join-Path $env:LOCALAPPDATA 'pwsh-tuned\logs'
Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction Ignore |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Recurse -Force -ErrorAction Ignore
$logPath = Join-Path $logsRoot ('{0:yyyyMMdd-HHmmss}-{1}' -f (Get-Date), $PID)
New-Item -ItemType Directory -Force -Path $logPath | Out-Null

& (Join-Path $modulesPath 'PowerShellEditorServices\Start-EditorServices.ps1') `
    -HostName 'Claude Code' -HostProfileId 'Claude.Code' -HostVersion '1.0.0' `
    -BundledModulesPath $modulesPath -LogPath $logPath -LogLevel Warning `
    -SessionDetailsPath (Join-Path $logPath 'session.json') `
    -FeatureFlags @() -AdditionalModules @() -LanguageServiceOnly -Stdio
