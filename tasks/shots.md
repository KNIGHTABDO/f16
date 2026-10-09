# Task: screenshot tour script (rendered, for marketing/review shots)

Write `game/tools/screenshot_tour.gd` + `game/tools/screenshot_tour.tscn`. Reuse the approach of game/tools/smoke_modes.gd for
setting GameState and loading levels. It runs WITH rendering (not headless) and saves PNGs via
`get_viewport().get_texture().get_image().save_png()` to `user://..`? No: save to the absolute path given by the command line
user arg `--out=<dir>` (OS.get_cmdline_user_args()), default `res://../screenshots/v1/`.
Window 1920x1080, quality preset high, wait for shader warmup and ~2-4 s of settled frames before each shot.
Shots (name files NN_description.png), ~25 total:
- main menu, mode select, map select, hangar (3 different aircraft incl. b2 and f16c), loading screen.
- free_flight gibraltar: chase cam over the strait at golden hour, cockpit view, low pass over Gibraltar rock, carrier nearby.
- free_flight atlas: valley flight chase cam, high altitude with clouds.
- dogfight: chase view with an enemy fighter in frame and HUD target box, a missile launch (fire one and capture 0.5 s later),
  a flare drop, an explosion.
- strike / sead: SAM site launching, bombs falling, ground explosion; anti_ship: frigate in frame.
- carrier_landing: approach view; time_trial: rings in a valley; night + storm weather shot.
Position the camera/aircraft directly (teleport the player, set heading) instead of flying there. Freeze AI damage if needed so
scenes stay alive. Quit when done. Print each saved file path.
You cannot see the screen: only verify the script parses with one `godot --headless --path game --import` and a headless run
that reaches the end (image saving is skipped/guarded when DisplayServer is headless). Commit. Touch nothing else.
