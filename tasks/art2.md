# Task: art pack pass 2 (fix weak images)

The first art pass (game/assets/ui/, manifest game/data/ui_art.json, tools/resize_art.py) is merged. Backgrounds/loading/app icon are great.
Fix these with your IMAGE GENERATION tool (not Blender/Godot renders), same cinematic style, then update the manifest + CREDITS.md:
1. `game/assets/ui/modes/*.jpg`: every one of the 11 mode cards must be a UNIQUE new image that shows that mode (free_flight: lone jet
   cruising over Atlas peaks; instant_action: jets in a furball with flares; dogfight: two jets turning, vapour; strike: bombs hitting a
   coastal target; sead: SAM site exploding at night; anti_ship: missile skimming toward a frigate in the strait; convoy_hunt: jet strafing
   a desert truck convoy; base_defense: interceptors scrambling from a Moroccan airbase; carrier_landing: jet hooking a carrier wire at
   sunset; time_trial: jet through a narrow Atlas canyon with glowing rings; target_range: practice targets on a desert range). Do not reuse
   loading/menu images.
2. `game/assets/ui/aircraft/<id>.png`: replace the flat grey renders with generated photoreal 3/4-side profile images of the REAL aircraft
   (correct shape, plausible real livery), transparent background (remove it with PIL/rembg-free method: generate on pure white or
   pure green background and key it out with tools/resize_art.py), 1024x512. Do it for EVERY id in game/data/model_info.json plus every
   id in game/data/roster.json if that file exists (if not, also: f22a, f15c, su27, mig29, mig21bis, mirage2000, rafale, f14b, su57,
   fa18c, a10c, ja37, p51d, spitfire, bf109, b17, ah64). Use a reference image of the real aircraft when you have one.
3. Icons: the bomb icon looks like a fish: redo bomb, plus missile and rocket so they read clearly at 48 px.
Files you own: game/assets/ui/**, game/data/ui_art.json, tools/resize_art.py. Delete tools/render_aircraft.py if unused.
