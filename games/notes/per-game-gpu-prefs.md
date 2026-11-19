Surveyed 2026-08-20 on the Surface Laptop 7 (Snapdragon X Elite, Adreno X1-85).

**Where the flags live:** `HKCU\Software\Microsoft\DirectX\UserGpuPreferences`, one REG_SZ
per executable full path, value = `Key=Val;` pairs. Read/written directly; no UI needed.
Relevant keys: `AutoSuperResolutionEnable` (Auto SR, NPU upscaling), `AutoHDREnable`,
`SwapEffectUpgradeEnable` (legacy blit -> flip model, which is what gates VRR + Auto HDR on
older DX11 titles), `DXGIEffects`, `GpuPreference` (meaningless here — single GPU).

> **`AppStatus=2048` IS NOT CONFIGURATION.** Windows writes it when it merely *observes* a
> D3D app (Chrome, WARP, msrdc all carry it). An entry holding only `AppStatus` is untuned.

> ## ⚠ THE LAUNCHER-STUB TRAP — check binary size before trusting a tuned entry.
> Adding a game via Settings browses to the top-level exe, which for some UE titles is a
> relaunch stub. The flags then apply to a process that never creates the D3D device.
> **Gothic 1 Remake** had every flag (Auto SR, Auto HDR, SwapUp) on the **0.3 MB** stub
> `Gothic 1 Remake\G1R-Win64-Shipping.exe` while the real **163.8 MB**
> `Gothic 1 Remake\G1R\Binaries\Win64\G1R-Win64-Shipping.exe` had only `AppStatus=2048`.
> Fixed 2026-08-20 by merging the flags onto the real binary.
> **Counter-trap:** a small exe is NOT automatically wrong. Unity IL2CPP games are
> legitimately tiny (code lives in `GameAssembly.dll`) — Overcooked AYCE's 0.6 MB exe is
> the real one. Verify by looking for a `Binaries\Win64` tree, not by size alone.

**Auto SR gate:** needs the NPU — `Snapdragon(R) X Elite - X1E80100 - Qualcomm(R) Hexagon(TM)
NPU`, driver 30.0.220.3000, present and healthy. There is no `AutoSuperResolutionEnable` in
the `DirectXUserGlobalSettings` row, so Auto SR is **per-app opt-in only** here.

**What the 2026-08-20 Adreno bump actually changed (31.0.133.1 -> 31.0.152.1):**
- Shader compiler `qcgpuchpecompilercore.dll` **DX.50.28.00 -> DX.50.41.00** — the only
  substantive delta, and the only plausible source of per-title gains.
- Vulkan ICD `api_version` is **1.3.260 in both**. No new API tier, no new feature level.
- Every other UMD (`qcvkarm64xum`, `qcdx11/12arm64xum`, `qcdxdmlarm64x`, `OpenCL_adreno`)
  just tracks the package version.
So: **a driver bump does not raise the attainable settings on this box.** The levers that move
frame rate here are Auto SR and render resolution — the G95NC at 5120x1440 is the real load.

**Driver 31.0.152.1 state:** stable, with zero TDR / 4101 display resets, no LiveKernelReports dumps, GPU `CM_PROB_NONE`.
It is not the cause of the panel brightness fault (that was CABC, measured both ways).
Reinstall source, if it is ever removed by something else:
`C:\QCDrivers\Drivers\gfx_drivers_8380_ARM64_53DA4775-8DAF-4F74-A4DF-DE9389C0C578\qcdx8380`.

**Deliberately left alone:** Overcooked AYCE got no Auto SR, because adding it would
confound the pending in-game test of the 32:9 mod (see overcooked-ultrawide-mod.md).
Revisit only after that test passes.
