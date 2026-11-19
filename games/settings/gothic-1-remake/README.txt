GOLDEN config of Gothic 1 Remake - the one to restore.
Content as of 16 October 2026 (his verdict: "very good! keep it definitely golden").
The folder name keeps its first date (4 October 2026) on purpose; only one golden exists.
Restore: copy Engine.ini and GameUserSettings.ini to D:\games\saves\G1R\Saved\Config\Windows\ with Gothic closed,
then set Engine.ini read-only again (his order: the game deletes it otherwise).
16 October 2026, later: + visual batch A (refraction 2, contact shadows 1, translucency lighting 32) after his 'performance good'. Batch B is NOT in golden yet.
16 October 2026, later: + visual batch B (AO 2 levels / quality 75, SSR quality 2) after his 'running good'.
17 October 2026: + sharper textures (r.MipMapLODBias=-0.5) after his 'very good!'. Output resolution 55 % was tried and rolled back (too slow).
17 October 2026: NEW GOLDEN = the full live pair after Epic detail (r.DetailMode=3), his 'very good, mark as new golden'.
19 October 2026: NEW GOLDEN = live pair with visual batch D (shadow filter 5, AO 3/100, SSR 3 + roughness 0.6, bloom 100 %, full-res SSS) after his 'good performance! put as golden'.
19 October 2026: NEW GOLDEN = live pair with visual batch F (GTAO, SSR 4, lens flares, sky 64, capsule shadows) after his 'amazing! put as golden'.
19 October 2026: NEW GOLDEN = live pair with particle lights on (r.ParticleLightQuality=1; translucency stays 50 %) after his 'amazing! put as golden'.
19 October 2026: NEW GOLDEN = live pair with visual batch G (Lanczos upscale, full-res GTAO x4 angles, full CSM transition, sky aerial perspective 4) after his 'good! put as new golden'.
20 October 2026: NEW GOLDEN = live pair with small-object sun shadows (r.Shadow.RadiusThreshold=0.08) after his 'great - put as golden'.
20 October 2026: NEW GOLDEN = live pair with character shading (r.SkinCache.RecomputeTangents=2) after his 'put as golden'.
21 October 2026: NEW GOLDEN = live pair with SSR roughness 0.7 + motion blur at half (r.MotionBlurQuality=2, MotionBlurIntensity=0.5) after his 'amazing - update golden'.
23 October 2026: NEW GOLDEN = live pair with screen-space GI medium (r.DynamicGlobalIlluminationMethod=2, r.SSGI.Quality=2), DoF quality 3, sharpen 1.8 after his 'amazing - update golden'.
23 October 2026: NEW GOLDEN = live pair with SSGI high (3), effects quality High, motion blur full, sharpen 2.0, DoF 4, refraction 3 after his 'good - put as new golden'.
24 October 2026: NEW GOLDEN = live pair with FOV 55 (LOD scale 1.73), GTAO 2 angles, sky 32/32, bloom 64 %, shadow quality 4, SSGI epic (4), particle lights 2 after his 'very good! make it golden'.
24 October 2026: NEW GOLDEN = live pair after the 'bright, colourful' round: grain off, bloom 2.0, SSR 0.6, MidLuminance 45, fringe off, refraction 2, scene colour 32-bit, highlight 2.0, translucency volume 64, saturation 0.6, effects Epic, textures -0.75, SSS half-res, aerial 2; his 'it is very good'.
24 October 2026: NEW GOLDEN = live pair with light shafts on (r.LightShaftQuality=1) and bloom at 100 % resolution after his 'good - put as golden'. Also that day: Change Stack Size ammo capped at 99 (Ring,Ammo blacklist); backup loop 24 + 7 daily.
24 October 2026: NEW GOLDEN = the CALMER pair (saturation 0.4, bloom 1.3, highlight 1.6, MidLuminance 40, sharpen 1.5; light shafts on, grain off) after his 'too bright and vivid' -> 'keep as golden'.
25 October 2026: NEW GOLDEN = live pair with interior exposure 1.0, TAA frame weight 0.12, grass 15 % / bushes 12 % after his 'put as golden'.
26 October 2026: NEW GOLDEN = live pair with interior exposure 1.3, contrast +0.1, particle lights 1, effects High after his 'amazing! great config'.
28 October 2026: NEW GOLDEN = live pair with interior exposure 1.4, contrast +0.15, HDR mid-brightness 43, texture pool 12 GB, volumetric clouds on, after his 'put config as golden'. Put Away Torch removed the same day.
30 October 2026: NEW GOLDEN on game 1.1 + driver 31.0.178.0 = live pair with VRS contrast adaptive shading, HDR mid-brightness 45, film grain on, interior exposure 1.5, gamma 2.4, bloom 1.3, HDR on, music 0.35, after his 'put as golden'.
31 Oct: dialogues smooth (his 'fix worked'): capsule reach 200/100, shadow max res 512, SSS.Quality 0; forests/water fast: shadow distance 0.25, view distance 0.7, grass 0.15/0.12, water refraction /2; restored TAA quality 2, SSS full res, DoF 1.0; fog off
31 Oct later: 'superfast even dialogues' - same Engine as the morning golden; GUS as rewritten by the game
31 Oct 20:17: 'very good, very fast everywhere' (played with the game's HDR switch off by accident); game HDR switch restored to True
'very good! fast', dialogues fast, swamp a little slow but loved: output 55 %, view 0.6, FOV 51 + LOD 1.89, fog grid 44 (cheap injection, no supersampled history miss), interior 1.3, brightness 0.18
1 Nov: 'amazing!': output 60 %, FOV 47 + LOD 2.07, fog Z 32 + grid 48, interior 1.3, brightness 0.18
1 Nov: 'good': output 67 %, fog grid 54 + Z 32, FOV 45 + LOD 2.18, rooms 1.1 (his pick), brightness 0.18
1 Nov: 'mostly 28-30 FPS stable': output 50 % exact 2x, Lanczos, sharpen 2.0, mip -0.75, SSGI 2, sun shadows 0.2, fog grid 40 + Z 32; probe: GPU >= 95 % in 127/180 samples
1 Nov 23:06: finer fog (grid 24 at 50 %) 'was good'; session ended in a game-thread crash (not settings-related)
2 Nov: sun shadows 0.25 'same good, 27-29 FPS, dips to 19 in hard scenes' - tuning complete
