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


## PARALLEL BUILD NOTE (read this, it overrides "needs")
Several agents are coding at the same time; the user wants code first, verification later. Do NOT run test scenes or playtests;
one `godot --headless --path game --import` error check at the end is the only test. Stay strictly inside the files you own.
Interfaces being written right now by other agents (code against these; guard with `ResourceLoader.exists()` / `has_method()` so your
code works even if the other side is not merged yet):
- Combat units (combat-units job): `game/core/combat/combat_unit.gd` class_name CombatUnit (team, health, `is_alive()`, signal `destroyed`),
  `sam_site.gd`, `aaa.gd`, `ship.gd`, `ground_vehicle.gd`, `convoy.gd`, structures. Spawn with `load(path).new()` then add_child.
- AI pilots (ai job): `game/core/controls/ai_pilot.gd` class_name AIPilot; API `setup(aircraft, skill, role)`, `set_patrol`, `set_target`,
  `set_escort`, `set_strike`, `order(cmd)`, `get_state()`; `game/core/missions/flight_group.gd` FlightGroup.
- Modes (modes-missions job): spawns aircraft via the existing level/aircraft code, attaches AIPilot as a child, uses CombatUnit for ground targets.
- Weapons (merged): game/core/weapons/weapon_system.gd API as documented in tasks/cont_weapons.md.
Commit early and often.
