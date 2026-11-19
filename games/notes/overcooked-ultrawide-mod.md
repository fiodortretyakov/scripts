**Game:** Steam app 1243830, Unity 2019.4.11f1 IL2CPP, MelonLoader 0.7.3 on the .NET 6 x64 runtime in
`D:\games\dotnet6-x64` (moved 8 October 2026; `UserData\Loader.cfg` `hostfxr_path_override` follows since 14 October). Runs at 5120x1440 borderless (PlayerPrefs under
`HKCU\Software\Team17\Overcooked All You Can Eat`; the game asks for 3840x2160 and the mod rewrites it).

**Source and build:** `%USERPROFILE%\src\ayce-ultrawide` (`UltrawideMod.cs`, `AyceUltrawide.csproj` referencing
the game's `MelonLoader\net6\*` and `MelonLoader\Il2CppAssemblies\*` including `Assembly-CSharp`). Build with
`dotnet build -c Release` (SDK 10.0.401 since 2 October 2026; SDK 8 and the .NET 9 runtime were removed, a scratch copy of the v3.13.0 source built with 0 warnings). Deploy = copy `bin\Release\OvercookedAYCE_Ultrawide_Mod.{dll,pdb,deps.json}`
into the game's `Mods\`. Rollbacks sit next to the source: `v3.4.0\` and `v1-original\`. Never two mod DLLs in
`Mods\`, they fight over the same preferences category. Preferences: `UserData\MelonPreferences.cfg`
(`ResetCameraAspect` is the switch for everything below).

**The squashed-icons defect (found 29 September 2026 from `MelonLoader\Latest.log`):** the game's own
`Il2Cpp.FixedAspectRatioManager.LateUpdate`, `Il2Cpp.FixedAspectRatioCamera.SetCameraAspectRatio(Rect)` and
`Il2Cpp.OrthoCameraResizer.Update` re-pin the level cameras 'Camera' and 'ParticleCamera' to aspect 6.857 every
frame on a 3.556 viewport, so everything they draw is squeezed to 52 % width. v3.4.0 reset the aspect only four
times a second and only for 8 s after a scene load (58 "(was pinned)" lines in one level), so the game won.

**v3.5.0 fix:** a Harmony prefix on `Camera.set_aspect` rewrites any pin to `pixelWidth / pixelHeight` before
Unity applies it (same preventive pattern as the `Screen.SetResolution` prefix); postfixes on the three game
methods above reset anything that slipped past the detour. Log lines: `aspect pin '<camera>' 6.857 -> 3.556
rewritten ...` (max three per camera, each with ortho/mask/rect/viewport/target texture), and at quit
`aspect pins rewritten: N (setter patch on), aspect guard corrections: M`.

**Why:** the mod's sweep printed the aspect after `ResetAspect()` and it still read 6.857, four times a second,
for the whole window. Only a per-frame re-pin or a render-texture target explains that; the metadata of
`Assembly-CSharp.dll` (read with System.Reflection.Metadata, no launch) named the per-frame classes.

**How to apply:** after a play session read
`MelonLoader\Latest.log` (older runs in `MelonLoader\Logs\`). Expect `patched Camera.set_aspect`,
`game-class fallback hooks: 3 of 3`, `aspect pin 'Camera' 6.857 -> 3.556 rewritten` and no `(was pinned)` line.
If a line says `target RT '...'`, that camera draws into a texture of that shape, the pin is legitimate and the
squash has another cause. His in-game check of v3.5.0 is pending as of 29 September 2026, 11:30.

**29 September 2026, 12:20 — v3.5.0 FAILED and was REVERTED to v3.4.0 (sha256 d37bf041...).** His run: icons still
squashed AND he could not pick anything up. Latest.log: `aspect pins rewritten: 0, aspect guard corrections: 0`, so
the per-frame-pin diagnosis was wrong; the squash has another cause. The postfixes on the game's own
FixedAspectRatio*/OrthoCameraResizer methods are the likely cause of the broken pickup: never hook those again.
Source in UltrawideMod.cs is still v3.5.0; the deployed DLL is v3.4.0. Do nothing more until he asks.

**29 September 2026, ~12:45 — v3.6.0 DEPLOYED (v3.4.0 + UI retarget; rollback = copy `v3.4.0\*` into `Mods\`).** Root
cause found from metadata: the game's UI goes through `Il2Cpp.FixedAspectRatioManager` (`m_aspectRatio` Vector2 16:9,
`m_correctedRect`, `m_screenWidth`) and `FixedAspectRatio.DefaultAspect`; the mod widens the world to 32:9 but the UI
still lays out for a 16:9 box (HoverIconCanvas 1357.6 wide inside a 2715.3 root), so icons are half width. v3.6.0
writes 5120:1440 into both values and sets `m_screenWidth = -1` to force a re-layout; field writes only, no Harmony
hook on any game method. Switch `MatchUiAspect`. Expect `UI aspect '<name>' (16.0, 9.0) -> (5120.0, 1440.0)` in
Latest.log and HoverIconCanvas rect ~2715 wide in the next CANVAS DUMP. Risk to check: HUD elements stretched wide.

**29 September 2026 — v3.6.0 REVERTED to v3.4.0 at his request:** retargeting the UI manager to 32:9 made ALL UI far
too big (the whole HUD scales with the aspect). Do not retarget FixedAspectRatioManager globally again; a future fix
must touch only the hover icons. Deployed = v3.4.0 (d37bf041...).

**29 September 2026 — v3.7.0 DEPLOYED (rollback = copy `v3.4.0\*` into `Mods\`).** v3.4.0 plus a hover-icon-only fix:
under canvases named `HoverIconCanvas`, any RectTransform whose localScale.x/y equals (16/9)/(screen aspect) = 0.5 gets
x set to y, applied in `Canvas.willRenderCanvases` (fallback OnLateUpdate). No game-method hooks, no global UI change.
Switch `FixHoverIconAspect`. Latest.log: `hover icon '<name>' localScale ...` lines and a `HOVER ICON DUMP` per level
(size, local/lossy scale, components). If the fix count at quit is 0, the squash is not in localScale: read the dump.

**29 September 2026 — v3.7.0 REVERTED to v3.4.0 at his request ("bad").** Log excerpt saved at `src\ayce-ultrawide\v3.7.0-run.log`. Deployed = v3.4.0 (d37bf041...). Three fixes failed today; do not attempt another unless he asks.

**29 September 2026 — v3.8.0 DEPLOYED at his request (rollback = copy `v3.4.0\*` into `Mods\`).** The v3.7.0 dump
located the squash: `TutorialIconUI(Clone)` (the "+" ring prompts; RectTransformExtension + HoverIconUIController +
Animator) under HoverIconCanvas is laid out 18.3x55.0 with children `Arrrow` and `Icon` at 18.3x27.5, so width is
2/3 of the square design; localScale is (1,1,1), which is why v3.7.0 fixed 0. v3.8.0 sets TutorialIconUI
localScale.x = localScale.y * height/(2*width) (= 1.5) in Canvas.willRenderCanvases. Log: `hover icon
'TutorialIconUI(Clone)' 18.3x55.0 widened x1.500`, quit line `hover icon scale fixes: N`.

**29 September 2026 — v3.8.0 result: rings wider but "still a little squashed and in wrong places, should be near the
pots".** Model: HoverIconCanvas is a centred 16:9 box (1357.6 wide in a 2715.3 root) and the game maps icons into it
as if it spanned the screen, halving x positions about the centre and widths. v3.9.0 DEPLOYED: drops the 1.5 widening
and sets HoverIconCanvas localScale.x = (screen aspect / box aspect) * localScale.y (= 2.0) in willRenderCanvases.
Log: `HoverIconCanvas ... stretched x2.000` plus `icon at <pos>, follow '<obj>' projects to <screen pos>` lines to
compare placement. Rollback = `v3.4.0\*`.

**29 September 2026 — v3.9.0 result: rings ROUND (shape fixed) but all icons too far left.** Comparing his v3.8.0 and
v3.9.0 screenshots: every icon shifted left by the same amount and icon spacing stayed HALF the pot spacing, so the
canvas stretch only resizes; the game places icons itself at half the true distance from the centre. v3.10.0
DEPLOYED: keeps the x2 HoverIconCanvas stretch and, in willRenderCanvases, sets each HoverIconUIController's
position.x = Camera.main.WorldToScreenPoint(m_followTransform.position + m_followOffset).x (y stays the game's).
Log: `hover icon '<name>' on '<object>' x A -> B`, quit line `icon placements: N`. Rollback = `v3.4.0\*`.

**29 September 2026 — v3.10.0 result: icons now too far RIGHT.** Log: every read of the icon's rt.position was
(0,0,0) and 11,690 writes were needed, so RectTransformExtension re-drives the icon through anchors each frame and a
position write is the wrong lever. Icons follow e.g. 'FireExtinguisher 1' and 'MultiControlTerminal_02', not only
pots. v3.11.0 DEPLOYED = v3.9.0 shape fix + a READ-ONLY `ICON PROBE` (GetScreenPos, anchors, RTE fixed anchors and
offsets, drawn centre, and every camera's WorldToScreenPoint of the followed object). Next step: compute the mapping
from the probe; hypothesis is that the game projects through a camera whose aspect is pinned (6.857 seen earlier).

**29 September 2026 — v3.11.0 probe (saved `src\ayce-ultrawide\v3.11.0-probe.log`):** HoverIconCanvas 1920x1080
stretched x2 spans 0..5120. `HoverIconUIController.GetScreenPos()` returns viewport coords that EQUAL Camera.main
('Camera', aspect 3.556, full rect) projection / screen size, so the game's target is right. The TutorialIconUI root
stays at the canvas corner (localPos -960,-540, anchors x 0; RTE PreserveVerticalAnchors); the ring is drawn through
its children. v3.12.0 DEPLOYED: each frame in willRenderCanvases, measure the drawn x extent of all the icon's rects and
move the root by (object x - drawn centre x); log `align '<icon>' on '<object>': drawn x A..B, object x C, moved D`.

**29 September 2026 — v3.12.0 result: icons still off, now ~1.5x the pot x.** Log: drawn extent -35..35 EVERY frame =
at willRenderCanvases the root is at world x 0 and the game places the icon later. The "+" icons DO follow the pots
(his screenshot pattern matches the pots; the probe's first 3 icons were extinguisher/terminal/sink). Screenshot fit:
game-drawn x ~= k * object x, k = (16/9)/aspect = 0.5, measured from the LEFT screen edge. v3.13.0 DEPLOYED: root
position.x = (1 - k) * object x (absolute); probe widened to 8 icons.

**29 September 2026 — v3.13.0 CONFIRMED by him ("all amazing"): "+" rings round and on the pots. PINNED at
`src\ayce-ultrawide\v3.13.0\` (dll sha256 d12545a2..., source as UltrawideMod.cs.txt so the build ignores it).** Only defect left: the terminal's lettered
"A" button prompt is twice too wide (it never needed the canvas x2). v3.14.0 DEPLOYED: every direct child of
HoverIconCanvas except `TutorialIconUI*` gets localScale.x = localScale.y / k (log `unstretch '<name>'`). Rollback
order: `v3.13.0\*` (known good), then `v3.4.0\*`.

**29 September 2026 — v3.14.0 FAILED, rolled back to v3.13.0; working source restored from v3.13.0.** Undoing the
stretch on non-Tutorial children squashed the "+" rings again (they are not the only direct children that matter)
and did not fix the "A" prompt. The A prompt is therefore not a direct child of HoverIconCanvas, or is squashed by
something else. Deployed = v3.13.0 (d12545a2...).

**v3.14.0 log facts:** the pot rings are `CookingUI(Clone)` (they NEED the x2), plus `HoverProgressUI(Clone)`; the
"A" prompt is `ControlTerminalMovePrompt(Clone)`, whose root scale the game resets every frame. **v3.15.0 DEPLOYED**
(= v3.13.0 + only the prompt's direct children get localScale.x = y / k, plus a one-off `PROMPT DUMP`). Rollback =
`v3.13.0\*`.

**29 September 2026, FINAL: v3.15.0 did not change the "A" prompt; he said "maybe that's fine - let's stop there".
Working source = v3.13.0. Pinned v3.13.0 (d12545a2...) re-deployed after he closed the game; this is the final deployed version.** The A prompt (`ControlTerminalMovePrompt`) stays
twice too wide by his choice; its structure is in `src\ayce-ultrawide\v3.15.0-prompt-dump.log`. Do not reopen unless he asks.

**1 October 2026: Fast Launch skip-intro (Nexus `overcookedallyoucaneat` mod 4) INSTALLED next to MelonLoader.** The
archive ships Ultimate ASI Loader v9.7.4 x64 as `version.dll` (sha256 fa266e35..., byte-identical to the official PDB
build) + `SkipIntro.asi` (sha256 faa245b9...). NEVER copy its `version.dll`: MelonLoader's proxy is `version.dll`
(sha256 0ce7a4e5...). The loader is installed as `winhttp.dll` instead (UnityPlayer.dll imports winhttp, winmm and
version; the loader exports all 78 WinHttp functions). `SkipIntro.asi` (only KERNEL32 imports) hooks CreateFileW to
fail opens of paths containing logo/splash/intro/bumper/startup/boot with a media extension, hooks
QueryPerformanceCounter so the clock runs 20x for the first 2 s after launch and then 1x with a +38 s offset, and at
process exit terminates only UnityCrashHandler64 children of the game. FPS-neutral. Backup:
`BackupPersonal\game-tweaks\overcooked\skipintro\` (both files as installed). Uninstall = delete `winhttp.dll` and
`SkipIntro.asi`. If the logos still play, check Defender Operational events 1121/1122 (ASR prevalence rule) first.

**1 October 2026 ~13:35: the Fast Launch skip intro did NOT work for him (logos still played) -> REMOVED at his
request.** `winhttp.dll` + `SkipIntro.asi` deleted from the game root and `game-tweaks\overcooked\skipintro\` deleted;
MelonLoader `version.dll` unchanged (sha256 0ce7a4e5...). No Defender/ASR event for those files, MelonLoader ran at
13:31, so the likely cause is that AYCE's logos are not loose media files (Addressables / resources.assets), which the
CreateFileW blocker never sees. Do not retry this mod; a skip would have to be a Harmony patch in his own MelonLoader mod.

**History: what v1 got wrong and the v2 fixes (August 2026; decompiled from strings: `ApplyBurst`/`ApplyOnce`/`ForceAllCamerasFullRect`).**
v1 had no source anywhere, only the built DLL; it called `Screen.SetResolution` three times on every scene load
(bursts at 0.1/0.5/1.0 s) unconditionally, which caused the visible wide-then-normal snap mid-game, and it only
touched cameras, never the UI (squashed, mispositioned HUD icons). v2 sets the resolution only when it actually
differs; calls `ResetAspect()` after clearing the camera rect so the view goes Hor+ instead of stretching; and sets
`CanvasScaler` `screenMatchMode=MatchWidthOrHeight` with `matchWidthOrHeight=1.0` (match height): with a 1920
reference, matching width scales the UI about 2.7x on a 5120-wide screen versus about 1.3x for height, which is the
cause of the squashing. MelonLoader needs the .NET 6 x64 runtime; missing it crashed the game twice before a session
finally started. If the HUD comes out too small, lower `CanvasMatchWidthOrHeight` toward 0 in
`UserData\MelonPreferences.cfg`. Logs: `MelonLoader\Latest.log` and
`%USERPROFILE%\AppData\LocalLow\Team17\Overcooked All You Can Eat\Player.log`.

