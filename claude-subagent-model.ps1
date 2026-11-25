<#
Claude Code PreToolUse hook: every subagent call must name its model and effort, chosen by Claude for the task.

The model choice belongs to Claude, guided by a rule in CLAUDE.md (which model and effort for which kind of work).
This hook only refuses a call that omits either one or names a model outside -Allow, so the rule cannot be skipped.
Forks are exempt from the model check: they always run on the parent model and effort.
It also refuses every subagent, forks included, while available memory is under -MinAvailableGB (default 8).
It rewrites nothing on purpose: in auto mode the classifier refuses a call whose input a hook changed (Claude Code
2.1.325), while a refusal from this hook just costs one round trip.

Setup, in the Claude Code user settings.json:
  "hooks": { "PreToolUse": [ { "matcher": "Agent|Task", "hooks": [ { "type": "command",
    "command": "pwsh",
    "args": ["-NoLogo", "-NoProfile", "-NonInteractive", "-File", "D:\\bin\\claude-subagent-model.ps1"],
    "timeout": 15 } ] } ] }
and a CLAUDE.md line such as: "Every Agent call names model and effort: haiku low for lookups; sonnet low or medium
for log reading and mechanical edits; opus medium or high for implementation and reviews; fable high for the hardest
work." The Agent tool sets effort only when instructions ask for it, so the CLAUDE.md line is required.

Test: '{"tool_name":"Agent","tool_input":{"description":"x","prompt":"y","model":"sonnet"}}' | pwsh -NoProfile -File D:\bin\claude-subagent-model.ps1
#>
param(
    # Models Claude may pick for a subagent; a comma-separated string also works.
    [string[]]$Allow = @('fable', 'opus', 'sonnet', 'haiku'),
    # Available memory (GB) a new subagent needs; 0 turns the check off.
    [double]$MinAvailableGB = 8
)

$allowed = @($Allow | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
try {
    $toolInput = ([Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop).tool_input
} catch {
    exit 0  # Unreadable hook input: leave the call alone.
}
if ($null -eq $toolInput) { exit 0 }

# Memory floor for every new subagent, forks included (freezes of 14, 17 and 25 November 2026).
try {
    $availableGB = [math]::Round((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1MB, 1)
} catch {
    $availableGB = $MinAvailableGB  # Counter unreadable: do not block.
}
if ($MinAvailableGB -gt 0 -and $availableGB -lt $MinAvailableGB) {
    $reason = "Subagent call refused by D:\bin\claude-subagent-model.ps1: $availableGB GB available, under the " +
        "$MinAvailableGB GB floor that prevents laptop freezes. Do not work around it: tell him the number and ask " +
        "him to close idle Claude sessions or reboot; do the work in this session or wait."
    $decision = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason }
    [Console]::Out.Write((@{ hookSpecificOutput = $decision } | ConvertTo-Json -Compress -Depth 3))
    exit 0
}
if ([string]$toolInput.subagent_type -eq 'fork') { exit 0 }

$model = [string]$toolInput.model
$problems = @()
if (-not $model) { $problems += 'no model' }
elseif ($allowed -notcontains $model) { $problems += "model '$model' is not one of $($allowed -join ', ')" }
if (-not $toolInput.effort) { $problems += 'no effort' }
if (-not $problems) { exit 0 }

$reason = "Subagent call refused by D:\bin\claude-subagent-model.ps1: $($problems -join ' and '). Issue it again " +
    "with model ($($allowed -join ', ')) and effort (low, medium, high, xhigh, max) chosen for this task at the " +
    "fewest tokens: haiku low for pure lookups and searches; sonnet low/medium for log reading, summaries and " +
    "mechanical edits; opus medium/high for implementation, tests and reviews; fable high for the hardest work."
$decision = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason }
[Console]::Out.Write((@{ hookSpecificOutput = $decision } | ConvertTo-Json -Compress -Depth 3))
exit 0
