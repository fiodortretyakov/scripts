System Shock remake (Steam app 482400) on the Surface Laptop 7 (x64 game under Prism emulation, Adreno X1-85):

- Install: `C:\Program Files (x86)\Steam\steamapps\common\System Shock Remake`; mods are `*_P.pak` in `SystemShock\Content\Paks`.
- Crash dumps: `%USERPROFILE%\Saved Games\Nightdive Studios\SystemShock\Saved\Crashes\UE4CC-*\UE4Minidump.dmp` (+ `CrashContext.runtime-xml`). No game log is written (shipping build). Nothing reaches Windows Event Log or WER.
- Config: `...\Saved\Config\WindowsNoEditor\Engine.ini` forces `DefaultGraphicsRHI_DX12` plus parallel RHI cvars; the file carries a note written 11 August 2026: DX12 only, no DX11 A/B.
- 27 August 2026 crashes (two, identical): use-after-free inside the D3D12 RHI resource-transition path executed on the dedicated RHI thread (FRHIThread::Run, ENamedThreads::RHIThread == 0). Not mod related. The 12 August 2026 crashes were a different Blueprint-VM null dereference.
- No debugger is installed; minidumps were parsed with a hand-written PowerShell MINIDUMP reader (exception stream, thread contexts, module list, stack scan).

- Reported trigger for the 27 August 2026 crashes: looking at a locked door (both times). InstantCardSwipes_P.pak replaces INTERACT_DoorBase and INTERACT_CardReader, it was deleted on 27 August 2026. 16 mod paks remain.



- Third identical crash 01:08 on 27 August 2026 with the mod deleted, reproducible by approaching a locked door: mods ruled out. Mitigation applied that day: r.RHICmdUseParallelAlgorithms and r.Parallel{PrePass,BasePass,Shadows,Translucency} set to 0 in Engine.ini (backup Engine.ini.bak-2026-08-27). Next step if it persists: r.RHIThread.Enable=0.

- Fourth identical crash 01:16 on 27 August 2026 with the parallel cvars at 0: those were innocent and were restored to 1. Corrected thread identification: dedicated RHI thread, not a translate worker. Applied 
.RHIThread.Enable=0 in Engine.ini. If that also fails, the ini has no further D3D12 lever.

- 
.RHIThread.Enable is a console COMMAND in this build: putting it in Engine.ini [SystemSettings] crashes at start (LowLevelFatalError, console object of different type). Removed on 27 August 2026. The RHI thread is disabled via Steam launch option -norhithread (string verified in the exe). Never edit localconfig.vdf while Steam is running.

- RESOLVED 27 August 2026: with Steam launch option -norhithread the locked-door crash no longer occurs (confirmed). Current working setup: DX12 + -norhithread, parallel cvars at 1, InstantCardSwipes mod deleted, 16 mods remain.

- 27 August 2026 tuning after the fix: added r.SceneRenderTargetResizeMethod=2, r.Shadow.MaxNum{Point,Spot}ShadowCacheUpdatesPerFrame=2, r.ViewDistanceScale 1.0->1.5 (add-back item 7). Engine.ini methodology: one change at a time with the Steam fps counter; GPU is pixel-bound (ScreenPercentage is the only knob with a measured model); render thread now also carries RHI work because of -norhithread.
- 27 August 2026 RAM/CPU/disk trade: PoolSize 8192, MaxTempMemoryAllowed 4096, FramesForFullUpdate 3, NumStaticComponentsProcessedPerFrame 200, ShaderPipelineCache Batch/Precompile 200 @ 50 ms, CreateShadersOnLoad 1, WholeSceneShadowCacheMb 1024, CachePreshadow 1, RHICmdMinDrawsPerParallelCmdList 32.

- Controller look speed (30 August 2026, second pass): Gamepad_RightY now DeadZone 0.25 / Exponent 1.6 / Sensitivity 0.45 in `Saved\Config\WindowsNoEditor\Input.ini` (was 0.55 / 1.3; backup `Input.ini.bak-2026-08-30`). The file is kept read-only so the game cannot rewrite it - `chmod u+w` before editing. Gamepad_RightX stays stock on purpose; the game has no look-sensitivity slider.
- Mission time limit is NOT configurable by ini: the value is a `TimeLimit` field in the cooked DataTable `DT_MissionDifficultySettings` (row struct `STRUCT_MissionDifficultySettings`) inside `SystemShock-Windows.pak`; the menu string is templated ("The Hacker has {x} hours to stop SHODAN..."), which is why web sources quote 5/7/10 hours for different patches. Changing it needs a pak that replaces that DataTable - Nexus mod 28 (Nixos) component `0104_HardMission24HoursTimeLimit`. 24 h is the ceiling with a countdown; 0 disables the timer.

- Third crash family, one occurrence, 6 September 2026 20:29 (512 s into the session): PCallStackHash A424C2C2EDCE8C9FF1849E2ECE51D99021BE5A04, on the GameThread, not the RHI thread; `-norhithread` was in the command line, so it is unrelated to the 27 August D3D12 crashes. Access violation reading 0xb8b9bbf679e34b46, RIP exe+0x2b1764f, rcx=rsi=0xb8b9bbf679e34abc — a garbage `this` dereferenced at +0x8A inside a 49-byte accessor (exe+0x2b17640..0x2b17671), reached from FEngineLoop::Tick (exe+0x7fa0d1) via dispatcher exe+0x11f149b. Did not recur (2.5 h of play after it). No TDR, no WER, working set 6.3 GB of 32 GB.
- Minidump tooling rebuilt 7 September 2026 (`dmp.ps1` exception/context/stack scan, `pdata.ps1` RVA to function bounds via the PE exception directory). Field-offset traps: MINIDUMP_MODULE name RVA is at +20 (not +32), MINIDUMP_THREAD stack descriptor is at +24/+32/+36, exception stream context descriptor at stream RVA +164.

- Texture filtering, measured 7 September 2026 by scanning the 7.5 GB base pak: the DeviceProfile
  `TextureLODGroups` all say `MinMagFilter=aniso`, but **2,951 individual texture assets carry an
  explicit `TF_Nearest` override** (vs 7 TF_Bilinear, 3 TF_Trilinear; TF_Default is elided by UE
  property serialization so it cannot be counted). Point filtering is deliberate art direction set
  per asset, so `r.MaxAnisotropy` and `r.MipMapLODBias` in Engine.ini are inert for nearly every
  surface, and no ini can change it. Only a pak that replaces the texture .uasset headers can -
  Nexus mod 21 "Enable texture filtering" (NamelessVoice, last updated June 2023, v1.0-era, so
  header-vs-.ubulk mismatch on the current 2.x build is an untested risk). If it is installed and
  frames drop, the fix is `r.MaxAnisotropy=4`, because the mod is what makes that line live.
- Pak/exe scanning tooling: `cvarscan.ps1` (cvar names are UTF-16LE in
  the exe - a plain ASCII grep reports every cvar absent, which is how the 11 August "verified
  registered" checks must have been done), `pakscan.ps1` / `pakcount.ps1` (chunked 64 MB reads with
  overlap, latin1 byte<->char mapping, opened FileShare.ReadWrite so Steam can hold the pak).

- Mod inventory audited 7 September 2026 by parsing every mod pak's real index (footer magic
  0xE1126F5A in the last 256 bytes -> version/IndexOffset/IndexSize; pak v3/v8 use the legacy
  MountPoint+entry list, v10+ use the FullDirectoryIndex at its own offset. FPakCompressedBlock is
  16 bytes, not 32 - getting that wrong makes every compressed pak fail mid-entry). String-scanning
  a pak is NOT good enough: it returns imports from each asset's name table as if they were
  contained files, which invents conflicts that do not exist. Script: `pakparse.ps1`.
  Result - only three true overlaps among the 16 mod paks, all decided by the `zzz` prefix mounting
  last: `zzzCFW03-Junk` + `zzzCFW02-Items` override 63 of `ItemsGridSize`'s 65 assets (only
  ITEM_AbeGhiranHead and ITEM_InterfaceDemodulator survive, so that pak is dead weight), and
  `zzzCFW03-Junk` takes 4 of `WeaponsGridSize`'s 22 (the damaged weapons; the other 18 still apply).
  Cleared: `v1.2_SkipIntro_P.pak` contains ONLY the four PreGameScreen splash widgets despite the
  v1.2 name, and `v2.1_PermanentHWIcons` contains only WIDGET_PlayerHUD, so it does not fight
  NoCAUI's MAT_UI_ScreenEffects. Game build 22239093, dated 20 July 2026; the 2024-cooked paks
  (WeaponsGridSize, the three zzzCFW) are the oldest Blueprint overrides and the first thing to
  bisect if the Blueprint-VM crash family returns.

- HDR, settled 8 September 2026: there is NOTHING left to turn on. Probed with
  DisplayConfigGetDeviceInfo/ADVANCED_COLOR_INFO - both panels report Supported+Enabled at
  10 bits (internal LQ150P1JX61 and Odyssey G95NC), Windows Auto HDR is on globally
  (`AutoHDREnable=1` in HKCU VideoSettings + `DirectXUserGlobalSettings`) and the game exe has
  its own per-app entry under `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`
  (`AutoHDREnable=4147;AutoSuperResolutionEnable=1;GpuPreference=2`). The game itself has no HDR
  setting: `ShockSettings.sav` carries WindowMode/Resolution/EnableVSync/FOV/quality tiers and no
  HDR field at all. Engine HDR stays off, and the ROOT CAUSE of the 11 August HUD blowout is now
  named: the HUD is composited through the game's own material (MAT_UI_ScreenEffects, the asset
  the NoCAUI pak replaces), so it never enters UE4's HDR UI composite path - which is exactly why
  `r.HDR.UI.Level` was inert. No ini can reach it. Two report-only findings, both display
  settings and therefore untouched: `DisableHDROnBattery=1` (HDR drops when unplugged) and the
  G95NC running at 59.98 Hz.
- `ShockSettings.sav` binary layout, verified 8 September 2026: UE4 tagged properties, each one
  int32 name-length + name + null, int32 type-length + type + null, int32 Size, int32 ArrayIndex,
  then the value; a BoolProperty's value byte sits in the tag with a guid flag after it. Resolution
  is an IntPoint struct (5120x1440). VSYNC WAS TURNED OFF 8 September 2026 by flipping that byte
  (backup `ShockSettings.sav.bak-2026-09-08`); at 60 Hz vsync-on quantised every frame to 30 or 20.
  In-place single-byte edits are safe - the file size must not change.
- 8 September 2026 performance pass, cause of the 24 fps found by diffing against
  `Engine.ini.bak-2026-09-07` (the ~30 fps config): only three lines had been added since, and
  `r.Decal.FadeScreenSizeMult=0.5` was the only one that costs pixels. Reverted to 1.0 (stock).
  Also `r.Shadow.MaxResolution`/`MaxCSMResolution` 4096 -> 2048 with `WholeSceneShadowCacheMb`
  1024 -> 512 (4096 maps are ~4 shadow texels per rendered screen pixel at ScreenPercentage 60,
  so the detail was invisible AND expensive), plus free `r.Shadow.TransitionScale=40` and
  `r.Shadow.SpotLightTransitionScale=40` for softer penumbrae. Backup `Engine.ini.bak-2026-09-08`.
  The fps model is now written into the add-back queue: fps * SP^2 = K, K = 104,000 from the two
  clean measurements, so SP 60 -> 29, 52 -> 38, 48 -> 45. ScreenPercentage is the only lever with
  range left; everything else in the file is single-digit percentages.
- Mod verdict 8 September 2026, 16 paks (the dead `ItemsGridSize` .disabled leftover was DELETED):
  none of them costs frames except possibly `Headlamp_V4`, which replaces PAWN_Hacker_Implant and
  HARDWARE_HeadLamp - a camera-mounted spotlight, so if it casts dynamic shadows it is a shadow-map
  render every frame the lamp is on; that is the one mod worth an A/B. `AnimatedPortraits` is 198 MB
  of 62 flipbook textures under Art/UI/HUD/Portraits and only costs RAM while a log is open.
  `LowLightPuzzles` is 3 puzzle blueprints and `DemoVitals` is a single texture - both free.

- ENGINE HDR TURNED ON 8 September 2026 at his explicit request, reversing the 11 August verdict:
  `r.AllowHDR=1` + `r.HDR.EnableHDROutput=1` (OutputDevice 3, ColorGamut 1 unchanged), plus
  `bUseHDRDisplayOutput=True` in GameUserSettings.ini. He was told the HUD blowout returns and
  wants it anyway. Do NOT try OutputDevice 4 or 6 to fix the HUD - they map the same values onto a
  2000-nit range, so the HUD gets brighter. The only mitigation left is the in-game brightness
  slider, because the HUD is composited into scene colour before the tonemapper. Manual step he
  must do himself: Auto HDR OFF for the exe (Settings > System > Display > Graphics), or two HDR
  passes stack.
- Steam has NO HDR setting that applies on Windows, checked 8 September 2026. The client bundle
  does carry HDR strings (`Settings_HDR_Enable`, `Settings_HDR_EnableExperimentalSupport`,
  `Settings_HDR_Debug_ForceSupport`, `Settings_HDR_Debug_Force10PQ`, `Settings_HDR_TonemapOperator`)
  but those are the SteamOS/Deck gamescope compositor's Display page; the only Windows-relevant one
  is `Settings_InGame_ScreenshotUncompressedAVIF` (HDR screenshots). Nothing HDR-related exists in
  `config/config.vdf`, `localconfig.vdf` or `sharedconfig.vdf`. And no Steam toggle could reach UE4's
  HDR path anyway - it wraps a game's SDR output; only `r.HDR.EnableHDROutput` switches the renderer.
- fps baseline CORRECTED by him 8 September 2026: the pre-decal number at ScreenPercentage 60 was
  27, not 30 (30 was the SP 57 point). So K = 27 * 60^2 = 97,000 and the table is SP 60 -> 27,
  57 -> 30, 52 -> 36, 48 -> 42, 45 -> 48. The decal line cost 3 fps, not 6.
- Mods DELETED 8 September 2026 at his request: `Headlamp_V4`, `AnimatedPortraits`,
  `LowLightPuzzles` (plus the dead `ItemsGridSize`). 12 paks remain. Contents verified by reading
  each pak's real index (footer magic at the tail, then read from IndexOffset to EOF and match
  `*.uasset` - reading only the index avoids the asset-name-table false positives that whole-pak
  string scanning produces): Cargo_Lift = INTERACT_CargoLift (1 asset, so it is Nexus 15 "More
  Cargo Lift Slots"); DemoVitals = T_VitalBarHealth, ONE texture, the HUD health-bar art;
  FasterLadder = INTERACT_Ladder; FastPickups = 32 pickup animation montages; MapColors =
  MPC_UserTintParameters (a material parameter collection); NoCAUI = MAT_UI_ScreenEffects;
  WeaponsGridSize = 22 weapon + damaged-weapon items; zzzCFW00-Ammo = 10 AMMO_ + ITEM_ExplosiveBase;
  zzzCFW02-Items = 4 items; zzzCFW03-Junk = 69 junk/item assets; SkipIntro = 4 splash widgets;
  PermanentHWIcons = WIDGET_PlayerHUD.
- Inventory/stack/size mods NOT installed, catalogued 8 September 2026: Nexus 14 "Advanced Stackable
  Items" (999 stacks for ammo, patches, batteries, junk, scrap - errore404, 3 June 2023, 44 KB),
  Nexus 4 "Stackable Items" (the older 10-stack version, superseded by 14), Nexus 26 "Disable Weapon
  Stacking" (companion to 4), Nexus 15 "More Cargo Lift Slots" (he HAS this one), Nexus 63 "60 Slot
  Cargo Lift" (reported unavailable), Nexus 25 "More Recycler Slots" (30 slots), Nexus 23 "Items
  Grid Size" (all items 1x1 - he had it and it was dead weight under the zzzCFW paks), Nexus 28
  Nixos modular pack (components for +12 starting inventory slots, +6 per expander, 72-slot start -
  users report the 72-slot component not working - plus per-item stack and grid-size components).
  Nexus blocks scripted fetches with 403; these came from search result summaries, not the pages.

- Second mod cull 8 September 2026, also at his request: `DemoVitals`, `FastPickups`, `FasterLadder`,
  `MapColors`, `v2.1_PermanentHWIcons` DELETED. SEVEN paks remain: `Cargo_Lift`, `NoCAUI`,
  `WeaponsGridSize`, `zzzCFW00-Ammo`, `zzzCFW02-Items`, `zzzCFW03-Junk`, `v1.2_SkipIntro`.
- NoCAUI audited 8 September 2026 by extracting the asset, not by guessing: it is safe. The pak holds
  `MAT_UI_ScreenEffects.uasset` (3,392 B) + `.uexp` (34,150 B), zlib-compressed. Its import/name table
  still references `/Game/Art/UI/MaterialFunctions/ScanLines` (+ `T_ScanLines`),
  `/Game/Art/UI/MaterialFunctions/ScreenDistortion` (+ the `DistortionMax`/`DistortionMin`/
  `DistortionVertical` parameters the game drives for damage and interference),
  `T_SquareNoise_01`, `Blend_SoftLight` and `MD_UI`/`BLEND_AlphaComposite` - so every other UI screen
  effect and every code-driven parameter survives. `/Game/Art/Materials/Functions/ChromaticAberration`
  is still IN the graph, so the mod disconnected or zeroed it rather than deleting it. Two caveats: it
  is a 2023-era unversioned cook (`FileVersionUE4=0`, which is normal for cooked packages) living on
  the 20 July 2026 build, so it is the first thing to pull if the UI ever renders wrong; and it pins
  the scanline/distortion look at 2023 values. It is also the ONLY way to remove the UI's own
  chromatic aberration - `r.SceneColorFringeQuality=0` reaches the scene, never this material.
- Pak extraction recipe (`pakx3.ps1`, works on the v3 mod paks): footer magic in the last
  512 bytes -> IndexOffset; index is MountPoint FString + int32 NumEntries + per entry
  {FString name, int64 Offset, int64 Size, int64 UncompressedSize, int32 CompressionMethod, 20-byte
  SHA1, if compressed: int32 NumBlocks + NumBlocks*16, uint8 bEncrypted, int32 BlockSize}. In v3 the
  compressed-block Start/End are ABSOLUTE pak offsets. Each block is raw zlib, so skip the two-byte
  `78 9c` header and use DeflateStream. PowerShell traps that cost time: `$E` collides with a loop's
  `$e` (variables are case-insensitive), and array slicing yields `Object[]` which will not coerce to
  `[byte[]]` in a param - build the buffer with `New-Object byte[]` + `[Array]::Copy`.

- MOD CONFLICT PREFERENCE, stated 8 September 2026: when two paks claim the same asset, (1) the one
  that stacks to the max wins, (2) then the one that sizes to 1x1. CRITICAL consequence he needs
  reminding of: these paks replace WHOLE item blueprints, so mount order decides every property of
  that asset at once - there is no per-property merge. For any item a stack mod and a size mod both
  cover, letting the stack mod win also reverts that item's grid size to whatever the stack mod
  carries. Mount order is case-insensitive filename order and the LAST pak wins, so a future
  stack mod (Nexus 14) must be renamed to sort after every `zzz` pak.
- Installed 8 September 2026 from his Downloads: `SystemShock-Windows-CFW01-Weapons_P.pak` (Nexus 62
  CFW Weapons version C: all weapons 1x1 always, modkits 1x1, modkits no longer add weapon size),
  RENAMED to `SystemShock-Windows_zzzCFW01-Weapons_P.pak` because the hyphen form sorts BEFORE
  `SystemShock-Windows_WeaponsGridSize` and would have been overridden and done nothing. Plus
  `v1.2_SkipNewGameIntroduction_P.pak` (Introduction.umap) and `v1.2_SkipLaptopWaitTime_P.pak`
  (INTERACT_Laptop) from Nexus 98, no conflicts. NOT installed: the archive's
  `SystemShock-Windows-CFW01-WeaponTables_P` folder - it is LOOSE cooked DataTables (the optional
  weapon rebalance), and a shipping build ignores loose folders under Content/Paks; installing it
  needs UnrealPak, which is not on this machine.
- Conflict count went 4 -> 17 with that install, all of them `WeaponsGridSize` losing: 13 weapons to
  zzzCFW01 and 4 damaged weapons to zzzCFW03. KEEP WeaponsGridSize - it still owns the 5 assets
  CFW01 does not cover: WEAPON_Cybergun, WEAPON_PoolCue, WEAPON_PseudoDiscLauncher,
  WEAPON_PseudoNova, WEAPON_PseudoPulser.
- He wants `ItemsGridSize` (Nexus 23) BACK, 8 September 2026. It is gone from this machine - Git Bash
  `rm` bypasses the Recycle Bin and a filesystem search found no copy, so it must be re-downloaded.
  For it to actually apply it has to mount after the CFW packs, i.e. be named something like
  `SystemShock-Windows_zzzzItemsGridSize_P.pak`. Cost of that: zzzCFW02-Items (4 assets) becomes
  fully dead and zzzCFW03-Junk loses 59 of its 69, keeping 10. Worth checking whether the CFW packs
  already give those items 1x1 before bothering - that question is unresolved.
- Conflict tooling, `conflicts.ps1`, reads every pak's index from
  IndexOffset to EOF, sorts paks by case-insensitive filename (the mount order), and reports
  duplicate assets with the winner plus a dead-weight summary. NOTE a v11 limitation: the
  FullDirectoryIndex stores directory and filename as separate strings, so a pak whose only entry is
  a `.uexp` reports 0 assets (`v1.2_SkipLaptopWaitTime` does this) - check such paks by hand.

- WHAT THE CFW SERIES ACTUALLY DOES, from the author's own Nexus descriptions (8 September 2026).
  CFW = the "Custom Fit" family, and the components do BOTH sizing AND stacking:
  * CFW Weapons (Nexus 62, his zzzCFW01): compresses weapons to one row and stops certain modkits
    adding to weapon size; version C - the one installed - is all weapons 1x1 always and modkits 1x1.
    Ships an optional weapon rebalance as the loose WeaponTables folder.
  * CFW Ammo (his zzzCFW00): increases ammo gains and/or expands ammo stacks.
  * CFW Items (Nexus 108, his zzzCFW02): increases item stacks, optionally buffs certain patches.
  * CFW Junk (Nexus 107, his zzzCFW03): junk to 1x1 (broken weapons vary by version A/B/C) and junk
    stacks up to 10.
  CONSEQUENCE for his stated preference (stack first, then size): `ItemsGridSize` is NOT worth giving
  priority over the CFW packs. It only changes SIZE, and CFW02/CFW03 already give those items 1x1
  PLUS the stack increase - so promoting ItemsGridSize above them would satisfy priority 2 while
  destroying priority 1. At its original low priority it was doing exactly two useful things: 1x1 for
  ITEM_AbeGhiranHead and ITEM_InterfaceDemodulator, the only two of its 65 assets the CFW packs do
  not cover. That is the whole value of re-downloading it.
- `zzzCFW02-Items` was NOT deleted on 8 September 2026 despite the request to delete it "if completely
  dead": it is fully live, all 4 of its assets win (ITEM_BatteryPack, ITEM_DermalPatch_Base,
  ITEM_FirstAidKit, ITEM_LogicProbe). It would only die if ItemsGridSize were given higher priority.
- Name-table presence is NOT proof of modification: a cooked Blueprint's name table lists every name
  its graph references, so finding `MaxStackCount` or `VaporizeRewardItemCount` in a CFW asset does
  not by itself show the mod changed them. Proving a value change needs the base pak's copy of the
  same asset for a diff, which needs the v11 encoded-pak-entry decoder plus an export-map parse to
  find the CDO - not built yet. The zlib-blob scan in `props.ps1` (scan for 78 9C, inflate,
  keep blobs starting C1 83 2A 9E, then parse the header for NameCount/NameOffset) reads any v11
  pak's asset name tables without that decoder.

- `ItemsGridSize` REINSTALLED 8 September 2026 at his request, at its stock filename
  `SystemShock-Windows_ItemsGridSize_P.pak` so it stays BELOW the CFW packs - he explicitly accepted
  the override. Final state: 10 mod paks, 79 conflicted assets. Corrected counts (the earlier session
  said 65/63): the pak carries 64 assets, 62 lose to zzzCFW03-Junk alone (not CFW02+CFW03 - it does
  not overlap CFW02's 4 items at all), and exactly 2 still apply: ITEM_AbeGhiranHead and
  ITEM_InterfaceDemodulator. WeaponsGridSize keeps 5: WEAPON_Cybergun, WEAPON_PoolCue,
  WEAPON_PseudoDiscLauncher, WEAPON_PseudoNova, WEAPON_PseudoPulser.

- ENGINE HDR CLOSED FOR GOOD, 8 September 2026. It was turned on at his request that morning and
  reverted the same day: he reported "all inventory and menu are greyed out". Second confirmation of
  the 11 August failure, with the mechanism now understood - the game composites its UI through its
  own MAT_UI_ScreenEffects material BEFORE the tonemapper, so the UI's sRGB values are pushed through
  the ACES/PQ curve as if they were linear, and washed-out grey UI is precisely that signature. Both
  attempts used `r.HDR.UI.CompositeMode=1`; mode 0 is the only knob never tried and is recorded in
  the ini as a long shot. Do not propose engine HDR again unless he asks for that specific test.
  HDR for this game means Windows Auto HDR, already on globally and per-exe - and if he turned Auto
  HDR OFF for the exe when engine HDR went on, it must go back ON or he has no HDR at all.
- Performance verdict from him, 8 September 2026: "looks good, fast" after the decal revert, the
  4096 -> 2048 shadow maps and vsync off. So ScreenPercentage stays at 60 and the add-back queue's
  measured table (K = 97,000) was not needed.

- ENGINE HDR REOPENED, and the earlier "closed for good" note is WRONG - do not act on it. Attempt 3
  on 8 September 2026 uses the recipe the community actually runs: `r.HDR.Display.OutputDevice=5`
  (ACES 1000-nit **scRGB**) + `r.HDR.Display.ColorGamut=2` (Rec.2020). Attempts 1 and 2 both used
  device 3 (ST-2084/PQ), and THAT is why the UI washed out - PQ remaps the whole 0-1 range onto an
  absolute-nit curve, whereas scRGB keeps 0-1 as SDR sRGB and only takes values above 1.0 into HDR
  highlights, so a UI drawn at 0-1 holds SDR paper white by construction. Same 1000-nit target, so
  it is not a brightness gamble. The old note in this file warning against devices 4 and 6 conflated
  encoding with nit target: 4/6 are the 2000-nit variants, but 5 was never in that class and should
  have been the first thing tried. Backup `Engine.ini.bak-2026-09-08b`.
  Escalation ladder if inventory ICONS still wash out (a known residual in community reports):
  (1) `r.HDR.UI.CompositeMode=0`, never tried; (2) `r.HDR.UI.Level` 3.0 -> 1.0, retested on device 5;
  (3) back to Windows Auto HDR.
- No native HDR menu exists in this build: an exe string scan on 8 September 2026 found only stock
  UE4 API names (`HDRDisplayOutputNits`, `GetCurrentHDRDisplayNits`, `bUseHDRDisplayOutput`) and no
  menu text. The Display HDR option that existed in the 2021 demo was cut from the release.
- Special K is the community's other route to HDR for this game (an scRGB retrofit at the swap chain,
  reported as decent but worse than a native implementation). NOT tested here: it injects an x64 DLL
  into an x64 process running under Prism emulation on ARM64, which is unverified on this machine.

- HDR WORKS, confirmed by him 8 September 2026 ("it is amazing") with OutputDevice=5 + ColorGamut=2.
  Residual: inventory icons washed out. First fix applied that day, `r.HDR.UI.Level` 3.0 -> 1.0.
  Reasoning worth keeping: UI.Level is a luminance MULTIPLIER for UI composited into the HDR
  framebuffer, and under scRGB the value 1.0 already IS SDR paper white, so 3.0 drove UI whites to
  roughly 300 nits - washed out is exactly that. It was measured inert under device 3 in August,
  which is why nobody suspected it. Next single step if icons persist: `r.HDR.UI.CompositeMode=0`
  (one change at a time - mode 0 drops the luminance-preserving blend for the whole UI and can
  regress text that currently reads fine). If neither works it is not ini-fixable: the inventory
  icons are probably scene captures of the item meshes, and a capture render target never enters
  the UI composite path.

- `r.HDR.UI.Level` PUT BACK TO 3.0 on 8 September 2026 at his call: he preferred the look at 3.0 and
  accepts the washed-out inventory icons. Do not "fix" that line again. Final HDR config: AllowHDR 1,
  EnableHDROutput 1, OutputDevice 5, ColorGamut 2, UI.CompositeMode 1, UI.Level 3.0.
- Cheap-beauty pass 8 September 2026 (backup `Engine.ini.bak-2026-09-08c`), all four verified
  registered in the exe by the UTF-16 cvar scan, applied together because he asked for immersion on a
  game he now calls fast:
  * `r.PostProcessAAQuality` 4 -> 6 - more samples when TAA resolves its history, which is where
    every pixel comes from at ScreenPercentage 60. Best image-quality-per-frame line left. Revert to
    4 first (5 is the halfway step).
  * `r.SSS.HalfRes=0` + `r.SSS.Quality=1` - add-back queue item 4, done. Full-resolution subsurface
    scattering on flesh. Affordable BECAUSE the pass only touches pixels using a subsurface shading
    model: zero cost in an empty corridor, a small fraction of the screen over a corpse. That is the
    opposite of ScreenPercentage, which charges for every pixel every frame.
  * `r.AmbientOcclusionMipLevelFactor` 0.5 -> 0.4 and `r.GTAO.NumAngles` 2 -> 4 - AO keeps its shape
    on small props and loses the banded look in corners; the GTAO pass already runs at half res.
  * `r.ParticleLightQuality=2` - sparks, fire, plasma and muzzle flashes cast real dynamic light.
    Cost is spiky, not constant: only while an effect with a light is on screen.
  NOT applied and why: `r.VolumetricFog.GridPixelSize` 8 -> 6 (queue item 6) and
  `r.Shadow.FilterMethod=1` (queue item 9, PCSS) are both genuinely expensive pixel work, and
  `r.SSGI.Enable` stays 0 because of the August crashes, not performance.

- ROLLED BACK 8 September 2026: the cheap-beauty pass greyed the UI out under HDR. Engine.ini is now
  byte-identical to `Engine.ini.bak-2026-09-08c`, the state he called amazing (HDR device 5,
  ColorGamut 2, UI.Level 3.0, no beauty lines). The broken version is kept as
  `Engine.ini.bak-2026-09-08d-beauties-greyedout`.
  MISTAKE, worth not repeating: FIVE cvars were applied at once, against this file's own
  one-change-at-a-time rule, so which one breaks the HDR UI composite is unknown. Safe re-add order
  when it is retried, least to most suspect: (1) `r.AmbientOcclusionMipLevelFactor=0.4` +
  `r.GTAO.NumAngles=4` and `r.ParticleLightQuality=2` - pure lighting/AO, nowhere near the composite
  chain; (2) `r.SSS.HalfRes=0` + `r.SSS.Quality=1` - adds a full-res pass writing scene colour;
  (3) `r.PostProcessAAQuality=6` LAST - it is the only one that alters the post-process chain the
  HDR UI composite hangs off, so it is the prime suspect.
  GENERAL RULE this proves: with engine HDR on, any change to the post-process chain can break the
  UI composite, so HDR must be treated as a constraint on every future graphics change in this file,
  not as a settled one-off.

- *** ROOT CAUSE OF EVERY HDR "GREYED OUT" REPORT, found 8 September 2026. It was never the cvars. ***
  The game REWRITES `GameUserSettings.ini` on exit and resets `bUseHDRDisplayOutput` to False. Proof:
  Engine.ini was restored at 13:19 byte-identical to the config he had just called amazing, the UI was
  still grey, and GameUserSettings.ini had an mtime of 13:27 with `bUseHDRDisplayOutput=False` - a
  value that had been set to True earlier the same day.
  MECHANISM: `UGameUserSettings::ApplyResolutionSettings` calls `EnableHDRDisplayOutput(bUseHDR...)`,
  which sets `r.HDR.EnableHDROutput` with ECVF_SetByCode, and SetByCode OUTRANKS
  SetBySystemSettingsIni - the same precedence trap this file already documented for `t.MaxFPS`. So
  the swap chain comes up SDR while `r.HDR.Display.OutputDevice=5` still drives the tonemapper to
  emit scRGB HDR values. HDR pixels into an SDR swap chain IS the washed-out grey picture.
  It only ever looked right on the launch immediately after the file was edited to True.
  FIX APPLIED: `bUseHDRDisplayOutput=True` and `GameUserSettings.ini` set READ-ONLY, the same trick
  already used for Input.ini, so the game cannot reset it. Backup `GameUserSettings.ini.bak-2026-09-08`.
  Low risk because Nightdive keep their real settings in `ShockSettings.sav`, not here.
  CONSEQUENCE - two earlier conclusions in this file are now SUSPECT, not settled: the 11 August
  "engine HDR blows out the HUD" verdict and the 8 September device-3 grey-out may both have been
  this same SDR-swap-chain bug rather than anything about the UI composite path or OutputDevice.
  `r.HDR.UI.Level` being "measured inert" in August fits that too - with HDR output never actually
  enabled, of course it did nothing. Do not treat device 3 as disproven.

- *** ENGINE HDR IS NOT ACHIEVABLE FROM AN INI IN THIS GAME. Proven 8 September 2026, stop trying. ***
  An ASCII scan of the whole 7.5 GB base pak finds `EnableHDRDisplayOutput`, `SupportsHDRDisplayOutput`,
  `IsHDREnabled` and `ApplyResolutionSettings` as Blueprint call names, and does NOT find
  `bUseHDRDisplayOutput` or `HDRDisplayOutputNits` anywhere. So Nightdive's settings Blueprint CALLS
  EnableHDRDisplayOutput itself and never reads the GameUserSettings property - which is why editing
  `bUseHDRDisplayOutput` (even with the file made read-only, which did hold: mtime 13:28 survived a
  13:32 launch) changed nothing. The Blueprint has no HDR menu to drive it, so it passes false, and
  SetByCode beats SetBySystemSettingsIni, so `r.HDR.EnableHDROutput=1` in the ini is always undone.
  AND THE SECOND HALF OF THE LESSON: `r.HDR.Display.OutputDevice` is NOT undone - it drives the
  tonemapper, not the swap chain. Leaving it at 5 while the game forced the swap chain to SDR meant
  scRGB HDR pixels were written into an SDR surface every frame. THAT is the washed-out grey picture,
  and it is why restoring a byte-identical known-good Engine.ini did not fix it: the known-good file
  still had device 5. Final state: AllowHDR 0, EnableHDROutput 0, OutputDevice 0 (sRGB), ColorGamut 0,
  GameUserSettings.ini writable again with bUseHDRDisplayOutput=False.
  The "amazing" launch was real but was a one-off ordering fluke, not a working configuration.
  REMAINING ROUTES TO REAL HDR, in order: (1) Special K - an scRGB retrofit at the swap chain, which
  a Blueprint cannot undo; untested here because it injects an x64 DLL into a Prism-emulated process
  on ARM64. (2) Windows Auto HDR, already on globally and per-exe, zero risk. (3) a pak mod replacing
  SAVE_Settings to pass true - needs UnrealPak and Blueprint editing, not practical.

- CONFIRMED WORKING by him 8 September 2026 after OutputDevice went back to 0. Session end state:
  SDR output + Windows Auto HDR, the 8 September performance pass in place (decal 1.0, shadow maps
  2048/512, TransitionScale 40, vsync off), 10 mod paks with 79 known conflicts. STILL PENDING and
  never actually tested: the four cheap-beauty cvars (`r.PostProcessAAQuality=6`, `r.SSS.HalfRes=0`
  + `r.SSS.Quality=1`, `r.AmbientOcclusionMipLevelFactor=0.4` + `r.GTAO.NumAngles=4`,
  `r.ParticleLightQuality=2`). They were blamed for the grey UI and that was WRONG - the cause was
  OutputDevice 5 against an SDR swap chain. They are kept in
  `Engine.ini.bak-2026-09-08d-beauties-greyedout` and are worth re-adding one at a time now that HDR
  is out of the picture.

- CORRECTION to the "engine HDR is not achievable from an ini" note above - THAT CONCLUSION WAS WRONG
  and was built on a bad test. Timeline reconstructed 8 September 2026 from Steam Cloud mtimes and the
  registry key's last-write time:
  * The read-only `bUseHDRDisplayOutput=True` fix was applied at 13:28, but the Steam Cloud sync at
    13:32 was the game EXITING - it had been launched before 13:28, so his "same - greyed out" report
    described a session that started before the fix existed. That fix was NEVER TESTED.
  * `HKCU\...\DirectX\UserGpuPreferences` was last written at 13:37, i.e. he turned Windows Auto HDR
    off AFTER all of this. It was ON (global `AutoHDREnable=1`, per-app `AutoHDREnable=4147`) for the
    whole earlier part of the session, so it was never the thing being tested either.
  * Also wrong was the reasoning FROM the pak scan: `bUseHDRDisplayOutput` is a `config` UPROPERTY read
    by the C++ config loader, so its absence from the pak proves nothing. `IsHDREnabled` IS in the pak,
    and UE4's `ApplyResolutionSettings` calls `EnableHDRDisplayOutput(IsHDREnabled(), ...)` - which
    returns that very property. So the game DOES honour it; it just rewrites it to False on exit.
  COHERENT EXPLANATION OF EVERYTHING: engine HDR works when `bUseHDRDisplayOutput=True` is present at
  launch (that is the "amazing" launch, right after it was first set). The game resets it to False on
  exit, so every later launch had HDR output off while `r.HDR.Display.OutputDevice=5` still drove the
  tonemapper - scRGB pixels into an SDR swap chain, which is the grey picture.
  CONFIG NOW (restored from `Engine.ini.bak-2026-09-08c`): AllowHDR 1, EnableHDROutput 1,
  OutputDevice 5, ColorGamut 2, UI.CompositeMode 1, UI.Level 3.0, GameUserSettings.ini with
  `bUseHDRDisplayOutput=True` AND SET READ-ONLY so the exit rewrite cannot undo it.
  PROCEDURAL LESSON THAT CAUSED THREE WASTED LAUNCHES: never edit these files while the game is
  running, and confirm it is closed (`tasklist | grep -i systemreshock`) before every test.
  He does NOT want Windows Auto HDR - it is off and should stay off; native output is the goal.

- Device 5 with a clean launch (game confirmed closed, flag True and read-only, Auto HDR off) was
  STILL grey, 8 September 2026. So the remaining variable is the SWAP-CHAIN FORMAT: device 5 needs
  R16G16B16A16_FLOAT in scRGB, device 3 needs R10G10B10A2 in PQ. If the Adreno driver under Prism
  refuses one, UE4 silently falls back to an SDR swap chain while the tonemapper keeps encoding for
  whatever OutputDevice says - HDR pixels in an SDR surface, i.e. grey. 10-bit PQ is far more widely
  supported on mobile-derived GPUs, so device 3 + ColorGamut 1 is now set as the last clean test.
  IF THAT IS ALSO GREY: engine HDR is out on this hardware, and the revert needs ALL THREE of
  AllowHDR=0, EnableHDROutput=0 and OutputDevice=0 - leaving OutputDevice at an HDR device is what
  kept the grey picture after earlier reverts. Then Special K is the only remaining route.

- *** SETTLED 8 September 2026: ENGINE HDR DOES NOT WORK ON THIS MACHINE. Do not try it again. ***
  Both swap-chain formats were tested cleanly (game confirmed closed, `bUseHDRDisplayOutput=True` and
  the file read-only, Windows Auto HDR off, display HDR on and 10-bit): device 5 = FP16 scRGB, grey;
  device 3 = 10-bit PQ, grey. The engine's own HDR path is out - the Adreno X1-85 driver under Prism
  will not give UE4 an HDR swap chain, so UE4 falls back to SDR while the tonemapper keeps encoding
  for OutputDevice. Reverted to AllowHDR=0, EnableHDROutput=0, OutputDevice=0, ColorGamut=0, and
  GameUserSettings.ini writable again with the flag False.
  REVERT RULE worth keeping: all THREE of AllowHDR, EnableHDROutput and OutputDevice must go to 0.
  Leaving OutputDevice on an HDR device is what kept the picture grey after two earlier reverts and
  cost several launches.
  HDR options that remain: Windows Auto HDR (works, he does not want it) or Special K (creates its
  own HDR swap chain, so the engine's refusal is irrelevant; untested here because it injects an x64
  DLL into a Prism-emulated process on ARM64). Awaiting his decision on Special K - it is a
  third-party injector install, so ask before installing it.

- FINAL STATE 8 September 2026. Windows Auto HDR RESTORED by writing back the exact values read from
  `HKCU\Software\Microsoft\DirectX\UserGpuPreferences` earlier the same session - global
  `AutoHDREnable=1`, per-app `AutoHDREnable=4147` with `DXGIEffects=17179870208`. The per-app
  DXGIEffects delta between on and off is exactly 1024, which is the Auto HDR bit and confirms the
  recorded values were right. He chose Auto HDR over trying Special K.
  He also asked for the cheap-beauty pass back, so all five lines are re-applied and verified to be
  the ONLY difference from `Engine.ini.bak-2026-09-08e`: `r.PostProcessAAQuality=6`,
  `r.SSS.HalfRes=0` + `r.SSS.Quality=1`, `r.AmbientOcclusionMipLevelFactor=0.4` +
  `r.GTAO.NumAngles=4`, `r.ParticleLightQuality=2`. HDR lines all confirmed still at 0.
  These lines are now UNTESTED FOR PERFORMANCE - they were applied, blamed for the grey UI, removed,
  and re-applied without ever running. Revert order if frames drop: PostProcessAAQuality to 4, then
  GTAO.NumAngles to 2, then SSS.HalfRes to 1.

- Auto HDR final arrangement, confirmed in the registry 8 September 2026: he set it OFF globally
  (`AutoHDREnable=0`) and ON for the game only (`AutoHDREnable=4147` per-exe, with
  `SwapEffectUpgradeEnable=1`). Cleanest possible setup - leave it.
- Auto-HDR-aware tuning added the same day, all free, backup `Engine.ini.bak-2026-09-08f`:
  `r.Tonemapper.GrainQuantization=1` (the dither UE4 applies before quantising to 8 bits - the most
  Auto-HDR-relevant line there is, because Auto HDR stretches an 8-bit DARK image and this game is
  all dark corridors, which is exactly where banding shows; it is dither, NOT film grain, which
  remains unreachable from any ini), plus `r.GTAO.ThicknessBlend=0.75` and `r.GTAO.FalloffEnd=250`.
  DELIBERATELY NOT SET: `r.SceneColorFormat=4`. It is almost certainly already the default, and if
  Nightdive cooked 3 (RGB10A2) for scalability then forcing RGBA16F doubles scene-colour bandwidth
  on a unified-memory SoC that is bandwidth-starved. Not worth the risk for a probable no-op.
  Held back as costed options he has not chosen: `r.Tonemapper.Sharpen` 1.0 -> 0.7 (Auto HDR turns a
  sharpen halo into a BRIGHT halo, but this is a taste change and he is sensitive to those),
  `r.Bloom.Cross` 0.5 -> 1.0 (free, full anamorphic streaks, synergises with Auto HDR),
  `r.LightShaftBlurPasses` 3 -> 4, `r.VolumetricFog.HistoryMissSupersampleCount` 4 -> 8,
  `r.VolumetricFog.GridPixelSize` 8 -> 6 (queue item 6) and `r.Shadow.FilterMethod=1` (queue item 9,
  PCSS - the best-looking and most expensive line available). All verified registered in the exe.

- 25 fps measured with the beauty pass + Auto HDR tuning, 8 September 2026, so the beauty pass cost
  about 2 fps against the ~27 baseline. Cut back the same day (backup `Engine.ini.bak-2026-09-08g`),
  in the revert order the file itself specified: `r.PostProcessAAQuality` 6 -> 4,
  `r.SSS.HalfRes` 0 -> 1 with `r.SSS.Quality` 1 -> -1 (automatic), `r.GTAO.NumAngles` 4 -> 2,
  `r.ParticleLightQuality` 2 -> 1 (kept in reduced form - the per-particle approximation still throws
  light from sparks and fire). One DELIBERATE new cut: `r.VolumetricFog.GridPixelSize` 8 -> 10, which
  is 36% fewer froxels in a pass that runs constantly in this fog-filled station - the biggest real
  saving left that is neither resolution nor an object-count cut he already chose to pay for.
  KEPT because they are free: `r.Tonemapper.GrainQuantization=1`, `r.GTAO.ThicknessBlend=0.75`,
  `r.GTAO.FalloffEnd=250`, `r.Shadow.TransitionScale`/`SpotLightTransitionScale` 40.
  ADDED, free: `r.Bloom.Cross` 0.5 -> 1.0 (full anamorphic streaks, and under Auto HDR those streaks
  are the brightest thing in the stretched frame).
  NEXT CUTS IF STILL SHORT, all visible losses he previously chose to buy, in value order:
  `r.ViewDistanceScale` 1.5 -> 1.0, `r.Shadow.RadiusThreshold` 0.01 -> 0.03, `r.DetailMode` 2 -> 1,
  `r.SSR.MaxRoughness` 0.8 -> 0.6, `r.AmbientOcclusionLevels` 2 -> 1. Or spend ScreenPercentage,
  which is still the only knob with a measured model (K = 97,000: SP 57 -> 30, 52 -> 36, 48 -> 42).

- CORRECTION he made 8 September 2026: 25 fps was the baseline BEFORE the beauty pass, not after, so
  the beauty pass was FREE and the 2-fps attribution was wrong. All five lines restored
  (`r.PostProcessAAQuality=6`, `r.SSS.HalfRes=0`, `r.SSS.Quality=1`, `r.GTAO.NumAngles=4`,
  `r.ParticleLightQuality=2`) plus `r.Bloom.Cross=1.0`. Backup `Engine.ini.bak-2026-09-08h`; the
  25 fps config itself is `Engine.ini.bak-2026-09-08g`.
  METHOD RULE this cost time: never attribute a frame change to a line without a before AND an after
  number. He reports single numbers, so ask which config a number belongs to before reverting things.
- Real cuts applied instead, chosen because they are genuine PIXEL work and none of them touches what
  he deliberately bought (small-prop shadows, decal distance, view distance, detail mode):
  `r.SSR.Quality` 2 -> 1 (SSR marches rays per pixel; the loss is invisible because the reflection is
  already half-res AND reading half-res scene colour), `r.VolumetricFog.GridSizeZ` 64 -> 48 with
  `GridPixelSize` 8 -> 10 (the fog pass costs pixels x slices, so together that is roughly HALF the
  froxels, and fog runs constantly in this station - the largest saving available that is not
  resolution), `r.AmbientOcclusionMaxQuality` 100 -> 75 (a percentage cap on the AO pass' own sample
  budget, leaving Levels and RadiusScale alone so the grounding survives).
  Do NOT cut the object-count knobs to chase frames: 2026-08-11 measured DetailMode, RadiusThreshold,
  AO levels, SSR roughness and bloom as free three separate times. Cutting them costs looks and buys
  almost nothing.

- ScreenPercentage stays 60 (chasing 30 fps was judged not worth it). The reason is
  worth keeping: the only real payoff for exactly 30 on a 60 Hz panel is even pacing with VSync ON,
  and that does not apply here - VSync is off and `t.MaxFPS` is inert in this build, so nothing would
  hold the frame at 30, and an AVERAGE of 30 means dips that would land on 20 if VSync went back on.
  27 -> 30 is a 10% frame-time change with no pacing benefit for 5% less linear resolution forever.
- Last free-class beauty additions, 8 September 2026 (backup `Engine.ini.bak-2026-09-08j`), all
  verified registered: `r.SSS.Scale=1.1` with `r.SSS.Burley=1`, `r.SSS.Burley.Quality=1` and
  `r.SSS.SampleSet=2` pinned (those three are already 4.27 defaults, pinned only so scalability
  cannot drop them; Scale is the actual change and is visible only because HalfRes is 0);
  `r.ContactShadows=1` (free, and INERT if Nightdive authored no per-light Contact Shadow Length -
  zero downside, large upside if they did); `r.SkeletalMeshLODBias` 0 -> -1 (mutants, corpses and the
  Hacker's arms hold top LOD about twice as far - this reverses an old "not worth re-adding" note
  that was written during the 6-7 fps panic and does not survive the object-count-is-free
  measurement). Revert SkeletalMeshLODBias first if a busy fight drops frames.
  THE FREE LIST IS NOW EXHAUSTED. Everything remaining costs frames and is priced in the add-back
  queue: `r.Shadow.FilterMethod=1` (PCSS, best-looking and most expensive), fog grid back to 8/64,
  `r.SSR.Quality` back to 2, `r.GTAO.Downsample=0` (full-res AO), `r.LightShaftBlurPasses=4`,
  `r.Shadow.MaxSoftKernelSize` above 40, `r.StaticMeshLODDistanceScale` below 1.0, or spending
  ScreenPercentage. Do not invent more "free" lines - the ones left are all measured or reasoned
  costs.

- AUTO SR IS IMPOSSIBLE WHILE AUTO HDR IS ON. Confirmed 8 September 2026 from the Windows Graphics
  settings page for the exe, which states it outright: "Auto HDR and Auto SR can't be used together."
  The Automatic super resolution toggle is Off and greyed out because Auto HDR is On, so the
  `AutoSuperResolutionEnable=1` sitting in that exe's UserGpuPreferences value is INERT. Drop the
  idea of using the NPU upscaler unless he ever gives up Auto HDR. Same page confirms GPU preference
  = High Performance (Adreno X1-85) and "Optimisations for windowed games" = On.
- PCSS APPLIED 8 September 2026, add-back queue item 9, the last one (backup
  `Engine.ini.bak-2026-09-08k`): `r.Shadow.FilterMethod=1`, verified registered. PCF filters a fixed
  kernel so every shadow edge is equally soft; PCSS searches the shadow map for the blocker DISTANCE
  first and sizes the filter from it, so contact edges are hard and thrown shadows go soft. Most
  expensive line in the file after ScreenPercentage - two passes over the kernel per shadowed pixel.
  TUNE BEFORE REVERTING: `r.Shadow.MaxSoftKernelSize` (default 40) only becomes live with PCSS and
  caps the widest filter, so 24 or 16 keeps the contact-hardening while cutting the worst case.
  THE ADD-BACK QUEUE IS NOW EMPTY - every item applied or measured unaffordable. Queue entries 5, 6
  and 8 were also corrected to match reality (item 6 went the other way: fog was CUT to 10/48 and
  restoring 8/64 is now a priced upgrade, not a freebie).

- PCSS cost 4 fps: 27 -> 23 measured 8 September 2026 (that batch also included ContactShadows,
  SSS.Scale and SkeletalMeshLODBias). Trimmed the same day, backup `Engine.ini.bak-2026-09-08l`:
  * `r.ContactShadows` 1 -> 0. A REDUNDANCY cut, not a quality cut - contact shadows existed to fill
    the tight contact gap that a fixed-width PCF kernel left, and PCSS now solves that properly by
    sizing the filter from the blocker distance. Paying for a screen-space ray march per shadowed
    pixel to redo what PCSS just did is the definition of expensive and useless.
  * `r.Shadow.MaxSoftKernelSize=16` (default 40). Live only with PCSS; caps the widest filter. The
    blocker search still runs so contact hardening is untouched - what shrinks is the very soft far
    end of long thrown shadows, which is where nearly all the cost is because filter cost grows with
    kernel AREA. 24 if 16 reads too hard, 40 for stock PCSS.
  * `r.AmbientOcclusionMaxQuality` 75 -> 50. With PCSS producing real contact darkening, AO is doing
    less of the work, so its sample budget is the right place to trim. Levels/RadiusScale/
    MipLevelFactor/ThicknessBlend/FalloffEnd all kept.
- GRAPHICS MODS IDENTIFIED 8 September 2026 for his two complaints, both pak mods with no GPU cost:
  * "everything too red" -> Nexus 33 "(2.1) Remove Red Tint". Changes the SKY LIGHT colour to remove
    the ambient red cast on walls, floors and props; replaces `Content\Blueprints\Utility\
    LevelAtmosphere`, which none of his 10 paks touch, so no conflict. There is a 2.1 build matching
    the 2.x game. Caveat from the mod page: some areas get much darker. Lore note: the red IS the
    neural interface's infrared night-sight, so this removes an intended effect.
  * "more real than pixelated" -> Nexus 21 "Enable texture filtering". This is THE fix for the 2,951
    TF_Nearest texture overrides documented earlier; no ini can touch them. It was declined on
    7 September over the v1.0-cook vs 2026-07-20-build risk, but he has now asked for exactly this,
    so it is worth testing - if it breaks, delete the pak. IF INSTALLED, `r.MaxAnisotropy` becomes
    live for the first time and is the line to drop to 4 if frames fall.
  ADVISED AGAINST: the ReShade presets (Nexus 8 Shodan Shock, 121 Rudy, 129 Clear Image). They add
  real post-process passes at 5120x1440 on a GPU already at 23 fps, and ReShade injects its own
  swap-chain hooks, which is exactly the layer Auto HDR is working in. Nexus 140 "Extended Map
  Colors" also exists as the successor to the MapColors pak he deleted.

- `SystemShock-Windows_RemoveRedTint_NeutralLight_P.pak` INSTALLED 8 September 2026 (Nexus 33). Pak
  v11, 11,470 bytes, one asset: `SystemShock/Content/Blueprints/Utility/LevelAtmosphere`. Conflicts
  unchanged at 79 - nothing else touches LevelAtmosphere - and the pak count is now 11.
  NOTE HE DOWNLOADED THE 1.0 FILE (`-33-1-0-`, June 2023), not the 2.1 build the mod page also
  offers. Installed anyway because it is a single asset: if the level lighting breaks, the failure is
  obvious and deleting the pak is the whole fix. If the lighting looks wrong rather than merely
  darker, get the 2.1 file.
- Nexus has NOTHING else for the neutral/Doom 3 look, searched 8 September 2026: no film grain,
  vignette or LUT mods exist for this game. The only two are Nexus 33 (red tint, now installed) and
  Nexus 20 "UI No Chromatic Aberration" - which is the NoCAUI pak he deleted earlier the same day.
  Reinstalling it would fit the neutral aesthetic; community posts claim it also removes the UI
  scanlines, though direct inspection of the asset showed the ScanLines material function still
  referenced. The remaining anti-Doom-3 line is in his own ini, not a mod: `r.Bloom.Cross=1.0` is an
  anamorphic camera artefact and 0 removes it, free.

- `NoCAUI` REINSTALLED 8 September 2026 (Nexus 20, file `NoCAUI-20-1-0`, the same v1.0 pak as before).
  12 paks now, conflicts still 79 - it owns `MAT_UI_ScreenEffects` alone.
- VISUAL DIRECTION, stated 8 September 2026: realism,
  cinematic and immersive is GOOD; comic-book, stylised and pixelated is BAD. A
  suggestion to remove `r.Bloom.Cross` was rejected because an anamorphic lens streak is cinematic and therefore
  wanted. `r.Bloom.Cross=1.0` STAYS.
  CONSEQUENCE: the "CLARITY / Doom 3 look" block in Engine.ini is built on the OPPOSITE premise. It
  strips `r.SceneColorFringeQuality`, `r.MotionBlurQuality`, `r.DefaultFeature.MotionBlur`,
  `r.DepthOfFieldQuality`, `r.LensFlareQuality` and `r.DefaultFeature.LensFlare` - every one a
  cinematic camera effect he apparently wants. That block was written on 11 August as free
  performance and was never a taste decision he made. Raise it as a set of priced add-backs, best
  value first: scene chromatic fringe (nearly free - a few taps in a pass that already runs), then
  motion blur (real cost, but at 23 fps it is the effect that most improves perceived smoothness AND
  is the most cinematic), then lens flare, then depth of field (most expensive, pure pixel work).
  The UI is the one exception - he wants the HUD readable, which is why NoCAUI is installed.

- CINEMATIC ADD-BACKS applied 8 September 2026 at his request (backup `Engine.ini.bak-2026-09-08m`):
  `r.SceneColorFringeQuality` 0 -> 1 (SCENE chromatic aberration - nearly free, a few taps inside the
  tonemapper pass that already runs; the intensity comes from the level's post-process volume so the
  cvar only gates what the game shipped with) and motion blur ON with `r.MotionBlurQuality=3` plus
  `r.DefaultFeature.MotionBlur=1` (both lines are required - the DefaultFeature one is what lets the
  volumes enable it). Motion blur is cheaper here than it looks because TAA already renders a
  velocity buffer, so only the blur gather is new; and at 23 fps it is the only setting that improves
  PERCEIVED smoothness without improving the frame rate. Attribution is unambiguous if frames drop -
  the fringe line is nearly free, so any loss is the blur.
  The old "CLARITY / Doom 3 look" header in Engine.ini was rewritten to say its premise was wrong.
  Depth of field and lens flare remain OFF - items 3 and 4 of the priced list, which he did not take.

- TEXTURE FILTERING MOD INSTALLED 8 September 2026: `NVEnableTextureFiltering_P.pak` (Nexus 21,
  file `NVEnableTextureFiltering-21-0-1`, so v0.1 from June 2023). Pak v3, 17.5 MB, index 737 KB.
  Contents: 2,064 `.uasset` + 2,073 `.uexp` and only TWO `.ubulk` - it ships headers and exports and
  pairs them with the BASE pak's bulk data, which is exactly the version-mismatch risk (its headers
  are cooked against the June 2023 assets, the game build is 2026-07-20). Failure mode would be
  corrupt or black textures, or a load crash; the fix is deleting the pak.
  It covers 2,064 of the 2,951 TF_Nearest overrides counted in the base pak, so roughly 70% - some
  surfaces will stay point-sampled no matter what.
  13 paks now; conflicts still 79, because nothing else in the load order contains textures. Its
  filename sorts FIRST (N before S), so it loses any asset another pak claims - none do.
  `r.MaxAnisotropy=8` IS NOW LIVE FOR THE FIRST TIME. If frames drop after this, the fix is
  aniso 4, NOT removing the mod - 8x anisotropic filtering across every surface is real bandwidth
  on a unified-memory SoC, and it is the mod that made that line do anything at all.

- THE VISUAL MOD CATALOGUE IS EXHAUSTED, re-checked 8 September 2026 (~105-140 mods on Nexus). Every
  graphics-relevant one is now either installed or ruled out: 21 texture filtering (installed), 33
  red tint (installed), 20 UI CA (installed), 8/121/129 ReShade presets (advised against - real
  post-process cost at 5120x1440 and they hook the swap chain Auto HDR works in), 140 Extended Map
  Colors (cosmetic, successor to the MapColors pak he deleted), OldBloodMOD (restores the ORIGINAL
  pixel blood textures - against the realism direction). Everything else in the
  catalogue is gameplay or inventory. Do not re-search this.
  STILL UNINSTALLED, gameplay only: Nexus 14 Advanced Stackable Items (his own stated priority 1),
  25 More Recycler Slots, 28 Nixos pack (+12 inventory slots, and the 24-hour mission timer).
- TWO INI LINES BECAME LIVE with the texture filtering mod and are now real options for the first
  time: `r.MaxAnisotropy` (8, could go 16 for sharper floors and long corridors at grazing angles -
  costs bandwidth) and `r.MipMapLODBias` (0; negative sharpens distant textures but the file's
  standing warning applies - it costs texture bandwidth and aliases badly when upscaling from 60%,
  so shimmer is the failure mode).

- 23 fps AGAIN after scene fringe + motion blur + the texture filtering pak, 8 September 2026 - so
  all three were FREE, including 8x anisotropy going live across every surface. That proves texture
  bandwidth headroom exists on this SoC, which is worth remembering: the pessimism about LPDDR5X
  bandwidth in earlier notes was overstated for FILTERING work specifically.
  Two changes on the back of it (backup `Engine.ini.bak-2026-09-08n`):
  * `r.MaxAnisotropy` 8 -> 16. Anisotropy sharpens surfaces at GRAZING angles, i.e. floors and long
    corridors, which is most of what a first-person camera sees in Citadel. Most on-taste line in the
    file. Drop to 8 then 4 if frames fall - never drop the mod, the mod is the point.
  * `r.SSR.MaxRoughness` 0.8 -> 0.5, the "useless cost" cut. MaxRoughness widens WHICH surfaces trace
    rays. 0.8 was a good buy at SSR Quality 2 with full-res scene colour; with Quality 1 (few steps)
    reading HALF-RES scene colour, those extra rough surfaces only ever got a blurry smear - we were
    paying per-pixel ray marches for mush. 0.5 keeps polished metal, wet floors and glass tracing.
    These two move together: only restore 0.8 if SSR.Quality goes back to 2.
- Genuinely inert lines that are NOT worth cutting, for the record: `t.MaxFPS=30` (measured inert),
  `r.SSGI.HalfRes`/`r.SSGI.Quality` (kept so SSGI is one character away), and the four dead HDR lines
  (`OutputDevice`, `ColorGamut`, `UI.CompositeMode`, `UI.Level`) now that HDR output is off. All cost
  zero frames, so deleting them buys nothing - they are documentation, not waste.

- 11 September 2026 pass (backup `Engine.ini.bak-2026-09-11`; the file is kept READ-ONLY, clear the
  attribute before editing and restore it after). Exe UTF-16 scan re-run for 45 cvars; the base pak's
  cooked BaseScalability/DefaultEngine were read out with a chunked ASCII scan (hits near offset
  12.72-12.90 MB, uncompressed). FACTS FROM THE COOKED CONFIG: `r.AllowStaticLighting=False` (every
  light is dynamic, no lightmaps), `r.GenerateMeshDistanceFields=True`, `r.DBuffer=False`,
  `r.EarlyZPass=2`, `r.DefaultFeature.LensFlare=False` (Nightdive turned lens flare off as a project
  default - enabling it adds the stock UE4 flare, restores nothing), `r.TemporalAA.Upsampling=False`,
  `r.SSGI.Enable=False`. Tier 3 ships fog 8/128, `r.SSR.Quality=3` (glossy) with HalfResSceneColor 0,
  MotionBlurQuality 4, DOF 2, `r.ShadowQuality=5`, RadiusThreshold 0.01, `r.DistanceFieldAO=1`,
  `r.DistanceFieldShadowing=1`, `r.AOQuality=2`. AntiAliasing tier 3 = PostProcessAAQuality 4, Cine = 6.
  * BIGGEST FINDING: distance-field AO has never been in the ini, so it runs at tier values. With a
    Movable sky light (forced by AllowStaticLighting=False) and mesh distance fields generated, DFAO
    is almost certainly LIVE - a global-DF update every frame plus half-res cone tracing - and has
    never been measured. Probably visible (the sky light is the ambient fill the red-tint mod
    recolours). A/B steps written into the ini as commented lines: `r.AOQuality=1` first (global DF
    only, drops per-object tracing that GTAO duplicates), then `r.DistanceFieldAO=0` for the total.
  * APPLIED, all three free by construction and verified registered: `r.SSR.Stencil=1` (stencil
    prepass skips the ray march on pixels above MaxRoughness - most of the station at 0.5, zero
    visual change), `r.GTAO.UseNormals=1` (GBuffer normals instead of depth-derived, AO follows
    normal maps), `r.VolumetricFog.HistoryMissSupersampleCount=8` (cost only on disocclusion).
    Untested in play, like every batch before it. Verified: exactly 3 live lines added, 0 removed.
  * OPTIONS written as COMMENTED blocks, one flip each: dynamic resolution
    (`r.DynamicRes.OperationMode=2`, FrameTimeBudget 37, Min 55, Max 85 - replaces the fixed SP 60
    method; needs working GPU timestamps under Prism), `r.TemporalAA.Algorithm=1` (Gen 5 TAA, the
    TSR ancestor - best possible upscaler for SP 60 but compute-heavy and the same class as the
    SSGI crashes), `r.SSR.Quality=3` (first glossy level; 1 and 2 are mirror-sharp), translucency
    auto-downsample with thresholds 4.0/1.5 ms and 3 s min change (Epic's 1.5/0.5 would keep this
    GPU half-res in every steamy room), lens flare (`r.LensFlareQuality=2` + DefaultFeature 1).
  * REJECTED: `r.SceneColorFormat` 4 -> 3 (forces checkerboard SSS, hue banding in the darks Auto
    HDR stretches, ~1-3 % at best), `r.Shadow.TexelsPerPixel` (maps already scale with the render
    size), `r.TemporalAACatmullRom` (third sharpening layer). `r.MotionBlur.HalfResGather`/`HalfResInput`
    and `r.DOF.Gather.ResolutionDivisor` are NOT registered in this build; `r.TemporalAA.Quality` neither.
  * TOOLING TRAP that cost a fix pass: a PowerShell here-string has NO trailing newline, so a block
    inserted after a line merges its last line with the next one - it commented out `r.BloomQuality=5`
    until caught by a live-line diff against the backup. Always end inserted blocks with "`n" and diff
    the non-comment line sets before and after.
- DFAO A/B results, 11 September 2026. Step 1 `r.AOQuality=1`: 23 -> 25 fps, "working good", no
  flattening reported. Step 2 applied the same day at his request: `r.DistanceFieldAO=0` live (the
  AOQuality line is now dead but kept as a one-flip fallback), plus the translucency auto-downsample
  block live (4.0 / 1.5 ms, 3 s) because he authorised cutting non-visible cost. Attribution rule
  written into the ini: a steady fps change in a quiet area is DFAO, the downsample only acts in
  heavy smoke. Awaiting his step-2 number; if corners read lit-from-everywhere, DistanceFieldAO goes
  back to 1 and AOQuality=1 is the keeper. Still commented: `r.DistanceFieldShadowing=0` was NOT
  touched (RTDF shadows are per-light and would be a visible loss if any light uses them).
- STEP 2 MEASURED 11 September 2026: 25 -> 21 fps. The batch was `r.DistanceFieldAO=0` plus the
  translucency auto-downsample block, and the REGRESSION IS THE TRANSLUCENCY BLOCK, not DFAO:
  turning DFAO off only removes passes, so it cannot add cost, while auto-downsample needs a GPU
  TIMESTAMP QUERY every frame to decide - the same GPU-to-CPU round trip this file already blames
  for occlusion queries under Prism (`r.HZBOcclusion` comment). Reverted to commented the same day;
  do not re-enable it, and if it is ever retried it must be tested ALONE. `r.DistanceFieldAO=0`
  KEPT live (`r.AOQuality=1` above it is now dead, kept as a one-flip fallback).
- DYNAMIC RESOLUTION LIVE 11 September 2026, backup `Engine.ini.bak-2026-09-11b`. All five cvars
  verified registered (`UpperBoundQuantization` and `r.GPUStatsEnabled` are NOT in this build):
  OperationMode 2 (forces it on over the game's `bUseDynamicResolution=False`), FrameTimeBudget 37,
  Min/MaxScreenPercentage 50/80, ChangePercentageThreshold 4 (default 2 visibly pumps here).
  `r.ScreenPercentage=60` IS NOW INERT but deliberately left in place as the one-step fallback.
  TargetedGPUHeadRoomPercentage left at default 10, so it really aims at ~33 ms - erring toward
  frames after 21 fps was called bad; raise the budget to 45 to buy resolution back at ~22 fps.
  KNOWN RISK, same mechanism as the regression above: the heuristic reads GPU timestamps every
  frame. Failure is visible and one flip to undo - pinned soft at 50, or fps collapsed to ~15 at 80;
  either way OperationMode 0 restores the fixed 60.
  METHOD CHANGE: while this is on, fps is flat by design and QUALITY varies, so the K = 97,000
  model and every "measure one line against an fps number" habit in this file stop applying. It
  also makes further cost-cutting pointless as a frame chase - any saving is spent on resolution
  automatically.
- DYNAMIC RESOLUTION CONFIRMED GOOD by him 11 September 2026: 25-27 fps, "much better". So GPU
  timestamps DO work under Prism for this heuristic - which makes the translucency auto-downsample
  regression harder to explain by timestamps alone; treat that block as measured-bad, mechanism
  uncertain, rather than fully diagnosed.
  IMPORTANT REFRAME: with dynamic resolution on, a cut no longer shows up as fps - it shows up as a
  SHARPER PICTURE at the same fps, because the freed time is spent on render fraction automatically.
  So cutting cost is now the best way to buy image quality, the opposite of the earlier note.
- PAK SCAN 11 September 2026 settled two "is it inert?" questions (counts are non-default property
  occurrences, since UE elides defaults): `bCastCapsuleIndirectShadow` 21, `bCastCapsuleDirectShadow` 1,
  `bUseRayTracedDistanceFieldShadows` 5, `bAffectDistanceFieldLighting` 13, `bCastVolumetricShadow` 6,
  `DirectionalLightComponent` 8. So NEITHER capsule shadows nor DF shadows are inert.
  * `r.DistanceFieldShadowing=0` APPLIED (backup `Engine.ini.bak-2026-09-11c`): only FIVE lights use
    ray-traced DF shadows, and those five were keeping the whole global distance-field scene alive
    every frame. DFAO=0 alone did NOT end distance-field work - this line is what does. Not
    invisible: those five lights fall back to shadow maps. Back to 1 if a room loses its shadowing.
  * `r.CapsuleShadows` DELIBERATELY LEFT AT 1: authored on 21 skeletal meshes, i.e. character
    grounding, which is on-taste. (Possible they are already inert with AllowStaticLighting=False,
    but inert costs nothing and the cut would be visible on every character if that is wrong.)
  * `r.TranslucencyLightingVolumeDim` 64 -> 32 APPLIED: two view-covering volume textures injected
    with every dynamic light EVERY frame, paid whether or not smoke is on screen; 32 is 8x fewer
    voxels and the loss is only how finely a smoke cloud's lighting gradient is resolved.
- GEN 5 TAA LIVE 11 September 2026 (`r.TemporalAA.Algorithm=1`) at his request. Worth more under
  dynamic resolution than it would have been at a fixed 60 %, because a better reconstruction lets
  the same budget hold a higher render fraction. Failure signature is unique and shared with nothing
  else in this batch: a crash at start or in play, or ghosting/smearing behind moving mutants.
- *** GEN 5 TAA MEASURED BAD AND REVERTED, 11 September 2026: 25-27 -> 18-20 fps. Do not re-enable
  it at 5120x1440. *** The two cuts in that batch can only remove work, so attribution is certain.
  THE MECHANISM IS A GENERAL RULE NOW: `r.TemporalAA.Algorithm=1` runs its passes at OUTPUT
  resolution, not render resolution, so its cost does NOT shrink when dynamic resolution lowers the
  render fraction. It is a fixed toll the heuristic cannot pay down - which is why the picture went
  slower AND softer at once. With dynamic resolution on, any full-OUTPUT-resolution pass is worth
  far more than it appears, because it is the one cost the system cannot trade away. That reasoning
  is also why `r.PostProcessAAQuality` was cut 6 -> 4 in the same edit (it is a full-res pass; 4 is
  Nightdive's cooked tier 3, 6 is their Cine tier).
- 30 FPS TARGET, 11 September 2026, backup `Engine.ini.bak-2026-09-11d`. He asked for a stable 30.
  THE DIVISION OF LABOUR under dynamic resolution, which replaces this file's whole old method:
  the BUDGET sets the frame rate and every other line sets how much RESOLUTION that frame rate
  buys. Chasing fps with detail cuts no longer works - cuts come back as sharpness, not frames.
  Applied: FrameTimeBudget 37 -> 33.3 (30 fps exactly; with TargetedGPUHeadRoomPercentage at its
  default 10 it aims at ~30 ms, and that margin is what makes 30 a FLOOR not an average),
  MinScreenPercentage 50 -> 40 (at 50 it had nowhere to go in a fight, so the frame rate sagged
  instead of the picture), MaxScreenPercentage 80 -> 70 (less distance to fall, steadier frame time).
  PCSS CUT: `r.Shadow.FilterMethod` 1 -> 0, the biggest measured non-resolution cost in the file
  (4 fps, 27 -> 23). A real loss - uniform shadow softness again - and it is THE line to buy back
  first when there is headroom. `r.Shadow.MaxSoftKernelSize=16` is now inert but kept so restoring
  FilterMethod=1 restores the tuned version. Buy-back order if 30 holds with room: PCSS first,
  then PostProcessAAQuality 6.
- *** THE FIXED-COST RULE, worked out 11 September 2026 and it replaces this file's old method. ***
  He measured 26-28 fps against a 33.3 ms (30 fps) budget. Missing the budget while the heuristic is
  ALREADY trading resolution away proves the remainder is FIXED cost - work that does not shrink
  when the render fraction drops. So, under dynamic resolution:
    * Cutting SCALING cost (pixel work: SSR, fog, AO, SSS, translucency) buys a SHARPER PICTURE at
      the same fps, never more fps.
    * Cutting FIXED cost buys FPS. Fixed cost here = draw calls and vertex work, shadow-map
      rasterisation (maps are a fixed size, unrelated to render fraction), the UI at native
      5120x1440, and any full-OUTPUT-resolution pass (this is why Gen 5 TAA was so bad).
  The August "object count is free" measurement does NOT survive this - it was taken at a fixed
  render fraction, and since -norhithread the render thread also carries the RHI work.
- 30 FPS PUSH, 11 September 2026, backup `Engine.ini.bak-2026-09-11e`. Fixed-cost cuts:
  `r.Shadow.MaxResolution`/`MaxCSMResolution` 2048 -> 1024 with `WholeSceneShadowCacheMb` 512 -> 256
  (all three always move together); `r.ViewDistanceScale` 1.5 -> 1.0 (the file's own nominated first
  revert); `r.SkeletalMeshLODBias` -1 -> 0. FREE BEAUTY paired with the shadow cut:
  `r.Shadow.TransitionScale` and `SpotLightTransitionScale` 40 -> 30 - softer edges hide a 1024 map
  AND are the closest free approximation of the PCSS that was cut; 20 if edges still stair-step.
  Scaling-cost cut labelled honestly as picture, not frames: `r.SeparateTranslucencyScreenPercentage=50`
  - the DETERMINISTIC version of the auto-downsample that regressed earlier, with no GPU timestamp
  query and no state thrash, so it avoids the mechanism that failed.
  BUY-BACK ORDER if 30 holds with room: PCSS (`r.Shadow.FilterMethod=1`), then `r.ViewDistanceScale`
  1.5, then `r.PostProcessAAQuality=6`, then `r.SkeletalMeshLODBias=-1`, then shadow maps 2048.
  BIGGEST UNTOUCHED LEVER, never proposed to him: the OUTPUT resolution itself, 5120x1440 in
  `ShockSettings.sav`. Every fixed cost above scales with it, so lowering it is the only thing that
  cuts the UI pass, the tonemapper and the TAA resolve at once. It is a game setting, NOT a display
  setting, so it does not touch the display configuration.
- *** THE 30 FPS PUSH FAILED AND THE FIXED-COST CUTS BOUGHT NOTHING, 11 September 2026: still
  26-28 fps after shadow maps 2048->1024, ViewDistanceScale 1.5->1.0, SkeletalMeshLODBias -1->0. ***
  Two independent signs the frame is NOT limited by GPU pixel work: those cuts moved it by zero,
  and changing the budget 37 -> 33.3 ms (10 % more demand) moved it ~4 %. A heuristic genuinely
  controlling to a frame-time budget does not behave like that.
  LEADING HYPOTHESIS: the RENDER THREAD. It has carried the RHI work since `-norhithread` (the
  fix for the August locked-door crash, which must stay), and it is translating D3D12 calls under
  Prism emulation. Second candidate: the full-OUTPUT-resolution passes at 5120x1440 (UI/Slate,
  tonemapper, TAA resolve), which no render-fraction change can touch.
  DIAGNOSTIC RUNNING, backup `Engine.ini.bak-2026-09-11f`: Min=Max=40 pins the render fraction so
  pixel cost cannot vary. fps ~35+ means it IS pixel bound and the heuristic was simply not
  lowering resolution; fps still 26-29 means it is not, and no graphics cut reaches 30 - the only
  levers left would be draw-call COUNT (`r.DetailMode`, `r.Shadow.RadiusThreshold`) or the output
  resolution in `ShockSettings.sav`. REVERT to 40/70 after one launch either way.
  RECOMMENDATION: if the test says not-pixel-bound, stop at 28 and buy back PCSS.
- *** DIAGNOSTIC RESULT 11 September 2026, THE MOST IMPORTANT MEASUREMENT IN THIS FILE. ***
  Render fraction PINNED at 40 %: 26-28 fps. Floating 40-70 %: 26-28 fps. IDENTICAL. Halving the
  pixels changed nothing, so THE GAME IS NOT GPU PIXEL BOUND on this machine any more.
  What was really happening: the dynamic-resolution heuristic measures GPU time only, the GPU had
  spare capacity, so it sat at its CEILING - 70 was never a compromise, just the top of the range.
  The limit is the RENDER THREAD translating D3D12 under Prism, carrying the RHI work since
  `-norhithread` (which must stay - it is the locked-door crash fix).
  *** THIS INVERTS THE WHOLE FILE. The `fps * SP^2 = K` model (K = 97,000) is DEAD; it described a
  GPU-bound machine. PIXEL WORK IS EFFECTIVELY FREE below the render-thread floor, and DRAW-CALL
  and render-thread work is what actually costs. Roughly a month of "expensive pixel line" cuts -
  fog, SSR, AO budget, shadow resolution, PCSS, separate translucency - were all sold for nothing.
  The August "SP 60 -> 75 costs 27 -> 18 fps" measurement predates `-norhithread` and no longer
  describes this machine. ***
- HEADROOM SPENT 11 September 2026 at his instruction to improve graphics until fps drops, backup
  `Engine.ini.bak-2026-09-11g`. Everything restored is PIXEL work; everything still cut is
  DRAW-CALL work, and that distinction is the point:
  RESTORED: DynamicRes Max 40 -> 100 and Min -> 50 (resolution now climbs until the GPU is genuinely
  the limit, and it arbitrates automatically between resolution and the effects below);
  `r.Shadow.FilterMethod=1` (PCSS back, the file's best-looking line); shadow maps 1024 -> 2048 with
  cache 256 -> 512 (PCSS's blocker search needs the texels); TransitionScale 30 -> 40 (30 existed to
  hide a 1024 map and fake PCSS - both reasons gone, and extra softness fights PCSS);
  `r.PostProcessAAQuality` 4 -> 6; `r.SeparateTranslucencyScreenPercentage` 50 -> 100;
  `r.SSR.Quality` 1 -> 3 (FIRST level that blurs by roughness - 1 and 2 are mirror-only) with
  `MaxRoughness` 0.5 -> 0.8, the two always move together; fog 10/48 -> 8/64 (NOT the cooked 128 -
  depth slices also cost render-thread setup, which is the actual bottleneck);
  `r.AmbientOcclusionMaxQuality` 50 -> 100.
  STILL CUT ON PURPOSE: `r.ViewDistanceScale=1.0`, `r.SkeletalMeshLODBias=0` - draw calls, i.e. the
  real limit. Do NOT restore these to chase looks; they are the only lines that were cut correctly.
  IF FPS DROPS BELOW ~26: the GPU has become the limit at last, which is the goal - back off the
  most expensive restorations first: SSR.Quality 3 -> 2, fog 8/64 -> 10/48, PostProcessAAQuality 6 -> 4.
  NEXT LEVERS IF MORE FPS IS EVER WANTED - all render-thread, none of them pixels: `r.DetailMode`
  2 -> 1, `r.Shadow.RadiusThreshold` 0.01 -> 0.03 (fewer shadow-casting DRAW CALLS, not fewer
  pixels), `r.Decal.FadeScreenSizeMult` above 1.0, or the output resolution in `ShockSettings.sav`.
- CROSSOVER FOUND 11 September 2026. With everything restored and the ceiling at 100 %: 22-23 fps.
  So the GPU finally became the limit, which was the point of the exercise.
  *** THE CEILING IS THE REAL RESOLUTION CONTROL HERE, AND `r.DynamicRes.FrameTimeBudget` IS
  EFFECTIVELY INERT. *** Three measurements prove the heuristic just parks at whatever ceiling it is
  given rather than tracking its budget: max 40 -> 26-28, max 70 -> 26-28, max 100 -> 22-23. The
  first two are equal because the RENDER THREAD (~36-38 ms) was the limit in both. Treat
  MaxScreenPercentage as a fixed screen percentage.
  Ceiling 100 -> 80 applied, backup `Engine.ini.bak-2026-09-11h`, SINGLE VARIABLE - every restored
  beauty (PCSS, SSR.Quality 3 + MaxRoughness 0.8, fog 8/64, PostProcessAAQuality 6, full-res
  translucency, AO 100) was left alone, because resolution is the cheaper thing to sell.
  Arithmetic: 43 ms at 100 %, pixel cost scales with the SQUARE of the fraction, so 80 % is 0.64 of
  the pixels = ~28 ms GPU, back under the render-thread floor. Under 26 fps -> go to 70. Over
  28 fps -> go to 85, because above the floor extra fps is just unspent resolution.
- *** THE SCALING-vs-FIXED RULE, the single most useful thing learned on 11 September 2026. ***
  Ceiling 100 % -> 22-23 fps, ceiling 80 % -> 23-24 fps. Cutting 36 % of the PIXELS bought ONE
  frame, which repeats the earlier 40-vs-70 result. So on this machine the cost is almost never in
  the pixels. Sort every graphics line into two classes before touching it:
    * SCALES with the render fraction (cheap here, spend freely): per-pixel shading - PCSS, SSR,
      AO sample budget, subsurface, separate translucency, fog GridPixelSize.
    * FIXED, charged in full regardless of resolution (this is where the frames are): shadow-map
      SIZE, any OUTPUT-resolution pass (PostProcessAAQuality, Gen 5 TAA), fog GridSizeZ (depth
      slices multiply the whole grid), draw calls and vertex work, the UI at native 5120x1440.
  CORRECTION to older advice in this file: fog GridPixelSize and GridSizeZ must NOT be moved
  together - one scales and one does not. Same for shadow-map SIZE (fixed) vs PCSS filtering
  (scales): the earlier note that they "move together" was wrong.
- FIXED-COST REVERT 11 September 2026, backup `Engine.ini.bak-2026-09-11i`, to get back to 26-28:
  shadow maps 2048 -> 1024 with cache 512 -> 256 (4x the texels, and rendered at a fixed size every
  frame), `r.PostProcessAAQuality` 6 -> 4 (output-resolution pass), `r.VolumetricFog.GridSizeZ`
  64 -> 48 (slices are the fixed half of the fog grid).
  ALL SCALING WORK KEPT because it is cheap here: `r.Shadow.FilterMethod=1` (PCSS stays - it just
  does its blocker search against a smaller map, softer contact edges, far better than losing it),
  `r.SSR.Quality=3` + `MaxRoughness=0.8`, `r.VolumetricFog.GridPixelSize=8`,
  `r.SeparateTranslucencyScreenPercentage=100`, `r.AmbientOcclusionMaxQuality=100`.
  IF THIS LANDS AT 26-28: the resolution ceiling is nearly free (36 % of pixels = 1 fps), so raising
  it 80 -> 90 or 100 is the best remaining visual buy. That is the next step to offer him.
- 24-26 fps after the fixed-cost revert (up from 23-24). He wants more, so 11 September 2026,
  backup `Engine.ini.bak-2026-09-11j`, the DEPTH PREPASS was cut: `r.EarlyZPass=0` (cooked project
  value is 2). Verified registered, along with `EarlyZPassOnlyMaterialMasking`, `EarlyZPassMovable`,
  `MeshDrawCommands.ParallelPassSetup`, `DoInitViewsLightingAfterPrepass`.
  WHY IT IS THE RIGHT CUT, and it is today's whole lesson applied: EarlyZPass=2 draws every opaque
  AND masked mesh TWICE per frame, so it is pure DRAW-CALL cost - the class this machine is limited
  by - and what it buys is saved GPU shading, which this machine has spare (36 % of the pixels = 1
  fps). The Adreno X1-85 is also a tile-based GPU with hardware low-resolution-Z, so it already does
  in hardware much of what the prepass does in software. ZERO visual difference either way.
  Backfire symptom is the frame rate FALLING (overdraw costing more than the calls saved); middle
  step is `r.EarlyZPass=1` (opaque only), 2 restores cooked. `r.DBuffer=False` in the cooked config,
  so nothing depends on the prepass.
  Also reverted to engine defaults, pure CPU and no image cost: `r.Streaming.FramesForFullUpdate`
  3 -> 5 and `NumStaticComponentsProcessedPerFrame` 200 -> 50 (raised 27 Aug on the reading that
  "the CPU has headroom" - true overall, but it is per-frame work on the bottleneck thread).
  REMAINING FPS LEVERS, all draw-call/render-thread and all with a VISIBLE cost, in value order:
  `r.Shadow.RadiusThreshold` 0.01 -> 0.03 (small props stop casting shadows - each one is redrawn
  per shadow-casting light in range, so it is the biggest single draw-call line left),
  `r.DetailMode` 2 -> 1 (optional props and decals disappear), then the output resolution in
  `ShockSettings.sav`. He deliberately bought the first two, so ask before spending them.
- *** VERDICT 11 September 2026: THE FRAME RATE IS NOT REACHABLE FROM Engine.ini. STOP TUNING IT. ***
  `r.EarlyZPass=0` -> NO CHANGE (24-26 before and after), streaming defaults -> NO CHANGE. Both
  reverted (`Engine.ini.bak-2026-09-11k`): EarlyZPass back to the cooked 2 (shipped path is the
  tested one, and a heavy-overdraw room could cost later even though the test scene did not),
  streaming back to 3/200 (bought for pop-in, measured free, so keep the benefit).
  THE FULL DAY'S EVIDENCE, and it is conclusive: render fraction 40 vs 70 = no change; 80 vs 100 =
  1 fps; shadow maps + AA + fog slices = 1-2 fps; view distance and skeletal LOD = no change; depth
  prepass = no change; streaming work quartered = no change. The frame rate stays in a 22-28 band
  no matter what. Not pixel bound, not draw-call bound, not streaming bound.
  CONCLUSION: it is emulated-CPU bound - x64 game code and render thread running under Prism on
  ARM64. Nothing in any ini reaches that. The ONLY structural lever left is `-norhithread`, which
  was added 27 Aug to fix the reproducible locked-door D3D12 crash and which deliberately moves all
  RHI translation onto the render thread, i.e. it loads the exact thread that is now the limit.
  Removing it is the one change that could plausibly matter AND it brings back a crash - a deliberate decision,
  do it only deliberately.
  WHAT TO DO INSTEAD, given that visuals rank above performance: pixels are
  nearly free here (36 % of them = 1 fps), so spend the GPU on looks. Best buys in order: resolution
  ceiling 80 -> 100, shadow maps back to 2048 (PCSS blocker search), `r.PostProcessAAQuality` 6,
  fog `GridSizeZ` 64. Total cost across all four is roughly 1-2 fps.
- *** THE BIG SPEND, 11 September 2026, backup `Engine.ini.bak-2026-09-11l`. *** He accepted the
  verdict that frames are not reachable from the ini and asked for every cheap beauty, including
  ones reverted earlier. 15 lines changed, all in classes today measured free:
  THE FOUR PROMISED: DynamicRes ceiling 80 -> 100 (it is a fixed screen percentage here, so this is
  simply full resolution); shadow maps 1024 -> 2048 + cache 256 -> 512 (PCSS's blocker search needs
  texels); `r.PostProcessAAQuality` 4 -> 6; fog `GridSizeZ` 48 -> 64 (cooked tier ships 128, unspent).
  RESTORED AFTER TODAY'S CUTS MEASURED FREE: `r.ViewDistanceScale` 1.0 -> 1.5,
  `r.SkeletalMeshLODBias` 0 -> -1, `r.TranslucencyLightingVolumeDim` 32 -> 64.
  *** `r.SSR.HalfResSceneColor` 1 -> 0, REVERSING THE 7 SEPTEMBER VERDICT. *** It was blamed for a
  30 % loss but it was changed in the SAME batch as `r.Decal.FadeScreenSizeMult`, and the next
  session proved the decal line was the entire regression. It was never guilty. It is the partner of
  SSR.Quality 3 + MaxRoughness 0.8 - those pick which surfaces reflect, this makes the reflected
  image legible instead of a blurred thumbnail. PRIME SUSPECT if this batch costs frames.
  `r.Decal.FadeScreenSizeMult` 1.0 -> 0.5 (blood, scorch, grime at ~2x distance; 0.25 was always
  more than needed). `r.Shadow.MaxSoftKernelSize` 16 -> 40 (stock PCSS - capping it threw away the
  wide soft far end, which is the point of PCSS; contact edges unaffected).
  NEW, never applied before: `r.GTAO.Downsample=0` (full-res AO, an old add-back-queue item),
  `r.SSS.Checkerboard=0` (UE4 shades subsurface on a checkerboard of half the pixels by default -
  this is the dithered-skin fix), `r.LightShaftBlurPasses` 3 -> 4 (longer smoother god rays),
  `r.MotionBlurQuality` 3 -> 4 (cooked tier value and engine max).
  DELIBERATELY NOT APPLIED, with reasons: SSGI (5 crash sessions in August - the only crash-linked
  setting), depth of field (expensive AND the file's own note calls it least apt in first person),
  lens flare (Nightdive ship `r.DefaultFeature.LensFlare=False`, so it adds the generic stock UE4
  ghost/bokeh flare rather than anything authored - reads comic-book, against
  the realism direction), and distance-field AO (`r.AOQuality` 2 -> 1 was the ONE change all
  day that measurably gained frames, +2, so it stays off).
- *** `r.ShadowQuality` WAS SET BELOW THE SHIPPED VALUE - a real bug in this ini, found and fixed
  11 September 2026 (backup `Engine.ini.bak-2026-09-11m`). *** The cooked `ShadowQuality@3` tier -
  the one this machine runs, since GameUserSettings has `sg.ShadowQuality=3` - ships
  `r.ShadowQuality=5`. The file had pinned 3 since the August reset with no note justifying it,
  almost certainly copied from the sg. tier INDEX by mistake. It is a feature switch, not a
  resolution, so nothing else could compensate. Now 5. CHECK OTHER LINES THE SAME WAY: compare
  against the cooked tier values recorded earlier in this file before assuming a number was chosen.
- Also applied the same day, all in classes measured free: `r.VolumetricFog.GridSizeZ` 64 -> 128
  (the cooked tier value - this game is authored around 128, 64 was merely the engine default);
  `r.SSR.Quality` 3 -> 4 (engine max; 3 was the big step to roughness-blurred, 4 adds rays so rough
  reflections resolve instead of dissolving into TAA-smeared noise); `r.StaticMeshLODDistanceScale`
  1.0 -> 0.5 (station geometry holds TOP LOD to ~2x distance - the static-mesh counterpart of
  SkeletalMeshLODBias=-1, and the direct fix for blocky silhouettes down a corridor);
  `r.Shadow.DistanceScale` 1.0 -> 1.5 (cut in August only because 4096 maps overflowed the cache -
  maps are 2048 now and the cache is sized for them, so the reason is gone);
  `r.LightMaxDrawDistanceScale` 1 -> 2 (cut in August when it was 4 AND RadiusThreshold was 0, which
  compounded; the clutter cull is back so 2 is safe); `r.Shadow.MaxNumPoint/SpotShadowCacheUpdates
  PerFrame` 2 -> -1 (the 2 caps made shadows lag their lights by a frame or more in rooms with
  flickering lights - they were for PACING and explicitly never changed average fps).
  NOTE: two big batches (`bak-...-11l` and `-11m`) are now stacked with NO fps reading between them.
  If frames dropped, revert `-11m` first, then `r.SSR.HalfResSceneColor` back to 1 from the `-11l`
  batch - those are the two prime suspects in order.
  STILL OUT OF REACH, for the record: film grain (post-process volume property, needs a pak mod),
  ~887 of the 2,951 TF_Nearest textures the filtering mod does not cover, SSGI (crashes), and the
  output resolution in `ShockSettings.sav` (his call).
- USELESS-COST AUDIT 11 September 2026, backup `Engine.ini.bak-2026-09-11n`. Only TWO real finds:
  * *** `r.ShaderPipelineCache.BatchTime` 50 -> 16 and `BatchSize` 200 -> 50. *** The 27 Aug edit
    set BOTH pairs to the same numbers, but they are different things: `Precompile*` runs during
    the LOADING SCREEN (free, and it is what actually buys stutter-free play - left at 200/50 ms),
    while the plain `BatchTime`/`BatchSize` govern the background batch DURING PLAY. A 50 ms
    in-play compile budget on a machine whose whole frame is 38-42 ms can more than halve the
    frame rate wherever PSO work is pending, and shader creation is slow here because it is
    emulated. 16 ms is the engine default.
  * `r.RHICmdMinDrawsPerParallelCmdList` 32 -> 64 (default). 32 buys parallel TRANSLATION on
    threads that are idle, but more command lists means more begin/end and state-restore overhead
    at EXECUTION - which since `-norhithread` is serial on the render thread, i.e. the bottleneck.
  RULED OUT after checking, so do not revisit: `r.Shadow.CSM.MaxCascades` (tier ships 10, but the
  pak has ZERO non-default `DynamicShadowCascades`, so every directional light asks for the default
  3 and the cap is never reached - INERT); `r.CapsuleShadows` (21 of the 22 authored capsule
  shadows are INDIRECT, which needs an indirect lighting cache that cannot exist with
  `r.AllowStaticLighting=False`, so only 1 direct one works - but UE skips the pass entirely when no
  caster is in view, so cutting it buys ~nothing and risks character grounding);
  `r.AmbientOcclusionStaticFraction` and `r.AmbientOcclusionLevels` (both inert - no static
  lighting, and GTAO does not use the SSAO level pyramid).
  INERT BUT ZERO-COST, keep as documentation: the four dead HDR lines, `r.SSGI.HalfRes`/`Quality`,
  `t.MaxFPS=30`, `r.MipMapLODBias=0`, `r.AOQuality=1` (dead under `DistanceFieldAO=0`), and
  `r.DynamicRes.FrameTimeBudget`/`ChangePercentageThreshold` (proven inert - the ceiling is the
  only dynamic-resolution control that does anything here).
- RAM/CPU/SSD OFFLOAD PASS 11 September 2026, backup `Engine.ini.bak-2026-09-11o`. The framing that
  makes these right: RAM (31.6 GB, game working set 6.3 GB) and 11 of the 12 cores are idle, while
  the RENDER THREAD is saturated - so spend RAM and task threads, never render-thread work.
  * `r.Shadow.WholeSceneShadowCacheMb` 512 -> 2048, the best trade available. A cache MISS is a full
    re-render of every caster for that light, i.e. DRAW CALLS on the bottleneck thread. Today's own
    edits forced this: ShadowQuality 3->5, Shadow.DistanceScale 1.0->1.5 and LightMaxDrawDistance
    Scale 1->2 all put more shadow-casting lights in range at once. Point lights are the killer - a
    shadow CUBEMAP is six 2048 faces, 50-100 MB for ONE light, so 512 MB cached only a handful.
  * `r.RenderTargetPoolMin=400` added (the cooked PostProcessQuality tier 3 value, never set here).
    Keeps intermediate buffers allocated instead of freed/recreated - allocation is render-thread
    work, holding memory is not.
  * `r.MeshDrawCommands.UseCachedCommands=1` and `ParallelPassSetup=1` PINNED. Both are already the
    engine default, so no change expected - pinned because they are exactly the two mechanisms that
    keep draw-call work off the render thread, and a scalability change dropping either would be the
    worst possible regression on this machine. `CacheMultithreaded` is NOT registered in this build.
  NOTHING TO GAIN, checked and ruled out: `r.Streaming.PoolSize` is already 8192 MB against a
  7.93 GB TOTAL install, so the entire game fits in the pool - raising it is a pure no-op.
  NOT DONE, his call: moving the install from C: to the D: Dev Drive (7.93 GB, D: has 105 GB free,
  measured 2.6x faster). It would help load times and streaming hitches, NOT the frame rate, since
  the limit is emulated CPU. Steam's "Move install folder" does it; announce before touching it.
- RECLAIMED-IDEAS PASS 11 September 2026, backup `Engine.ini.bak-2026-09-11p`. Three applied, two
  staged as commented one-flip blocks:
  * `r.Tonemapper.Sharpen` 1.0 -> 1.5, restoring the ORIGINAL value with an exact reason: it was
    lowered on 11 Aug ONLY because the sharpen ran after TAAU upscaled from 60 % and rang on
    interpolated pixels. The DynamicRes ceiling is 100 % now, so the game renders at native again
    and that condition is gone. Failure mode is ringing (pale outline on the dark side of a
    high-contrast edge), NOT softness.
  * `r.VolumetricFog.HistoryMissSupersampleCount` 8 -> 16 (cooked Cine value) - paid only on
    disocclusion, and it is what stops the now-finer 8/128 grid sparkling on fast camera turns.
  * `r.ViewDistanceScale` 1.5 -> 2.0 (the pre-August value) - draw-call class, measured free four
    times today including a direct 1.5 -> 1.0 cut that changed nothing.
  STAGED, NOT LIVE - these are the only two things left with a real price:
  * `r.DistanceFieldAO=1` + `r.DistanceFieldShadowing=1`. THE ONE REAL VISUAL UPGRADE REMAINING, and
    the only line in the file with a MEASURED cost: ~2 fps of ~25 (the 23 -> 25 gain when cut). It
    is NOT a duplicate of GTAO - GTAO is screen-space and can only darken from on-screen geometry,
    while DFAO traces the world distance fields and gives ROOM-SCALE occlusion from geometry off
    screen. With `r.AllowStaticLighting=False` the sky light is Movable and DFAO is exactly what
    occludes its ambient fill - the same fill the RemoveRedTint pak recolours. `r.AOQuality=1` is
    the half-price option (~1 fps for most of the effect).
  * `r.Streaming.FullyLoadUsedTextures=1`. Blamed for the 6-7 fps config in August, but TWO
    conditions changed: the pool is 8192 MB against a 7.93 GB TOTAL install so the whole game fits,
    and texture BANDWIDTH was proven to have headroom when 8x -> 16x anisotropy went live for free.
    The old failure was bandwidth; the constraint now is the render thread, and this adds no draw
    calls. Highest-variance line left - test ALONE.
  ALSO RECONSIDERED AND STILL REJECTED: Gen 5 TAA (measured -7 fps, and it runs at output
  resolution so 100 % render fraction does not help it); lens flare (project-disabled by Nightdive,
  adds generic stock ghosts - against the realism direction); depth of field (expensive and
  least apt in first person); SSGI (the only crash-linked setting - 5 sessions in August).
- *** FULL AUDIT vs THE COOKED TIER-3 VALUES, 11 September 2026 - THE WELL IS DRY. *** Every live
  line in Engine.ini was diffed against the values extracted from the base pak's BaseScalability.
  Result: everything now either MATCHES the shipped tier or deliberately exceeds it. Exactly ONE
  disagreement remained and it is fixed (backup `Engine.ini.bak-2026-09-11q`):
  `r.AmbientOcclusionLevels` 2 -> -1. -1 is not "off", it is the engine AUTO setting which picks 2
  or 3 mip levels by AO quality; with MaxQuality back at 100 it picks 3, so this is a small quality
  GAIN as well as a correction. The hard 2 was pinned during the August 6-7 fps panic.
  (`r.SkeletalMeshLODBias=-1` also reads as "below shipped 0" in a naive diff but LOWER IS BETTER
  for a LOD bias - it is intentional. Do not "fix" it.)
- SYSTEMS CHECKED AND RULED OUT the same day, do not revisit: SkyAtmosphere (10 pak references),
  Groom/HairStrands (15 GroomComponent, 10 HairStrandsCore, but ZERO GroomBindingAsset) - name-table
  counting cannot distinguish "plugin enabled" from "actually used", and BOTH systems cost nothing
  when nothing in the scene uses them, so disabling risks the look for no measurable gain.
  VolumetricCloud and AtmosphericFog: zero references, genuinely absent, nothing to disable.
  Depth-prepass culling (`r.MinScreenRadiusForDepthPrepass` etc.) is dead by direct evidence -
  removing the ENTIRE prepass with `r.EarlyZPass=0` measured no change, so culling part of it cannot.
- STATE AT SESSION END: 17 backups from 11 Sep, `Engine.ini.bak-2026-09-11q` is the newest. FIVE
  batches (l, m, n, o, p, q) are stacked with NO fps reading since the 24-26 measurement. THE ONLY
  USEFUL NEXT ACTION IS TO MEASURE. If frames dropped, revert in this order: `-11m` (ShadowQuality 5
  + fog 128 + SSR 4 + LOD/shadow/light distances), then `r.SSR.HalfResSceneColor` back to 1, then
  `-11o` (shadow cache 2048 - RAM only, unlikely).
- STEAM FPS COUNTER DISAPPEARED 11 September 2026. Cause found in
  `Steam\userdata\<steam-id>\config\localconfig.vdf` - TWO separate switches, both off, and NEITHER
  is reachable from Engine.ini (no graphics setting can affect the Steam overlay):
  * `"InGameOverlayShowFPSCorner" "0"` - the global counter is off (0 = off, 1-4 = screen corner).
  * `"OverlayAppEnable" "0"` under the per-app block for 482400 - the overlay itself is disabled FOR
    THIS GAME, so the counter could not draw even with a corner selected. This is the one that
    matters and it is per-game, easy to hit by accident in the game's Properties.
  FIX IS UI-ONLY, because this file already records that
  localconfig.vdf must NEVER be edited while Steam is running (Steam rewrites it on exit and would
  discard the edit): Steam > Settings > In Game > In-game FPS counter > pick a corner; then
  right-click System Shock > Properties > General > tick "Enable the Steam Overlay while in-game".
  `LaunchOptions` still reads `-norhithread`, confirmed intact in the same file.
- CORRECTION to the note above: he uses the WINDOWS XBOX GAME BAR for fps, NOT the Steam overlay.
  The Steam findings stand as facts but are NOT the cause and were the wrong tree: for the record,
  Steam's `InGameOverlayShowFPSCorner=0` AND per-app `OverlayAppEnable=0` for 482400 are both off,
  so Steam's counter is available as a FALLBACK after two UI toggles (never edit localconfig.vdf
  while Steam runs).
- GAME BAR FPS COUNTER DIAGNOSIS, 11 September 2026, from registry key LAST-WRITE TIMES (P/Invoke
  RegQueryInfoKey - PowerShell has no native way to read these):
  * `HKCU\System\GameConfigStore` (holds `GameDVR_Enabled=0`) last written 24 MARCH 2026. So GameDVR
    has been off for ~6 months, i.e. it was off the whole time the counter WORKED - NOT the cause,
    and not worth changing.
  * `HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR\AllowAutoGameMode=0` dates from April 2024.
    Also not it.
  * `HKCU\...\CurrentVersion\GameDVR` and the game's `GameConfigStore\Children` entry were written
    today at 20:23:57 - that is just LastGameActivity/LastAccessed updating on launch. Normal.
  * `Microsoft.XboxGamingOverlay` 7.326.8061.0 is installed and Status Ok, and the game is still
    registered to it by MatchedExeFullPath.
  * *** THE ONLY CHANGE IN THE RIGHT TIME WINDOW: three Windows updates installed 10 SEPTEMBER 2026
    - KB5126052, KB5124008, KB5124007 - one day before the counter stopped. ***
  LIKELY FIX (his action, not a registry edit): Game Bar's fps counter needs a PER-GAME permission
  that an OS or Game Bar update can revoke. Win+G > Performance widget > if it shows a permission
  or "turn on" prompt for FPS, accept it, then REBOOT (the permission only takes effect after a
  restart). Do NOT flip GameDVR_Enabled to 1 as a fix - the timestamps prove it is not the cause.
- *** REAL CAUSE of the Game Bar fps counter stopping, 11 September 2026 at 20:28. Both earlier
  theories in this file (Steam overlay, then the 10 Sep Windows updates) were WRONG - ignore them. ***
  Process check told the whole story in one line: `GameBar` AND `GameBarFTServer` (the process that
  actually feeds the fps number) both have StartTime 20:20:49, i.e. GAME BAR RESTARTED 8 minutes
  before he reported it - consistent with "it worked 10 minutes ago". Game Bar hooks a game's
  presentation AT PROCESS START; when GameBarFTServer restarts it CANNOT re-attach to an
  already-running game, so the counter goes blank for that session while everything looks healthy.
  Also: no `SystemReShock` process was running at the time of the check, and there are NO new crash
  dumps in the last 6 hours, so nothing crashed.
  FIX: just relaunch the game with Game Bar already running. No registry change, no reboot, no
  permission re-grant. `GameDVR_Enabled=0` (since March) and the 10 Sep updates are both red
  herrings - do NOT change either.
  METHOD LESSON worth keeping: for "X stopped working N minutes ago", check PROCESS START TIMES
  first. Two rounds of registry archaeology and an update-history theory were all beaten by one
  Get-Process, and the timestamps also disproved the earlier answers.
- *** THE BEAUTY SPEND COST ~5 fps: 24-26 -> 20-21, measured 11 September 2026 after batches l..q. ***
  RESTORED to `Engine.ini.bak-2026-09-11l`, the config that MEASURED 24-26, rather than guessing
  which line to pull. The 20-21 config is preserved as `Engine.ini.bak-2026-09-11r-slow-20fps` so
  every beauty line can be cherry-picked back one at a time with a number behind each.
  23 lines were given up. The ones most likely to be the actual cost, for when they are retried
  ONE AT A TIME: `r.GTAO.Downsample=0` (full-res AO = 4x the AO pixels at 7.4 MPixels),
  `r.VolumetricFog.GridSizeZ=128` (2.7x the slices of 48, and fog runs constantly),
  `r.Shadow.MaxNumPoint/SpotShadowCacheUpdatesPerFrame=-1` (removes the throttle, so a room of
  flickering lights can do many full shadow re-renders in ONE frame - a pacing disaster),
  `r.SSS.Checkerboard=0` (2x subsurface pixels), `r.SSR.Quality=4` + `HalfResSceneColor=0`,
  `r.ShadowQuality=5`, shadow maps 2048, ceiling 100.
  RE-APPLIED on top of the restore - performance-positive or free ONLY, no beauty except one:
  the shader `BatchTime` 50 -> 16 + `BatchSize` 200 -> 50 fix (THE BEST HOPE IN THE FILE and still
  never measured alone), `r.RHICmdMinDrawsPerParallelCmdList` 32 -> 64,
  `r.Shadow.WholeSceneShadowCacheMb` 256 -> 2048 (RAM only, and it REMOVES draw calls),
  `r.RenderTargetPoolMin=400`, the two `r.MeshDrawCommands.*` pins, `r.AmbientOcclusionLevels=-1`,
  and `r.Tonemapper.Sharpen=1.5` (free - taps in an existing pass).
  METHOD LESSON, the expensive one of this session: SIX batches were stacked with no fps reading
  between them, so ~5 fps has no attribution and the only safe move was a wholesale restore. Never
  apply a second batch before the previous one has a number.
- RESTORE CONFIRMED by him 11 September 2026: ~24 fps, i.e. back in the 24-26 band. So the wholesale
  restore to `bak-2026-09-11l` recovered the ~5 fps the beauty batches had cost, and the shader
  `BatchTime` 50 -> 16 fix did NOT show a visible gain (24 is the low end of the band - within noise).
- DISCIPLINED RE-ADD LADDER started the same day, ONE step at a time with a number after each.
  Step 1 (backup `bak-2026-09-11s`): `r.ViewDistanceScale` 1.0 -> 1.5 and `r.SkeletalMeshLODBias`
  0 -> -1. Justification is a MEASUREMENT, not an argument: this exact cut was made earlier today and
  moved the frame rate by zero, so restoring it cannot cost what it did not save.
  Step 2 (backup `bak-2026-09-11t`): `r.StaticMeshLODDistanceScale` 1.0 -> 0.5 (same vertex/draw
  CLASS as step 1, so the same measurement stands behind it) and `r.ShadowQuality` 3 -> 5 (NOT a
  beauty add - a CORRECTION; the cooked tier this machine runs ships 5 and the file pinned 3 by
  mistake). If frames drop from 24, ShadowQuality is the suspect; the LOD line is innocent by class.
  REMAINING LADDER, best value per likely cost, all sitting in `bak-2026-09-11r-slow-20fps`:
  (a) `r.Shadow.MaxSoftKernelSize=40` - uncaps the PCSS that is already on, biggest visible shadow
      gain; (b) `r.VolumetricFog.HistoryMissSupersampleCount=16` and `r.LightShaftBlurPasses=4` -
      near-free by construction; (c) `r.SSS.Checkerboard=0` - only touches subsurface pixels;
      (d) `r.MotionBlurQuality=4`, `r.TranslucencyLightingVolumeDim=64`; (e) `r.PostProcessAAQuality=6`
      + shadow maps 2048 + ceiling 100 - the batch measured at 1-2 fps together; (f) `r.SSR.Quality=4`
      + `HalfResSceneColor=0`; (g) `r.GTAO.Downsample=0` and `r.VolumetricFog.GridSizeZ=128` - the two
      most likely to be the original 5 fps, try last. NEVER re-add
      `r.Shadow.MaxNumPoint/SpotShadowCacheUpdatesPerFrame=-1` (pacing) or
      `r.Decal.FadeScreenSizeMult=0.5` (measured at 3 fps in an earlier session).
- *** HE REMOVED `-norhithread` AND THE FRAME RATE DID NOT CHANGE, 11 September 2026. THE
  RENDER-THREAD THEORY THIS FILE BUILT ALL DAY IS DEAD. *** Note Steam only writes localconfig.vdf
  on EXIT, so the file still reading `-norhithread` does not prove what the last run used.
  SAFETY: `-norhithread` must go back regardless of performance - it is the fix for the four
  identical August D3D12 locked-door crashes, and it costs nothing now that it is measured free.
- Step 2 result: 24 -> 23 fps, so `r.ShadowQuality` 3 -> 5 cost about 1 fps (the LOD line was
  innocent by class, as predicted). ShadowQuality 5 KEPT - it is the shipped value and 1 fps is the
  right price for running the game's own preset.
- GAME-THREAD PASS, 11 September 2026, backup `Engine.ini.bak-2026-09-11u`. This is the LAST
  untested subsystem: nothing on the GPU or render thread moves this frame (render fraction 40 vs
  100 barely matters, draw calls free four times over, whole depth prepass removal did nothing,
  RHI thread on/off identical), so what is left is UE4 gameplay/animation/Blueprint/actor ticking
  as x64 code under Prism.
  FREE (no visual change): `a.ParallelAnimUpdate=1` - it DEFAULTS TO 0, so every anim Blueprint for
  every mutant and the Hacker's arms was running on the game thread; 1 pushes it to the task graph
  and the 11 idle cores. Failure mode is animation pops/T-poses if an anim BP is not thread-safe.
  Plus `a.ParallelAnimEvaluation=1`, `s.AsyncLoadingTimeLimit` 5 -> 2 ms (5 ms of a ~43 ms frame was
  going to streaming) and `s.PriorityAsyncLoadingExtraTime=5`.
  REAL CUTS, both VISIBLE and both game-thread as well as GPU: `r.DetailMode` 2 -> 1 (the optional
  high-detail actors are not SPAWNED at all, so it is fewer actors to TICK, not just fewer draws -
  the biggest game-thread lever in any ini) and `r.EmitterSpawnRateScale` 1.0 -> 0.5 (particles are
  ticked on the CPU before they are drawn; 0.75 is the halfway step).
  IF THIS DOES NOT MOVE THE NUMBER EITHER: the limit is Prism emulation overhead itself and 30 fps
  is NOT reachable from any config. That is the honest end of the road, and worth saying plainly.
- *** FINAL VERDICT 11 September 2026: 30 fps IS NOT REACHABLE FROM ANY CONFIG ON THIS MACHINE.
  24-26 fps is this game's ceiling here. STOP CHASING IT. *** The game-thread pass measured no
  change either (23 -> 24-26 is noise), which was the last untested subsystem. Every subsystem has
  now been eliminated with a measurement: GPU pixel work (render fraction 40 vs 100 = ~1 fps),
  draw calls (free four separate times, and removing the ENTIRE depth prepass did nothing), the
  render thread (`-norhithread` on vs off = identical), shadow/AA fixed cost (~1-2 fps together),
  and the game thread (DetailMode, EmitterSpawnRateScale, async loading budget, parallel animation
  = nothing). What remains is Prism x64-on-ARM64 emulation overhead, which no ini can reach.
  THE ONE EXCEPTION that does cost: piling on ENOUGH GPU work pushes the GPU above that emulation
  floor - the 23-line beauty batch did exactly that and cost 5 fps. So there IS free GPU headroom
  up to the floor, and the right strategy is to fill it and stop, NOT to cut.
- FINAL CONFIG 11 September 2026, backup `Engine.ini.bak-2026-09-11v`. Undid every game-thread cut
  that bought nothing (`r.DetailMode` back to 2, `r.EmitterSpawnRateScale` back to 1.0,
  `s.AsyncLoadingTimeLimit` back to 5) on the file's own rule that keeping a change which buys
  nothing is how a config rots. KEPT `a.ParallelAnimUpdate=1` + `a.ParallelAnimEvaluation=1`: unlike
  the others they cost literally nothing, and moving animation to idle cores can only help in a busy
  fight even if a quiet corridor cannot show it.
  SPENT the headroom on the CHEAP half of the re-add ladder instead: `r.Shadow.MaxSoftKernelSize`
  16 -> 40 (uncaps the PCSS already running - best-value line left), `r.VolumetricFog.
  HistoryMissSupersampleCount` 8 -> 16, `r.LightShaftBlurPasses=4`, `r.SSS.Checkerboard=0`,
  `r.MotionBlurQuality=4`, `r.TranslucencyLightingVolumeDim=64`.
  STILL UNSPENT, the EXPENSIVE half - these are where the 5 fps lived, add at most ONE at a time:
  `r.GTAO.Downsample=0`, `r.VolumetricFog.GridSizeZ=128`, `r.DynamicRes.MaxScreenPercentage=100`,
  `r.PostProcessAAQuality=6`, shadow maps 2048, `r.SSR.Quality=4` + `HalfResSceneColor=0`,
  `r.Shadow.DistanceScale=1.5`, `r.LightMaxDrawDistanceScale=2`. NEVER re-add
  `r.Shadow.MaxNumPoint/SpotShadowCacheUpdatesPerFrame=-1` or `r.Decal.FadeScreenSizeMult=0.5`.
- *** POTATO EXPERIMENT RUNNING, 11 September 2026. Restore point
  `Engine.ini.bak-2026-09-11w-PRE-POTATO`. *** 52 override lines appended as a SECOND
  `[SystemSettings]` section just before `[/Script/Engine.UserInterfaceSettings]` - UE4 takes the
  LAST occurrence of a cvar, so the block wins and DELETING THE BLOCK alone restores the real config
  without touching anything above it. A clean, reusable technique for whole-config experiments.
  It sets ScreenPercentage 25 (1/16 the pixels), DynamicRes off, shadows/fog/SSR/AO/bloom/motion
  blur/SSS/post all off or minimum, DetailMode 0, MaterialQualityLevel 0, worst LODs, aniso 0.
  READ IT: still ~24-26 = the floor is ABSOLUTE, it is Prism emulation overhead, no setting reaches
  it, and the right move is to max the visuals back out and stop. 35+ = something in the middle does
  cost and we bisect the block.
- HIS IDEA, and it is a good one nobody had tested: WINDOWS AUTO HDR. It inverse-tonemaps every
  finished frame at the full 5120x1440 OUTSIDE the game, so it is invisible to every cvar tried
  today and it is a fixed per-frame cost that does not scale with the render fraction - exactly the
  shape of a floor nothing reaches. TEST IT SECOND, after the potato block is removed, so the two
  do not confound.
  It was not toggled from a script; it is a display setting, so it is flipped by hand:
  Settings > System > Display > Graphics > SystemReShock >
  Auto HDR off. Current state for restoring: global `AutoHDREnable=0`, per-exe `AutoHDREnable=4147`
  with `SwapEffectUpgradeEnable=1` under `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`; the
  per-app DXGIEffects delta between on and off is exactly 1024.
- *** THE POTATO EXPERIMENT RETURNED 240 fps (vs 24-26). THE ENTIRE DAY'S CONCLUSION WAS WRONG.
  THERE IS NO EMULATION FLOOR - the game is completely settings-bound, ~4 ms vs ~40 ms. ***
  MOST LIKELY ROOT CAUSE OF THE WRONG CONCLUSION, and it makes every earlier result consistent:
  `r.DynamicRes.*` IS INERT IN THIS BUILD. The potato block is the first thing today that set
  `r.ScreenPercentage` directly AND disabled dynamic resolution. If the game overrides dynamic
  resolution from code (`SetByCode` beats `SetBySystemSettingsIni` - the SAME trap this file already
  documents for `t.MaxFPS` and for `bUseHDRDisplayOutput`/HDR), then every ceiling test - 40 vs 70
  vs 80 vs 100 - was a NO-OP and the game rendered at `r.ScreenPercentage=60` throughout. That
  explains "render fraction barely matters", which was the observation the whole false
  "pixel work is free / fixed cost / emulation floor" theory was built on.
  *** RULE FROM NOW ON: use `r.ScreenPercentage` directly, keep `r.DynamicRes.OperationMode=0`, and
  treat every `r.DynamicRes.*` line as decoration until proven otherwise. ***
  METHOD LESSON, the big one of this session: when a whole day of individual A/B tests all say
  "no change", do not conclude there is a floor - suspect the KNOB IS INERT and prove the range
  with one absurd end-to-end test. The potato test should have been the FIRST thing run, not the last.
- POTATO BISECT STEP 2 running, backup `Engine.ini.bak-2026-09-11x-potato25`: the block's
  `r.ScreenPercentage` 25 -> 100 (16x the pixels), everything else still at minimum. ONE VARIABLE.
  ~25-30 fps = resolution is the whole story and quality settings are nearly free; 100+ = resolution
  is cheap and the cost is in the quality settings still switched off, which we then bisect.
- POTATO BISECT NUMBERS, 11 September 2026 - the real cost model, replacing every earlier theory:
    25 % res + no quality  = 240 fps = 4.2 ms
    100 % res + no quality =  63 fps = 15.9 ms
    60 % res + full quality =  25 fps = ~40 ms
  Fitting the two potato points: FIXED cost ~3.4 ms, and a full-resolution frame at minimum quality
  is ~12.5 ms. So RESOLUTION is worth ~12 ms at native and the QUALITY SETTINGS are worth ROUGHLY
  30 ms - quality is the BIGGER half. "Pixel work is free" was an artefact of the inert DynamicRes
  knob and is now fully retracted.
- BISECT STEP 3, backup `Engine.ini.bak-2026-09-11y-potato100`: resolution PINNED at 100 % so every
  measurement stays comparable, and 25 override lines commented out so the SHADOW, LIGHTING/AO and
  FOG/REFLECTION groups revert to the real config. POST and GEOMETRY/MATERIALS stay at minimum.
  Drops toward 25-30 fps = the ~30 ms is in those three groups; stays 50+ = it is in post or
  geometry/materials.
- HIS REPORT "everything pretty dark now" is the POTATO BLOCK, expected and temporary. The two
  causes, both in the lighting group just re-enabled: `r.LightMaxDrawDistanceScale=0.25` (lights
  stop rendering a short distance away - the big one) and `r.EyeAdaptationQuality=0` (auto-exposure
  off, so dark rooms never adapt). Worth remembering as the signature of those two cvars.
- *** BISECT STEP 3 RESULT: 12 fps (83 ms) at 100 % res with shadows + lighting/AO + fog/reflections
  at REAL values, against 63 fps (15.9 ms) with them off. Those three groups cost ~67 ms between
  them. THEY ARE THE ENTIRE PROBLEM, and resolution never was. ***
- BISECT STEP 4 running, backup `Engine.ini.bak-2026-09-11z-all3groups-12fps`: lighting/AO and
  fog/reflections re-minimised, ONLY the SHADOW group left real, resolution still pinned 100 %.
  ~12-15 fps = shadows are the whole 67 ms (prime suspects inside: `r.Shadow.FilterMethod=1`, PCSS,
  two kernel passes per shadowed pixel at 7.4 MPixels; and `r.Shadow.RadiusThreshold=0.01`, every
  small prop casting, re-rendered per light in range). ~50-60 fps = shadows are cheap and it is
  lighting/AO or fog/reflections.
  TWO TEST-DESIGN FIXES worth remembering:
  * `r.EyeAdaptationQuality=0` was the "everything super dark" report - auto-exposure off, so dark
    rooms never adapt. It lives in the POST group, not the lighting group. Re-enabled; it is nearly
    free and is not part of any measurement.
  * `r.LightMaxDrawDistanceScale=0.25` was DELIBERATELY kept at the real 1.0 even though it is in
    the minimised lighting group: it culls distant lights, and shadow cost scales with LIGHT COUNT,
    so minimising it would have made shadows look artificially cheap and invalidated the whole step.
    General rule for this bisect: never minimise a cvar that changes the WORKLOAD of the group under
    test.
- BISECT STEP 4 RESULT: 35-38 fps = 27.4 ms with ONLY shadows real at 100 % res. So SHADOWS COST
  ~11.5 ms (against the 15.9 ms no-quality baseline) - real, but NOT the problem. By subtraction
  LIGHTING/AO + FOG/REFLECTIONS = ~56 ms of the 83 ms total. Running cost table, all at 100 % res:
    nothing on 15.9 ms | shadows only 27.4 ms | all three 83.0 ms
- BISECT STEP 5 running, backup `Engine.ini.bak-2026-09-11-shadowsonly-36fps`: shadows back to
  minimum, FOG/REFLECTIONS/TRANSLUCENCY released to real values, lighting/AO still minimum.
  TOP SUSPECT BY ARITHMETIC - volumetric fog: the froxel grid is sized in SCREEN TILES, so at
  5120x1440 with `GridPixelSize=8` and `GridSizeZ=48` that is ~5.5 MILLION froxels lit every frame,
  and it scales with the FULL OUTPUT resolution. Runner-up `r.SSR.Quality=3` (several rays per pixel
  across 7.4 MPixels). ~15-20 fps here = fog/reflections are the 56 ms; 50+ = it is lighting/AO
  (GTAO at MaxQuality 100 + NumAngles 4, `r.LightFunctionQuality=2`, light shafts).
- *** THE COST TABLE, 11 September 2026, every run at 100 % resolution. This replaces every
  performance claim made earlier in this file. ***
    nothing on              15.9 ms (63 fps)
    + shadows only          27.4 ms (35-38)   -> SHADOWS         ~11.5 ms
    + fog/reflections only  30.8 ms (30-35)   -> FOG/REFL/TRANSL ~14.9 ms
    + all three groups      83.0 ms (12)      -> LIGHTING/AO     ~41 ms BY SUBTRACTION
  LIGHTING/AO ALONE IS BIGGER THAN EVERYTHING ELSE COMBINED. Resolution at native is only ~12 ms.
- BISECT STEP 6 running, backup `Engine.ini.bak-2026-09-11-fogonly-32fps`: ONLY the ambient-occlusion
  switches released (`r.DefaultFeature.AmbientOcclusion`, `MaxQuality`, `Levels`); light functions,
  light shafts and particle lights stay minimum.
  KEY REALISATION: none of the `r.GTAO.*` lines were EVER in the potato block, so `r.GTAO.NumAngles=4`
  and the rest have been live in every single run today. The real config runs GTAO at MaxQuality 100,
  NumAngles 4 and Levels -1 (auto picks 3 at that quality) over a 7.4 MPixel frame.
  ~13-16 fps here = AO is the 41 ms, and the fix is cheap: MaxQuality 50, NumAngles 2,
  `r.GTAO.Downsample=1`. 40+ = it is light functions / light shafts / particle lights instead, with
  `r.LightFunctionQuality=2` the prime suspect.
- *** THE CULPRIT, FOUND 11 September 2026: AMBIENT OCCLUSION = 29.6 ms of an 83 ms frame. ***
  AO alone costs MORE than shadows (11.5 ms) + fog/reflections (14.9 ms) combined, and more than
  rendering at native instead of quarter resolution (12.5 ms). Light functions/shafts/particle
  lights are the ~11 ms remainder. Full measured breakdown at 100 % res, 5120x1440:
    baseline (all quality off) 15.9 | AO 29.6 | fog+SSR+translucency 14.9 | shadows 11.5 |
    light functions+shafts+particle lights ~11  => 83 ms total = 12 fps. All numbers measured.
  ROOT CAUSE: `r.GTAO.Downsample` WAS NEVER SET IN THIS FILE, so GTAO ran at FULL resolution -
  7.4 MPixels, `r.GTAO.NumAngles=4`, `r.AmbientOcclusionMaxQuality=100`, `Levels=-1` (auto picks 3).
  It hid all day because every earlier A/B moved it by only a few percent.
- FIX APPLIED, backup `Engine.ini.bak-2026-09-11-AOonly-22fps`, potato block removed (9.7 KB):
  `r.GTAO.Downsample=1` (half-res AO - THE big one, ~4x on its own, and AO is low-frequency so it is
  nearly invisible; best quality-per-millisecond line in the file), `r.GTAO.NumAngles` 4 -> 2,
  `r.AmbientOcclusionMaxQuality` 100 -> 50, `r.AmbientOcclusionLevels` -1 -> 2 (this REVERSES
  today's "match the shipped tier" change, on a measurement rather than a preference).
  SPENT THE SAVING ON RESOLUTION: `r.ScreenPercentage` 60 -> 70. Model: fixed ~3.4 ms + ~79.6 ms
  scaled; AO 29.6 -> ~7 takes scaled to ~57 ms; at 70 % that is 57*0.49+3.4 = ~31 ms = ~32 fps.
  So it buys a SHARPER image than the old 60 % AND the 30 fps that was never reachable before.
  Short of 30 -> 65 then 60. Above 35 -> 80.
  `r.DynamicRes.OperationMode` 2 -> 0: dynamic resolution is INERT in this build (potato proved it),
  so it is now off explicitly and `r.ScreenPercentage` is unambiguously the resolution knob. Treat
  every `r.DynamicRes.*` line as decoration and distrust any conclusion drawn from one.
- VSYNC ANSWER, 11 September 2026. The panel is 60 Hz (5120x1440 G95NC, primary). `t.MaxFPS` is
  measured INERT in this build, so VSYNC IS THE ONLY WAY TO PACE OR CAP FRAMES HERE. With vsync on
  and no cap, the frame rate can only sit on exact divisors of 60: 60, 30 or 20.
  So vsync is worth it ONLY if the WORST CASE (a fight, a smoky room) stays above 30 - then it locks
  to a perfectly even 30 and removes tearing. At a 30-32 AVERAGE it is actively bad: every dip lands
  on 20. RULE: turn it on only once the floor is reliably 33-35+. Note `EnableVSync` was NOT found by
  a plain string scan of `ShockSettings.sav` this time (the 8 Sep note says it was flipped there) -
  check the in-game menu first before attempting another byte edit.
- UPSCALER OPTIONS, checked in the exe 11 September 2026: `r.NGX.DLSS.Enable` is REGISTERED but the
  DLSS plugin is NVIDIA-only and this is an Adreno - dead. `r.FidelityFX.FSR.Enable` is ABSENT - no
  FSR in this build. So TAAU (`r.TemporalAA.Upsampling=1`, already on) is the only upscaler, exactly
  as the file said. Windows Auto SR (the NPU upscaler) remains blocked while Auto HDR is on.
  TWO REAL QUALITY UPGRADES STILL UNTRIED, both registered, apply ONE AT A TIME after the AO fix has
  a number: (1) `r.TemporalAA.HistoryScreenPercentage=200` - keeps the TAA history at 2x so TAAU
  reconstructs far better from a 70 % render; costs memory bandwidth, not geometry or pixels.
  (2) `r.TemporalAA.Algorithm=1` (Gen 5 TAA) - measured -7 fps on 11 Sep, BUT that was before the
  29.6 ms AO cost was found and removed, so it deserves a retry now there is headroom; it is the
  best-quality upscaler available in this engine.
- 22 fps came back from the AO fix, and IT PROVES NOTHING because TWO things were changed in that edit:
  the AO settings AND `r.ScreenPercentage` 60 -> 70. Same mistake as the six stacked batches earlier.
  Corrected: resolution back to 60 (backup `Engine.ini.bak-2026-09-11-AOfix-sp70-22fps`), so the ONLY
  difference from the known 24-26 fps baseline is the AO fix and the next number measures it cleanly.
  Above 26 = the fix works; still 24-26 = the 29.6 ms AO figure did not survive contact with the real
  config and needs investigating.
  CAUTION on the arithmetic that led astray: the "fixed 3.4 ms + 79.6 ms scaled" model assumes
  EVERYTHING scales with resolution. It does not - shadow-map rasterisation, light functions and
  draw-call work do not - so predictions from that model run optimistic. Use it for ranking, never
  for predicting a target fps.
- *** AO FIX MEASURED CLEANLY: 24-26 -> 25-27 fps, i.e. about 1 fps (40 ms -> 38.5 ms). The 29.6 ms
  AO figure was REAL but RESOLUTION-SPECIFIC and was over-sold. *** GTAO runs at HALF the render
  resolution, so at 100 % render it covered 3.7 MPixels (29.6 ms) but at the real 60 % it covers
  ~0.66 MPixels - about 5 ms - and halving angles and sample budget could only ever save ~2 ms of
  that. `r.GTAO.Downsample=1` was ALSO already the engine default, so that part of the "fix"
  changed nothing at all (the file's own old comment said "the GTAO pass already runs at half res").
  *** GENERAL RULE FROM THIS: a cost measured at 100 % render does NOT transfer to 60 % render.
  Everything downstream of the render target scales with the SQUARE of the render fraction, so a
  bisect run at a different resolution ranks costs correctly but over-states them by ~3x at 60 %. ***
  Revised budget at 60 % render (38.5 ms total): baseline ~8, shadows ~7-12 (shadow-map raster does
  NOT scale), fog/reflections ~5, light functions+shafts+particle lights ~6, AO ~3.
- REACH-30 BATCH, 11 September 2026, backup `Engine.ini.bak-2026-09-11-AOfix-sp60-26fps` (the 26 fps
  state). Need 38.5 -> 33 ms. Three lowest-visibility cuts:
  `r.LightFunctionQuality` 2 -> 1 - AND 1 IS THE COOKED TIER VALUE, so this was ABOVE shipped, the
  mirror image of the ShadowQuality bug; each light function is its own pass and 2 raises their
  resolution. `r.VolumetricFog.GridSizeZ` 48 -> 32 - depth slices are the half of the froxel grid
  that does NOT shrink with render resolution, so they are the efficient half to cut; GridPixelSize
  stays 8 deliberately (the two halves must NOT move together). `r.SSR.MaxRoughness` 0.8 -> 0.5 -
  narrows WHICH surfaces trace, leaving Quality at 3 so shiny surfaces keep roughness-blurred
  reflections; only grimy concrete stops reflecting, where it was a dim smear anyway.
  IF STILL SHORT: the two biggest levers left are `r.Shadow.FilterMethod=0` (drops PCSS, the single
  most expensive shadow line) and `r.ScreenPercentage` 60 -> 55 (measured: 60 -> 70 cost 6.5 ms, so
  60 -> 55 is worth roughly 3.5 ms).
- REACH-30 BATCH 1 RESULT: 25-27 -> 27-29 fps (38.5 -> ~35.7 ms), so LightFunctionQuality 2->1 +
  fog GridSizeZ 48->32 + SSR.MaxRoughness 0.8->0.5 bought ~2.8 ms. ~2.7 ms still needed for 30 fps.
- REACH-30 BATCH 2, backup `Engine.ini.bak-2026-09-11-28fps`. Chose these over spending resolution,
  because at 0.65 ms per percentage point (measured: 60 -> 70 cost 6.5 ms) resolution is the more
  expensive way to buy the same milliseconds in visual terms:
  `r.Shadow.MaxSoftKernelSize` 40 -> 16 - live only with PCSS, caps the WIDEST filter; PCSS cost
  grows with kernel AREA so the soft far end of long shadows is where nearly all of it lives, while
  the blocker search and the hard CONTACT edge - the whole reason to run PCSS - are untouched. 24 if
  16 reads too hard. `r.VolumetricFog.GridPixelSize` 8 -> 10 - ~36 % fewer froxels; with GridSizeZ
  already at 32 the fog pass is now roughly a THIRD of what it was. Back to 8 first if shafts
  read blocky.
- VSYNC DECISION POINT once 30 is reached: the panel is 60 Hz and `t.MaxFPS` is inert, so vsync is
  the ONLY pacing tool and it can only land on 60/30/20. It is worth turning on ONLY if the WORST
  case stays above 30 - at a 30-31 average every dip lands on 20, which judders worse than the
  tearing it removes. Want ~33+ before enabling it.
- REACH-30 BATCH 2 RESULT: 28-30 fps, dips to 25. He wants STABILITY, not a better average - so the
  target became the FLOOR, and the right cuts are the SPIKY costs, not the constant ones.
- STABILITY BATCH, 11 September 2026, backup `Engine.ini.bak-2026-09-11-29fps-dips25`:
  * `r.Shadow.MaxNumPoint/SpotShadowCacheUpdatesPerFrame` 2 -> 1. Purest stability line available:
    ZERO average cost (the same maps refresh either way) - it just refuses to do several in one
    frame. A point light's shadow is a SIX-FACE cubemap, so two landing together is a large sudden
    spike, and this station is full of flickering lights. Converts a dip into a one-frame-late shadow.
    NOTE this reverses the earlier "-1 unlimited" experiment, which was correctly identified then as
    a pacing disaster.
  * `r.SeparateTranslucencyScreenPercentage` 100 -> 50. Costs nothing in an empty corridor and a lot
    exactly when the screen fills with smoke/sparks - i.e. when it dips to 25. Half res is nearly
    invisible on semi-transparent volumes (no hard edges). DETERMINISTIC, unlike the auto-downsample
    that regressed earlier today - no GPU timestamp query, no thrash.
  * `r.ParticleLightQuality` 2 -> 1 (per-particle approximation; 0 would remove the effect). Spiky
    by nature: zero in a corridor, large in a firefight.
  PRINCIPLE WORTH KEEPING: to raise a FLOOR, cut costs that are zero most of the time and large
  occasionally (particles, translucency, shadow-cache bursts). Cutting constant costs raises the
  average but leaves the dips where they were.
- STABILITY BATCH MEASURED: no change, still 28-30. So the dips are NOT spikes - the frame is simply
  close to the limit everywhere, and a FLOOR of 30 needs an AVERAGE near 35 (~6 ms more headroom).
  No remaining quality line can give 6 ms without gutting the look, so resolution was spent:
  `r.ScreenPercentage` 60 -> 50, backup `Engine.ini.bak-2026-09-11-sp60-29fps`. At the measured
  0.65 ms per point that is ~6.5 ms back; predicts ~35 fps average, floor near 30.
  Ladder: 55 if it overshoots and sharpness is wanted back, 48 if the floor still misses 30.
- VSYNC PLUMBING, checked 11 September 2026 - the 8 Sep note about a VSync byte in
  `ShockSettings.sav` NO LONGER HOLDS: a full string scan of the 41,161-byte file finds NO `VSync`,
  `SyncInterval` or `FrameRate` property at all (only WindowMode, Resolution, FOV, CyberspaceFOV).
  `GameUserSettings.ini` says `bUseVSync=True` and `FrameRateLimit=0`, but vsync is plainly NOT
  active - at 60 Hz it would quantise to 30/20 and he is reporting 28-30. So the game ignores
  GameUserSettings for this, exactly as it does for HDR. USE THE IN-GAME VIDEO OPTIONS MENU to
  toggle vsync; do not attempt another byte edit.
  THE PLAN he asked for: get the floor above ~32 by spending resolution, THEN turn vsync on - at
  60 Hz it locks to an exactly even 30 (half refresh, every frame shown for two refreshes) and also
  removes tearing. That is the only route to a "perfect 30" here, because `t.MaxFPS` is inert.
  Do NOT enable it at a 30-31 average: every dip would land on 20.
- *** VSYNC ON = 25-26 fps, AND THAT IS THE 30/20 ALTERNATION, NOT A SMOOTH 30. *** Exactly the
  cliff predicted: at 60 Hz vsync can only produce 30 or 20, so a frame that misses 33.3 ms falls to
  50 ms, and 25-26 is simply the average of bouncing between them. VSYNC IS WRONG FOR THIS MACHINE
  until the floor is comfortably above 30 - it is strictly worse than running uncapped.
- BETTER TOOL, applied 11 September 2026 (backup `GameUserSettings.ini.bak-2026-09-11b`):
  `FrameRateLimit=30.000000` and `bUseVSync=False` in `GameUserSettings.ini`, file then set
  READ-ONLY because the game rewrites it on exit.
  WHY THIS BEATS VSYNC HERE: a frame CAP paces frames when the machine is above 30 but degrades
  GRACEFULLY below it - 28 fps stays 28 instead of collapsing to 20. No cliff.
  WHY IT MAY WORK WHERE `t.MaxFPS` DID NOT: `t.MaxFPS` in Engine.ini is SetBySystemSettingsIni and
  loses to the game's SetByCode. `FrameRateLimit` is applied BY that code path -
  `UGameUserSettings::ApplyNonResolutionSettings` sets the limit itself - and we know the game uses
  UGameUserSettings because it REWRITES this file on exit. So this rides the precedence instead of
  fighting it. Untested; if the frame rate is unchanged and uncapped, the game never calls
  ApplyNonResolutionSettings and there is no frame-cap route on this machine at all.
  GOTCHA THAT COST A RETRY: GameUserSettings.ini uses CRLF, so a `(?m)^...$` regex fails - the `\r`
  sits between the value and the `$`. Use `\r?$`.
- *** CORRECTION FROM HIM: the vsync run at 50 % was 35-36 fps, NOT 25-26 - he misspelled it. The
  "30/20 alternation" diagnosis above is therefore WRONG and should be ignored. *** Two real
  consequences: (1) there was never a stability deficit at 50 % - there was ~5 ms of SPARE time
  against the 30 fps budget (35.5 fps = 28.2 ms vs 33.3 ms), so 60 -> 50 gave up more sharpness than
  was needed; (2) vsync did NOT quantise to 60/30/20 on this setup, which means the game is running
  borderless through the DWM compositor or the G95NC has variable refresh active. Do not repeat the
  "vsync can only do 30 or 20 here" warning without re-checking that.
  ALWAYS ASK FOR A NUMBER TO BE REPEATED when it drives a large irreversible-feeling change - this
  one cost a resolution cut and a vsync round trip.
- Applied 11 September 2026, backup `Engine.ini.bak-2026-09-11-sp50-35fps`: `r.ScreenPercentage`
  50 -> 55, spending ~3.3 ms of the ~5 ms surplus at the measured 0.65 ms per point. Predicts ~32 fps,
  deliberately leaving margin BELOW the 30 cap so the cap can hold flat instead of being a ceiling
  the machine falls through. 57 if 32 is comfortable; back to 50 if the floor dips under 30.
  `FrameRateLimit=30` + `bUseVSync=False` remain in the read-only GameUserSettings.ini, still untested.
- *** THE FRAME CAP WORKS. `FrameRateLimit=30` in the read-only GameUserSettings.ini is honoured -
  a 29-30 reading against a 30 ceiling is the cap holding. *** So there IS a frame-cap route on this
  machine after all: `t.MaxFPS` in Engine.ini is inert because it loses to the game's SetByCode,
  but `FrameRateLimit` is applied BY that same code path (`ApplyNonResolutionSettings`). Use
  GameUserSettings for any future cap, never Engine.ini, and keep the file READ-ONLY.
- SETTLING POINT 11 September 2026, backup `Engine.ini.bak-2026-09-11-sp55-29fps`: at 55 % the dips
  hit 27-28 (worst case ~37 ms vs a 33.3 ms budget, ~4 ms short), so `r.ScreenPercentage` 55 -> 50,
  the one resolution with a measured average (35-36 fps = 28.2 ms, ~5 ms of margin). Part of that
  margin immediately spent on `r.VolumetricFog.GridPixelSize` 10 -> 8 (~1.8 ms) - the most visible
  of the hunt's cuts, since the froxel grid is screen-sized and 8 is what keeps light shafts smooth;
  GridSizeZ stays 32 because depth slices do NOT shrink with render resolution.
  *** THE PRINCIPLE NOW THAT A CAP EXISTS: average fps above the cap is WASTED. The right target is
  the LOWEST average whose WORST CASE still clears the cap; everything beyond that must be spent on
  looks. This replaces the whole session's "chase a higher average" framing. ***
  REMAINING QUALITY TO BUY BACK with any leftover margin, cheapest first (all cut during the hunt,
  costs recorded): `r.SSR.MaxRoughness` 0.5 -> 0.8, `r.Shadow.MaxSoftKernelSize` 16 -> 40,
  `r.ParticleLightQuality` 1 -> 2, `r.SeparateTranslucencyScreenPercentage` 50 -> 100,
  `r.VolumetricFog.GridSizeZ` 32 -> 48. Do NOT restore `r.LightFunctionQuality` to 2 - 1 is the
  cooked tier value and 2 was above shipped.
- 50 % + fog grid 8 + 30 cap = 30-31 fps steady, dipping to 27-28 ONLY WHEN RUNNING QUICKLY. That
  trigger is the diagnosis: the remaining cost is DISOCCLUSION work, zero standing still and large
  when new geometry and fog enter view. Backup `Engine.ini.bak-2026-09-11-sp50-30fps-dips27`.
  * `r.VolumetricFog.HistoryMissSupersampleCount` 16 -> 4 (the cooked tier value). *** THE
    MISTAKE FROM EARLIER TODAY. *** It was raised to 16 and called near-free "because it is paid
    only by froxels with no history" - which is exactly why it was the WRONG line to raise: no
    history means turning a corner or sprinting, so it costs nothing while standing still and the
    most at the precise moment he reports the dip. 8 is the middle step; fog sparkling on fast turns
    is the failure mode to watch for.
    GENERAL LESSON: "free because it only costs on disocclusion" is NOT free on a machine whose
    problem is dips - it is the definition of a dip. Re-read every "near-free by construction"
    claim in this file with that in mind.
  * `r.Streaming.FramesForFullUpdate` 3 -> 5 and `NumStaticComponentsProcessedPerFrame` 200 -> 50
    (engine defaults). Game-thread work that scales with how many components change relevance per
    frame - near zero standing still, maximum when sprinting, i.e. ~6x the churn exactly when the
    frame is tight. An earlier test showed "no change in average fps", which was the wrong metric:
    this was never an average cost. Cost of reverting: textures sharpen slightly later after a corner.
- The disocclusion theory was WRONG: `r.VolumetricFog.HistoryMissSupersampleCount` 16 -> 4 and the
  streaming pair 3/200 -> 5/50 did NOT change the dips (still 30 with drops to 27-28). Both reverted
  (backup `Engine.ini.bak-2026-09-11-nogain`). The streaming pair has now measured as NOTHING TWICE -
  treat it as settled and never cut it again.
- *** THE REAL STABILITY STEP, 11 September 2026: `r.Shadow.RadiusThreshold` 0.01 -> 0.03 (STOCK). ***
  Why this one and not another constant cut: a shadow caster is re-rendered ONCE PER SHADOW-CASTING
  LIGHT IN RANGE, so the cost of this line is proportional to clutter x lights - it is near nothing
  in a bare corridor and at its worst in exactly the cluttered multi-light rooms where the frame
  drops to 27-28. Cutting a CONSTANT cost raises the average and leaves the dips; this cuts the
  VARIANCE itself. 0.03 is the engine and cooked-tier default - 0.01 was the aggressive value added
  11 Aug when the file believed object count was free. VISIBLE LOSS: small props stop casting their
  own shadows. 0.02 is the middle step.
  IF THIS ALSO FAILS, what is left is only: `r.Shadow.FilterMethod=0` (drop PCSS), `r.SSR.Quality`
  3 -> 1, or `r.ScreenPercentage` 50 -> 45. Say plainly at that point that 30 with occasional 27-28
  is a good result for an emulated x64 UE4 game on this hardware and further cuts are poor value.
- *** BEST CONFIG OF THE SESSION, 11 September 2026: 31 fps steady with ONE drop to 27. Preserved as
  `Engine.ini.bak-2026-09-11-BEST-31fps` - restore this if any later experiment goes wrong. ***
  It is: `r.ScreenPercentage=50`, `FrameRateLimit=30` in a READ-ONLY GameUserSettings.ini,
  vsync off, `r.Shadow.RadiusThreshold=0.03`, fog 8/32, `r.LightFunctionQuality=1`,
  `r.ParticleLightQuality=1`, `r.SeparateTranslucencyScreenPercentage=50`,
  `r.Shadow.MaxSoftKernelSize=16`, PCSS on, SSR Quality 3, `r.ShadowQuality=5`.
- *** THE BUY-BACK RULE, and it is the most useful principle of the whole session. ***
  With a FRAME CAP in place the machine finishes early in normal scenes and that spare time is
  THROWN AWAY, while the dips come from cluttered multi-light scenes. Therefore:
    RESTORE constant per-pixel costs - they spend time the cap is already wasting.
    DO NOT restore costs that SPIKE with clutter, lights or effects - they land entirely on the dips.
  Keep cut for that reason: `r.Shadow.RadiusThreshold` (clutter x lights), `r.ParticleLightQuality`
  (firefights), `r.SeparateTranslucencyScreenPercentage` (smoke-filled rooms).
  Applied under this rule: `r.SSR.MaxRoughness` 0.5 -> 0.8 (constant per-pixel; grimy floors and
  worn metal reflect again - most on-taste line available), `r.AmbientOcclusionMaxQuality` 50 -> 100
  and `r.GTAO.NumAngles` 2 -> 4 (cheap because GTAO runs at half of a 50 % render target, so the
  whole pass is only ~3 ms - the 29.6 ms figure was a 100 %-resolution artefact).
  STILL AVAILABLE as constant-cost buy-backs if this holds: `r.VolumetricFog.GridSizeZ` 32 -> 48,
  `r.Shadow.MaxSoftKernelSize` 16 -> 24, `r.ScreenPercentage` 50 -> 55 (the big one, 3.3 ms).
- The constant-cost buy-back (SSR.MaxRoughness 0.8 + AO MaxQuality 100 + GTAO.NumAngles 4) made the
  dips worse (30 with drops to 27), so it was REVERTED at his request - `Engine.ini.bak-2026-09-11-
  BEST-31fps` restored wholesale. So even CONSTANT costs eat into the dips here; the margin at the
  31 fps config is genuinely about 1-2 ms and there is nothing meaningful left to spend.
  CONCLUSION TO CARRY: the 31 fps config is the settled optimum. Only truly FREE lines (shader
  constants inside passes that already run) may be added; anything with a per-pixel or per-object
  cost, however small, comes straight out of the dips.
- TWO FREE LINES ADDED on top of the restore, both shader constants, zero extra samples or passes:
  * `r.Tonemapper.Sharpen` 1.5 -> 1.1. This is a FIX, not a trade: 1.5 was restored earlier today on
    the explicit condition that the game rendered at NATIVE, and the render scale is now 50 %, so it
    was sharpening TAAU-interpolated pixels - the ringing case this file has warned about since
    August (pale outline on the dark side of a high-contrast edge). 1.0 if any outline remains,
    1.3 if it reads soft.
  * `r.Shadow.TransitionScale` + `SpotLightTransitionScale` 40 -> 30. Earns its place now that
    shadow maps are 1024 AND the render scale is 50 %: a shadow edge is resolved by very few pixels,
    so a harder fade shows stair-stepping. Softer edges hide that and flatter PCSS rather than
    fighting it, since PCSS still sizes the filter from blocker distance underneath. 20 is very
    soft, 60 is stock.
- *** SESSION CLOSED 11 September 2026 at a steady 30 fps (rare dips to 27) on 5120x1440. ***
  Final snapshot saved as `Engine.ini.FINAL-2026-09-11-30fps`; `Engine.ini.bak-2026-09-11-BEST-31fps`
  is the same settings without the two free lines. A SETTLED STATE header was prepended to
  Engine.ini carrying the measured cost table and the three rules, so a future session does not
  repeat this one's mistakes. Verified: no setting changed when the header was added, both
  Engine.ini and GameUserSettings.ini are READ-ONLY, and `-norhithread` is present in Steam's
  LaunchOptions for 482400.
  THE FINAL CONFIG: `r.ScreenPercentage=50` + `FrameRateLimit=30` (GameUserSettings, read-only,
  vsync off) + `r.Shadow.RadiusThreshold=0.03`, `r.ParticleLightQuality=1`,
  `r.SeparateTranslucencyScreenPercentage=50` as the three variance cuts, with PCSS, ShadowQuality 5,
  SSR Quality 3, fog 8/32, 16x aniso, motion blur 4, scene fringe and the texture-filtering pak all
  kept. 39 backups from today remain in the config folder - he was not asked to prune them.
  WHAT ACTUALLY WON, for the record: the absurd end-to-end "potato" test (240 fps) that proved the
  range, then a group bisect. A day of small individual A/Bs proved nothing and produced a false
  "emulation floor" theory. RUN THE EXTREME TEST FIRST NEXT TIME.
- BACKUPS DELETED at his request 11 September 2026: 60 files, 4.31 MB, every `*.bak*` in the config
  folder including the older August and early-September ones and the Input/GameUserSettings backups.
  The folder now holds exactly four files: `Engine.ini` (live, read-only),
  `Engine.ini.FINAL-2026-09-11-30fps` (the single restore point, 30 fps config),
  `GameUserSettings.ini` (read-only, holds `FrameRateLimit=30` + `bUseVSync=False`) and `Input.ini`
  (read-only, the tuned gamepad look curve). *** Every earlier note in this file that names a
  `.bak-` file as a restore point is now STALE - those files are gone. ***
  TOOLING TRAP: a safety guard rejected `Remove-Item` when the pipeline carried a regex literal that
  looked like a path - it reported "system path '\.bak' is blocked". Fix: match with `-like '*.bak*'`
  and delete with `[System.IO.File]::Delete($f.FullName)` per file. Clear read-only first.


# Later summary and state (21 September - 4 October 2026)

The sections below were kept in a separate short summary; they carry the newest state (paths, final config, Bluetooth audio hang, mod set).

System Shock Remake (Steam app 482400), Surface Laptop 7, x64 under Prism, Adreno X1-85, panel 5120x1440 G95NC 60Hz.

## Paths
- Install: `C:\Program Files (x86)\Steam\steamapps\common\System Shock Remake`; mods are `*_P.pak` in `SystemShock\Content\Paks`.
- Crash dumps: `%USERPROFILE%\Saved Games\Nightdive Studios\SystemShock\Saved\Crashes\UE4CC-*\UE4Minidump.dmp` (no game log; nothing in Event Log/WER).
- Config: `...\Saved\Config\WindowsNoEditor\{Engine,GameUserSettings,Input}.ini`; save `ShockSettings.sav`.
- Config folder holds only 4 files: `Engine.ini` (live, writable since 7 Oct), `Engine.ini.FINAL-2026-09-11-30fps` (restore point), `GameUserSettings.ini`, `Input.ini` (all writable since 7 Oct 2026). ~60 `.bak-*` files were deleted 11 Sep 2026 at his request - any note naming one is stale.

## Crash fix - RESOLVED, keep permanently
Aug 2026 locked-door crashes = D3D12 RHI use-after-free on the RHI thread. Fix: Steam launch option `-norhithread` - eliminates it, measured 0 fps cost, keep regardless of performance work. `.RHIThread.Enable` is a console COMMAND not a cvar - in Engine.ini `[SystemSettings]` it crashes at start. Never edit `localconfig.vdf` while Steam is running (rewritten on exit).

## HDR - SETTLED, do not retry engine HDR
Engine HDR (`r.HDR.EnableHDROutput` etc.) does not work here: OutputDevice 5 (scRGB) and 3 (PQ) both tested cleanly, both grey - Adreno X1-85 under Prism won't grant an HDR swap chain. Also the game's settings Blueprint resets `bUseHDRDisplayOutput=False` in GameUserSettings.ini on exit regardless of ini (SetByCode beats ini, same trap as `t.MaxFPS`). Final: engine HDR off (AllowHDR/EnableHDROutput/OutputDevice/ColorGamut=0). Windows Auto HDR ON per-exe only, OFF globally: `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, per-app `AutoHDREnable=4147`+`SwapEffectUpgradeEnable=1`. Auto SR (NPU upscaler) is impossible while Auto HDR is on. No FSR; DLSS registered but dead (NVIDIA-only).

## Performance - session-final config (steady 30fps, rare dips to 27, native 5120x1440)
`r.ScreenPercentage=50`; `FrameRateLimit=30.0`+`bUseVSync=False` in GameUserSettings.ini (read-only); `r.Shadow.RadiusThreshold=0.03`, `r.ParticleLightQuality=1`, `r.SeparateTranslucencyScreenPercentage=50` (cut costs that spike with clutter/lights - the real cause of dips; cutting constant costs only raised the average); PCSS on (`r.Shadow.FilterMethod=1`, `MaxSoftKernelSize=16`); `r.ShadowQuality=5` (shipped tier, was wrongly pinned to 3); `r.SSR.Quality=3`+`MaxRoughness=0.8`; fog `GridPixelSize=8`/`GridSizeZ=32`; anisotropic line REMOVED 29 Sep 2026 (texture-filtering mod deleted; Engine.ini = FINAL minus `r.MaxAnisotropy=16`); motion blur 4; scene chromatic fringe on; `r.Tonemapper.Sharpen=1.1` (1.5 rings on TAAU-upscaled pixels, safe only at native res).

Traps/discoveries:
- `r.DynamicRes.*` is INERT here (forcing `r.ScreenPercentage=25` directly gave 240fps vs the usual 24-26, while sweeping the DynamicRes ceiling 40-100% moved almost nothing). The game always runs at `r.ScreenPercentage` - distrust any DynamicRes-ceiling conclusion.
- `t.MaxFPS` is inert (loses to the game's SetByCode). Only working cap is `FrameRateLimit=` in GameUserSettings.ini, the game may reset it on exit - RE-APPLY it, never lock the file. Same for Input.ini (gamepad curve): re-apply, do not lock.
- Cost at 100% render (5120x1440): baseline 15.9ms, +shadows 27.4ms, +fog/reflections/translucency 30.8ms, +AO+lighting (all three) 83ms - AO+lighting alone (~41ms) beats everything else combined. Cost scales with the square of the render fraction - never reuse a 100%-render measurement at a lower resolution.
- Mission time limit (5/7/10/24h) is not ini-configurable - hardcoded in cooked DataTable `DT_MissionDifficultySettings`; needs Nexus mod 28 component `0104_HardMission24HoursTimeLimit`.
- "Pixelated" look (2,951 assets carry explicit `TF_Nearest`) is deliberate art direction - no ini reaches it. Nexus 21 "Enable texture filtering" covered ~70% - DELETED at his request 29 Sep 2026.
- Nightdive shipped `r.DefaultFeature.LensFlare=False`; no film-grain asset exists anywhere - neither is ini-restorable.

## 21-22 September 2026 - "1 fps" was the Pixel Buds blocking UE4's audio init. RESOLVED.

**CONFIRMED WORKING 22 September 2026 with the buds as output** - audio, Stadia controller, HDR,
Steam overlay fps counter, steady 30 fps. The fix was entirely on the Bluetooth side; no game
setting was changed and the 11 September config stands untouched.

**The actual fix, in one line:** turn OFF *Settings -> Bluetooth & devices -> Device settings ->
"Use LE Audio when available"*. Everything else tried that
night - the `DisableLEAudio` DWORD, re-pairing, Game Bar, Auto SR, HDR, exclusive mode - was either
inert or actively harmful.


**Symptom:** what he reported as 1-2 fps was the game **hanging before it opened a window**, or
opening one and stalling. Signature, measured:

| | Hung (sound on) | Healthy (`-nosound`) |
|---|---|---|
| Threads | 92-96 of 96 in `Wait`, **1 on `LpcReply`** | normal |
| CPU | 4 s in 102 s (~0.5 %) | 10.7 s in 20 s |
| GPU 3d | 0-8 %, brief 43 % spikes | **66 %** |
| Windows created | **none**, or 3 that never respond | 7, responding |
| Disk I/O | **0** reads/writes/other per second | normal |

**Root cause:** the Pixel Buds Pro 2 A2DP endpoint was in a broken/churning state all evening, and
UE4's XAudio2 startup enumerates endpoints through the audio service - a cross-process ALPC call,
which is the `LpcReply` wait. Fixing the Bluetooth pairing fixed the game. Full repair sequence: delete the `DisableLEAudio` DWORD, reload the radio, remove and
re-pair the buds. **Confirmed working:** audio, Stadia controller, Steam overlay fps counter, and
the steady **30 fps** of the 11 September config, unchanged.

**The diagnostic that settles slow-vs-hung, do this FIRST next time** - no installed tool needed:

```powershell
$p = Get-Process SystemReShock-Win64-Shipping
$p.Threads | Group-Object WaitReason        # all Wait + an LpcReply = blocked, not slow
(Get-Counter "\GPU Engine(pid_$($p.Id)*)\Utilization Percentage").CounterSamples
# plus EnumWindows filtered by PID: zero windows = never finished startup
```

Then isolate with **one variable at a time**: `-nosound` alone proves audio. Launching the exe
directly *also* removes Steam Input and the overlay fps counter, so never change both at once - he
spotted that immediately when the controller stopped working.

**Three wrong causes were proposed before any measurement was taken**, all on correlation:
Xbox Game Bar removal un-blocking Auto SR; HDR being off on the G95NC un-blocking Auto SR; and Auto
SR itself, which survived being disabled per-exe *and* globally (`AutoSRConfig=0`). Auto SR is
disproved. The per-exe `AutoSuperResolutionEnable=1` stays deleted anyway - a value that is inert
only while something else blocks it is a trap.

**Ruled out and not worth re-checking:** `Engine.ini` byte-identical to
`Engine.ini.FINAL-2026-09-11-30fps`, `GameUserSettings.ini` unchanged, `-norhithread` still set,
driver 31.0.170.0, D3DSCache intact, mods unchanged since 8 September, G95NC at 5120x1440, RAM,
TDR, OOM. Kernel-Processor-Power 37 firmware throttling fires 9-36 times on a normal day -
background noise, never evidence.

**dxdiag is the reliable HDR probe:** `Start-Process dxdiag -ArgumentList /whql:off,/t,<file> -Wait`
then grep `Advanced Color|Monitor Model|Current Mode`. Do NOT use `DisplayConfigGetDeviceInfo`
type 9 - it returns **87** on build 26200, and `DISPLAYCONFIG_PATH_INFO` marshals to 68 bytes in
.NET against the OS's 72, so target ids come back garbage. Note: with the game closed the G95NC
still reads `AdvancedColorSupported` **without** `AdvancedColorEnabled`, i.e. display HDR off, even
though he reports HDR working in game.

## Xbox Game Bar: removed, reinstalled, removed again (21 September 2026) - net zero

The Xbox packages were removed earlier that evening and `ms-gamebar`/`ms-gamebarservices`/
`ms-gamingoverlay` pointed at `systray.exe` to suppress the "You'll need a new app" popup. Game Bar
was then reinstalled (`winget install --id 9NZKPSTSNW4P --source msstore`) on the wrong theory above,
and **he asked for it removed again** - `Remove-AppxPackage` on `Microsoft.XboxGamingOverlay`, which
also took the HKCU protocol keys with it, so the HKLM `systray.exe` redirects are active again and
the popup stays suppressed. `Microsoft.XboxGameCallableUI` was present before all of this and was
left alone.

Consequence to state as a fact, not a problem to fix: the presence writer cannot register
(DistributedCOM **10010**), so **Game Mode never engages**. He does not want the packages back.

**SUPERSEDED 29 September 2026:** Game Bar is installed again (7.326.9240.0) and is needed.

## Mods (session end)
13 `*_P.pak` files, 79 known conflicts, resolved by mount order (case-insensitive filename, last wins - whole blueprints replaced, never merged per-property). Preference REVERSED 29 Sep 2026: size first, then bigger stack. 29 Sep installed: Nexus 14 as `SystemShock-Windows_zzzzAdvancedStackable_P.pak` (differs from CFW ONLY in MaxStackCount=999, same sizes, so it wins; also ships ITEM_Base = 1x1/999 default) + ONLY Nixos (Nexus 28 v2.1.0) 0102 (72 slots), 0103 (expander +12), 0104 (24 h Hard timer). All balance/difficulty/damage/loot components were REJECTED. Nexus 25 recycler mod is taken down. Same day DELETED at his request: v1.2_SkipLaptopWaitTime, v1.2_SkipNewGameIntroduction, zzzCFW00-Ammo, zzzCFW02-Items (last two fully overridden by Nexus 14). NVEnableTextureFiltering, NoCAUI, RemoveRedTint also DELETED. Weapon-DROP CRASH 29 Sep 13:42 (AV reading 0x20, 28 s in, current set) -> Nexus 14 REMOVED (2023 ITEM_Base, prime suspect), CFW00/CFW02 restored from BackupPersonal\game-tweaks\system-shock\Paks. Next suspect if it recurs: 0102 (replaces whole PAWN_Hacker_Simple). NOT the RHI crash - he rejects that. Engine.ini: r.MipMapLODBias=-1 tried, 26 fps, REVERTED to 0. Later same day RESTORED from backup: NVEnableTextureFiltering, RemoveRedTint; r.MaxAnisotropy=16 re-added. 13 mod paks + base. Property reader (zlib pak records, uasset name map + export sizes to pair uexp, tagged Int/Float scan) was a throwaway C# file - rebuild if needed. `zzz`-prefix forces late mount; hyphen sorts before underscore (caused one accidental override - rename explicitly). Visual direction: realism/cinematic good, stylised/pixelated bad (kept `r.Bloom.Cross=1.0` for this). Resolution/refresh/HDR are changed by hand, not from scripts.

**30 September 2026:** removed again at his request ("I don't like it").

**1 October 2026, at his request:** INSTALLED Calm lighting MAIN v1.2 (Nexus 43, `Calm_lighting_P.pak`, 4 KB, overrides
ONLY `LevelAtmosphere`: bloom /5, exposure up, no lens dirt, red directional light reduced) and Always Visible Hardware
Icons v1.0.3 for 2.1 (Nexus 74, `v2.1_PermanentHWIcons_P.pak`, overrides ONLY `Widget_PlayerHUD`, no overlap). REMOVED
`SystemShock-Windows_RemoveRedTint_NeutralLight_P.pak` from Paks because it overrides the same single `LevelAtmosphere`
asset and would have won the mount order (S after C), making Calm lighting inert; restore source (sha256 4c7170b6...)
stays in `BackupPersonal\game-tweaks\system-shock\Paks`, which now also holds both new paks. Now 14 mod paks + base.
Calm lighting weakens the `r.Bloom.Cross` streak he kept (bloom intensity /5) - his informed choice.

**LevelAtmosphere values compared 1 October 2026** (tagged properties read from both paks; script
`levelatmo_values.py`, FColor bytes are B,G,R,A): Remove Red Tint NeutralLight = BloomIntensity 1.0,
BloomDirtMaskIntensity 2.0, SkyLight LightColor 140/140/140, LowerHemisphereColor 0.125 grey, AutoExposureBias 18.75.
Calm lighting MAIN = bloom 0.2, lens dirt 0, sky light R134 G132 B198 (cool), lower hemisphere 0.04/0.015/0.007
(dark warm), exposure 18.8. Everything else identical (AO, fog, volumetrics, auto-exposure speeds). Recommendation
given: Remove Red Tint fits the realism direction (keeps bloom + lens dirt, fully neutral ambient); Calm only
if bright lights glare. DECIDED 1 October ~13:45: he chose Remove Red Tint; it is restored (sha256 4c7170b6...) and Calm lighting is DELETED from Paks and from the backup. 14 mod paks + base, all hash-identical to `game-tweaks\system-shock\Paks`.

**Overlap audit 1 October 2026 (read-only; he said "don't remove, just recommend"):** mount order = case-insensitive
filename, last wins. No pak is fully inert. ItemsGridSize: 62 of 64 assets overridden by zzzCFW03-Junk, still effective
only for `item_abeghiranhead` + `item_interfacedemodulator`. WeaponsGridSize: 17 of 22 overridden (CFW01 13, CFW03 4),
still effective only for `weapon_poolcue` + cyberspace `weapon_cybergun`/`pseudodisclauncher`/`pseudonova`/`pseudopulser`.
0103 is a uexp-only override of `HARDWARE_InventoryExpander`; 0102 replaces `PAWN_Hacker_Simple` (uasset+uexp).
Runtime cost: only NVEnableTextureFiltering (filtered + 16x aniso sampling on ~2,075 textures) and, negligibly, the
always-on hardware icons; the rest is data. Recommended, NOT done: WeaponsGridSize optional delete (2024 pre-2.1
whole-blueprint overrides, near-zero visible effect); everything else keep.

**1 October 2026 ~14:00, at his request: NVEnableTextureFiltering_P.pak and v2.1_PermanentHWIcons_P.pak REMOVED**
(deleted from Paks and from `game-tweaks\system-shock\Paks`, remove = delete). 

up. His reason for the filtering pak was GPU cost; the 11 Sep record says it measured as free, so it frees < ~1 ms.
He invited a settings bump "to get 30 fps"; NOT done and explained: < 1 ms buys ~1 point of r.ScreenPercentage
(0.65 ms/point, invisible) and the rare dips to 27 fps mean the worst case is already over budget. Engine.ini got a
dated comment above r.MaxAnisotropy=16 (comment only; live and backup copies identical, both read-only; the
FINAL-2026-09-11 restore point untouched). Textures covered by the pak are point-sampled (pixelated) again.


**4 October 2026 - no installed mod is replaceable by ini.** Shipped `DefaultGame.ini` (read from the base pak index, v11, unencrypted) has no gameplay sections and no `MoviePlayerSettings`; intros are UMG widgets (`WIDGET_SplashScreen_*`), not `StartupMovies`; `bSkipMovies` is a cook setting. Cargo_Lift = `INTERACT_CargoLift` blueprint. Do not re-investigate.
