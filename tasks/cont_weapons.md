# CONTINUATION: finish weapons

A previous agent started this task and was interrupted. Its work is ALREADY COMMITTED on this branch (last commit 'WIP: overnight progress'; see `git log main..HEAD` and `git diff main --stat`). Review that work first, keep what is good, fix what is broken, and complete everything the original brief below asks for. Verify headless with Godot (`godot --headless --path game --import` first, then run the relevant test scene) before finishing.

# Task: weapons and targeting

Guns, missiles (IR, radar, air-to-ground), bombs (dumb + laser guided), rockets, flares, target selection and lock-on.
Must feel punchy and fair, like a good arcade/sim hybrid (War Thunder / Ace Combat), and run at 60 fps on an A15.

## Read first
`docs/ARCHITECTURE.md`, `game/data/weapons.json`, `game/data/aircraft/f16c.json`, `game/core/aircraft/aircraft.gd`,
`game/core/flight/aircraft_data.gd`, `game/core/controls/control_input.gd`, `game/core/combat/hitbox.gd`,
`game/autoload/{events,ground,world_origin,sfx,vfx,settings}.gd` (Sfx and Vfx may still be stubs: call them anyway, they are
implemented in parallel by other agents with exactly those signatures).

## Files you own
`game/core/weapons/` : `weapon_system.gd` (class_name WeaponSystem extends Node), `gun.gd` (Gun), `bullet_pool.gd`,
`missile.gd` (Missile extends Node3D), `bomb.gd` (Bomb), `rocket.gd` (Rocket), `flare.gd` if needed, `weapon_models.gd`
(procedural low-poly meshes for missiles/bombs/rockets/pylons when no glb exists), `targeting.gd` (helpers),
`game/scenes/test_weapons.tscn` + `game/core/missions/test_weapons.gd`, `game/core/combat/dummy_target.gd` (test targets only).

## WeaponSystem API (the Aircraft already calls these; HUD and AI will call the getters)
- `setup(aircraft: Aircraft, loadout: String)` (loadout "" = `data.default_loadout`), `tick(controls: ControlInput, delta: float)`
- `get_selected() -> Dictionary` {id, name, type, count}, `get_weapon_list() -> Array` (for HUD), `select_next()`
- `get_gun_ammo() -> int`, `get_gun_ammo_max() -> int`, `get_flares() -> int`
- `get_target() -> Node3D`, `set_target(node)`, `cycle_target()` (nearest-to-boresight first among valid kinds for the selected weapon)
- `get_lock_state() -> int` (0 none, 1 seeking, 2 locking, 3 locked), `get_lock_progress() -> float`
- `get_gun_lead_point() -> Vector3` (where to aim to hit the current target with the gun; LOCAL coords), `get_gun_range() -> float`
- `get_ccip_point() -> Vector3` (bomb/rocket continuously computed impact point; Vector3.INF if none)
- `get_visible_targets() -> Array[Node3D]` (damageables of the other team within 20 km, refreshed at 5 Hz, for HUD boxes)
- `get_incoming_missiles() -> Array[Node3D]` (missiles guiding on this aircraft)
- signals `weapon_changed`, `target_changed(target)`, `lock_changed(state)`, `fired(weapon_id)`

## Gun
- Fire while `controls.fire_gun`; rate from rpm; ammo; muzzle velocity + aircraft velocity; gravity drop; spread (mrad).
- Bullets: one pooled `MultiMeshInstance3D` tracer system for ALL guns (static shared pool, ~600 instances max, glowing stretched
  quads, every Nth round is a visible tracer, other rounds simulated but not drawn). Per physics tick each bullet segment is tested
  with `PhysicsDirectSpaceState3D.intersect_ray` against Hitbox areas (collide_with_areas, mask layers 2|3|4, exclude own hitbox)
  and against `Ground.raycast` only every 3rd tick or when low. Hit -> `Hitbox.apply_damage`, `Vfx.impact`, `Sfx.play_3d`.
- Sound: looped gun sound while firing via `Sfx.attach_loop`, `gun_tail` on release. `Vfx.muzzle_flash`. Camera shake via
  `Events.weapon_fired`. Hit marker: `Sfx.play_2d("hit_marker")` when the player hits; `Sfx.haptic`.
- Aim assist in arcade (Settings.flight_mode == "arcade" and player): bullets get slight magnetism toward the target within 1.5 deg.

## Missiles
- Launch from alternating hardpoint positions (left/right under wings), drop 0.3 s then motor ignites (`Vfx.attach_trail`).
- Kinematics: thrust for boost_s (accel), then coast with drag; speed cap speed_max; gravity; max_g turn limit; lifetime; proximity fuze.
- Guidance: proportional navigation (`a_cmd = N * Vc * LOS_rate`, plus gravity compensation), lead pursuit fallback.
  IR missiles need a lock (target within lock_fov for 1.2 s with growl tone: `lock_tone` loop then `lock_solid`) unless fired
  boresight (they then lock the first target in seeker). Radar missiles: lock from up to range in a 60 deg cone, loft slightly at
  long range. AG missiles: lock on ground targets. Seeker loses target outside seeker_fov.
- Countermeasures: `controls.drop_flares` spawns `Vfx.flare` pairs, adds them to a static flare list; each IR missile tick (10 Hz),
  for each new flare in its seeker cone, roll vs `flare_resist` to switch to the flare. Radar missiles roll vs `chaff_resist`.
- Warnings: emit `Events.missile_launched` and each second `Events.missile_warning(missile, target)`; register on the target's
  WeaponSystem incoming list (if it has one).
- Damage: within proximity -> explode: damage falls off with distance to all damageables within 25 m (air) / blast_radius (ground).
- Visual: procedural missile meshes (body, fins, seeker head) sized by type, white/grey; also shown on the aircraft pylons until fired
  (simple MeshInstance3D children of the aircraft at hardpoint positions: derive positions from wing span/length).

## Bombs, guided bombs, rockets
- Bombs: ballistic with drag, small stabilising rotation (nose follows velocity), impact on `Ground.raycast` -> blast damage +
  `Vfx.explosion(…, "ground")`, water -> "water". Guided bombs (gbu12): steer gently (max_g) toward the locked ground target.
- CCIP: predict impact by integrating the same ballistic model (cheap, 0.1 s steps, at 10 Hz).
- Rockets: salvo pairs, short boost, spread, blast damage, `Vfx.attach_trail(rocket,"rocket")`.

## Test scene
`test_weapons.tscn`: player aircraft (Aircraft.create) at 2000 m, a few `dummy_target.gd` targets (Damageable contract: a flying
drone target moving in circles, static ground tanks as boxes, a ship-sized box at sea level). An automated headless script fires
gun bursts at the drone, launches an AIM-9 and an AIM-120 at drones, drops Mk82 and GBU-12 on ground targets, fires rockets,
drops flares against a missile fired at the player, and prints hits/kills/time-to-impact. Every weapon must kill its intended
target in the automated run. Screenshot of tracers + missile trails with DISPLAY=:0.
