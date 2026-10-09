# Task: hangar + progression (choose your jet, loadout, livery, unlocks)

## Read first
`game/data/roster.json`, `game/data/aircraft/*.json` (loadouts), `game/data/weapons.json`, `game/data/model_info.json`, `game/core/aircraft/aircraft_visual.gd`
(how GLBs load), `game/autoload/{game_state,settings}.gd`, `game/ui/theme/`, `game/ui/menu/`, `game/data/ui_art.json` + `game/assets/ui/` (bg_hangar, aircraft
profiles, liveries).

## Files you own
`game/ui/hangar/` (hangar.gd, turntable, loadout editor, livery picker, stats panel), `game/core/progression.gd` (+ register as autoload
`Progression` in project.godot), `game/data/progression.json`, hooks in main menu to open the hangar.

## Do
3D turntable of the selected GLB on the hangar background with lights, slow rotation + drag to rotate + pinch zoom; aircraft list by
category (fighters, attack, bombers, helicopters, WW2) with locked/unlocked states and prices; stats bars (speed, climb, turn, payload)
from the json; loadout editor per pylon (only legal weapons per aircraft json), presets (A/A, A/G, SEAD, anti-ship); livery picker
(default + overlays from game/assets/ui/liveries via a shader param); credits + XP + rank from missions (Progression saves to user://).
Start unlocked: F-16C, Mirage 2000, P-51D. Everything else priced so ~20 missions unlock most jets. "Unlock all" toggle in Settings for testing.
