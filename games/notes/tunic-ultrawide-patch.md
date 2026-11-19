TUNIC (Steam app 553420, Unity 2020.3.17f1 IL2CPP) has no ultrawide support and pillarboxes to
16:9 on the 5120x1440 G95NC. The fix is a byte patch of `GameAssembly.dll`, first built
12 August 2026, re-applied 29 September 2026 after a fresh reinstall.

**Re-apply (idempotent, restores vanilla from the backup first):**

```powershell
& 'C:\Program Files\Python313-arm64\python.exe' D:\bin\tunic_aspect.py 3.5555556 1,2,3
```

Must print sites 1, 2 and 3 (`@0x57876f`, `@0x7ca704`, `@0x7cfdfa`), `CanvasScaler @0x88eeee -> forced Expand`, `shared literal
still 1.7777...`, `private constant = 3.5555...`. Vanilla backup: `GameAssembly.dll.bak16x9`
in the game folder (sha256 `CDDAFC9A...`); patched dll sha256 `A725DF99...` (sites 1,2,3). Both hashes were
confirmed 29 September 2026: Steam build `10650562` shipped a dll byte-identical to the August
backup, so the script's offsets are still valid. If a future build changes the dll, the
script's asserts fail ("vanilla literal missing" / "canvas switch moved") and the offsets need
re-deriving; do not force it.

**Verify from a real run (no need to launch from a script):**
`%USERPROFILE%\AppData\LocalLow\Andrew Shouldice\Secret Legend\Player.log` must contain
`[World RTex] Creating render texture 5120 x 1440` (vanilla logs `2560 x 1440`).

**Already correct, do not touch:** PlayerPrefs in `HKCU\Software\Andrew Shouldice\Secret
Legend` hold 5120x1440, `Fullscreen mode = 1` (borderless), `Use Native = 1`; the per-exe
GPU entry for `Tunic.exe` is `AppStatus=1028;AutoHDREnable=4147;SwapEffectUpgradeEnable=1;`
(set 29 September 2026, the System Shock pattern; the inert Auto SR flag from August was dropped;
Auto SR and Auto HDR are mutually exclusive).

**Site 1 ALONE = STRETCHED (confirmed by him 29 September 2026):** the world texture goes full width but both camera resizers still assume 16:9. Sites 2 and 3 are the same code in two classes (CameraResizer, ClearingCameraResizer) and must agree; the CanvasScaler patch (added 12 August, 13:01) keeps the UI at normal size once they are widened. Applied `1,2,3` on 29 September 2026 (patched sha256 `A725DF99...`); CONFIRMED WORKING by him the same day: correct framing, normal UI, no bars.

**Why the shared literal is never edited:** the 16:9 float is one deduped `.rdata` literal shared by three code
sites; editing it in place widens the camera AND doubles the UI (seen twice). Full site table and reasoning are in the section "Patch sites" at the end of this note.

**Graphics state on disk (29 September 2026):** `UnityGraphicsQuality=0` is the top tier (the
August log shows a full 5120x1440 world texture at that value, so the render divider is 1);
`SSAO=2` is Unity's top `SSAOSamples` level. Shadow, FXAA, motion blur, depth of field and
VSync are set in the in-game Options menu and are not persisted anywhere greppable (not in
PlayerPrefs, not in the `.tunic` saves). The `999999999999~*.tunic` save is a special/debug
profile, not a settings file. ReShade + RenoDX (13 August 2026, never launched) were DELETED at
his request on 29 September 2026; do not reinstall. Auto HDR needs display HDR ON on the G95NC,
which is his toggle only (dxdiag 29 September: G95NC AdvancedColorSupported, not Enabled).

**Nexus (game id 4386, domain `tunic`, 18 mods):** worth
considering are TUNIC Checklist (id 55, BepInEx 6 IL2CPP, chest/item tracker for vanilla saves,
achievement-friendly), Focus Loss Bypass (id 60, BepInEx, keeps the game running when tabbed
out), Tunic Randomizer (id 4, replay only). Ultrawide Button Image Fix (id 51) targets
RoseTheFlower's UltrawideIndex mod, not our patch; Remove Post Processing (id 56) is against his
taste. No BepInEx is installed; the game folder has only `Tunic_Data`.

**Save editing (5 October 2026):** saves in `SAVES\<profile>~<timestamp>.tunic` are plain CRLF text, one `key|value` per line, no checksum; the newest timestamp per profile is the one the game loads. Blueberries (blue, restore MP) = `inventory quantity Berry_MP`; red = `Berry_HP`. Set to 28 on `<profile>~<timestamp>.tunic` at his request; edit only with the game closed.

**Patch sites (GameAssembly.dll, IL2CPP, Unity 2020.3.17f1; first fixed 12 August 2026).**
The trap: the float `1.7777779f` is deduped into ONE `.rdata` literal (file `0xFDDCD8`, rva `0xFDF4D8`)
shared by three code sites. Editing it in place, as community hex-edit guides suggest, widens the camera
*and* doubles the UI (menus and health bars too big; seen twice). Instead a private float is parked in `.rdata`
tail padding (file `0x12912B0`, rva `0x1292AB0`, 344 zero bytes) and only the chosen site's `disp32` is rewritten.

| site | disp32 file off | role | patch? |
|---|---|---|---|
| 1 | `0x57876F` | world render-texture sizer (`movss xmm1` after `comiss`/`ja`) | yes |
| 2 | `0x7CA704` | normalized UI rect (`mov byte [rbx+0x20],1` = `letterboxedOrPillared`) | see above: 2 and 3 are patched together with 1 in the final version |
| 3 | `0x7CFDFA` | duplicate of site 2 in another class | see above |

Proof it is site 1: it computes `width * (1.7778/aspect)` = `5120 * 0.5` = 2560, matching
`[World RTex] Creating render texture 2560 x 1440` in `Player.log`. That log line is the cheap way to confirm a
patch worked. Sites 2/3 patched alone left the RT at 2560 but still enlarged the menus, which isolated them as UI.

Use exactly `3.5555556` (`39 8E 63 40`), the true 5120/1440. The value `71 3D 63 40` (3.5506) quoted in community
guides as "32:9" is slightly narrower than the panel and leaves a few pixels of bar.

Quality settings need no change: `GetDividerBasedOnQuality` makes the graphics setting a render-scale divider,
and `UnityGraphicsQuality=0` in `HKCU\Software\Andrew Shouldice\Secret Legend` is already divider 1 (no downscale).
