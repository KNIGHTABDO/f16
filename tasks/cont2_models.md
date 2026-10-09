# CONTINUATION: models2, last four aircraft

Most of the roster is converted and merged (see game/assets/models/aircraft/, game/data/model_info.json, tools/convert_models.py, tools/models.json).
Convert the remaining ones the same way (same pipeline, same model_info.json keys, same texture compression): b17, fa18c, rafale, ah64.
Then make sure every GLB is < 9 MB (recompress textures 2048 jpg q85) and update game/assets/models/CREDITS.md.
Do not touch other files. Original brief below for the details.

# Task: convert the rest of the aircraft roster (continuation of tasks/models.md)

Read `tasks/models.md` (original brief: rules, orientation, naming, verification) and then the existing pipeline that already works:
`tools/convert_models.py`, `tools/fetch_models.sh`, `tools/models.json` (per-model recipes), `game/data/model_info.json`,
`game/assets/models/CREDITS.md`. f16c, ef2000, f35a are DONE (do not redo them). Add recipes to models.json for each new aircraft
and run the same pipeline.

Order (do as many as possible, all of them ideally; commit after EACH aircraft so partial progress is kept):
1. mig29 (FGAddon), su27 (`yanes19/SU-27SK`), f15c (`Zaretto/F-15`), mig21bis (`l0k1/MiG-21bis`), a10c (`l0k1/A-10`),
2. f22a, mirage2000, f14b, su57, ja37 (look in subfolders for the .ac; the -set.xml model path tells you), p51d,
3. FGAddon: spitfire, bf109, b17, fa18c, rafale, ah64 (or another attack helicopter; for helicopters name the rotor nodes
   `rotor_main` and `rotor_tail` with origin on the hub and record their spin axis in model_info).
FGAddon source: SourceForge SVN `https://svn.code.sf.net/p/flightgear/fgaddon/trunk/Aircraft/<Name>` (use `svn export` if svn exists,
else `https://sourceforge.net/p/flightgear/fgaddon/HEAD/tree/trunk/Aircraft/<Name>/` "Download Snapshot" zip URL, else find a GitHub mirror
with `gh search repos`). If a model is unobtainable or broken after reasonable effort, skip it and note why.

Also: re-encode the f35a textures to bring its GLB under 15 MB (2048 max, JPG q85 for opaque) and keep the look.
Size budget: each GLB 3-15 MB, <= 60k triangles. Run Blender one job at a time (7 GB RAM shared with other agents).
Verify every model as in the original brief and append rows to a contact sheet `/tmp/models_contact2.png` (look at it).
Report: table id | triangles | MB | surfaces OK? | notes, plus anything skipped.
