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
| `sweeps/remove-windows-ai-workloads.ps1` | Switches the Windows AI runtime off and removes its model packages. |
| `sweeps/remove-extra-local-users.ps1` | Removes every extra local account with its profile and scheduled tasks. |
| `sweeps/fix-winget-daily-wsl-update.ps1` | Lets a daily winget task keep WSL up to date under Administrator protection. |
| `sweeps/test-home-latency.ps1` | Measures latency to the Wi-Fi point, the mesh root and the internet, optionally under load. |
| `sweeps/set-vulkan-native-driver.ps1` | Makes Vulkan programs use the native Qualcomm driver instead of the Direct3D 12 translation layer. |
| `sweeps/enable-game-bar-recording.ps1` | Turns Game Bar recording back on (machine policy and user keys). |
| `sweeps/restore-xbox.ps1` | Restores the Xbox parts that Microsoft Store games need: sign-in, cloud saves, multiplayer, Game Bar. |
| `sweeps/prepare-games-2026-11-06.ps1` | Prepares the laptop for four games (everything except Steam and the games themselves). |
| `sweeps/uninstall-epic-games-launcher.ps1` | Uninstalls the Epic Games Launcher and what its uninstaller leaves behind. |
| `sweeps/remove-epic-uninstall-keys.ps1` | Removes only the "Installed apps" registry entries of the Epic Games Launcher. |

## Claude Code
| Script | What it does |
|---|---|
| `claude-subagent-model.ps1` | PreToolUse hook: refuses a subagent call that does not name its model and effort, so Claude picks both for each task. Setup in the script header. |
| `claude-notion-read-only.ps1` | PreToolUse hook: keeps every Notion MCP connection read-only, except for comments. |
| `claude/plugins/` | Local plugin marketplace with `gopls-tuned` and `pwsh-tuned`: the Go and PowerShell language servers with the style analyzers off. |
| `claude/output-styles/concise-correct.md` | Output style: short answers in full, correct sentences. |
| `sweeps/set-claude-effort-default.ps1` | Removes the machine variable that overrides the effort level of `settings.json`. |

## Games
| Script | What it does |
|---|---|
| `tunic_aspect.py` | TUNIC at 32:9: patches the aspect-ratio code sites in `GameAssembly.dll` (keeps a vanilla backup). |
| `risen_hud_center.py` | Risen (2023 64-bit): keeps the 16:9 HUD centred and undistorted on a wider screen. |
| `risen_focus_text_fix.py` | Risen: correct shape and size of the focus labels and marker on 32:9. |
| `games/risen-mod-combo/` | Builds one Risen template pack from several mods (templates, monster and sprint tweaks). |
| `games/gothic-1-remake/g1r_ue4ss_rename.py` | Gothic 1 Remake 1.1: loads UE4SS as `RE4SS.dll` so the game does not block it. |
| `games/gothic-1-remake/FocusNearbyPickups-ue4ss-shim-main.lua` | Runs the "Highlight All Nearby Items" mod under UE4SS. |
| `melonloader-portable-net6.ps1` | Gives MelonLoader games a private .NET 6 runtime so the machine-wide one can be removed. |
| `games/notes/` | Notes per game: ultrawide patches, Unreal Engine 4 `ini` tuning, GPU preference per game, troubleshooting. |
| `games/settings/` | The settings files in use (Gothic 1 Remake, Overcooked, Risen, System Shock), Steam launch options and the per-game GPU preferences. |

The Overcooked! All You Can Eat ultrawide mod lives in its own repository:
[OvercookedAYCE-Ultrawide-Mod](https://github.com/fiodortretyakov/OvercookedAYCE-Ultrawide-Mod).

Game patches change the game's own files; Steam's "verify integrity" or a game update undoes them, and running the
script again re-applies them.

## License
MIT, see [LICENSE](LICENSE).
