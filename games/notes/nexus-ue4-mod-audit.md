Auditing a Nexus-modded UE4 game (used for System Shock 2023 on this laptop).

**Nexus catalog without an API key.** `www.nexusmods.com` returns Cloudflare 403 to scripted fetches, including local `Invoke-WebRequest` (browser UA doesn't help), and `api.nexusmods.com/v1/*` needs a key. But **`https://api-router.nexusmods.com/graphql` answers unauthenticated POSTs** (so does `api.nexusmods.com/v2/graphql`). No key, no login.

```
mods(filter: {gameDomainName: {value: "systemshock2023", op: EQUALS}},
     sort: {endorsements: {direction: DESC}}, count: 50, offset: 0)
  { totalCount nodes { modId name summary version downloads endorsements updatedAt gameId modCategory { name } } }
```

Gotchas: `mod(...)` and `modFiles(...)` require the **numeric** `gameId`, not `gameDomainName` (read `gameId` off any `mods` node first — System Shock 2023 is **5415**). `modFiles` returns `uri`, the real download filename, which is how you match an installed pak back to its mod page. Batch many mods per round trip with GraphQL aliases (`f119: modFiles(modId: 119, ...)`). Introspection is enabled.

**Detecting mod conflicts locally.** UE4 `_P.pak` files store their asset paths as **plaintext** in the index — read the bytes and regex `[A-Za-z0-9_/]{4,}\.uasset` (try ASCII *and* UTF-16). Two paks listing the same `.uasset` = a real conflict where only load order wins. This turns "mod page says incompatible with X" into a verified yes/no instead of a guess. Some paks compress the index (no plaintext `.uasset`); scan all printable runs `[\x20-\x7E]{6,}` instead — the path usually still surfaces.

Nexus title prefixes like `(2.1)` are an author convention meaning "verified against game patch 2.1", not an upload date — old files can be current, so check the filename (`... (game ver 2.1)`) rather than `updatedAt`.

**Diagnosing a crash caused by a stale mod pak.** Worked end-to-end on System Shock 2023,
2026-08-12, for a repeatable crash on removing a pistol from the inventory.

1. Crash reports are at `Saved/Crashes/<UE4CC-...>/CrashContext.runtime-xml`. Parse it as XML —
   `RuntimeProperties.ErrorMessage`, `.PCallStack`, `.PCallStackHash`, `.SecondsSinceStart`.
   The `CallStack` node is usually EMPTY in shipping builds; `PCallStack` (module + hex offset)
   is the one with content. **Two crashes sharing a `PCallStackHash` proves the same code site**,
   which is how you confirm "repeatable" without reproducing it yourself.
2. `EXCEPTION_ACCESS_VIOLATION reading address 0x20` (any small fixed offset) is a null
   dereference — a field that should hold an object holds null.
3. Map the crashing *action* to the `.uasset`, then find which pak owns it using the pak-index
   grep above. Here only one mod overrode `WEAPON_MiniPistol` / `WEAPON_MagnumPistol`.
4. **Check the mod's version against the game's CURRENT patch — this is the actual diagnosis.**
   A `_P.pak` overriding a Blueprint replaces the WHOLE serialized asset, not a delta. If the
   underlying C++ class gained or reordered properties in a later patch, the old Blueprint
   deserializes with those fields absent → null → access violation.
   - game build: `steamapps/appmanifest_<appid>.acf` → `buildid` + `LastUpdated`
   - is that build current: `https://api.steamcmd.net/v1/info/<appid>` → `depots.branches.public`
   - buildid → marketing version: `https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=<appid>&count=30`
     and match the patch-note date to the branch `timeupdated`. Both unauthenticated.
   Result: game on **v2.1 "Parity Patch" (2026-03-20)** vs mods from 2023–2024, all pre-1.3.

**CONFIRMED CULPRIT (2026-08-12): the mod overriding `Blueprints/Inventory/ITEM_Base.uasset`** —
a `zzz_StackUpgrade_P.pak` stack-size mod. Deleting it fixed the crash; the pistol drops cleanly.

**The reasoning mistake, which is the real lesson.** `Weapons Grid Size` v1.2.42 was blamed first
because it owned `WEAPON_MiniPistol` — the asset named in the repro. It was deleted, the crash
was unchanged (identical `PCallStackHash`), and a mod was lost for nothing.
**Match the suspect to the OPERATION, not to the noun in the bug report.** "Remove *a pistol*
from inventory" is an operation every item shares, so it lives on the shared base class; the
pistol was incidental. The leaf class only owned the grid footprint and could never have been it.
Rank overrides of base/parent assets (`*_Base`, anything directly under the feature root) far
above leaf overrides whenever the failing action is generic — add/remove/drop/stack/use.
A `zzz_` filename prefix is a manual rename to force alphabetical load order, i.e. the author
*intends* it to win over every other pak — that alone makes it a prime suspect.

Beware the mirror-image trap: `ItemsGridSize` (v1.2.12) is the same 2024 vintage and carries
identical risk, but touches no weapon asset — removing it alongside would have confounded the
test. Change one pak at a time; `PCallStackHash` equality is what tells you a "fix" did nothing.

**Pak load order decides who wins, and it is ORDINAL — `-` (0x2D) sorts BEFORE `_` (0x5F).**
Later-mounted wins, which is why modders prefix `zzz`. This silently gutted two mods here: CFW
paks ship as `SystemShock-Windows-CFW03-Junk_P.pak` (hyphen), so they mounted *before*
`SystemShock-Windows_ItemsGridSize_P.pak` and lost 66 of 69 assets. Renaming to
`SystemShock-Windows_zzzCFW03-Junk_P.pak` fixed it. **Do not check this with PowerShell's
default `Sort-Object`** — it is culture-aware, ignores the hyphen, and reported the opposite
order. Use `[Array]::Sort($n,[StringComparer]::OrdinalIgnoreCase)`.

**Compare pak asset lists by BASENAME, not full path.** Different paks store paths at different
depths (some full `SystemShock/Content/...`, some bare filenames), so a full-path set
intersection returns a confident, wrong "0 conflicts". Also cache each pak's asset set once —
a nested re-read loop over a 200 MB pak times out.

Working System Shock 2023 inventory set as of 2026-08-12 (all verified crash-free): weapons 1x1
via `WeaponsGridSize`, plus CFW `Ammo` (10 ammo types **and** `ITEM_ExplosiveBase`), `Items`
(battery/probe/patches/first-aid), `Junk` (69 assets) — all three renamed with a `zzz` prefix.
`CFW Ammo Packs` is a LOOT-quantity mod (`AMMOPACK_*`), not a stacking one; don't install it for
stacking. Category base classes like `ITEM_Junk_Base` / `ITEM_ExplosiveBase` are fine — it was
the global `ITEM_Base` that crashed.

Header-version comparison across paks is a **dead end** — the package summaries are inside
compressed pak blocks, so a raw scan for the `0x9E2A83C1` magic finds nothing. Don't spend
time on it; a byte-wise PowerShell loop over a 200 MB pak also takes minutes.
