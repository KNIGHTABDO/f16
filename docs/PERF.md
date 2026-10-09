# Performance and export size

Branch `hk/perf-ipa`. Measured on the local checkout on 2026-10-09. Nothing here has run on a device, and no export has been built (no iOS export templates locally).

## What changed

| Commit | Change |
| --- | --- |
| `1c642d3` | Map binaries packed: height and landcover as zstd, colour as a 4096 px JPEG (`color.jpg.bin`). |
| `5de3592` | iOS export ships the packed maps and terrain textures; test and dev files excluded. |
| `c9928ac` | Aircraft GLB embedded textures: opaque to JPEG q85, capped at 2048 px; alpha stays PNG. |
| `8d11abd` | Runtime: `PerfGovernor` (dynamic 3D resolution), `LodRanges` (aircraft draw distance), `ShaderWarmup`, `PerfHud`; presets retuned; shadow distance wired up. |

## Map sizes (raw files on disk)

| File | Before | After |
| --- | --- | --- |
| atlas `height.r16` | 33.55 MB | 31.40 MB (zstd) |
| atlas `landcover.u8` | 16.78 MB | 2.68 MB (zstd) |
| atlas colour | 28.8 MB | 5.99 MB (`color.jpg.bin`, 4096 px) |
| gibraltar `height.r16` | 33.55 MB | 16.24 MB (zstd) |
| gibraltar `landcover.u8` | 16.78 MB | 1.92 MB (zstd) |
| gibraltar colour | 15.4 MB | 3.11 MB (`color.jpg.bin`, 4096 px) |

Rebuild with: `godot --headless --path game --script ../tools/perf/pack_map_binaries.gd -- atlas gibraltar`. The script verifies each container by round trip before it rewrites `data/maps/<id>.json`.

Height is the largest remaining item. An offline experiment (not in the repo) split the 16-bit height into high-byte and low-byte planes and compressed each with zstd -19. Atlas height came to 20.50 MB, about 11 MB less than now. It needs a recombine at load. A GDScript loop over about 16.8 M samples is too slow, so it is deferred.

## Models

Aircraft GLBs: about 88 MB before, about 58 MB after. `f35a` stayed at 8.25 MB because no texture replacement made it smaller.

## Export size estimate

Measured raw sizes of what the export filters keep:

| Group | MB |
| --- | --- |
| Maps (atlas and gibraltar, packed; `test` excluded) | 61.4 |
| Models (GLB and other, JPEG-in-model excluded) | 60.5 |
| UI art | 13.7 |
| Terrain textures (raw JPEG, `include_filter`) | 5.4 |
| Icon, sounds, textures, data, scripts | 4.5 |
| **Total raw** | **about 145.5** |

This is raw input, not the shipped size. The shipped `.ipa` also includes the Godot engine binary and imported forms of models and textures, and neither is measured here. The 145.5 MB figure cannot confirm the 150 MB target without a real export.

## Export filters (`game/export_presets.cfg`)

- `include_filter`: `data/*.json`, `data/*/*.json`, `assets/maps/*/*.r16`, `assets/maps/*/*.u8`, `assets/maps/*/*.jpg.bin`, `core/world/terrain_textures/*/*.jpg`.
- `exclude_filter`: `assets/**/src/*`, `assets/maps/test/*`, `data/maps/test.json`, `assets/models/**/*.jpg`, `core/**/test_*.gd` (and `.uid`), `scenes/test_*.tscn`, `scenes/menu_test.tscn`.

## Runtime presets (`game/autoload/settings.gd`)

| Setting | low | balanced | high | ultra |
| --- | --- | --- | --- | --- |
| 3D render scale (ceiling) | 0.65 | 0.9 | 1.0 | 1.0 |
| Dynamic resolution floor | 0.5 | 0.6 | 0.75 | off |
| Frame cap (fps) | 30 | 60 | 60 | 120 |
| Unit draw distance (m) | 2500 | 4000 | 6000 | 9000 |
| Shadow distance (m) | 1000 | 1500 | 2500 | 4000 |
| MSAA 3D | off | 2x | 4x | 4x |
| FXAA | off | off | on | on |
| Terrain colour texture (px) | 2048 | 4096 | 4096 | 8192 |
| Terrain detail | low | medium | high | ultra |
| Vegetation | off | medium | high | high |
| City density | low | medium | high | high |

How the pieces behave:

- `PerfGovernor` steps the 3D scale down by 0.05 when frames run over 1.12× target, and up by 0.025 after 3 s of headroom. The scale stays between the floor and the ceiling. After 8 s overloaded at the floor it caps at 30 fps and probes the full cap again after 60 s.
- `Settings.shadow_distance` is applied in `sky.gd` when the world is built. Changing it mid-flight takes effect on the next build.
- `LodRanges` sets `visibility_range_end` from `Settings.unit_draw_m` on the aircraft (margin 150 m, fade self).
- `ShaderWarmup` draws 13 world and vfx shaders for 3 frames behind the loading screen. The sky shader and `livery_overlay` are skipped.
- `PerfHud` appears when `Settings.show_perf_hud` is on. It shows fps, frame ms, draw calls, scale and the throttle flag.

## Known gaps

- Not run on a device. No playtest was done.
- Thermal: Godot 4.7 has no thermal API on iOS. Sustained overload at the floor is the only signal used.
- Shader warmup: the hitch reduction is not measured.
- Export filter: whether `include_filter` ships the raw terrain JPEGs as intended is unverified. The imported `.ctex` copies of the same textures also ship, which duplicates about 5 MB. Moving the terrain loader to `ResourceLoader` would drop the raw copy.
- `f35a` is unchanged at 8.25 MB.

## Out of scope (not changed; owners to act)

1. **Regression on this branch:** `ui/hud/hud_minimap.gd:33-34` loads `Ground.meta["color_file"]` with `ResourceLoader.exists`/`load`. That returns false for `color.jpg.bin`, so the minimap loses its satellite background. Fix: use `Ground.get_color_texture()`.
2. `tools/build_map.py:1048` still writes `color.jpg` and raw height and landcover. A rebuilt map undoes the packing. It needs to write `color.jpg.bin` at 4096 px, quality 86, and then run `tools/perf/pack_map_binaries.gd`.
3. `tools/convert_models.py` should write opaque textures as JPEG, or run `tools/perf/shrink_glb_textures.py` after conversion.
4. Combat units and AI aircraft should call `LodRanges.apply_tree(self)` after `setup()`, as `aircraft_visual.gd` does.
5. `ui/settings_screen.gd` needs "Dynamic resolution" and "Unit draw distance" controls. The shadow slider already works.
6. `docs/ARCHITECTURE.md` should list `lod_ranges.gd`, `perf_governor.gd`, `perf_hud.gd` and `shader_warmup.gd`.
7. `assets/ui/maps/thumb_test.jpg` is kept because `data/ui_art.json` references it.
