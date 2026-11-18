<#
Claude Code PreToolUse hook: every subagent call must name its model and effort, chosen by Claude for the task.

The model choice belongs to Claude, guided by a rule in CLAUDE.md (which model and effort for which kind of work).
This hook only refuses a call that omits either one or names a model outside -Allow, so the rule cannot be skipped.
Forks are exempt: they always run on the parent model and effort.
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
    [string[]]$Allow = @('fable', 'opus', 'sonnet', 'haiku')
)

$allowed = @($Allow | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
try {
    $toolInput = ([Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop).tool_input
} catch {
    exit 0  # Unreadable hook input: leave the call alone.
}
if ($null -eq $toolInput -or [string]$toolInput.subagent_type -eq 'fork') { exit 0 }

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
