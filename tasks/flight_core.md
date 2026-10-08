# Task: flight core (aircraft, flight model, controls, camera, test scene)

Build the heart of the game: an aircraft that flies beautifully, controlled from keyboard/mouse (desktop testing),
gamepad, touch hooks and gyro, with a great chase/cockpit camera. Everything else (weapons, HUD, terrain) plugs into it.

## Read first
`docs/ARCHITECTURE.md`, `game/autoload/*.gd`, `game/core/controls/control_input.gd`, `game/core/combat/hitbox.gd`,
`game/data/aircraft/f16c.json`, `game/data/weapons.json`, `game/project.godot`.

## Files you own (create)
- `game/core/flight/aircraft_data.gd`: `class_name AircraftData extends RefCounted`. `static func load_id(id: String) -> AircraftData`
  (cached), typed fields for every key in f16c.json (keep the raw Dictionary in `raw` too), helpers: `mass_full()`, `stall_speed_ms()`, etc.
- `game/core/flight/flight_model.gd`: `class_name FlightModel extends RefCounted`. Pure physics, no nodes.
- `game/core/controls/instructor.gd`: `class_name Instructor extends RefCounted`: turns a desired LOCAL direction into stick inputs.
- `game/core/aircraft/aircraft.gd`: `class_name Aircraft extends Node3D` (public API exactly as in ARCHITECTURE.md).
- `game/core/aircraft/aircraft_visual.gd`: model loading + placeholder model + afterburner + nav lights.
- `game/core/controls/player_controller.gd`: `class_name PlayerController extends Node`.
- `game/core/camera/flight_camera.gd`: `class_name FlightCamera extends Node3D` (contains a Camera3D).
- `game/scenes/test_flight.tscn` + `game/core/missions/test_flight.gd`: a playable test scene.
Do not edit any other file (not project.godot, not autoloads). Define input actions at runtime with `InputMap` from PlayerController.

## Flight model (one model, two assist levels)
State: position (local), velocity (m/s), basis (orientation), angular velocity (body rad/s), spooled thrust fraction, fuel kg,
gear/airbrake state. Nose = local -Z, up = +Y, right wing = +X.
- Air: ISA-like density `rho = 1.225 * exp(-alt/8500)`, speed of sound `340.3 - 0.0041*alt` (clamp at 295 above 11 km). Mach, IAS (`tas*sqrt(rho/1.225)`).
- AoA alpha = angle between nose and velocity in the body pitch plane (positive nose above flight path), sideslip beta likewise in yaw.
- Lift: `CL = cl0 + cl_alpha*alpha` up to `alpha_stall`, then smooth fall to ~0.55*cl_max by 40 deg and toward 0 at 90 deg.
  Lift force perpendicular to velocity, in the plane spanned by velocity and body up. `L = 0.5*rho*V^2*S*CL`.
- Drag: `CD = cd0 + induced_k*CL^2 + wave(Mach)` (wave drag ramps from `cd_wave_mach` to `cd_wave_max` at Mach 1.1, eases after) `+ gear + airbrake`.
- Side force from sideslip (`side_force` * beta), gravity 9.81.
- Thrust along nose: jets `thrust_dry` (throttle 0..1 maps 0.05..1 of dry), afterburner = `thrust_ab`; spool toward the commanded value
  with `engine_spool_s`; altitude lapse `(rho/1.225)^thrust_altitude_lapse`. Props (`engine == "prop"`): `T = P*eff/max(V,30)` with
  power lapse. No fuel = no thrust.
- Rotation (rate-command, feels like fly-by-wire): stick -> commanded body rates. Pitch rate limited by `pitch_rate_deg` AND by the G
  available (`q_max = (max_g*9.81)/V`); roll rate `roll_rate_deg` scaled by dynamic pressure (sluggish below ~1.3*stall speed, full at
  normal speed); yaw small. Angular velocity approaches the command with `control_response` (1/s). Add natural pitch/yaw stability
  so the nose weathervanes toward the velocity vector when stick is neutral (no endless sideslip).
- **Arcade assists** (Settings.flight_mode == "arcade", and always for AI): G limiter and AoA limiter (never stalls or spins),
  automatic coordinated turns (yaw cancels sideslip), auto throttle never needed, stick release slowly levels the wings,
  minimum-speed protection (nose drops gently instead of stalling), extra lift so turns feel snappy, damage from over-G off.
- **Realistic**: no limiters except fly-by-wire jets keep a soft AoA limit (`max_aoa_deg`) unless the aircraft has `fly_by_wire: false`.
  Stalls drop the nose/a wing, low-speed controls get mushy, over-G beyond max_g*1.15 causes damage, and the pilot gets
  `get_blackout()` (0..1, builds with sustained >7 g, recovers below) and `get_redout()` (negative g).
- Ground: if gear is down and the aircraft touches `Ground.surface_at` with low sink rate (< 6 m/s), small bank/pitch angles and
  not over water, it rolls on wheels (friction, brakes when throttle 0 or airbrake held, nose-wheel steering from yaw/roll input),
  can take off. Any other ground/sea contact = crash (destroyed). `is_on_ground()` true while rolling.
- Integrate with semi-implicit Euler at the physics rate; substep 2x when speed > 400 m/s. Must be stable at 60 Hz for all speeds.
- Tune so the F-16: ~650 kt clean max at sea level, ~Mach 2 high, sustained turn ~9 g at 900 km/h with afterburner,
  roll ~280 deg/s, stall ~230 km/h in realistic, climb several km per minute. A test function in test_flight prints these numbers.

## Instructor (aim assist, used by Arcade mode and all AI)
Input: desired direction (unit vector, local/world space) + current state. Output: pitch/roll/yaw sticks.
Behaviour like War Thunder "mouse aim": bank toward the target direction, pull to bring the nose onto it, small yaw for
fine aim when the target is within ~5 deg, wings level when the target is straight ahead, no oscillation/overshoot (PD with
rate damping), and smooth handling of targets behind the aircraft (roll then pull). Expose gains as constants.

## Aircraft node
- `static func create(id: String, team: int, is_player: bool) -> Aircraft` builds the node (visual, hitbox Area3D on layer 2 with a
  capsule sized from length/wing_span, flight model). Groups and API exactly per ARCHITECTURE.md.
- Each `_physics_process`: read `controls` (if `controls.use_aim` the Instructor produces the sticks), step FlightModel, apply.
  Throttle >= 1.0 or `controls.afterburner` -> afterburner when `has_afterburner`.
- Weapons hook: in `_ready`, if `ResourceLoader.exists("res://core/weapons/weapon_system.gd")`, instantiate it as child "Weapons",
  call `weapons.setup(self, GameState.selected_loadout if is_player else "")`; every tick call `weapons.tick(controls, delta)` if present.
- Damage: `take_damage` per the Damageable contract; at 0 health: `alive=false`, emit signals/Events, the aircraft keeps falling
  (spin, trailing smoke via a small GPUParticles3D), explodes on ground impact (`Events.explosion`) and frees itself 3 s later.
  Expose `spawn_in_air(local_pos: Vector3, heading_deg: float, speed_kmh: float)` and `spawn_on_ground(local_pos, heading_deg)`.
- `get_heading_deg()` 0 = north (-Z), clockwise.

## Visual (aircraft_visual.gd)
- If `ResourceLoader.exists(data.model)`: instance the glb, apply model_scale/rotation/offset.
- Else build a good-looking procedural low-poly jet from code (ArrayMesh/primitives): fuselage, nose cone, canopy (dark glossy),
  delta/trapezoid wings, horizontal + vertical tails, intake, nozzle; grey two-tone StandardMaterial3D. Proportions from length/wing_span.
- Afterburner: additive unshaded cone/flame mesh at the nozzle (shader with flicker and shock diamonds), scale/alpha from throttle;
  heat glow when on afterburner. Navigation lights (red left wingtip, green right, white tail; small emissive spheres + blinking strobe).

## PlayerController
- Each tick writes `aircraft.controls` (call `clear_triggers()` first). Sources merged in priority: gamepad > touch > keyboard/mouse.
- Arcade (`Settings.flight_mode == "arcade"`): `controls.use_aim = true`; aim direction is moved by mouse motion / touch drag /
  gyro / right stick and **lives in the camera frame** (camera follows the aim like War Thunder); keys/left stick still allow
  direct overrides (while overriding, use_aim=false and the aim resets to the nose).
- Realistic: direct sticks with expo curves and `Settings.stick_sensitivity`; gyro (if `Settings.control_scheme == "gyro"`) tilts = stick.
- Keyboard: W/S pitch, A/D roll, Q/E yaw, Shift/Ctrl throttle up/down, Tab afterburner toggle, Space gun, Enter weapon, F cycle weapon,
  T cycle target, X flares, B airbrake, G gear, V camera mode, C hold look-back, Esc pause (emit nothing; just set `pause_requested`).
- Gamepad: left stick pitch/roll, right stick aim (arcade) or yaw (realistic), RT/LT throttle, A gun, B weapon, X flares, Y cycle
  weapon, LB/RB yaw, D-pad up camera, D-pad down gear.
- Touch API for the HUD task (public, documented): `touch_stick: Vector2`, `touch_stick_active: bool`, `add_aim_drag(pixels: Vector2)`,
  `touch_throttle: float` (-1 = unused), `touch_gun: bool`, `press_weapon()`, `press_flares()`, `press_cycle_weapon()`,
  `press_cycle_target()`, `press_gear()`, `press_camera()`, `set_airbrake(on: bool)`, `calibrate_gyro()`.
- Gyro: `Input.get_gyroscope()` (rad/s) integrated into aim yaw/pitch (arcade) with `Settings.gyro_sensitivity`, landscape-aware;
  calibrate neutral with `Input.get_gravity()`.
- Exposes `get_aim_direction() -> Vector3` (world/local) for the HUD aim circle.

## FlightCamera
Modes: `chase` (default; smooth spring follow behind and above, looks along the aim direction in arcade; lags a bit in turns,
FOV widens slightly with speed), `cockpit` (at `cockpit_eye`, head moves a little with G, look-around via aim), `orbit` (free look
around the aircraft by drag), `look_back`. `cycle_mode()`, `set_target(aircraft)`. Camera shake from gun fire, afterburner, G and hits
(respect `Settings.camera_shake`). Near 0.3 m / far 60000 m. Must never clip into terrain (`Ground.surface_at`). Group `floating`.
`get_camera() -> Camera3D`.

## Test scene (scenes/test_flight.tscn + core/missions/test_flight.gd)
World node, DirectionalLight3D sun with shadows, WorldEnvironment (ProceduralSkyMaterial, ACES tonemap, depth fog, glow), a
40x40 km ground plane at height 0 with a grid/checker shader that fades with distance (Ground has no map loaded -> heights are 0),
~50 tall reference pillars, one runway strip at the origin (2.5 km x 45 m). Player F-16 spawned in air at 1500 m, 600 km/h, plus a
second AI-less Aircraft flying straight ahead 800 m in front (for camera/aim testing). A Label at the top-left shows speed, alt, G,
AoA, Mach, throttle, mode, fps. `WorldOrigin.anchor = player`. Key `M` toggles arcade/realistic live, `N` respawns on the runway.
Print a flight-test report at startup in headless mode (run an automated 60 s sim with scripted inputs: level max speed, sustained
turn g, roll rate, stall speed, climb rate) so the numbers can be checked from the terminal.

## Done when
Headless run of test_flight is error-free, the automated flight test prints sane numbers close to the targets above, and a
rendered screenshot shows the jet, afterburner, ground grid and sky.
