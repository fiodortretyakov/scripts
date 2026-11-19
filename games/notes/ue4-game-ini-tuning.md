UE4 games on this laptop are hand-tuned with a consistent playbook (Gothic Remake and System Shock 2023 both follow it): max visuals, spend the spare CPU/RAM/NVMe, never push the weak Adreno GPU. Config lives at `%USERPROFILE%\Saved Games\<Publisher>\<Game>\Saved\Config\WindowsNoEditor\Engine.ini`, not under LOCALAPPDATA.

Three traps, all hit for real:

1. **Engine.ini is deliberately marked read-only** so UE4 can't overwrite the hand-tuning. Edit tools fail with `EPERM ... rename`. Clear it, edit, then **restore the flag** — leaving it writable silently loses the tuning on next launch.

2. **`r.*` console variables only take effect under `[SystemSettings]`.** Put them under `[/Script/Engine.UserInterfaceSettings]` (or any `[/Script/...]` section) and UE4 parses that section for UObject properties only, reads the `r.*` lines and silently discards them. A whole "cinematic realism" block sat dead there for weeks. `ApplicationScale` is the *only* thing that belongs in the UserInterfaceSettings section.

3. **UE4 honours `;` as a comment only at the START of a line.** A trailing comment is absorbed into the value, so `DefaultGraphicsRHI=DefaultGraphicsRHI_DX12   ; kept because…` never matches and the setting does nothing. Always put comments on their own line.

When verifying which keys are actually live, parse section-by-section and treat only lines matching `^\[.+\]$` as headers — splitting the file on a section *name* breaks when that name also appears inside a comment.

Brightness is not settable from Engine.ini in these games; the gamma slider lives in the game's own binary `*Settings.sav`, so it is in-game-menu only. AO (`r.AmbientOcclusionLevels`, `r.AmbientOcclusionRadiusScale`) is the ini-side knob that darkens a scene.

System Shock 2023 specifics, all verified 2026-08-11:

- **There is no look-sensitivity slider anywhere in the game.** `ShockSettings.sav` holds only FOV, brightness, master volume, the quality tiers and the keybind maps. Mouse/gamepad look speed is tunable *only* via `Input.ini` → `[/Script/Engine.InputSettings]` → `+AxisConfig=(AxisKeyName="Gamepad_RightX",AxisProperties=(DeadZone=..,Exponent=..,Sensitivity=..))`. Appended entries win (`UInputSettings` dedupes keeping the last match per axis name), and `AxisProperties` is a whole struct — omit `DeadZone` and it resets to 0 and the stick drifts.
- **FOV IS CLOSED: 120 is a hard ceiling and the 32:9 vertical squeeze is UNFIXABLE. Settled
  2026-08-11 by a clean single-variable test — do not reopen this.** The game cooks
  `AspectRatioAxisConstraint=AspectRatio_MaintainXFOV` (found by streaming a plain ASCII scan of
  `SystemShock-Windows.pak`, hit at offset 12,689,158 — the exe only carries the enum *names* as
  UObject metadata, so searching the exe proves nothing about the value). That pins the slider to
  the HORIZONTAL axis, so at 5120x1440 the vertical is only `2*atan(tan(60)/3.5556) = 51.9`
  degrees where a 16:9 player gets 88.5.
  Setting `AspectRatioAxisConstraint=AspectRatio_MaintainYFOV` under `[/Script/Engine.LocalPlayer]`
  in the user Engine.ini **is INERT** — verified with `RealspaceFOV` left at 120 as the only
  variable, which produced no visible change at all. Had it applied,
  the view would have gone to 161h/120v, unmissable. So `ULocalPlayer` does not read this property
  from the user config here; Nightdive set the constraint in code.
  **Nexus has no FOV or aspect mod either — all 110 mods for this game were enumerated and
  checked.** So there is no route left: slider max 120, and that's it.
  **Procedural lesson, the real takeaway:** attempt 1 changed the constraint AND `RealspaceFOV=65`
  AND `CyberspaceFOV=60` together, came back "doesn't work", and was uninterpretable — it cost a
  second launch to redo as one variable. That violated the one-change-per-launch rule
  recorded in this file. When a knob's effect is unknown, change exactly one thing and
  pick the value that makes the two outcomes maximally distinguishable.
  (Geometry note: at fixed aspect the FOV is a single free parameter — MaintainX@120 and
  MaintainY@51.9 are the identical projection — so the constraint flip was never worth anything on
  its own; its only value would have been unlocking the >120 range.)
- `CyberspaceFOV` is a **separate** float in `ShockSettings.sav`, default 89, and it is horizontal
  too — so cyberspace runs at ~31 degrees vertical on 32:9, in the game's only 6DOF free-flight
  section. Left at 89. It is the one FOV value still worth raising if motion sickness
  comes up again.
- **FOV lives in `ShockSettings.sav` as `RealspaceFOV` and `CyberspaceFOV` FloatProperties** and
  is safely patchable in place — same-width float overwrite, file size unchanged. Layout after
  the name string is: `\0` + 4-byte len + `FloatProperty\0` + int64 size + 1 guid byte + float.
  Set to 65 / 60 on 2026-08-11. Cyberspace was the worse offender: 89 horizontal meant **31
  degrees vertical**, in the game's only 6DOF free-flight section.
- **`t.MaxFPS` is REGISTERED but INERT in this game — do not cite it as a stability mechanism.**
  Proven 2026-08-11: at `r.ScreenPercentage=52` the ini predicted "~36 avg uncapped" and measured exactly 36 with `t.MaxFPS=30` present. Nightdive run their own settings system
  (`ShockSettings.sav`, not `UGameUserSettings`), and `IConsoleVariable::Set` defaults to
  `ECVF_SetByCode`, which outranks `SetBySystemSettingsIni`. So their code wins and the ini
  cap never binds.
- **`-ExecCmds=` is stripped from the shipping exe**, so there is no way to auto-run `stat fps` (or any console command) at startup from a launch option. `STAT_FPS` *is* still compiled in, so `stat fps` / `stat unit` work if the console opens.
- The FPS-counter route is therefore the **Steam overlay** (Properties → General, plus Settings → In Game → FPS counter). The overlay is off for appid 482400 by default here, and the game runs `FullscreenMode=0` (exclusive), where pinned Xbox Game Bar widgets will not draw.
- The exe is legitimately named `SystemReShock-Win64-Shipping.exe`. That is Nightdive's pun, not a ReShade install.
- Verify any candidate cvar before adding it by string-searching the exe **as UTF-16** — cvar names are wide strings there, so an ASCII-only search reports every one of them as missing.
- **DX12 only, no DX11.** Settled 2026-08-11. `DefaultGraphicsRHI=DefaultGraphicsRHI_DX12` stays put in every game; it also unlocks the D3D12 driver-optimized PSO disk cache. If framerate needs to move, spend `r.ScreenPercentage` or detail knobs.
- **Never trade fps for input latency here.** `r.OneFrameThreadLag=0` was proposed and applied on 2026-08-11 (37 ms of latency at 27 fps) and it was reverted immediately. Framerate wins over latency, and over any knob that "might" cost frames.
- **Engine HDR is a DEAD END in System Shock 2023 — use Windows Auto HDR. Tested 2026-08-11, do not retry.** Forcing `r.AllowHDR=1` + `r.HDR.EnableHDROutput=1` + `OutputDevice=3` (ACES 1000-nit PQ) + `ColorGamut=1` made the *scene* look great and cost no fps, but left the **HUD unreadable**. `r.HDR.UI.Level=1.0 → 3.0` changed nothing at all, which proves the HUD never enters UE4's HDR UI composite path — the game draws UI into the scene and it gets tonemapped. **No `r.HDR.UI.*` cvar can fix that**, and Nightdive shipped no HDR menu option, so the path was never wired up. Auto HDR cannot have this bug: the OS expands a finished SDR frame, so the UI keeps SDR reference brightness.
- For any UE4 game with no in-menu HDR toggle, assume the HDR UI composite path is unwired and reach for Auto HDR first. The tell is `r.HDR.UI.Level` having zero visible effect.
- **Pick exactly one of: engine HDR, Windows Auto HDR, Auto SR.** All three conflict pairwise. Engine HDR is the best of them; keep the game in **exclusive Fullscreen** (not borderless) for it, and the upscaler is UE4's own **TAAU** (`r.TemporalAA.Upsampling=1` + `r.ScreenPercentage`) since no DLSS/FSR path exists on Adreno.
- **Auto SR is useless for these games.** It only engages when the game presents *below* the display resolution, and it needs borderless. At native presentation it is inert no matter what the toggle says.
- Tuning is by measured framerate, one change per launch. Bundling many changes at once (as happened on 2026-08-11) leaves individual lines undefendable — `r.HZBOcclusion=1` is still unmeasured for that reason.
