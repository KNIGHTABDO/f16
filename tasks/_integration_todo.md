# Integration follow-ups (lead's checklist)
- [audio] aircraft.gd: add EngineAudio child + `setup(self)`; cockpit camera -> `Sfx.set_cockpit(true/false)`
- [audio] Settings: add `radio_cockpit_fx` and have Settings.apply set Cockpit bus volume
- [audio] replace synthesized lock/RWR/warning tones later if better sources found; engine_heli weak
- [models] f16c.json: length/span/cockpit_eye/gun muzzle -> use model_info values (14.31 / 9.59 / [0,0.13,-2.92]?) verify in cockpit view
- [models] f35a GLB 24.6 MB: recompress textures (2048 jpg q85) later
- [terrain] level World node gets Terrain+Ocean at identity (not floating); pass Settings.graphics_preset to apply_quality; camera far >= 600 km
- [terrain] Ground: expose height bytes/texture so Ocean doesn't re-read file; color 8192² memory on iOS check
- [maps] ground.gd header says color.png -> color.jpg (color_file in json)
- [vfx] aircraft: AfterburnerFx per nozzle, Contrail, VaporFx; flares group "flares"; Vfx finds node named World
- [perf] IPA 294 MB: compress height.r16/landcover.u8 (zstd via FileAccess.open_compressed or PNG16), color.jpg 8192 -> KTX/ASTC?
- [terrain polish] real-map colour too dark/desaturated (grade satellite: exposure+saturation, dehaze); near-ground (300 m AGL) looks blurry: stronger detail-texture blend by landcover; grey flat patch NE of Tangier at 1500 m (tile seam?)
- [perf] a headless Godot run (level/import with real maps) peaked at 4.6 GB RSS on Linux (2026-10-09): stream/downsample map data; iPhone has 6 GB total
- [world] level.gd must call WorldBuilder (core/world/world_builder.gd) for sky/clouds/weather/vegetation/cities/airbases/carrier; settings-menus' MenuRoot should replace the temporary main_menu
- perf-ipa (13:40): maps are now packed (zstd height/landcover, color.jpg.bin 4096). Verify both maps load and look right in the integration pass.

## smoke-v1 integration pass (2026-10-09)
Verified headless: all 12 mode runs (gibraltar, free flight on atlas) finish without engine or script errors; the menu flow main menu → MISSIONS → mission card → START → loading → level → Escape pause → RESUME → mission end → results → MENU → main menu passes (`tools/smoke_flow.tscn`); the project main scene boots 600 frames clean.
- [smoke] Exit-time leaks: Godot reports ObjectDB instances, resources and RIDs still alive at quit, and the count grows with each level load (one level: 13 ObjectDB; one time-trial run: 25 ObjectDB + 6 resources; 12-mode pass: 51 ObjectDB + 9 resources + RID leaks). Owner not found. Next: a 2-mode run with `--verbose` to get the class names, then check whether our code keeps references (Vfx lights, FxPool, WorldBuilder, Ground).
- [smoke] dogfight ends "All enemy fighters down" at ~12 s with air kills 0 and no hits (`dogfight.gd` victory when no fighter is alive). Check whether an AI crash or collision should end the fight, and whether it should count as a kill.
- [smoke] Straight flight never hits anything, so the missile and gun hit and damage paths are not exercised. time_trial (one life) ends with "No aircraft left" at ~7 s because the straight-flight aircraft flies into terrain; expected for this check, not a bug.
- [smoke] time_trial ignores the START option: `_plan_time_trial` always starts at the standoff point, so RUNWAY does nothing.
- [flow] Not covered: RETRY and NEXT on the results screen, RESTART/SETTINGS/RADIO in the pause menu, and the loading screen's look (only that the level comes up after START).
- [world] Done: level.gd calls WorldBuilder.build; both maps load in the smoke runs.
