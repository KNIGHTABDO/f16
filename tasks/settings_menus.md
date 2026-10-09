# Task: UI theme + menu framework + a COMPLETE settings screen with many options (Knight Wings)

Make the menu system and a very complete, beautiful settings screen. The user explicitly wants "a lot of options and customizations".
Landscape phone UI (iPhone 13 Pro Max, 2778x1284, with notch/safe areas) and iPad. Touch-first, big hit targets (min 88 px at 1280x720 base).

## Read first (open each file, use only APIs that exist)
`docs/ARCHITECTURE.md`, `tasks/_common.md` (general rules: apply them), `game/autoload/settings.gd` (current settings + save/apply),
`game/autoload/game_state.gd`, `game/autoload/radio.gd` (test_connection, fetch_playlists, fetch_genres, signals), `game/autoload/sfx.gd`,
`game/project.godot` (viewport 1280x720, stretch canvas_items/expand), `game/data/maps/*.json` (map names), `game/data/aircraft/*.json`.

## Files you own (create ONLY these; other agents are editing other files right now)
- `game/autoload/settings.gd`: ADD the new settings vars below (keep every existing var name, type and the save()/apply() design;
  apply() must apply everything it can at runtime: max_fps, render scale (`get_viewport().scaling_3d_scale`), MSAA, bus volumes, etc.,
  and emit a new signal `changed(key: String)` from a new `set_value(key, value)` helper so game systems can react live).
- `game/ui/theme/knight_theme.tres` (Godot Theme: dark translucent "military glass" panels, accent cyan #3FD0FF + amber warnings,
  rounded 14 px corners, fonts) and `game/ui/theme/fonts/` (download a free OFL font: e.g. "Rajdhani" or "Exo 2" + "Inter" from
  Google Fonts GitHub `google/fonts` repo raw files; include OFL.txt).
- `game/ui/menu/` : `menu_root.gd` + `menu_root.tscn` (screen stack: push/pop screens with slide+fade transitions, back button,
  safe-area margins via `DisplayServer.get_display_safe_area()`), `main_menu_screen.gd` (title "KNIGHT WINGS", buttons: FREE FLIGHT,
  MISSIONS, HANGAR, SETTINGS, CREDITS; animated background: slowly panning image `game/ui/menu/art/menu_bg.png`), `settings_screen.gd`,
  `pause_menu.gd` (Resume, Settings, Restart, Quit to menu; usable in flight: `get_tree().paused`, process_mode ALWAYS),
  `credits_screen.gd` (reads all CREDITS.md files under res://assets and shows them), `widgets/` (reusable: `setting_slider.gd`,
  `setting_toggle.gd`, `setting_choice.gd` (left/right arrows segmented), `setting_text.gd` (line edit, password mode), `section_header.gd`),
  `art/` (images you generate: see below).
- `game/ui/controls_editor/` : `controls_editor.gd` + `.tscn` (drag on-screen buttons to reposition/resize them, per-button opacity,
  reset to default; saved to Settings `touch_layout` Dictionary {button_name: {pos: [x,y] (0..1 screen fraction), scale, opacity}}).
  Button names: stick, throttle, gun, weapon, cycle_weapon, cycle_target, flares, airbrake, gear, camera, look, pause, radio.
- `game/scenes/menu_test.tscn` (opens menu_root for testing). Do NOT change `game/scenes/main.tscn` or `game/ui/main_menu.gd` (another agent).

## Settings screen: tabs (left vertical tab bar with icons, content scrolls), every option saved immediately and applied live
1. GRAPHICS: preset (Low/Balanced/High/Ultra/Custom; changing any sub-option switches to Custom), render scale 50-100%,
   frame rate 30/60/120 (ProMotion), MSAA off/2x/4x, FXAA, terrain detail, view distance (km), cloud quality, shadows quality,
   shadow distance, vegetation density, city density, effects quality, water quality, bloom/glow, lens flare, motion blur (camera
   speed lines), heat haze, colour grading: brightness, contrast, saturation, colour filter (None/Warm/Cool/Cinematic/Vivid),
   show FPS counter, battery saver (caps 30 fps when on battery... iOS can't detect: just a cap toggle).
2. FLIGHT: flight mode Arcade/Realistic (with a short explanation of each), assists: stall protection, G limiter, auto-rudder,
   auto-level when stick released, auto-throttle, landing assist, blackout/redout effects, damage model (Off/Arcade/Realistic),
   infinite fuel, infinite ammo, invincible (free flight only), units (Metric/Imperial/Aviation: kt/ft).
3. CONTROLS: scheme (Touch stick / Gyro tilt / Hybrid: gyro+touch aim / Mouse-aim style drag), pitch/roll/yaw sensitivity,
   gyro sensitivity, gyro smoothing, gyro dead zone, recalibrate gyro (button: calls a `calibrate_gyro_requested` signal on Settings),
   invert pitch, left-handed layout, stick size, stick dead zone, stick floating vs fixed, auto-fire when lead pip on target, aim assist
   strength, haptics on/off + intensity, "Edit touch layout" (opens controls_editor), gamepad: enabled + remap list (fire, weapon,
   flares, etc. via InputMap actions; show current bindings, press to rebind).
4. CAMERA: default view (Chase/Cockpit/Far chase/Cinematic), FOV 60-100, chase distance, chase height, camera shake intensity,
   look-around with gyro in cockpit, auto-look at target (padlock), smoothing, show own aircraft in cockpit (canopy frame).
5. HUD: HUD colour (Green/Cyan/Amber/White/Red), HUD scale, HUD opacity, show minimap, minimap zoom, show target info, show
   RWR, show speed/alt tapes, show G meter, show waypoint markers, show damage indicators, show kill feed, subtitles for radio voices.
6. AUDIO: master, sound effects, engine, weapons, music, radio chatter/voice warnings, UI sounds, cockpit muffle on/off,
   warning voice (Female "Bitching Betty" / Male / Tones only), mute when app in background.
7. RADIO (Navidrome): enabled, server URL, username, password (masked, show/hide), "Test connection" (calls Radio.test_connection(),
   shows status from `status_changed`), source (Random/Playlist/Genre/Starred), playlist picker (Radio.fetch_playlists -> list),
   genre picker, shuffle, auto-start when flying, radio volume, duck during warnings, cockpit radio effect, show now-playing toast.
8. GAMEPLAY: difficulty (Easy/Normal/Hard/Ace), default time of day (incl. Real time), default weather, AI aircraft count,
   ground target density, friendly AI wingmen on/off, mission time limit on/off, show tutorial hints.
9. ACCOUNT/DATA: pilot callsign (text), reset settings to defaults (confirm dialog), reset progress (confirm dialog), unlock all
   aircraft (personal use toggle), export/import settings (copy JSON to clipboard / paste).
Each option row: label, short grey description, control on the right. Changing graphics shows a live preview? No: just apply.

## Art (Gemini can generate images): create `game/ui/menu/art/menu_bg.png` (2048x1024, dramatic sunset photo-real F-16 over the
Strait of Gibraltar, cinematic) and tab icons (64x64 white line icons on transparent background: graphics, flight, controls, camera,
hud, audio, radio, gameplay, data). If image generation is not possible, use free icons (e.g. Google Material Symbols SVG, Apache 2.0)
and a gradient background, and say so in the report.

## Validation
`godot --headless --path game --import`, then run `godot --headless --path game --quit-after 300 res://scenes/menu_test.tscn` with zero
errors. With `DISPLAY=:0` render screenshots of: main menu, each settings tab, controls editor, pause menu (save PNGs to /tmp/ui_*.png),
LOOK at them and polish spacing/alignment until it looks like a premium mobile game. Commit (no push). Report ≤25 lines.
