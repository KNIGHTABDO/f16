# Integration follow-ups (lead's checklist)
- [audio] aircraft.gd: add EngineAudio child + `setup(self)`; cockpit camera -> `Sfx.set_cockpit(true/false)`
- [audio] Settings: add `radio_cockpit_fx` and have Settings.apply set Cockpit bus volume
- [audio] replace synthesized lock/RWR/warning tones later if better sources found; engine_heli weak
- [models] f16c.json: length/span/cockpit_eye/gun muzzle -> use model_info values (14.31 / 9.59 / [0,0.13,-2.92]?) verify in cockpit view
- [models] f35a GLB 24.6 MB: recompress textures (2048 jpg q85) later
