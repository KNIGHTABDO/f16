# Common rules for every coding agent (Knight Wings)

You are one of several agents building **Knight Wings**, a combat flight game for iPhone 13 Pro Max (A15) / iPad (A16),
made with **Godot 4.7.2 + GDScript, Mobile renderer**. The Godot project is `game/` in this repo.
Other agents are editing OTHER files at the same time in other git worktrees: only create/edit the files your brief allows.
If you believe a file outside your scope must change, do not change it: describe the needed change in your final report.

1. Read `docs/ARCHITECTURE.md` first, then every file your brief says you depend on. Use only APIs that exist there or in Godot 4.7.
   Godot 4 API reminders: `Node3D.basis`, `Transform3D`, `Basis.looking_at`, `Quaternion`, `@export`, `@onready`,
   typed arrays `Array[Node3D]`, `PackedFloat32Array`, `MultiMeshInstance3D`, `ShaderMaterial.set_shader_parameter`,
   `Input.get_vector`, `Input.get_gyroscope()`, `Input.get_gravity()`, `Input.vibrate_handheld(ms, amplitude)`.
   GDScript gotchas: `:=` cannot infer from Variant (use explicit types), integer division warnings, shadowed variable warnings.
2. Quality bar: this must feel like a polished commercial game. No placeholder TODOs left in your scope, no fake data,
   no "simplified for now". Write complete, well-tuned code with sensible constants grouped at the top of each file.
3. Performance bar: 60 fps on an A15 phone. No allocations in per-frame hot loops, no scene-tree searches per frame,
   pool frequently spawned objects, prefer shaders and MultiMesh.
4. Validate before finishing (Godot is installed as `godot`, version 4.7.2):
   - `cd game && godot --headless --import` once (creates .godot cache),
   - `godot --headless --path game --check-only --script res://<your script>.gd` for each script you wrote,
   - run your test scene headless: `godot --headless --path game --quit-after 600 res://<scene>.tscn 2>&1 | grep -E "ERROR|WARNING" `
     must print nothing caused by your files.
   - If a display is available (`DISPLAY=:0`), you may render a screenshot with a small script that waits a few frames and
     saves `get_viewport().get_texture().get_image()` to a PNG under `/tmp`, then look at it.
5. Commit your work in your worktree with a clear message (git add only your files). Do not push.
6. Final report (max 25 lines): files created/changed, public API you exposed, how you tested, known limitations,
   and any change you need in files outside your scope.

## Speed over testing (user, 2026-10-09)
The machine is very slow. Build features completely, but keep verification to one `godot --headless --path game --import` parse check
at the end (fix any script errors it prints). No screenshots, no long test scenes, no repeated runs.
