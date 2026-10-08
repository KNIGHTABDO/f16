# Task: ground/sea combat units and structures (targets that fight back)

## Read first
`docs/ARCHITECTURE.md` (Damageable contract!), `game/core/combat/hitbox.gd`, `game/core/weapons/` (WeaponSystem, Gun, Missile: reuse
Missile for SAMs and Gun for AAA; read their setup APIs), `game/data/weapons.json`, `game/autoload/{ground,world_origin,events,vfx,sfx}.gd`,
`game/data/maps/gibraltar.json` (roads, places, airports), `game/data/model_info.json` + `game/assets/models/ground/` (available models).

## Files you own
`game/core/combat/` : `combat_unit.gd` (class_name CombatUnit extends Node3D: shared Damageable base: team, health, hitbox, death FX,
wreck), `ground_vehicle.gd` (GroundVehicle: drives along a path following terrain, convoy formation), `convoy.gd`, `sam_site.gd`
(search radar + launchers + optional tracking radar; states idle/search/track/launch; uses Missile with weapon ids sa6 / sa2 / sa15
(add them to weapons.json: same keys as radar_missile/ir_missile types) and MANPADS sa18 ir), `aaa.gd` (ZSU-23-4 / Bofors style: leads
targets, uses Gun with id `zu23` / `bofors40` (add to weapons.json), flak airbursts for bofors), `ship.gd` (patrol boat, frigate with SAM +
gun, cargo ship; floats at sea level with bobbing, wake effect, sails waypoints), `structure.gd` (buildings, hangars, fuel tanks
(big secondary explosion), radar dish (rotating), bunker, bridges), `unit_factory.gd` (UnitFactory.spawn(kind: String, team, local_pos,
heading) -> CombatUnit: kinds tank, apc, truck, fuel_truck, sam_sa6, sam_sa2, sam_sa15, manpads, aaa_zsu, aaa_bofors, radar,
patrol_boat, frigate, cargo_ship, hangar, shelter, fuel_tank, bunker, tower, ammo_dump, comms), `unit_models.gd` (procedural
low-poly but well-shaped meshes for each kind when no GLB exists: a tank must look like a tank: hull, turret, barrel, tracks; desert
camo colours; LOD: far units as single merged mesh), `game/scenes/test_combat.tscn` + `game/core/missions/test_combat.gd`.

## Behaviour
- Units only engage within realistic envelopes (SA-6 3-25 km, SA-15 1.5-12 km, MANPADS < 5 km, ZSU < 2.5 km, Bofors < 4 km),
  need line of sight (`Ground.raycast`), have reaction delays and reload times, and a difficulty multiplier from `GameState.difficulty`.
- Emit `Events.missile_launched` so the player's RWR works. SAM radars emit a "radar lock" state readable by the HUD via group
  `radars` + `is_tracking(target) -> bool`.
- Death: `Vfx.explosion`, wreck mesh (darkened, smoking via `Vfx.wreck_smoke`), `Events.target_destroyed(unit, killer)`.
- Vehicles: follow road polylines from the map json (convert lat/lon/metres per the map json conventions: read ground.gd / map json keys),
  drive 30-60 km/h, align to terrain normal, scatter off-road when attacked, convoys of 4-10 units with spacing.
- Cheap: units tick at 10 Hz unless engaging; far units (> 15 km from camera) freeze visuals.

## Test
`test_combat.tscn`: flat or `test` map; a scripted target drone aircraft (or `Aircraft.create` with a simple autopilot: fly straight
lines through the envelope) at 1500 m; place one of each unit; verify SAMs launch and hit the drone, AAA tracers converge on it,
a convoy drives a road, a ship sails, then destroy every unit by direct `take_damage` calls and confirm wrecks + events.
Screenshots with DISPLAY=:0 of the unit lineup (close camera) and of a SAM launch; look at them and make units look good.
