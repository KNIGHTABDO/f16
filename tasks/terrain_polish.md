# Task: terrain + ocean visual polish (make the real Morocco maps look stunning from 30 m to 12 km)

## Read first
`docs/ARCHITECTURE.md`, `tasks/_integration_todo.md` ([terrain], [terrain polish], [maps], [perf] items), `game/core/world/{terrain,ocean}.gd`
+ their .gdshader files, `game/core/world/terrain_textures/`, `game/autoload/ground.gd`, `game/data/maps/*.json`, `tools/build_map.py`.

## Files you own
`game/core/world/terrain.gd`, `terrain.gdshader`, `ocean.gd`, `ocean.gdshader`, `game/core/world/terrain_textures/`, `game/autoload/ground.gd`
(keep its public API), `tools/build_map.py` + the map binaries it outputs under `game/assets/maps/` (only if you regenerate them).

## Do
- Colour: satellite colour is too dark/desaturated: grade it in the shader (exposure, saturation, dehaze, warm Moroccan tones), with
  aerial perspective (height/distance fog tinted by sky colour) so distant mountains turn blue-hazy like real photos.
- Near ground (< 500 m AGL) is blurry: blend high-res tiling detail textures (rock, sand, grass, forest, farmland, urban, snow) chosen by
  landcover + slope + altitude (snow above ~3000 m in Atlas), triplanar on steep slopes, stochastic/hex tiling to hide repetition,
  normal maps, macro variation noise. Generate textures (PIL/numpy) or download CC0 (ambientCG/Poly Haven) at 1024² , list in CREDITS.md.
- Fix the grey flat patch NE of Tangier at ~1500 m (tile seam / LOD hole). No cracks between clipmap rings.
- Ocean: beautiful deep Atlantic/Mediterranean blue, shoreline foam + shallow turquoise from depth (terrain height under water),
  Gerstner waves near camera, sun glint, fresnel reflection of sky colour; cheap on mobile.
- Expose height data from Ground so Ocean does not re-read the file. `apply_quality(preset)` honours low/medium/high/ultra.
- Perf: A15 iPhone at 60 fps on "high": keep texture fetches reasonable (document the count per preset in a shader comment).
