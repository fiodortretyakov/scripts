Risen was reinstalled 30 September 2026 (build 10475629, the 2023 64-bit executable in `bin\`). It is
still DirectX 9 (`Engine.dll` imports `d3d9.dll`); on the Adreno X1-85 it runs under x64 emulation
through `d3d9on12.dll` (seen in a crash dump), so Windows sees a D3D12 swap chain.

**Config layering (paths from the binaries):** `data\ini\ConfigDefault.xml` (all defaults, incl. the
per-quality blocks) -> `data\ini\ConfigLocal.xml` (documented override file, root `<local>`) ->
`%LOCALAPPDATA%\Risen\ConfigUser.xml` (root `<options>`, REWRITTEN by the game on exit with only the
menu-managed keys, so unknown keys placed there may vanish). The five in-game quality settings equal
`ConfigPerformanceHigh.xml`: ViewDistance 3, Shadows High, Vegetation High, Effect High, Cache High,
TextureFilterMode 4, DoF; his ConfigUser already had all of them at maximum.

**Resolution** = `Window` Left/Top/Right/Bottom in ConfigUser (was a stale 3840x2160 from June; set to
0/0/5120/1440, RefreshRate 120 = the desktop mode of 30 September, Vsync false, `FOV="100"` is the
2023 build's slider value, kept). The GUI picks the nearest of FOUR canvases in
`eCApplication::OnSize` (Engine.dll rva 0x4BF540: table 16:9 / 10:9 / 5:4 / 4:3, start tolerance
`g_fPosInfinity`), so 32:9 always gets `/Engine/GUI/Aspect16x9` (1365x768) stretched twice.
**Fix:** `Aspect16x9 VirtalWidth="2731"` (768 x 32/9) in ConfigLocal.xml; DrawScale then stays
uniform (5120/2731 = 1440/768). Also in ConfigLocal: `Render MSAA="0"` (MSAA="4" CRASHED at startup 30 September 15:54: null renderer singleton at Engine.dll+0x506464, i.e. device creation failed; the key is an `eEMultiSample` enum, so 4 is probably out of range, never re-try blindly), `Shadows/High` DetailShadowMapSize and TerrainShadowMapSize 2048 (shipped 1024),
`Vegetation/High ViewRange 10000` (shipped 7500). Rollback = delete the block; shipped file is in
`BackupPersonal\game-tweaks\risen\orig\`.

**30 September 16:00, his report with ConfigLocal overrides + FOV 100: "everything squashed", world AND HUD.** The only
reading consistent with both is a 16:9 frame stretched to 32:9, i.e. the ConfigLocal.xml override never took effect
(ConfigLocal may be inert or loaded before ConfigDefault). So the values were written straight into
`data\ini\ConfigDefault.xml` (shipped copy in `game-tweaks\risen\orig\`, diff = VirtalWidth 2731, shadow maps 2048,
vegetation range 10000); FOV lowered 100 -> 75 at 16:03. No hardcoded 16:9 projection constant with code references
exists in Engine.dll or Game.dll (only the GUI class table), so the world aspect most likely follows
VirtalWidth/VirtalHeight too. Result of his next run: PENDING. Steam F12 screenshots land in
`C:\Program Files (x86)\Steam\userdata\<steam-id>\760\remote\40300\screenshots\` and can be read as images.
**Nexus catalog (gameId 342, domain `risen`, 45 mods, 30 September 2026, via api-router GraphQL; downloads are
blocked for curl and need a manual download or an API key).** No-Intro-Splash (id 35, 4 KB zip) = empty
`data\extern\videos\logo.ini` + blank `bin\splash.bmp`; replicated natively 30 September (shipped copies in
`game-tweaks\risen\orig`; the story `Intro.bik` is untouched). 2023-build-compatible and worth it: Risen Customizable
Camera (id 58, d3d9.dll proxy + DLLMods, FOV for every camera state; untested under D3D9On12), Larger Focus Item Font
(id 62, `compiled_fonts.bin`), Risen Improvements Pack Next-Gen (id 31, `data` p0x files), Risen Redefine (id 56,
840 MB AI-upscaled textures, beta with seams). AVOID on this build: Risen Remaster (id 22, 2009 build + Vulkan
wrapper), Elusively Patched Unit (id 37, states it does not work with the 64-bit re-release), any script mod
(scripts are broken on the 2023 version per id 31), ReShade presets (he had ReShade removed).
**30 September 21:45, at his "seems I broke settings": ConfigDefault.xml RESTORED to the shipped file (md5 fc92d042...,
the modified copy deleted from game-tweaks).** His 21:42 run had set the resolution back to 3840x2160 in-game and
crashed on exit again (4th dump). Still modified on disk: ConfigLocal.xml (VirtalWidth 2731, shadows 2048,
vegetation 10000, probably inert), ConfigUser FOV 75, logo.ini empty, splash.bmp blank. The 32:9 world/HUD question
is UNRESOLVED; no screenshot was ever taken.
**Mods INSTALLED 30 September 22:00 (archives he downloaded; small ones copied to `game-tweaks\risen\mods\`, Redefine
884 MB is re-download only):** Customizable Camera 1.00 = `bin\d3d9.dll` proxy (x64, needs MSVCP140/VCRUNTIME140,
which the game process already loads from System32) + `bin\DLLMods\` (CustomizableCamera.dll hooks Game.dll; config
`CustomizableCamera.txt`, F1 GUI, saving the txt reloads live; defaults exploration FOV 110). Risen Redefine 0.5 beta =
899 loose `._ximg` in `%LOCALAPPDATA%\Risen\data\images\` (1.37 GB; the `appdata` physical mount is the 2023 build's
loose-file path). Vurt's Dark Risen = `data\compiled\images.p00`; Sounds Overhaul 1.1 = `data\compiled\sounds.p00`
(G3V0 format identical to the shipped `.pak`; Engine.dll knows `.p0`). Two textures overlap Redefine/Dark Risen
(itmisc_alpha_01, nat_stone_rock_01). Uninstall = delete those files. All UNTESTED by him as of install time.
**30 September ~22:20, his "everything squashed in the middle, it was good before, revert this":** the game had been
switched IN-GAME to 3840x2160 / FOV 74 / Vsync on (a 16:9 mode scaled into the middle of the 32:9 panel). Reverted
everything of mine that touches the picture: ConfigLocal.xml back to shipped (md5 c165d73a...), ConfigDefault.xml
confirmed shipped, ConfigUser set to 5120x1440 / FOV 100 (his original value) / Vsync true kept, and every
CustomizableCamera.txt value set to its vanilla number then at 22:30 the camera mod was REMOVED at his request (he plays with a controller; bin/d3d9.dll + DLLMods deleted, zip dropped from game-tweaks).
**22:40, his "it is stretched to display" at 5120x1440:** so the plain 2023 build draws a 16:9 frame (world + HUD) and
stretches it to 32:9. The ONE untested lever is `Aspect16x9 VirtalWidth=2731` in ConfigDefault.xml AT 5120x1440 (the
21:42 run with it was at 3840x2160, so it was never really tested); fallback = 16:9 picture centred (ConfigUser
Left 1280 / Right 3840, FullScreen false). **Windows Hello at every launch:** Administrator protection is ON
(TypeOfAdminApprovalMode=2), so any UAC = Hello prompt. Steam runs the Risen install script at each launch
(HKLM Deep Silver keys, redist installers that are not on disk) but the Steam Client Service is running, so that
should be silent; no Biometrics/WebAuthN/Security events at launch times; the CredentialUIBroker crash in WER is from
20 September. Cause NOT identified.
**22:55, his report at plain 5120x1440: "HUD stretched to 32:9 but game looking good", and he rejects 16:9 centred.**
So the WORLD is Hor+ from the window (earlier "squashed" reports were the 3840x2160 mode or FOV changes) and only
the HUD canvas is wrong. Applied the single change `Aspect16x9 VirtalWidth="2731"` in ConfigDefault.xml (from the
shipped copy; modified copy in `game-tweaks\risen\ConfigDefault.xml`, shipped in `orig\`). Result PENDING his launch.
**23:05, HUD-CENTRING BINARY PATCH applied at his explicit request ("I need exactly this": 16:9 HUD centred on a
32:9 world).** Script `D:\bin\risen_hud_center.py` (copy in `game-tweaks\risen\`), idempotent, `--restore` puts
vanilla back. Vanilla `bin\Engine.dll.bak-vanilla` sha256 5A8EA0A7..., patched Engine.dll sha256 87722277...
Mechanism (found with capstone in WSL): `eCGuiModule2::ReSize(w,h)` @rva 0x51A6A0
computed sx=w/VirtalWidth, sy=h/VirtalHeight into module +0x20/+0x24; module +0x2C/+0x30 are X/Y draw offsets that
`eCGuiModule2::Draw` copies into `eCGuiDevice2` +0x1F0/+0x1F4 every frame (device BeginFrame builds the GUI
transform = view * scale * translate(offset)); ToVirtualCoords, OnHandleMessage and SetFocusPos already apply
offset+scale, so mouse mapping stays consistent. Patch: hook at 0x51A6F5 (40 bytes -> jmp + nops) to a cave at
0x802C98 (zero padding at the end of .text; .text VirtualSize bumped 0x801C98 -> 0x801CD1) that sets sx=sy=h/VH,
offsetX=(w - VW*sy)/2, offsetY=0, then jumps back to 0x51A735. ConfigDefault.xml MUST stay shipped (VirtalWidth 1365)
for this to centre; it was restored. The 3D world is untouched (follows the window). Steam verify/update restores
Engine.dll -> re-run the script; if the ReSize bytes differ the script's assert fails, re-derive, never force.
CONFIRMED WORKING by him 30 September 23:15 ("it is good!").
**Steam "verify integrity" or an update restores ConfigLocal.xml** (it is a depot file); copy it back
from `%USERPROFILE%\BackupPersonal\game-tweaks\risen\ConfigLocal.xml`. ConfigUser survives.

**GPU preference entry** for `...\Risen\bin\Risen.exe` set 30 September 2026 to
`DXGIEffects=1024;AutoSuperResolutionEnable=0;AutoHDREnable=4147;SwapEffectUpgradeEnable=1;`
(Auto SR was 1; it halves render resolution and excludes Auto HDR). Display HDR was ON on the G95NC
that day (dxdiag: AdvancedColorEnabled, mode HDR). Whether Auto HDR engages through D3D9On12 is
UNVERIFIED; Windows documents DX11/DX12 only.

**Crash before the patch:** 30 September 15:39, `0xC0000005` in `SharedBase.dll+0x7CAA9` reading a
garbage pointer, one second after the game wrote ConfigUser.xml (exit-time crash). Dumps land in
`%LOCALAPPDATA%\Risen\.sentry-native\reports\*.dmp`; a new one after a run = still crashing.

**Verify after a play session:** ConfigUser.xml still says
Right 5120 / Bottom 1440 (the game rewrites it with what it actually used), no new `.dmp`. He judges
HUD size, menu placement and FOV in-game; the FOV slider in Options is the lever if the view is
zoomed-in (Vert-) or fisheyed (Hor+).
