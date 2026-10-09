# CONTINUATION: finish world_dressing

A previous agent started this task and was interrupted. Its work is ALREADY COMMITTED on this branch (last commit 'WIP: overnight progress'; see `git log main..HEAD` and `git diff main --stat`). Review that work first, keep what is good, fix what is broken, and complete everything the original brief below asks for. Verify headless with Godot (`godot --headless --path game --import` first, then run the relevant test scene) before finishing.

# Task: world dressing (sky, time of day, clouds, weather, vegetation, cities, airbases, carrier)

The terrain/ocean already exist (`game/core/world/terrain.gd`, `ocean.gd`). Make the world beautiful, like a modern mobile flight
game (think Ace Combat 7 skies) while staying at 60 fps on an A15 (Mobile renderer).

## Read first
`docs/ARCHITECTURE.md`, `game/core/world/terrain.gd` + `terrain.gdshader` + `ocean.gd` (their public API), `game/autoload/{ground,world_origin,settings,game_state}.gd`,
`game/data/maps/gibraltar.json` (airports, runways, places, roads, spawn), `game/assets/models/` + `game/data/model_info.json` (ground models available).

## Files you own
`game/core/world/sky.gd` + `sky.gdshader`, `clouds.gd` + `clouds.gdshader`, `weather.gd`, `vegetation.gd`, `cities.gd`,
`airbase.gd`, `runway.gdshader`, `carrier.gd`, `world_builder.gd` (class_name WorldBuilder: one call builds everything for a map),
textures under `game/assets/textures/world/` (generate with PIL/numpy or download CC0 from ambientCG / Poly Haven; CREDITS.md),
`game/scenes/test_world.tscn` + `game/core/world/test_world.gd`.

## WorldBuilder API
`WorldBuilder.build(world: Node3D, map_id: String, time_of_day: String, weather: String, camera: Camera3D) -> Dictionary`
returns {terrain, ocean, sky, clouds, environment (WorldEnvironment), sun (DirectionalLight3D), airbases: Array, carrier}.
time_of_day: "dawn","morning","noon","afternoon","sunset","dusk","night". weather: "clear","scattered","overcast","storm","haze".
Also `WorldBuilder.update(delta)` if anything needs per-frame work (cloud drift, etc.).

## Content
1. Sky: physically-inspired procedural sky shader (Rayleigh/Mie approximation, sun disk, moon + stars at night), matching fog colour
   (Environment fog with height falloff + aerial perspective: distant terrain fades to the sky's horizon colour, essential for scale),
   tonemap ACES/AgX, glow (cheap on Mobile), sun DirectionalLight3D with 2-split shadows only near the camera (max distance 2-3 km;
   preset-scaled), ambient from sky. Night: dark blue ambient, city lights (emissive in urban landcover via terrain? if not possible,
   emissive point MultiMesh in cities), runway lights.
2. Clouds: a cloud layer the aircraft can fly through: cumulus as MultiMesh of soft lit impostor billboards (noise-shaded spheres
   clustered, depth-faded, sun-lit side brighter) placed in clusters around the camera in a recycled grid (e.g. 32 km radius),
   plus a high-altitude cirrus dome texture. When the camera is inside a cloud: white-out fog. Density by weather preset.
   Must look good from above (sea of clouds) and below.
3. Weather: rain particles around the camera (storm), lightning flashes (storm), haze, wind vector (expose `Weather.wind` for flight
   model/missiles), turbulence intensity getter.
4. Vegetation: MultiMesh trees (low-poly billboarded or crossed-quad trees with atlas textures; 2-3 species: pine for mountains/
   north, palm near coast/urban in Morocco, argan/olive bushes in shrubland) placed from `Ground.landcover_at` (LC_TREES dense,
   LC_SHRUB sparse) in cells around the camera (cell 512 m, radius ~3 km, refill cells as camera moves; deterministic per-cell seed).
5. Cities: for each `places` entry (city/town) and LC_URBAN cells near the camera, MultiMesh boxes as buildings with a facade
   shader (windows, roofs, Moroccan white/ochre colours, minarets occasionally), dense near the centre, heights by place size.
   Draw within ~6 km, plus cheap far impostor (terrain colour already shows the city).
6. Airbases: for each map airport: runway meshes from runway endpoints (asphalt texture, markings: threshold piano keys, numbers,
   centreline, touchdown zones via shader), taxiway strip, apron, hangars/hardened shelters, control tower (models if available,
   else nice procedural), runway edge lights at night. Each airbase is a Node3D (group floating) with `get_runways() -> Array`
   (each {start: Vector3, end: Vector3, width, heading_deg, name}) for spawning/landing, and a `team` (main base of the map = team 0).
7. Carrier: if a carrier model exists use it, else build a convincing procedural carrier (hull, island, deck markings, angled deck,
   catapults, arresting wires positions exposed: `get_deck_transform()`, `get_wire_positions()`, `get_cat_positions()`), placed at the map's
   `carrier` spawn in the sea (or a sea point you pick near the main airport), moving 15 knots, deck height for Ground queries:
   expose `deck_height_at(local_x, local_z) -> float` (NaN when not over the deck).

Everything scales with `Settings.graphics_preset` (cloud counts, tree density/radius, shadow distance, building distance).
Every node in group `floating`; cell grids keyed by WORLD coords (WorldOrigin.world_x/z) so they don't jump on origin shifts.

## Test
`test_world.tscn`: builds gibraltar (fall back to `test` map if gibraltar data is missing), a free camera flying a scripted path
(low over Tangier city and the airport, through clouds, high over the strait) for each time of day; save screenshots with DISPLAY=:0
for noon, sunset and night at 3 positions, LOOK at them (PIL contact sheet) and iterate until they look great. Print the frame time
and draw calls (`RenderingServer.get_rendering_info`) at each shot; report them.
