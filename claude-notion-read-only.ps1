<#
Claude Code PreToolUse hook: keeps every Notion MCP connection read-only, except for comments.

Needed by: the hooks.PreToolUse entries with matcher ^mcp__.*[Nn]otion.*__ and matcher PowerShell (notion-cli) in
D:\config\claude\settings.json.
Created by Claude on 4 November 2026 at Fiodor's request ("i need notion readonly", then "do both").
Comments were allowed later the same day ("comment notion and add to mcp tools to comment").
It allows only the tools below and refuses every other Notion tool, including tools Notion adds
later: the exact-name deny rules in settings.json cover only the names known when they were written.
Delete this file together with that settings entry when Notion is disconnected for good.

Test: '{"tool_name":"mcp__claude_ai_Notion__notion-create-pages"}' | pwsh -NoProfile -File D:\bin\claude-notion-read-only.ps1
#>
param(
    # Bare tool names (the part after the last "__") that may run; a comma-separated string also works.
    # 11 November 2026: reads moved to notion-cli; only comments stay on the connector, because
    # notion-cli's `comment list` cannot parse the current Notion MCP comment response yet.
    [string[]]$Allow = @('notion-get-comments', 'notion-create-comment')
)

$allowed = @($Allow | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
# notion-cli (11 November 2026): the hooks.PreToolUse entry with matcher PowerShell (if: *notion-cli*) sends
# shell commands here. Its write commands are refused: page create/upload/sync/edit/archive and db create. Reads,
# search, comment list and comment create stay allowed, as with the connector. Flags may sit between the program
# and the subcommand (--profile x). A read that merely mentions "page create" in its arguments is refused too: the
# guard errs on the safe side.
$cliWrite = '(?i)notion-cli(?:\.exe)?["'']?\s(?:[^|;&\r\n]*\s)?(?:page\s+(?:create|upload|sync|edit|archive)|db\s+create)\b'
$tool = ''
try {
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
    $tool = [string]$payload.tool_name
    if ($tool -like 'mcp__*' -and $allowed -ccontains ($tool -split '__')[-1]) { exit 0 }
    if ($tool -in 'PowerShell', 'Bash') {
        $command = [string]$payload.tool_input.command
        if ($command -notmatch $cliWrite) { exit 0 }
        $tool = "the notion-cli write command '$($Matches[0])'"
        $allowed += 'notion-cli search, page list/view, db list/query, comment list/create, auth, tools, version'
    }
} catch {
    # Unreadable hook input: refuse, because the tool cannot be checked.
}
if (-not $tool) { $tool = 'a Notion tool (the hook input had no tool name)' }
$reason = "Notion is read-only on this laptop: $tool was refused by D:\bin\claude-notion-read-only.ps1. " +
    "Allowed Notion tools: $($allowed -join ', ')."
$decision = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason }
[Console]::Out.Write((@{ hookSpecificOutput = $decision } | ConvertTo-Json -Compress -Depth 3))
exit 0
