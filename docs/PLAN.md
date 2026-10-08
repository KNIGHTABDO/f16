# Knight Wings: master plan

Goal (from the user): ONE finished, polished game to play daily, not an MVP. Best possible graphics and sound, real aircraft,
huge real Morocco maps, targets, Arcade + Realistic flight, Navidrome radio. Public repo while building. Personal use only.
Work model: Claude = architect/reviewer/integrator; coding by Haiku 5.5 (xhigh) agents in worktrees, + Gemini (agy) when its quota resets.

## Wave 1 (running)
- [ ] flight_core: FlightModel, Aircraft, Instructor, PlayerController, FlightCamera, test_flight scene
- [ ] map_pipeline: tools/build_map.py -> gibraltar + atlas maps (DEM, WorldCover, Sentinel-2 colour, airports, places, roads)
- [ ] terrain: GPU clipmap terrain + ocean + test map
- [ ] audio: Sfx, EngineAudio, sound library, Navidrome Radio
- [ ] models: FlightGear aircraft + ground units -> GLB, model_info.json
- [x] iOS CI (Godot export on macos-26 runner -> unsigned IPA artifact; tags -> Release + SideStore source)

## Wave 2 (after integration of wave 1)
- weapons: WeaponSystem, guns (pooled tracers, ray hits), IR/radar/AG missiles (PN guidance, flares/chaff), bombs, GBU, rockets, lock/target cycling
- vfx: explosions, smoke, fire, contrails, vapor cones, wingtip vortices, heat haze, muzzle flash, impacts, water splashes, wreck debris
- combat units: GroundUnit (vehicles on roads/convoys), SAM site (search/track/launch), AAA, ships, structures, airbase objects
- ai: AIPilot (patrol/intercept/dogfight/defend/evade/RTB, terrain avoidance, difficulty levels), wingmen
- world dressing: sky (time of day, sun/moon/stars), volumetric-looking clouds, weather presets, vegetation (MultiMesh trees),
  cities (procedural buildings in urban land cover), airports (runway textures/lights, hangars), aircraft carrier
- aircraft data: per-aircraft JSON flight specs + loadouts for the whole roster (matching model_info)

## Wave 3
- HUD (F-16 style green HUD + arcade overlay: aim circle, lead pip, target boxes, RWR, minimap, warnings), touch controls layout
- menus: main menu, hangar (3D turntable, loadout, skins), map + mode select, settings (graphics/controls/audio/radio), pause, results
- missions/modes: free flight, target range, strike, dogfight waves, base defense, convoy hunt, SEAD, anti-ship, carrier landing,
  time trial rings, instant action; mission generator per map; progression (credits/unlocks), stats
- perf: presets, perf HUD, LOD, thermal-aware dynamic resolution, shader baking

## Wave 4
- full playtest pass (headless sims + screenshots), balance, polish, iPad layout, release tag v1.0
