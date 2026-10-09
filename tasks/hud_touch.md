# Task: HUD + touch controls (the full in-flight UI)

## Read first
`docs/ARCHITECTURE.md`, `game/core/aircraft/aircraft.gd` (public API), `game/core/weapons/weapon_system.gd` + `targeting.gd` (lock, selected weapon,
ammo, targets), `game/core/controls/player_controller.gd` + `control_input.gd`, `game/autoload/{events,settings,game_state,radio}.gd`,
`game/ui/flight_overlay.gd` (temporary overlay you replace), `game/ui/theme/`, `game/data/ui_art.json` + `game/assets/ui/` if present,
`game/core/missions/level.gd` (how the overlay is added).

## Files you own
`game/ui/hud/` (hud.gd + sub-scripts), `game/ui/touch/` (touch controls), `game/ui/radio_panel.gd` (reuse the existing `game/ui/menu/pause_menu.gd`; only wire it); in `level.gd` only
replace the flight_overlay instantiation with the HUD (keep everything else). Delete `flight_overlay.gd` when unused.

## HUD
- Realistic mode: F-16-style green (#3CFF6A, settings colour option) HUD drawn with `_draw()` in a Control projected to the camera: pitch ladder,
  flight path marker, heading tape, speed + altitude boxes, G, Mach, AOA, waterline, gun funnel / lead pip (from Gun ballistics), missile
  seeker circle + lock diamond, target box + range + closure, bomb CCIP pipper (falling bomb impact point via ballistic integration).
- Arcade mode: cleaner overlay: aim reticle, lead indicator, target brackets with distance + health bar, off-screen target arrows,
  missile incoming arrows, simple speed/alt readouts, hit markers + kill feed.
- Both: RWR scope (threats from group `radars` and `Events.missile_launched`, audio via Sfx), warnings (STALL, PULL UP, BINGO FUEL,
  MISSILE, LOW ALT) with voice/tones, minimap (map color texture + units + targets, rotate with heading), weapon panel (selected weapon,
  ammo, flares), damage indicator, score/objective line, radio now-playing ticker. Cockpit camera uses the same HUD sized to the HUD glass.
- iPad and iPhone safe areas; scale from Settings.ui_scale.

## Touch controls (landscape)
Left: virtual stick (or throttle slider, per Settings.control_scheme: gyro tilt / virtual stick / both), throttle slider with afterburner
detent; right: fire gun (hold), missile, bomb/AG, flares, target cycle, camera switch, gear/airbrake small buttons, pause. Multi-touch,
haptic feedback (`Input.vibrate_handheld`), customizable opacity/size from Settings, auto-hide when a gamepad is connected.
Pause menu: resume, restart, settings (open the settings menu scene from settings-menus), radio panel, quit to menu.

## Note (started before weapons merged)
The weapons system is still being written on another branch. Read weapon/ammo/lock state duck-typed (`has_method` / `has_signal` / `get(...)` with defaults) from the player aircraft or a `weapons` child node, so the HUD works with or without it. Show placeholders when absent. Do not create weapons code yourself.
