# smoke-v2 (Haiku xhigh) — pre-release robustness pass
Goal: make the v1.0 build crash-free. Work in this worktree only; commit often with clear messages.
1. Extend `game/tools/smoke_modes.gd` (headless runner from smoke-v1) to also cover: results screen RETRY and NEXT buttons, pause menu RESTART and QUIT-to-menu, and switching aircraft in hangar then launching. Each must load the expected scene with no script errors.
2. Fix the Sfx error seen in the screenshot run: `sfx.gd` `_apply_volumes` connected to a signal with the wrong argument count. Make the handler accept the signal's args (use `_a = null` defaults) — grep for where it is connected.
3. Fix exit-time leaks (ObjectDB instances leaked / resources still in use at exit) reported when the smoke runner quits: free orphan nodes, stop timers, disconnect autoload signals in `_exit_tree`.
4. Run: `godot --headless --path game --import` then the smoke runner (see smoke-v1 notes in tasks/smoke_v1.md). Grep output for `SCRIPT ERROR|ERROR:|Parse Error` and fix every one you can attribute to game code.
Do NOT touch environment/fog/sky/terrain (vis-world owns that) or HUD layout (vis-hud owns that). Do not wrap godot in flock yourself; the godot wrapper already serializes.
When done, commit and write a 5-line summary to tasks/smoke_v2.result.md.
