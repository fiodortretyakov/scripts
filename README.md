# scripts

Personal scripts for a Windows 11 ARM64 laptop (Snapdragon X Elite) with a Samsung Odyssey G95NC (5120x1440), and
fixes for games played on that screen. They are written for this machine: paths such as `D:\config` and the Steam
library location are set at the top of each script.

## Display and machine
| Script | What it does |
|---|---|
| `auto-brightness.ps1` | Sets the G95NC brightness over DDC/CI from the laptop's ambient light sensor (smoothed, with a calibration curve). Windows PowerShell 5.1. |
| `run-hidden.ps1` | Runs a program from Task Scheduler with no window (`conhost --headless`) and passes its exit code on. |
| `screen-dim.ps1` | Software dimming per display through the GDI gamma ramp. |
| `pc.ps1` | One entry point for the above: status, display profiles, charger health, scheduled tasks. |
| `netusage-hourly.ps1` | Network usage per app and per hour from the Windows data-usage store. Windows PowerShell 5.1. |
| `single-instance.ps1` | Lock helper so a scheduled script never runs twice at once. |
| `python3.bat` | `python3` shim for cmd and PowerShell. |
| `ide-reload-extension/` | VS Code extension that reloads the window when `auto-brightness.ps1` requests it. |
| `code-workspace.ps1` | Builds one VS Code workspace file: a main folder first, then every git repository under a second folder. Dry run by default. |

## One-off machine changes
The header of each script says what it changes and how to run it.

| Script | What it does |
|---|---|
| `sweeps/clean-temp.ps1` | Deletes temp files that nothing can still use. |
| `sweeps/set-build-priority.ps1` | Makes the Go toolchain and Java yield CPU, disk and memory to the foreground (IFEO `PerfOptions`). |
| `sweeps/test-home-latency.ps1` | Measures latency to the Wi-Fi point, the mesh root and the internet, optionally under load. |

## Claude Code
| Script | What it does |
|---|---|
| `claude-subagent-model.ps1` | PreToolUse hook: refuses a subagent call that does not name its model and effort, so Claude picks both for each task. Setup in the script header. |
| `claude-notion-read-only.ps1` | PreToolUse hook: keeps every Notion MCP connection read-only, except for comments. |
| `claude/plugins/` | Local plugin marketplace with `gopls-tuned` and `pwsh-tuned`: the Go and PowerShell language servers with the style analyzers off. |
| `claude/output-styles/concise-correct.md` | Output style: short answers in full, correct sentences. |

## Games
| Script | What it does |
|---|---|
| `games/notes/` | General notes: Unreal Engine 4 `ini` tuning, GPU preference per game, auditing Nexus mods. |

The Overcooked! All You Can Eat ultrawide mod lives in its own repository:
[OvercookedAYCE-Ultrawide-Mod](https://github.com/fiodortretyakov/OvercookedAYCE-Ultrawide-Mod).

Game patches change the game's own files; Steam's "verify integrity" or a game update undoes them, and running the
script again re-applies them.

## License
MIT, see [LICENSE](LICENSE).
