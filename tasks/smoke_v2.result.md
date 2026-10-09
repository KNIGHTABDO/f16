# smoke-v2 result
- Smoke runner: 17 runs (11 modes on gibraltar, free flight on atlas, 5 UI probes), all OK, with no SCRIPT ERROR or Parse Error in the run.
- UI probes pass: results RETRY and NEXT, pause RESTART SORTIE and QUIT TO MENU, and hangar pick, SELECT FOR FLIGHT, then FREE FLIGHT flies the picked aircraft.
- Fixed: sfx.gd `_apply_volumes` takes the Settings.changed key (was "Method expected 0 arguments").
- Exit leaks: 13 RefCounted ObjectDB instances (refcount 0) are still reported at exit and are not attributed; Radio's retry is now a node Timer, and Radio, Sfx and Vfx have `_exit_tree` cleanup, but the count did not change.
- Open: the menu hangar preview logs an engine WARNING (Interpolated Camera3D) on QUIT TO MENU; the full 17-run pass predates the exit-cleanup edits, and only the free-flight pair was rerun after them.
