# Task: visual effects (Vfx autoload + aircraft effects)

Make combat look spectacular (Ace Combat / War Thunder quality) while staying within an A15 phone budget (Mobile renderer, Metal).

## Read first
`docs/ARCHITECTURE.md`, `game/autoload/vfx.gd` (the stub: keep EVERY signature exactly), `game/autoload/{events,world_origin,ground,settings}.gd`.

## Files you own
- `game/autoload/vfx.gd` (replace the stub body; same function names/args/returns)
- `game/core/vfx/` : any helpers (`fx_pool.gd`, `explosion_fx.gd`, `trail_fx.gd`, `flare_fx.gd`, `contrail.gd`, `vapor.gd`,
  `afterburner_fx.gd`, shaders `*.gdshader`, `debris.gd`)
- `game/assets/textures/vfx/` : textures you generate (PIL/numpy noise flipbooks via `uv run --with pillow,numpy`) or download
  (free CC0 only, e.g. Kenney particle pack https://kenney.nl/assets/particle-pack, OpenGameArt CC0 explosion sheets). List sources in
  `game/assets/textures/vfx/CREDITS.md`.
- `game/scenes/test_vfx.tscn` + `game/core/vfx/test_vfx.gd`

## Effects (all with GPUParticles3D or MultiMesh billboards + shaders; soft-blended, lit by sun colour approx)
1. `explosion(pos, size, kind)`: flash light (OmniLight3D, 0.15 s, pooled 4 max), fireball flipbook billboard (additive core +
   alpha smoke), shockwave ring (ground), dirt/sparks/debris chunks with gravity, rising black smoke column (lingers 6-10 s),
   "water": white splash column + spray + foam ring; "aircraft": bigger fireball + burning debris pieces with smoke trails falling.
   Scales with `size` (1 = 500 lb bomb, 0.3 = missile air burst, 3 = ammo dump). Also connect `Events.explosion` to it in `_ready`.
   Camera shake: emit nothing; the camera reads distance itself (just document it).
2. `impact`: dust puff + sparks (ground), small splashes (water), bright sparks + flash (metal). Very cheap: one shared
   GPUParticles3D per kind using `emit_particle()` (request flag EMIT_FLAG_POSITION) so 100 impacts/s cost one draw call.
3. `muzzle_flash`: star-shaped additive quad + small light, 2 frames, random rotation.
4. `attach_trail(parent, kind, offset)`: missile = bright motor flame + long dense white smoke trail that stays in world space
   (GPUParticles3D local_coords=false, or a ribbon trail mesh updated from a ring buffer of positions); rocket = shorter;
   fire = flames + black smoke (burning aircraft/vehicle); smoke_light/heavy = grey/black damage smoke. Trails must survive the
   parent being freed for their fade-out (reparent to World on stop). Handle WorldOrigin.shifted (world-space particles must be
   offset: listen to the signal and move the emitters' existing particles is impossible, so use `local_coords=false` emitters
   parented under a node in group `floating` AND for ribbons shift stored points by delta).
5. `flare(pos, vel, life)`: blinding white-orange ball + light + smoke trail; integrates its own motion (drag + gravity).
   Expose its node in group `flares` with a `heat` float (decays) for missile seekers.
6. `wreck_smoke`: tall drifting smoke column + fire base at destroyed targets (cap 12 concurrent, oldest fades).
7. Aircraft effects (helpers the Aircraft visual will use; expose as static funcs or classes in `game/core/vfx/`):
   `AfterburnerFx` (shock diamonds + flame cone shader on nozzle, intensity 0..1), `Contrail` (wingtip ribbons when G>4 or
   altitude > 8000 m, engine contrails above 8000 m), `VaporFx` (vapor cone around the fuselage near Mach 1, wing vapor
   at high AoA/G), `HeatHaze` is optional (skip if too expensive on Mobile). Document how to attach them (node + `update(speed_mach, g, aoa, alt)`).

## Performance budget
Keep total particles alive < 4000, lights < 6 simultaneous, draw calls for all FX < 40. Pool everything; no `instantiate()` per bullet impact.
Use `Settings.graphics_preset` to scale counts (low = 40%, balanced 70%, high 100%, ultra 130%).

## Test
`test_vfx.tscn`: sky + flat ground + water plane, camera orbiting; script triggers each effect in sequence, one every 1.5 s, plus a
moving missile with trail and a looping flare drop. Render screenshots with DISPLAY=:0 at moments of each effect and LOOK at them
(make a PIL contact sheet). Effects must read clearly from 300 m and up close. No errors/warnings headless.
