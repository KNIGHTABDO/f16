# Task: performance + IPA size (iPhone 13 Pro Max A15 sustained 60 fps, iPad A16 high preset, IPA < 150 MB)

## Read first
`tasks/_integration_todo.md` ([perf]), `game/export_presets.cfg`, `.github/workflows/`, `game/autoload/settings.gd` (presets), `game/core/world/*`,
`game/assets/maps/*`, `game/assets/models/**`, `game/core/aircraft/aircraft_visual.gd`.

## Do
- Compress map binaries (height.r16/landcover.u8 via FileAccess.open_compressed zstd; colour textures as ASTC/ETC2 VRAM-compressed
  imports), recompress big GLB textures (f35a etc, 2048 jpg q85 or basis), exclude test/dev files from the iOS export.
- LODs (visibility ranges) for aircraft/units/buildings, MultiMesh for vegetation/buildings, shadow distances per preset, dynamic
  render scale driven by frame time (thermal aware), perf HUD toggle (fps, ms, draw calls) in settings.
- Shader warmup on the loading screen (spawn every material once behind the loading art).
- Report final per-preset settings and the expected IPA size (sum of exported files) in docs/PERF.md.
