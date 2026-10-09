# Task: AI pilots (enemy and wingmen) that are fun to fight

## Read first
`docs/ARCHITECTURE.md`, `game/core/aircraft/aircraft.gd`, `game/core/controls/{control_input,instructor,player_controller}.gd`
(the Instructor turns an aim direction into stick inputs: AI should mostly command `use_aim` + `aim_direction` + throttle, like the
player's arcade mode, so it flies the same physics), `game/core/weapons/weapon_system.gd` (targets, lock, lead point, incoming missiles),
`game/autoload/{ground,events,game_state}.gd`.

## Files you own
`game/core/controls/ai_pilot.gd` (class_name AIPilot extends Node: child of an Aircraft, writes `aircraft.controls` every physics tick
BEFORE the aircraft integrates: check how PlayerController does it and do the same), `game/core/controls/ai_tactics.gd` (helpers),
`game/core/missions/flight_group.gd` (FlightGroup: leader + wingmen formation, shared target picking), `game/scenes/test_ai.tscn` +
`game/core/missions/test_ai.gd`.

## AIPilot API
`setup(aircraft: Aircraft, skill: float (0..1), role: String ("fighter","attacker","bomber","wingman","helicopter"))`,
`set_patrol(points: Array[Vector3], altitude_m)`, `set_target(node)`, `set_escort(node)` (follow/defend), `set_strike(target_nodes)`,
`order(cmd: String)` for wingmen: "attack_my_target","cover_me","engage_free","rejoin". State readable via `get_state() -> String`.

## Behaviour (state machine at 10 Hz decisions, 60 Hz control)
- States: takeoff (if on ground), patrol, intercept, dogfight (BFM: lead/lag/pure pursuit, energy management: avoid stalling, use
  vertical, scissors/defensive breaks), gun attack (fire only when lead pip within skill-scaled tolerance and range < 900 m), missile
  attack (lock then fire within weapon envelope, never waste all missiles), evade (incoming missile: beam/notch, drop flares at
  ~2.5 km, break turn at 1 km, dive for ground clutter), ground attack (dive bombing / rocket runs / standoff missiles, pull out
  safely), RTB/bingo, formation (wingman: fingertip/echelon slots relative to leader with PID on position+velocity).
- Terrain avoidance ALWAYS overrides: look ahead along velocity (3-6 s) with `Ground.raycast`; pull up / climb over ridges.
- Skill scales: reaction time (0.8 s -> 0.15 s), aim tolerance, G tolerance used (6 -> 9), flare timing, missile usage.
  `GameState.difficulty` (easy/normal/hard/ace) maps to skill.
- Must be beatable but challenging: an ace AI with equal aircraft should win ~50% vs a good player.
- Cheap: no allocations per tick; 12 AI aircraft must cost < 1.5 ms per physics tick in total on desktop.

## Test
`test_ai.tscn` (flat or test map): 2v2 dogfight AI vs AI (F-16 vs MiG-29 or whatever aircraft data exists), plus a strike AI that
bombs a static ground target, plus a wingman formation following a scripted leader. Run headless 180 s with `--fixed-fps 60` and print
a timeline (states, shots, hits, kills, crashes into terrain must be 0, stalls), and per-tick AI cost. Tune until fights look
believable (turning fights, missiles defeated sometimes, kills happen within 1-3 min). DISPLAY=:0 screenshots of a merge.


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
