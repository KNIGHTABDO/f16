# Research: big map, graphics, assets on A15 (Oct 2026)

Method: ~14 web searches (no deep page fetches). Items marked [UNVERIFIED] come from general knowledge, not a source. Not legal advice.

## 1. Big map (100x100 km+)

### Elevation data
- Copernicus DEM GLO-30 (30 m): free on AWS Open Data, no AWS account needed (`aws s3 ... --no-sign-request`, bucket `copernicus-dem-30m`, eu-central-1, Cloud Optimized GeoTIFF). Free for general public under the Copernicus licence; a few country tiles are withheld. GLO-90 is global. Credit required.
  - https://registry.opendata.aws/copernicus-dem/
  - https://documentation.dataspace.copernicus.eu/APIs/SentinelHub/Data/DEM/resources/license/License-COPDEM-30.pdf
  - https://docs.digitalearthafrica.org/en/latest/data_specs/COP_DEM_specs.html
- SRTM (30 m/90 m, NASA/USGS, public domain) [UNVERIFIED in this research]. Use as fallback.
- Practical size: 100 km at 30 m = 3333x3333 samples = ~22 MB as 16-bit. Tiny. Heightmap data is not the problem; the render/streaming of detail is.
- Pipeline (run on Linux with GDAL/rasterio/Python): crop region -> reproject to a local metric CRS -> bake to 16-bit tiled quadtree (e.g. 257x257 or 129x129 tiles per LOD) -> ship in app bundle or a downloaded pack.
- Add procedural micro-detail (noise/fBm) on top of 30 m data in the vertex/fragment shader so low altitude flying doesn't look like melted wax.

### Imagery / texturing
- Sentinel-2: free incl. commercial use (EU Reg. 1159/2013, 377/2014). Credit: "Copernicus Sentinel data [year]" / "Contains modified Copernicus Sentinel data [year]". 10 m/pixel: 100 km = 10000^2 px, too big raw; use heavily downsampled as a macro colour map (e.g. 8k x 8k ASTC 8x8 ~ 32 MB) - good enough far away.
  - https://forum.sentinel-hub.com/t/can-satellite-photos-be-sold-as-art-photos/7978
  - https://wiki.osm.org/wiki/Eox.at (EOX "Sentinel-2 cloudless" mosaics have own terms; 2018+ layers are NON-COMMERCIAL, avoid or check)
- ESA WorldCover 10 m land cover (CC BY 4.0, free, AWS/COG): ideal for biome splat map (forest/grass/crop/urban/water/bare/snow) driving procedural tiling textures. https://worldcover2021.esa.int/download , https://registry.opendata.aws/esa-worldcover-vito/index.html
- OpenStreetMap (ODbL): roads, rivers, building footprints, airfields -> place targets/cities. Extruding footprints generally not a derivative DB per OSM legal-talk, but a shipped extract may trigger share-alike; credit "© OpenStreetMap contributors". https://osmfoundation.org/wiki/Licence_and_Legal_FAQ , https://lists.openstreetmap.org/pipermail/legal-talk/2021-February/009056.html
- Natural Earth: public domain (check per-layer notes). https://edesiderata.crl.edu/resources/natural-earth
- Recommended: DO NOT use Google/Bing/commercial aerial imagery. Use procedural biome textures (tileable ground textures, CC0 from e.g. ambientCG / Poly Haven [UNVERIFIED]) blended by WorldCover + slope + height, plus a low-res Sentinel-2 macro colour tint.

### Terrain LOD
- CDLOD (Strugar 2010): quadtree of regular grids, GPU vertex morphing, no stitching, heightmap as 16-bit texture. Best fit: simple, GPU-driven, source + paper at https://github.com/fstrugar/CDLOD (DirectX/C++ reference; port the idea to Metal). Discussion: https://gamedev.net/forums/topic/704946-lod-for-procedural-terrains/
- Geometry clipmaps: alternative, nested rings around camera; good for a camera that moves fast and flat world. Needs more care for fast jets (update cost) [UNVERIFIED].
- Plan: quadtree node = one 33x33 or 65x65 reused grid mesh drawn instanced with per-node params; heights sampled from a texture array/atlas in vertex shader; select ~200-400 nodes per frame; streaming of height/normal tiles from disk on a background queue (mmap).
- Jets move 200-700 m/s: need aggressive far-distance LOD (visible range 30-60 km with fog/haze) and prefetch along velocity vector.

### Memory budget (iPhone 13 Pro Max, 6 GB)
- Apple publishes no number. Forum reports: standard per-app limit well below RAM; the increased-memory-limit entitlement is profile-authorised (not available for free-account sideload builds [UNVERIFIED but likely]). Reports of ~6 GB ceilings on 8-12 GB phones with entitlement, and an App Store build crashing near 6 GB vs a dev build much higher on iPad.
  - https://developer.apple.com/forums/thread/834805
  - https://developer.apple.com/forums/thread/770868
  - https://developer.apple.com/forums/thread/685084
- Planning number: stay at or below ~2-2.5 GB total (the brief's "~3 GB" limit is a hard ceiling; leave headroom). Suggested split: terrain tiles+textures 600-800 MB, aircraft/objects 300 MB, audio 100 MB, render targets 150 MB, misc/CPU 500 MB. Check live with Xcode memory gauge / `os_proc_available_memory()` [UNVERIFIED API name accuracy; it exists in os/proc.h].
- Handle memory warnings: drop far LOD tile cache first.

### ASTC
- Supported on A8+ GPUs (all targets). Fixed 128 bit/block: 4x4 = 8 bpp, 5x5 5.12, 6x6 3.56, 8x8 2.0, 12x12 0.89. Suggested: normals 4x4 (or 5x5), albedo 6x6 (8x8 for macro maps), height 16-bit stays uncompressed (R16Unorm). Tools: Arm `astcenc` runs on Linux. Sources:
  - https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/astc-does-it---part-ii-how-to-use-it
  - https://metalbyexample.com/compressed-textures/

### Trees / cities / sky / ocean (mostly general knowledge, little verified)
- Trees: no per-tree geometry beyond ~1 km. Near: instanced low-poly (200-500 tris) from WorldCover forest mask; far: cross-billboard/impostor atlas; very far: bake into terrain colour. [UNVERIFIED]
- Cities: OSM footprints extruded + instanced, merged per tile; far LOD = flat texture/blocks; impostor cubes. [UNVERIFIED]
- Sky/atmosphere: Hillaire 2020 "Scalable and Production Ready Sky and Atmosphere" - small LUTs (transmittance, multi-scattering, sky-view) designed to scale to mobile; FlightGear shader port as reference: https://diglib.eg.org/handle/10.1111/cgf14050 , https://git.nayala.duckdns.org/fly/fgdata/src/commit/4d3466216a2d94eedf560186df77728ab242d80c/Shaders/HDR/atmos-sky-view.frag . Cheaper fallback: analytic gradient sky + height fog + aerial-perspective tint in the terrain shader (the single biggest "big world" visual win).
- Clouds: billboards/impostor sheets for most; limited-step raymarch only for hero clouds or at low res; https://80.lv/articles/creating-volumetric-clouds-for-mobile-in-unreal-engine-5 . Profile on device.
- Ocean: scrolling normal-map plane with fresnel + sky reflection + depth-based colour from heightmap (shore foam); no FFT. Distance fade into fog. [UNVERIFIED]

## 2. Performance on A15 / A16

- Thermals: AnandTech A15 review: iPhone 13/13 Pro throttle within minutes; GPU settles ~3-3.6 W, far below peak, but sustained is still strong. https://at-web1.www.anandtech.com/show/16983/the-apple-a15-soc-performance-review-faster-more-efficient/3 . Anecdote (forum, weak): 13 Pro Max could not hold 60 fps in Genshin 120 mode. Sustained 120 fps is unrealistic for a big-terrain game on A15. Design for 60 fps sustained; offer 120 only on a "light" preset / short sessions. Capping at 60 reduces heat (inference).
- 120 Hz: on iPhone must add Info.plist `CADisableMinimumFrameDurationOnPhone = YES` [UNVERIFIED in sources, widely documented]. Use CAMetalDisplayLink (iOS 17+) with preferredFrameRateRange 30-120: https://skills.cat/skills/charleswiltgen/axiom/axiom-display-performance . Also allow 30/40/60 caps (iPhone also supports 40/48/etc as divisors of 120 [UNVERIFIED]).
- MetalFX: Apple feature table lists spatial upscaling on Apple3+ and temporal on Apple7+ (A14/A15/A16 are Apple7/8) - so A15 and A16 should support both; a 2022 forum thread claimed no support on A15 (old). Always gate on `MTLFXTemporalScalerDescriptor.supportsDevice(_:)` at runtime. https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf , https://developer.apple.com/forums/thread/707667 . Temporal needs motion vectors + depth + jitter, work for a solo dev; spatial is trivially easy. Cost of MetalFX on A15 not measured here.
- Dynamic resolution: render 0.67-1.0 of native 2778x1284, adjust from GPU frame time (`MTLCommandBuffer.gpuStartTime/gpuEndTime`), upscale with MetalFX spatial/temporal or bilinear; keep UI/HUD at native.
- TBDR practices: use memoryless attachments for depth/MSAA, avoid unnecessary load/store, single render pass where possible, avoid readbacks. https://developer.apple.com/videos/play/wwdc2020/10602/ , https://developer.apple.com/videos/play/wwdc2020/10632/
- Budgets (rule-of-thumb, [UNVERIFIED] - validate with Xcode GPU Frame Capture/Instruments, which need a Mac; on Linux use in-app timers + on-screen HUD + CI-less on-device testing): 60 fps: <= 300-500 draw calls, 1-2 M visible triangles; 30-40 fps comfortable up to ~3M. Aim for GPU frame <= 12 ms at 60.
- No Mac => no Xcode Instruments/GPU capture. Build in-game perf HUD (frame time, tri/draw counts, `ProcessInfo.thermalState`, `os_proc_available_memory`) and log to file; react to `thermalState` >= .fair by lowering resolution/FPS cap.

## 3. Free/legal 3D aircraft

- Sketchfab: per-model licence. CC BY (4.0) and CC0 OK for commercial use; CC BY-NC/ND not. Must credit creator + link, credit must reach end users (credits screen). Keep an ATTRIBUTIONS file per asset. https://help.sketchfab.com/en/articles/16152215-crediting-users-for-3d-model-downloads , https://sketchfab.com/developers/download-api/guidelines , https://sketchfab.com/blogs/community/an-introduction-to-creative-commons-licenses . Check "downloadable" flag; download glTF/USDZ.
- FlightGear: code GPLv2+; aircraft licence is chosen by each author, FGAddon requires GPL-compatible. Sounds/textures in a package may NOT be GPL (UIUC page warns). F-16CJ page lists licence status unknown. GPL model in your app means shipping the app would have to comply with GPL (source offer) [general knowledge]. For a free personal sideloaded app this risk is smaller but real if distributed. Verify COPYING/README per aircraft. https://wiki.flightgear.org/FlightGear_and_content_protection_(DRM) , https://wiki.flightgear.org/F-16CJ , https://m-selig.ae.illinois.edu/apasim/fgfs-models.html
- Stock sites (TurboSquid/CGTrader): some are "editorial use only" - avoid. Some royalty-free are OK but check no-redistribution of raw model (you ship it in app bundle, extractable).
- Other sources [UNVERIFIED]: OpenGameArt (CC0/CC-BY), Kenney (CC0, low-poly), Poly Pizza, NASA 3D resources (public domain for NASA craft), self-made via AI image-to-3D tools (check their terms).
- Trademark: real aircraft designs / "F-16" naming are Lockheed trademarks - fine for personal use; avoid shipping publicly as is.
- Budgets: LOD0 8-15k tris (player jet), LOD1 3k, LOD2 800, LOD3 200 / impostor; AI planes 2-5k max. Textures: one 2k ASTC 6x6 atlas per aircraft (~1.4 MB). Cockpit: 3D cockpit is feasible only for one or two aircraft (15-30k tris, 2k-4k textures, interior culled); recommend HUD-only first-person view + exterior chase cam, add cockpit later.

## 4. Free sounds
- Sonniss GDC Game Audio Bundle (free yearly, royalty-free, commercial OK, no attribution, no resale, no AI training): https://rekkerd.org/sonniss-releases-gdc-2026-game-audio-bundle/ , https://licenseorg.com/guide/music-audio/sonniss . Best single source for engines/guns/explosions.
- Freesound: per-file licence; use CC0 filter (search "jet engine", "turbine", "afterburner"). CC-BY needs credit; avoid NC. https://freesound.org
- OpenGameArt CC0 SFX packs (bangs/explosions): https://opengameart.org/comment/106597
- Mixkit warfare SFX (Mixkit licence, not CC0, read terms): https://mixkit.co/free-sound-effects/warfare/
- Kenney audio packs (CC0) - no verified jet pack.
- ElevenLabs free tier requires attribution - avoid: https://elevenlabs.io/sound-effects/jet-engine
- No verified CC0 jet engine pack found; build engine sound from a looped idle/mil/AB samples with pitch+volume by throttle (crossfade 3 loops). Compress to AAC/CAF; keep < 100 MB.

## 5. Presets (proposal; numbers are starting points to tune on device)

| Setting | iPhone 13 Pro Max (A15) "Balanced" default | iPhone "Performance" | iPad A16 "High" |
|---|---|---|---|
| Target FPS | 60 (adaptive 40-60) | 60 locked / 120 optional with low res | 60, 120 optional |
| Internal res | 0.75x + MetalFX upscale (if supported, else spatial/bilinear) | 0.6x | 0.85-1.0x |
| View distance (terrain) | 40 km | 25 km | 60 km |
| Terrain nodes / max tris | ~1.0 M | 0.6 M | 1.5 M |
| Heightmap detail noise | on, 1 octave | off | on, 2 octaves |
| Textures (ASTC) | albedo 6x6, 1k tile maps | 8x8, 512 | 6x6, 2k |
| Shadows | 1 cascade, 1024, near only (or none) | off (blob shadows) | 2 cascades 2048 |
| Trees/objects | instanced to 1.5 km + billboards | 800 m | 3 km |
| Clouds | billboard + low-res layer | billboards only | billboards + hero raymarch |
| Sky | sky-view LUT | gradient sky | LUT |
| Ocean | normal-map + fresnel | flat colour shader | + foam |
| Post | none/ tone-map, light bloom | none | bloom + light AA |
| AA | none + MetalFX temporal (or FXAA-lite) | none | 4x MSAA memoryless or MetalFX |
| Aircraft LOD0 | 12k tris | 6k | 15k |
| Auto-fallback | thermalState>=.fair: step down one tier | | |
iPad A16 has more RAM (4-6 GB) [UNVERIFIED], larger screen: keep the same budget logic but with more headroom; verify iPad model RAM.

## Engine note (outside the question)
Brief's repo is SwiftUI + XcodeGen + Metal. Searched alternatives: Godot works from Linux via GH Actions macOS runner + Fastlane (https://talks.godotengine.org/godotcon-ams-2026/talk/VGASKF/), Unity still needs macOS build step. For a large custom terrain with CDLOD, a custom Metal renderer is more work than Godot; Godot has a built-in Terrain3D add-on community [UNVERIFIED]. Worth a quick comparison before committing; but keeping Swift+Metal is viable as AI agents write the code and no Mac profiling is available either way.

## Biggest gaps
- No real-device A15 benchmarks for MetalFX or sustained 60 vs 120.
- Jetsam limit not officially documented; test on device.
- Triangle/draw-call budgets are rules of thumb.
- Sketchfab/FlightGear specific aircraft licences must be checked per model.
