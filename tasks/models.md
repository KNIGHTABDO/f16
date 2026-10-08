# Task: real aircraft + ground-unit 3D models (FlightGear open-source models -> glTF for Godot)

Personal-use game. Use the excellent open-source FlightGear aircraft (GPL) as our 3D models.

## Read first
`docs/ARCHITECTURE.md` (axes: nose = -Z, up = +Y, right wing = +X, meters), `game/data/aircraft/f16c.json` (model keys).

## Files you own
- `tools/convert_models.py` (Blender headless script) + `tools/fetch_models.sh` + `tools/models.json` (source list)
- outputs: `game/assets/models/aircraft/<id>/<id>.glb` (+ nothing else in that folder), `game/assets/models/ground/<id>/<id>.glb`
- `game/data/model_info.json`: per model id: scale fixes, `cockpit_eye`, `nozzles` (array of [x,y,z] + radius),
  `muzzles`, `wingtips` [[l],[r]], `gear_nodes` (node names), `control_surfaces` (see below), `triangles`, `source`, `license`.
- `game/assets/models/CREDITS.md`.
Work only in these paths. Cache raw downloads in `tools/cache/models/` (gitignored).

## Sources (GitHub, download only the model folders: use `git clone --depth 1 --filter=blob:none --sparse` + `git sparse-checkout set Models`,
or the GitHub API/codeload for small repos; some repos are 1-2 GB, never clone them fully)
- F-16C: `NikolaiVChr/f16` | MiG-21bis: `l0k1/MiG-21bis` | JA-37 Viggen: `NikolaiVChr/flightgear-saab-ja-37-viggen`
- F-15C/E: `Zaretto/F-15` | F-14B: `Zaretto/f-14b` | Mirage 2000-5: `5H1N0B11/flightgear-mirage2000` | Su-27SK: `yanes19/SU-27SK`
- A-10: `l0k1/A-10` | P-51D: `Zaretto/p51d` | EF-2000 Typhoon: `IAHM-COL/EF-Typhoon` | F-22A: `MonotoneDevelopment/F-22` or `SamJD261/F-22-Raptor`
- F-35A: `PaoloAmoroso/F-35A` | Su-57: `ShFsn/Su-57`
- FGAddon SVN (sourceforge, `svn export` if svn exists, else the SourceForge "Download Snapshot" tarball or HTTP tree) for:
  MiG-29, Spitfire (spitfireIX), Bf-109, B-17, AH-64 or Ka-50 or UH-1 (any attack helicopter), F/A-18 (if found), Rafale (if found).
- Ground units (targets): search GitHub/FGAddon/FGData for FlightGear military AI models: tanks (T-72/T-90/M1), trucks, BMP/APC,
  SAM launchers (SA-2/S-75, SA-6, Buk, S-300), AAA (ZSU-23-4 Shilka), radar trailer, frigate/destroyer ship, patrol boat,
  aircraft carrier (USS Nimitz/Vinson in FGData `AI/Aircraft`/`Models/Geometry` or `OPRF` assets), hangar/hardened shelter,
  fuel tanks, control tower, bunker. Write what you found and what is missing in your report.
If a repo is gone, search GitHub (`gh search repos`) for another FlightGear model of the same aircraft.

## Conversion (Blender 4.0.2 is installed: `blender -b -P tools/convert_models.py -- <args>`)
- FlightGear models are AC3D `.ac` files (+ textures, + XML that references them and animates objects). Install an AC3D importer
  as a Blender extension/add-on under a temp `BLENDER_USER_SCRIPTS` (e.g. `majic79/Blender-AC3D` supports Blender 2.8+; if it fails
  on 4.0, write a minimal `.ac` parser yourself: the format is plain text and simple).
- Find the main exterior `.ac` from the aircraft's `-set.xml` -> `<model><path>` -> model XML -> `<path>` (plus sub-models that matter
  for the exterior, e.g. separate pylons are NOT needed, gear may be separate).
- Keep the exterior only: delete cockpit interior/instruments/pilot internals, keep canopy (glass material: transparent), keep
  landing gear, delete weapons/pylons/tanks (our game adds its own), delete invisible/collision/light-cone/shadow objects.
- Target <= 60k triangles for fighters (decimate the largest meshes if needed, keep silhouettes), <= 25k for ground units.
- Textures: keep the main livery; resize to max 2048 (fighters) / 1024 (ground), JPG for opaque, PNG for alpha. Embed in GLB.
  Materials: Principled BSDF, metallic 0.2-0.4 on airframe, roughness ~0.5, glass with alpha.
- Orientation: FlightGear uses X = aft, Y = right, Z = up (meters). Convert to glTF so Godot sees nose -Z, up +Y, right +X,
  origin at the visual centre of the airframe (or the FG CG reference), real-world scale (check length/wingspan vs real values).
- Keep control surfaces as separate named nodes with origin on the hinge line when the FG XML animations make that possible
  (rotate animations give the axis points): names `aileron_l`, `aileron_r`, `elevator_l`, `elevator_r` (or `stabilator_l/r`),
  `rudder` (or `rudder_l/r`), `flap_l/r`, `canopy`, and all gear parts under one node `gear`. Record each surface's hinge axis
  (unit vector in model space) and max deflection degrees in model_info.json. If not possible for a model, merge them and note it.
- Export with `bpy.ops.export_scene.gltf(export_format='GLB', export_yup=True, export_apply=True)`.

## Verify
For every model: import into Godot headless (`godot --headless --path game --import`), no errors; render a turntable screenshot
from 3 angles with `DISPLAY=:0` in a tiny scratch scene (do not commit it), look at it: correct orientation, textures present,
no missing parts/inside-out faces, canopy transparent. Put a contact sheet (PIL) at `/tmp/models_contact.png` and look at it.
Run Blender jobs one at a time (machine has 7 GB RAM). Commit GLBs (each must be < 50 MB; aim for 5-15 MB).
