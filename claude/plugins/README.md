# Local Claude Code plugins

Plugins in this folder are read from here directly: edits take effect at the next session start. Marketplace:
`.claude-plugin\marketplace.json` (name `local`).

## gopls-tuned

Why: the official `gopls-lsp@claude-plugins-official` plugin takes no settings, so it cannot pass
build tags, a memory limit or analyzer choices to gopls. `gopls-tuned` replaces it (the official one was uninstalled
on 14 November 2026).

- `buildFlags: -tags=testing`: 61 files of one large Go module carry `//go:build testing`; without the tag gopls
  cannot see them (no references, no diagnostics).
- `GOMEMLIMIT=2GiB` for gopls only: measured peak 2.0 GB without it, 1.3 GB with it (the same module, 14 November 2026).
  Not set in Claude's settings `env`, because that would also limit the Go linker.
- `analyses`: 68 of the 161 default analyzers are off: staticcheck `QF*` and `S1*`, the modernizers (`any`, `minmax`,
  `rangeint`, `stringscut`, ...), `writestring`, `unusedparams`, `unusedfunc`, `deprecated`, `infertypeargs`, `inline`.
  They only suggest style or newer syntax, and their warnings on untouched lines reached Claude after every edit.
  Bug finders stay on: staticcheck `SA*`, `printf`, `copylocks`, `lostcancel`, `nilness`, `unusedwrite`,
  `scannererr`, `hostport`, `appends`, `yield`. The list of defaults: `gopls api-json` (`Analyzers[].Default`).
- gopls checks Go files outside the session folder (for example upstream clones in `D:\data\sweeps`) in an ad hoc view
  without their module, so it reports false "could not import" errors there. Ignore those; `go build` in the
  clone is the check.

gopls itself: `go install golang.org/x/tools/gopls@latest` (lands in `D:\caches\gopath\bin`, on PATH).
Remove: `claude plugin uninstall gopls-tuned@local`, delete its entry in `.claude-plugin\marketplace.json` and the
`gopls-tuned` folder, then `claude plugin install gopls-lsp@claude-plugins-official`. When no plugin is left
here: `claude plugin marketplace remove local` and delete this folder.

## pwsh-tuned

Why: PowerShell is the second most edited language in Claude sessions. PowerShellEditorServices (PSES) reports parse
errors right after an edit and gives symbols, hover, definitions and references. No marketplace plugin exists.

- Source: the VS Code PowerShell extension `ms-vscode.powershell` (Microsoft-signed, updated by VS Code), which
  bundles PSES and PSScriptAnalyzer. `start-pses.ps1` starts PSES in stdio mode from the newest
  `ms-vscode.powershell-*` folder under `%USERPROFILE%\.vscode\extensions`, resolved at every start, so extension
  updates need nothing here. Logs: `%LOCALAPPDATA%\pwsh-tuned\logs`, one folder per server, deleted after 7 days.
- VS Code user settings: `"powershell.startAutomatically": false`, so VS Code does not start its own copy (about
  200 MB) whenever a .ps1 file opens. While a VS Code copy runs, its warnings also reach Claude as IDE diagnostics.
- `PSScriptAnalyzerSettings.psd1`: only the Error-severity rules, listed by name, because PSES passes its own
  `-Severity` that overrides a `Severity` key. Warnings would reach Claude after every edit and cost tokens.
  Parse errors come from the PowerShell parser and are always reported.
- `analyzeOpenDocumentsOnly: true`: references are searched only in files the session has opened. Without it,
  PSES scans every .ps1 file under the session folder: a findReferences from a folder with many repositories took 33.6 seconds and
  raised the peak working set from 156 MB to 288 MB.
- `enableProfileLoading: false`: PSES loads PowerShell profiles in its own runspace by default; `-NoProfile` on
  pwsh does not stop that.

Measured on 14 November 2026 (headless Haiku sessions from that folder): the server starts at the first .ps1 file
a session touches, initializes in 2.3 to 3.2 seconds, and peaks at 151 to 159 MB working set (52 to 57 MB
private) with documentSymbol on four scripts in `D:\bin` (up to 48 KB), hover, findReferences and an edit.

Remove: `claude plugin uninstall pwsh-tuned@local`, delete its entry in `.claude-plugin\marketplace.json` and the
`pwsh-tuned` folder, delete `%LOCALAPPDATA%\pwsh-tuned`. If the extension is no longer wanted either:
`code --uninstall-extension ms-vscode.powershell` and remove `powershell.startAutomatically` from
`D:\config\vscode\appdata\Code\User\settings.json`.
