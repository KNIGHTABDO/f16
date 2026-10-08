# Knight Wings: architecture and contracts

Godot **4.7.2**, GDScript only, **Mobile** renderer (Metal on iOS). Godot project is in `game/`.
Target: iPhone 13 Pro Max (A15, 6 GB RAM, sustained 60 fps), iPad A16 (higher preset). Landscape only.
Built on GitHub Actions macOS (no Mac locally); developed and tested on Linux with `godot` (4.7.2) in PATH.

## Layout
```
game/autoload/   WorldOrigin, Events, Settings, GameState, Ground, Sfx, Vfx, Radio  (singletons, see each file header)
game/core/flight/     FlightModel (pure physics), AircraftData (JSON loader)
game/core/aircraft/   Aircraft node + scene, visuals (control surfaces, afterburner, gear), damage FX
game/core/controls/   ControlInput, PlayerController (touch/gyro/keyboard/gamepad), AIPilot
game/core/camera/     FlightCamera (chase, cockpit, free orbit, weapon cam)
game/core/weapons/    WeaponSystem, Gun, Missile, Bomb, Rocket, Flare, projectile pools
game/core/combat/     Hitbox, GroundUnit, SamSite, AAA, Ship, Structure, Explosion FX
game/core/world/      Terrain renderer, Ocean, Sky/Weather/Clouds, Vegetation, Cities, Airbases
game/core/missions/   Level, mission modes, spawners, objectives
game/ui/              HUD, touch controls, menus, hangar, settings, radio panel
game/data/            aircraft/<id>.json, weapons.json, maps/<id>.json, modes.json
game/assets/          models/, textures/, sounds/, music/, maps/<id>/ (binary map data), fonts/
tools/                Python/Blender asset pipelines (map builder, model converter)
```

## Units and coordinates
- Meters, seconds, kilograms, newtons, radians internally. km/h, feet and degrees only in UI/data files where named `_kmh`, `_deg`, `_ft`.
- Godot axes: +X east, +Y up, **-Z north**. Aircraft nose points along its local **-Z** (Godot forward), +Y is the top of the aircraft, +X is the right wing.
- Floating origin: read `autoload/world_origin.gd`. Every world Node3D must be in group `floating` and a direct child of the level's `World` node.
- Terrain/sea queries: `Ground.height_at(x, z)`, `Ground.surface_at`, `Ground.raycast(from, to)`, `Ground.is_water`, `Ground.landcover_at` (local coords).

## Physics
- Gameplay simulation runs in `_physics_process` at 60 Hz with physics interpolation ON (renders smoothly at 120 Hz).
  After teleporting a node call `reset_physics_interpolation()`.
- Aircraft, missiles and bullets are NOT Godot rigid bodies; they integrate their own motion.
  Godot physics is used only for ray queries against `Hitbox` Area3Ds (layers: 2 aircraft, 3 ground units, 4 structures).
- Terrain collision = `Ground` heightmap queries (no terrain collision shapes).

## Damageable contract
Any node that can be destroyed (aircraft, vehicles, ships, SAM sites, buildings):
- is in groups `damageable` and `floating`, and `team_0` (player side) or `team_1` (enemy)
- `var team: int`, `var alive: bool`, `var max_health: float`, `var health: float`
- `func take_damage(amount: float, source: Node, hit_pos: Vector3) -> void` (emits `Events.damaged`, and on death `Events.target_destroyed` / `Events.aircraft_destroyed` with source as killer, spawns an explosion via `Events.explosion`)
- `func get_target_kind() -> String`: one of `"air"`, `"helicopter"`, `"vehicle"`, `"armor"`, `"sam"`, `"aaa"`, `"ship"`, `"structure"`
- `func get_velocity() -> Vector3` (zero if static)
- has a child `Hitbox` (core/combat/hitbox.gd) for gun hits; missiles/bombs use proximity / blast radius.

## Aircraft public API (core/aircraft/aircraft.gd, `class_name Aircraft`, extends Node3D)
- `aircraft_id: String`, `data: AircraftData`, `team: int`, `is_player: bool`, `alive: bool`, `health`, `max_health`
- `controls: ControlInput` (controller writes it every tick before the aircraft integrates)
- `velocity: Vector3` (local/world space m/s), `get_velocity()`
- `get_speed_kmh()`, `get_ias_kmh()`, `get_mach()`, `get_altitude_m()` (ASL), `get_agl_m()`, `get_g()`, `get_aoa_deg()`,
  `get_heading_deg()` (0 = north, clockwise), `get_pitch_deg()`, `get_roll_deg()`, `get_throttle()`, `is_afterburner()`, `get_fuel_frac()`,
  `is_stalling()`, `is_gear_down()`, `is_on_ground()`
- `weapons: WeaponSystem` (set up from the loadout)
- signals: `destroyed(killer)`, `damaged(amount, source)`
- groups: `aircraft`, `damageable`, `floating`, `team_N`

## Data files
- `data/aircraft/<id>.json`: see `data/aircraft/f16c.json` (the reference; every aircraft uses the same keys).
- `data/weapons.json`: weapon id -> parameters. `data/maps/<id>.json`: map metadata (see `autoload/ground.gd`).

## Code rules (for every agent)
- GDScript 2 with static types (`var x: float`, `func f(a: int) -> void`). Tabs for indentation. snake_case files, `class_name` PascalCase.
- No `@tool` scripts unless asked. No editor-only APIs at runtime. No C#, no GDExtensions, no addons unless the brief says so.
- Scenes (`.tscn`) must be valid Godot 4 text scenes. Prefer building node trees in code (`_ready`) over large hand-written .tscn files.
- Performance is a feature: no per-frame allocations in hot loops, no `get_nodes_in_group` per bullet, pool projectiles,
  use MultiMeshInstance3D for many identical objects, keep draw calls low, keep GDScript loops small.
- Read the files you depend on before using them. Never invent an API that is not in this document or the code.
- Validate with `godot --headless --path game --check-only --script <file>` per script and `godot --headless --path game --quit-after 300`
  (with `--scene` for test scenes): zero errors and zero warnings you introduced.
