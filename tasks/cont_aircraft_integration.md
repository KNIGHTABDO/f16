# CONTINUATION: finish aircraft_integration

A previous agent started this task and was interrupted. Its work is ALREADY COMMITTED on this branch (last commit 'WIP: overnight progress'; see `git log main..HEAD` and `git diff main --stat`). Review that work first, keep what is good, fix what is broken, and complete everything the original brief below asks for. Verify headless with Godot (`godot --headless --path game --import` first, then run the relevant test scene) before finishing.

# Task: aircraft polish + first playable level (integrate flight, models, audio, vfx, terrain)

Wave 1 is merged: flight model/aircraft/camera/controls, GLB models + `data/model_info.json`, Sfx/EngineAudio/Radio, Vfx helpers,
Terrain/Ocean, real maps (gibraltar, atlas). Wire them together so the game is actually playable on the phone: from the main menu's
FLY button you spawn in an F-16 over the Strait of Gibraltar and fly with touch/gyro (or keyboard on desktop).

## Read first
`docs/ARCHITECTURE.md`, `tasks/_integration_todo.md` (the checklist you are resolving), `game/core/aircraft/{aircraft,aircraft_visual,engine_audio}.gd`,
`game/core/camera/flight_camera.gd`, `game/core/controls/player_controller.gd`, `game/core/vfx/{afterburner_fx,contrail,vapor_fx}.gd` (+ `autoload/vfx.gd`),
`game/core/world/{terrain,ocean}.gd`, `game/core/world/test_terrain.gd` (how it sets up terrain/ocean/sky), `game/autoload/*.gd`,
`game/data/model_info.json`, `game/data/aircraft/f16c.json`, `game/data/maps/gibraltar.json`, `game/core/missions/level.gd`, `game/scenes/level.tscn`, `game/ui/main_menu.gd`.

## Files you own
`game/core/aircraft/aircraft_visual.gd`, `game/core/aircraft/aircraft.gd` (only additions for audio/vfx hooks; keep its public API),
`game/core/camera/flight_camera.gd` (cockpit Sfx toggle, far plane, shake from Events.weapon_fired/explosions by distance),
`game/core/missions/level.gd`, `game/scenes/level.tscn`, `game/ui/main_menu.gd` + `game/scenes/main.tscn` (keep simple: title, FLY,
map toggle gibraltar/atlas, Arcade/Realistic toggle; the real menus come later), `game/ui/flight_overlay.gd` (TEMPORARY minimal
on-screen touch controls + speed/alt/G text so the build is testable on the phone; a full HUD comes later: keep it in this one file),
`game/autoload/ground.gd` (comment fix + expose `get_height_bytes()`), `game/autoload/settings.gd` (add `radio_cockpit_fx`, Cockpit bus in apply),
`game/data/aircraft/f16c.json` (fix size/cockpit_eye/muzzle from model_info; the gun muzzle must be at the real M61 port on the left
wing root), `game/core/world/ocean.gd` (use Ground bytes if available).

## Work
1. AircraftVisual with GLB models: read `model_info.json[aircraft_id]`; animate control surfaces by node name around their hinge axis
   (ailerons from roll, elevators/stabilators from pitch (+ roll for tailerons when no ailerons; elevons combine), rudder from yaw,
   flaps with gear/low speed, speedbrake from airbrake, canopy closed), gear: retract/extend animation (rotate gear parts up into the
   body or scale-hide smoothly over 3 s if no hinge data) + `is_gear_down()`; afterburner: `AfterburnerFx` on each `nozzles` entry
   (intensity from throttle/afterburner), nozzle heat glow; `Contrail` on `wingtips`, `VaporFx`; nav/strobe lights at wingtips/tail.
   Check signs by rendering: full right roll stick -> right aileron trailing edge UP. Procedural fallback remains for models without GLB.
2. EngineAudio child + `Sfx.set_cockpit` when the camera is in cockpit mode; wind/stall/gear sounds if the Sfx library has them.
3. Level: build World node (name "World"), Terrain + Ocean (identity, not floating), sky/environment (simple good-looking ProceduralSky +
   fog + sun; WorldBuilder from another agent will replace it later: isolate this in `_build_environment()`), spawn the player with
   `GameState.selected_aircraft` at the map's `spawn` (in air), FlightCamera following, PlayerController, flight_overlay; crash -> explosion
   + respawn after 3 s; pause button -> back to menu. `Settings.graphics_preset` -> `apply_quality`. Camera far >= 600 km.
   Start `Radio` if `Settings.radio_enabled`.
4. Validate: headless run of level.tscn 900 frames with no errors; DISPLAY=:0 screenshots: chase view over the strait, cockpit view,
   close-up of F-16 with afterburner and gear down on the ground at GMTT (Tangier) runway start; LOOK at them (PIL contact sheet) and fix.
   Then `godot --headless --path game --export-release iOS /tmp/x.xcodeproj`-style export is NOT possible here: just make sure
   `godot --headless --path game --import` has no errors.

## Merge note
Another agent (Gemini) is adding settings keys and game/ui/menu/ in parallel. Keep your settings.gd additions minimal and in one clearly
commented block. Delete any game/tools_tmp/ before committing.
