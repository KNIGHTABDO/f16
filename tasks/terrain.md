# Task: terrain + ocean renderer (huge real-world map on an A15 phone)

Render a 256 km x 256 km real-terrain map that looks stunning from 10 km up AND at 50 m above the ground, at 60 fps on
iPhone 13 Pro Max (Mobile renderer, Metal). Also render the sea.

## Read first
`docs/ARCHITECTURE.md`, `game/autoload/ground.gd` (map formats; your shader heights MUST match `Ground.height_at` exactly,
otherwise aircraft collide with invisible ground), `game/autoload/world_origin.gd`, `game/autoload/settings.gd`.

## Files you own
- `game/core/world/terrain.gd` (`class_name Terrain extends Node3D`), `game/core/world/terrain.gdshader`,
  `game/core/world/ocean.gd` + `ocean.gdshader`, `game/core/world/terrain_textures/` (detail textures you download)
- `tools/make_test_map.py` + output `game/assets/maps/test/*` + `game/data/maps/test.json` (a synthetic map, see below)
- `game/scenes/test_terrain.tscn` + `game/core/world/test_terrain.gd` (fly-through camera test scene)
Do not edit other files.

## Map data
Real maps are being generated in parallel by another agent into `game/assets/maps/<id>/` with exactly the formats in ground.gd plus
`color.jpg` (8192^2 satellite colour; row 0 north, col 0 west) and metadata `color_file` in `data/maps/<id>.json`.
Until they exist, create a synthetic test map with `tools/make_test_map.py` (numpy via `~/.local/bin/uv run --with numpy --with pillow`):
4096^2 fBm + ridged mountains up to 3000 m, a coastline with sea, valleys, a flat area for a runway, matching landcover classes
(sea 0, beach/bare 6, grass 3, crop 4, trees 1 on slopes, snow 7 above 2500 m, a few urban 5 patches) and a plausible colour.jpg
(2048^2 is enough for the test), `size_m` 256000. Same metadata keys as ground.gd/load_map.

## Terrain technique (required)
- **GPU geometry clipmap** (Losasso/Hoppe style or CDLOD rings): a fixed set of grid meshes centred on the camera, each ring
  doubling cell size (finest ~4 m cells around the camera, ~12 levels to cover the whole map + horizon), snapped to their cell
  size to avoid swimming, with morphing between levels to hide seams/popping. Vertex shader samples height from the heightmap
  texture. Recenter meshes in `_process` from the active camera position. Few draw calls total (~13 meshes + skirts).
- Height texture: decode height.r16 to an `Image` of `FORMAT_RF` (or RG8 packed hi/lo if RF vertex fetch is a problem) with
  mipmaps; bilinear sample in the vertex shader. Pass the world/local mapping (WorldOrigin offset, size_m, height range) as uniforms;
  update the offset uniform on `WorldOrigin.shifted`.
- Close-range detail: add procedural fBm detail displacement below ~2 km camera distance (small amplitude, e.g. 1-6 m, faded to 0
  far away and near runways = where landcover is urban or terrain is flat). **Ground.height_at does not know about it**, so keep it
  small and expose `detail_amplitude` so the collision offset can be estimated; add a GDScript method
  `Terrain.detail_height_at(local_x, local_z) -> float` that reproduces the same detail function on the CPU (same hash/noise) so
  gameplay can use the exact rendered height if needed.
- Normals: computed in the fragment shader from the heightmap (central differences) + detail normal maps.
- Colour: far = satellite `color.jpg` (with mipmaps, anisotropic). Near (< ~3 km): blend in tiling **detail textures** per land-cover
  class (grass, dry grass/shrub, farmland, forest floor, rock, sand, snow, urban/asphalt) using the landcover texture (nearest
  sampling, with soft blending between classes using several taps) + slope-based rock + altitude snow, tinted by the satellite
  colour so the near look matches the far look. Use 2-3 scales of texture to kill tiling. Download CC0 PBR textures (albedo +
  normal, 1K or 2K jpg) from ambientCG (`https://ambientcg.com/get?file=Grass004_1K-JPG.zip` style direct links) or Poly Haven
  (`https://api.polyhaven.com`), pack them into Texture2DArrays (albedo array + normal array) in `terrain_textures/`.
- Lighting: works with the scene's DirectionalLight3D and environment fog; add subtle aerial perspective (blue haze with distance
  and altitude) inside the shader so mountains 80 km away fade into the sky colour. Shadows from the sun on terrain are optional
  (Mobile renderer cost), but compute a cheap horizon-based self-shadow or at least strong slope shading so the mountains read well.
- Quality presets from `Settings.graphics_preset` ("low", "balanced", "high", "ultra"): number of rings, ring resolution,
  detail texture distance, detail displacement on/off. `balanced` must hold 60 fps on A15.

## Ocean (ocean.gd/ocean.gdshader)
Large camera-following clipmap-ish water mesh at `Ground.sea_level`, rendered only where the terrain is below sea level
(depth test handles it). Look: deep blue to turquoise shallows (use water depth = sea_level - terrain height sampled from the same
height texture), scrolling multi-octave normal maps (procedural or CC0), sun specular glint, fresnel sky reflection, foam at the
shoreline and white caps, gentle Gerstner vertex waves near the camera only. Visible from 10 km up without tiling patterns.

## Test scene
`test_terrain.tscn`: loads `test` (or `gibraltar` if `game/data/maps/gibraltar.json` exists): `Ground.load_map(id)`, sun, sky
(ProceduralSkyMaterial), fog, the Terrain and Ocean, and a scripted camera fly-through (low pass over coast/mountains at 150 m, then
climb to 8 km) with an fps label. Headless run must be error-free. Render screenshots with `DISPLAY=:0` (Vulkan Mobile renderer)
at several altitudes and LOOK at them: no seams, cracks, popping rings, stretched textures or visible tiling.

## Public API
`Terrain.setup(map_id: String)` (assumes Ground.load_map already called), `Terrain.set_camera(cam: Camera3D)`,
`Terrain.apply_quality(preset: String)`, `Terrain.detail_height_at(x, z)`. Same idea for Ocean.
