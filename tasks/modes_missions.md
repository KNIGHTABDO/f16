# Task: game modes + missions + level flow (make it a real game)

## Read first
`docs/ARCHITECTURE.md`, `docs/PLAN.md` (Wave 3 modes list), `game/core/missions/level.gd`, `game/core/combat/unit_factory.gd`, `game/core/controls/ai_pilot.gd` +
`game/core/missions/flight_group.gd`, `game/core/world/world_builder.gd`, `game/autoload/{game_state,events,settings,ground}.gd`, `game/data/maps/*.json`
(places, airports, roads), `game/data/roster.json`, `game/ui/hud/`, `game/data/ui_art.json`.

## Files you own
`game/core/missions/` (new files: mission.gd base, one script per mode, mission_generator.gd, objectives.gd, spawner.gd), `game/data/modes.json`,
`game/ui/mode_select.gd`, `game/ui/map_select.gd`, `game/ui/results.gd`, `game/ui/loading_screen.gd`; minimal hooks in level.gd + game_state.gd.

## Modes (each works on gibraltar AND atlas, Arcade or Realistic flight)
free_flight (no enemies, time of day/weather picker, spawn airborne or on runway), instant_action (endless waves of enemy fighters,
score), dogfight (1v1 .. 4v4 with wingmen), strike (destroy targets at a real place: Tangier port, Ceuta, airbases; SAM cover),
sead (kill SAM sites), anti_ship (frigates + cargo convoy in the strait), convoy_hunt (trucks/tanks on real roads), base_defense
(bombers + escorts attacking a Moroccan airbase, intercept), carrier_landing (land on the carrier, scored), time_trial (rings through
Atlas valleys and the strait, generated along terrain), target_range (static targets for practice).
Mission generator: difficulty (easy/normal/hard/ace), picks real places from map json, briefing text, objectives with markers for the HUD,
win/lose conditions, takeoff + landing (optional RTB bonus). Results screen: kills, accuracy, time, score, credits earned (GameState).
Loading screen with map art + tips. Restart + next mission.


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
