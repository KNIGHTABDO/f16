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
