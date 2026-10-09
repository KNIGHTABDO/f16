# polish-a (Haiku xhigh) — audio + cockpit polish
Work in this worktree only; commit often. Items from tasks/_integration_todo.md:
1. [audio] aircraft.gd: add an EngineAudio child + `setup(self)` if game/core/audio has an EngineAudio class (check first); cockpit camera toggle -> `Sfx.set_cockpit(true/false)` if that method exists (guard with has_method).
2. [audio] Settings: add `radio_cockpit_fx` (bool, default true) and have Settings.apply set the Cockpit bus volume/effects accordingly; add the toggle to the audio settings screen.
3. [models] f16c.json: verify length/span/cockpit_eye/gun muzzle against the GLB's model_info values; fix cockpit_eye so the camera sits in the canopy (approx [0, 0.13, -2.92] in model space — check model_scale/rotation).
4. Run `python3 tools/check_roster.py` and `godot --headless --path game --import`; fix any errors you caused.
Do NOT touch environment/fog/sky/terrain or HUD layout files (other jobs own them). Do not wrap godot in flock yourself.
When done, commit and write a 5-line summary to tasks/polish_a.result.md.
