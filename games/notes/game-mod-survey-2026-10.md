Sources that work from this machine: Nexus `api-router` GraphQL (catalog + descriptions, no downloads), PCGamingWiki
MediaWiki API (`api.php?action=parse&page=<name>&prop=wikitext`), GitHub API/raw/releases, ModDB listing pages.
Blocked: nexusmods.com downloads (Cloudflare), forum.worldofplayers.de (Anubis proof-of-work).

**Risen (2023 64-bit build only):**
- Font Scale (GitHub Kanadeforever/GameFixMods, release tag `Risen`, July 2026, 9 KB: `RisenFontScale.asi` + ini,
  Scale=1.5, per-font overrides) - needs ThirteenAG Ultimate ASI Loader x64 (v9.7.4) in `bin\`. The only working
  big-text option for the 2023 build (the Nexus "Larger Focus Font" is 2009-only). Downloadable from GitHub.
- Harder game: Risen Enhanced v1.4 (Nexus 7, October 2023, explicitly adapted to the 2023 version; scaling LP costs,
  harder balance, bundled mods; clashes with Mini Mod/Improvements Pack on templates and strings; skip its strings.p00
  for a Russian game). Script-based difficulty mods (Anti-Click-Fest, EnableNPCPowerRaise, HP regen) are 2009-only.
- Already installed 30 September: Redefine textures, Dark Risen, Sounds Overhaul, skip intro, HUD-centring patch.
- Dead ends: VaanaCZ Risen-FPS-Patch (README: "will not work on the 2023 version"), worldofplayers "FPS and aspect
  ratio fix" thread 1586532 (unreadable, bot wall), ModDB "Risen HD Engine Mod" (2017 page, no files), ModDB
  Elusively Patched Unit (2009 only), Risen ModStarter (2009 tool). PCGamingWiki's skip-intro advice = our logo.ini.

**System Shock 2023 (v2.1 Parity Patch; 13 paks installed, see system-shock-remake-troubleshooting.md):**
- Not installed, fit his taste/eyes: Calm lighting (Nexus 43, March 2026, v2.1: bloom /5, less red light, no dirt
  lens; three variants), Music Fix and Revamp (128, March 2026: music no longer fades out, instrument chances fixed),
  Remember Citadel music restoration (87, 2025), Gore and FX (51, 2023, more sparks/debris - cinematic), Enable SSGI
  (2, 2023), Tiny Crosshair (85, April 2026, made for 55-65" screens), Hardware Icons Always Visible (74, April 2026),
  Tweaker Shock (119, dxgi.dll in Binaries\Win64, in-game tweak menu: skip intros, auto-vaporise, rebinds).
- Harder: Ironman - Item Randomizer (55, April 2026, v2.1, randomised loot + tougher AI + hardcore no-respawn
  variant; modular), Adjusted Respawn Limits (93, v2.1, 1.5x-4x or infinite spawns), Quick Enemies (90, 2024, faster
  enemies, 1.2-era), 24 Hrs (31, March 2026, 24 h timer + hardcore at all difficulties; he already has Nixos 0104 for
  the timer), Refibrillated balance (35, September 2026).
- Already covered/removed: Skip Intros (installed v1.2_SkipIntro), texture filtering (NVEnableTextureFiltering pak),
  Remove Red Tint (installed), UI No Chromatic Aberration (he keeps scene CA, UI CA removal fits his taste - mod 20).

**TUNIC (18 Nexus mods):** nothing for graphics or sound except RenoDX HDR (8), which he had deleted 29 September
(do not reinstall). Useful: TUNIC Checklist (55, BepInEx), Focus Loss Bypass (60). No difficulty mods (randomizer only).

**Overcooked AYCE (4 Nexus mods):** Ultrawide Fix by another author (1, January 2026, MelonLoader, forces a
resolution and camera rect - the same ground his own mod covers, see overcooked-ultrawide-mod.md), No/Overcooked-2 Chef
Indicators (2, 3, cosmetic), Fast Launch skip-intro (4, September 2026). Nothing for graphics, sound or difficulty.

**1 October follow-up.** Verdicts from the Nexus file
lists and content previews: Overcooked Fast Launch (mods/4) = startup only, but its 2.7 MB rar has no content preview
(new hashed uri) - inspect it for a `version.dll`/`winhttp.dll` before copying, MelonLoader's `version.dll` sits in
the game root; no loose intro videos exist (Addressables catalog in StreamingAssets/aa). Hardware Icons (mods/74) =
one 522 KB `v2.1_PermanentHWIcons_P.pak`, use the non-Ironman file. Calm lighting (mods/43) = 4 KB `Calm_lighting_P.pak`
in four variants; MAIN cuts bloom 5x and removes lens dirt, OPTIONAL "Not calm
lighting" keeps vanilla bloom; likely overlaps the installed RemoveRedTint pak, which mounts later and would win.
Gore and FX (mods/51) = `SystemShock-Windows_SYSCKHFX.pak`, June 2023, more sparks and longer debris: FPS cost in
combat plus pre-2.1 stale-pak risk.
**Installed 1 October 13:30:** Overcooked mods/4 (as winhttp.dll + SkipIntro.asi), System Shock mods/43 MAIN and
mods/74; details in overcooked-ultrawide-mod.md and system-shock-remake-troubleshooting.md.
Overcooked mods/4 REMOVED the same day: it did not skip the logos (see overcooked-ultrawide-mod.md).
System Shock mods/43 Calm lighting REMOVED the same day in favour of Remove Red Tint; mods/74 stays.
System Shock mods/74 Hardware Icons REMOVED the same afternoon ("I don't like it"), with the texture-filtering pak.
