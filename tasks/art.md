# Task: game art pack (generated images: menus, icons, loading screens, HUD symbols, liveries)

You have an image generation tool. USE IT (with and without reference images) to make every image below. Look at each result,
regenerate anything that looks bad (wrong aircraft shape, garbled text, artifacts). No text inside images unless stated (we draw text in Godot).
Style: cinematic, photoreal, golden-hour / dramatic sky, Moroccan landscapes (Strait of Gibraltar, Tangier coast, High Atlas snow peaks,
Sahara dunes), modern fighter jets. Consistent colour grade: deep navy + warm amber, the UI accent is cyan #3FD0FF.

## Files you own (create only these)
`game/assets/ui/` (all images below), `game/assets/ui/CREDITS.md` (what tool/prompt made each image), `game/data/ui_art.json`
(manifest: key -> res:// path, used by menus later), `tools/resize_art.py` (PIL: resize/compress outputs to the sizes below, JPG q85 for
photos, PNG for transparency).

## Images
- `menu/bg_main.jpg` 2532x1170: F-16 banking over the Strait of Gibraltar at sunset, Rock of Gibraltar + Moroccan coast visible.
- `menu/bg_hangar.jpg` 2532x1170: dim modern hangar interior, empty centre stage (a 3D jet is drawn on top), dramatic rim lights.
- `menu/bg_settings.jpg`, `menu/bg_results.jpg` 2532x1170: blurred cockpit at dusk / jets taxiing at an airbase at night.
- `loading/load_gibraltar.jpg`, `loading/load_atlas.jpg`, `loading/load_sahara.jpg`, `loading/load_generic_1..3.jpg` 2532x1170.
- `maps/thumb_gibraltar.jpg`, `maps/thumb_atlas.jpg`, `maps/thumb_test.jpg` 768x432 (map select cards).
- `aircraft/<id>.png` 1024x512 transparent-background side/3-quarter profile renders for every aircraft id in
  `game/data/model_info.json` (and game/data/roster.json if present): use a reference image of the real aircraft when you can find one
  in the repo (game/assets/models/aircraft/<id>/ textures) or describe its real shape precisely. Background must be removed (transparent PNG).
- `modes/` 768x432 cards: free_flight, instant_action, dogfight, strike, sead, anti_ship, convoy_hunt, base_defense, carrier_landing,
  time_trial, target_range.
- `icons/` 256x256 transparent white glyph icons (flat, clean): settings, radio, hangar, map, play, pause, missile, bomb, gun, flare,
  rocket, radar, fuel, gear, camera, trophy, credits, lock, back.
- `hud/` 128x128 transparent: rwr_threat_air, rwr_threat_sam, target_box, lock_diamond, missile_warning (simple vector-like glyphs, green #3CFF6A).
- `liveries/<id>_<name>.jpg`: for f16c, ef2000, f35a, mirage2000, rafale: 2 extra paint schemes each (e.g. Royal Moroccan Air Force
  grey with the Moroccan roundel, desert camo, aggressor splinter) as tileable 1024x1024 camo/paint pattern textures that a shader can
  overlay (not UV-mapped skins).
- App icon: `icon/app_icon_1024.png` (jet silhouette + "KW" monogram allowed, bold, readable at 60 px); copy it over `game/assets/icon_1024.png`.

Finish by writing the manifest json and CREDITS.md. Run one `godot --headless --path game --import` so the images import.
