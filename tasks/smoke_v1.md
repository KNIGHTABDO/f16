# Task: integration smoke pass v1 (make every mode actually run)

All features are merged: flight, world (WorldBuilder), weapons, combat units, AI pilots (AIPilot), HUD/touch, modes+missions
(game/core/missions/, game/data/modes.json), hangar/progression, perf. They were written in parallel against interfaces, so the
seams are untested. Your job is to make them work together. Read tasks/_integration_todo.md and fix the items in it.

1. Write `game/tools/smoke_modes.gd` (+ a tiny scene if needed): a headless runner that, for each mode in modes.json on the map
   `gibraltar` (and once on `atlas` for free_flight only), sets GameState exactly like the mode/map select screens do, loads the
   level, runs it ~15 s of game time with the player on an AI autopilot or straight flight, forcing one weapon fire per weapon type
   where the mode has enemies, then quits the level and moves on. Print one line per mode: OK / errors seen. Use
   `--fixed-fps 30` and a time scale if useful to keep it short.
2. Run it with: `godot --headless --path game res://tools/smoke_modes.tscn` (the godot wrapper serializes runs and caps memory at
   4.2 GB; if a map OOMs, use the low quality preset in the smoke runner).
3. Fix every SCRIPT ERROR / ERROR / missing method / null access / wrong API call you see, at the source, in whatever file it is.
   Prefer small seam fixes over rewrites. Re-run until every mode prints OK (max ~6 runs; if something still fails, write it in
   tasks/_integration_todo.md and move on).
4. Also boot the menu once (`godot --headless --path game --quit-after 600`) and check flow: main menu -> mode select -> map select
   -> loading -> level -> pause -> results -> back to menu, through code paths (call the same functions the buttons call).
Commit after each batch of fixes with a clear message. Do not add features. Do not restyle anything.
