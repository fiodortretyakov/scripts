# scripts

Personal scripts for a Windows 11 ARM64 laptop (Snapdragon X Elite) with a Samsung Odyssey G95NC (5120x1440), and
fixes for games played on that screen. They are written for this machine: paths such as `D:\config` and the Steam
library location are set at the top of each script.

## Display and machine
| Script | What it does |
|---|---|
| `auto-brightness.ps1` | Sets the G95NC brightness over DDC/CI from the laptop's ambient light sensor (smoothed, with a calibration curve). Windows PowerShell 5.1. |
| `auto-brightness-hidden.vbs` | Runs `auto-brightness.ps1` from Task Scheduler without a window. |
| `screen-dim.ps1` | Software dimming per display through the GDI gamma ramp. |
| `pc.ps1` | One entry point for the above: status, display profiles, charger health, scheduled tasks. |
| `netusage-hourly.ps1` | Network usage per app and per hour from the Windows data-usage store. Windows PowerShell 5.1. |
| `single-instance.ps1` | Lock helper so a scheduled script never runs twice at once. |
| `python3.bat` | `python3` shim for cmd and PowerShell. |
| `ide-reload-extension/` | VS Code extension that reloads the window when `auto-brightness.ps1` requests it. |

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

The Overcooked! All You Can Eat ultrawide mod lives in its own repository:
[OvercookedAYCE-Ultrawide-Mod](https://github.com/fiodortretyakov/OvercookedAYCE-Ultrawide-Mod).

Game patches change the game's own files; Steam's "verify integrity" or a game update undoes them, and running the
script again re-applies them.

## License
MIT, see [LICENSE](LICENSE).
