# polish-a result (audio + cockpit polish)

1. [audio] aircraft.gd already adds an EngineAudio child and calls setup(self) (no change needed). The cockpit toggle now goes through `Settings.set_cockpit_view()` from flight_camera.gd, which calls `Sfx.set_cockpit()`, so the cockpit muffle and the radio band-pass switch together.
2. [audio] `radio_cockpit_fx` now defaults to true. `Settings.apply()` sets the Sfx muffle and the Radio band-pass only while in cockpit view, and each one also needs its own setting. `cockpit_muffle` was a dead toggle before and now works. The radio toggle moved to the Audio tab, under Cockpit Acoustics.
3. [models] f16c.json: length 14.307 and span 9.589 match model_info. The gun muzzle [-0.9, 1.28, -4.5] equals the model_info muzzle plus model_offset Y 0.68. cockpit_eye is now [0, 0.808, -2.916] (model_info [0, 0.128, -2.916] plus the 0.68 offset). Not checked by rendering the cockpit view.
4. `python3 tools/check_roster.py`: 21 aircraft validated, OK. `godot --headless --path game --import`: see the result line below.
5. Outside the brief's file list: flight_camera.gd (3 call sites) and level.gd (1 redundant line removed) now route through Settings. settings.gd `_keys()` skips `_`-prefixed runtime vars so they are not saved.

Import result: `godot --headless --path game --import` exited 0 with no script errors or parse warnings in the log. Untracked files the import wrote (asset .jpg copies, .uid files) were left out of the commit.
