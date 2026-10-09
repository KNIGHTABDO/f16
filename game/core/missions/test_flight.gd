extends Node3D
## Flight test world (scenes/test_flight.tscn): sun, sky and fog, a 40 km ground with a distance-fading grid and
## checker, reference pillars, a 2.5 km runway, the player F-16 (PlayerController + FlightCamera + HUD) and a
## straight-flying target 800 m ahead. M toggles arcade/realistic, N respawns on the runway.
## In headless runs (or with `-- --flight-test`) it first prints a flight-test report. The report runs the flight
## model alone in fixed 1/60 s steps, so the numbers do not depend on the frame rate.

const TAG := "[flight-test] "
const AIRCRAFT_ID := "f16c"
const SIM_RATE := 60
const TEST_DT := 1.0 / 60.0
const SPAWN_ALT := 1500.0
const SPAWN_KMH := 600.0
const TARGET_AHEAD := 800.0
const GROUND_SIZE := 40000.0
const RUNWAY_LEN := 2500.0
const RUNWAY_WIDTH := 45.0
const RUNWAY_START_INSET := 100.0  ## respawn this far from the south threshold, facing north
const PILLAR_COUNT := 50
const PILLAR_HEIGHT := 120.0
const PILLAR_RADIUS := 14.0
const PILLAR_SPREAD := 5000.0
const PILLAR_CLEAR := 300.0  ## no pillars this close to the origin
const PILLAR_SEED := 1337
const HUD_HINT := "W/S pitch  A/D roll  Q/E yaw  Shift/Ctrl throttle  Tab afterburner  Space gun  V camera  M arcade/realistic  N respawn"

const TEST_TOP_ALT := 100.0  ## "sea level" for the top-speed runs
const TEST_HIGH_ALT := 15000.0
const TEST_STALL_ALT := 300.0
const TEST_ROLL_ALT := 1500.0
const TEST_TURN_ALT := 300.0
const TEST_CLIMB_ALT := 1000.0
const TEST_CLIMB_GAMMA_DEG := 45.0
const PATH_KP := 2.5  ## flight-path PD: rad/s of pitch rate per rad of error
const PATH_KD := 0.5  ## rad/s per rad/s of pitch rate
const ALT_BW := 0.2  ## 1/s altitude loop bandwidth (flight-path angle = ALT_BW * dh / speed)
const ALT_GAMMA_MAX := 0.2
const STALL_WARMUP_S := 10.0  ## the stall run starts untrimmed, so ignore sink until the pitch PD has settled
const BANK_KP := 2.5
const BANK_KD := 0.6
const BETA_KP := 6.0  ## 1/s: yaw-rate command per rad of sideslip (coordinated turn)
const PATH_KI := 0.5  ## flight-path integral: a banked turn needs a steady pitch rate, which only a steady gamma error can supply
const GAMMA_INT_MAX := 0.3
const GDOT_KD := 2.0  ## damping on the flight-path rate (the body pitch rate has a steady term in a banked turn)

const TARGET_TOP_KT := 650.0
const TARGET_ROLL_DEG_S := 280.0
const TARGET_STALL_KMH := 230.0
const TARGET_TURN_G := 9.0
const TARGET_HIGH_MACH := 2.0

const GROUND_SHADER := """
shader_type spatial;
varying vec3 world_pos;
uniform vec3 grass_a : source_color = vec3(0.24, 0.31, 0.19);
uniform vec3 grass_b : source_color = vec3(0.2, 0.27, 0.16);
uniform vec3 line_color : source_color = vec3(0.9, 0.95, 0.85);
uniform float cell = 100.0;
uniform float fade_near = 1500.0;
uniform float fade_far = 9000.0;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	float fade = 1.0 - smoothstep(fade_near, fade_far, dist);
	vec2 p = world_pos.xz / cell;
	vec2 g = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.00001));
	float grid = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float checker = mod(floor(world_pos.x / 500.0) + floor(world_pos.z / 500.0), 2.0);
	vec3 base = mix(grass_a, grass_b, checker * fade);
	ALBEDO = mix(base, line_color, grid * 0.35 * fade);
	ROUGHNESS = 0.95;
}
"""

const RUNWAY_SHADER := """
shader_type spatial;
uniform vec3 asphalt : source_color = vec3(0.16, 0.165, 0.17);
uniform vec3 paint : source_color = vec3(0.85, 0.85, 0.82);

void fragment() {
	float x = (UV.x - 0.5) * 45.0;
	float z = (UV.y - 0.5) * 2500.0;
	float centre = step(abs(x), 0.6) * step(0.5, fract(z / 60.0)) * step(abs(z), 1100.0);
	float band = step(1200.0, abs(z)) * step(abs(z), 1230.0) * step(abs(x), 18.0) * step(0.5, fract((x + 18.0) / 4.0));
	float paint_mask = clamp(centre + band, 0.0, 1.0);
	ALBEDO = mix(asphalt, paint, paint_mask);
	ROUGHNESS = 0.9;
}
"""

var player: Aircraft
var target: Aircraft
var controller: PlayerController
var camera: FlightCamera
var hud_label: Label

@onready var _sun: DirectionalLight3D = $Sun
@onready var _env_node: WorldEnvironment = $WorldEnvironment

var _runway: MeshInstance3D
var _test_data: AircraftData
var _gamma_last := 0.0
var _gamma_valid := false
var _gamma_int := 0.0


func _ready() -> void:
	WorldOrigin.reset()
	_setup_environment()
	_build_ground()
	_build_runway()
	_build_pillars()
	if _test_requested():
		run_flight_test()
	_build_hud()
	controller = PlayerController.new()
	controller.name = "PlayerController"
	add_child(controller)
	camera = FlightCamera.new()
	camera.name = "FlightCamera"
	camera.controller = controller
	add_child(camera)
	_spawn_player_airborne()
	_spawn_target()


func _process(_delta: float) -> void:
	controller.aim_drag_enabled = camera.get_mode() != FlightCamera.Mode.ORBIT
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.physical_keycode == KEY_M:
		toggle_flight_mode()
	elif k.physical_keycode == KEY_N:
		respawn_on_runway()


## Switches the live player between arcade and realistic. The flight model reads Settings every tick.
func toggle_flight_mode() -> void:
	Settings.flight_mode = "realistic" if Settings.flight_mode == "arcade" else "arcade"


## Puts the player back on the runway, gear down, nose north.
func respawn_on_runway() -> void:
	_replace_player()
	if player == null:
		return
	var spawn_z := _runway.position.z + RUNWAY_LEN * 0.5 - RUNWAY_START_INSET
	player.spawn_on_ground(Vector3(_runway.position.x, 0.0, spawn_z), 0.0)
	_attach_player()


func _test_requested() -> bool:
	return DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--flight-test")


func _setup_environment() -> void:
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 400.0
	_sun.light_energy = 1.1
	_sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.ground_horizon_color = Color(0.55, 0.6, 0.62)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.2)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.00004
	env.fog_sky_affect = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.0
	_env_node.environment = env


func _build_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.add_to_group("floating")
	add_child(ground)


func _build_runway() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(RUNWAY_WIDTH, RUNWAY_LEN)
	var shader := Shader.new()
	shader.code = RUNWAY_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_runway = MeshInstance3D.new()
	_runway.name = "Runway"
	_runway.mesh = mesh
	_runway.material_override = mat
	_runway.position = Vector3(0.0, 0.2, 0.0)
	_runway.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_runway.add_to_group("floating")
	add_child(_runway)


func _build_pillars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = PILLAR_SEED
	var mesh := CylinderMesh.new()
	mesh.top_radius = PILLAR_RADIUS
	mesh.bottom_radius = PILLAR_RADIUS
	mesh.height = PILLAR_HEIGHT
	mesh.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.36, 0.2)
	mat.roughness = 0.7
	var holder := Node3D.new()
	holder.name = "Pillars"
	holder.add_to_group("floating")
	add_child(holder)
	var placed := 0
	while placed < PILLAR_COUNT:
		var p := Vector2(
			rng.randf_range(-PILLAR_SPREAD, PILLAR_SPREAD), rng.randf_range(-PILLAR_SPREAD, PILLAR_SPREAD))
		if p.length() < PILLAR_CLEAR:
			continue
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.material_override = mat
		m.position = Vector3(p.x, PILLAR_HEIGHT * 0.5, p.y)
		holder.add_child(m)
		placed += 1


func _spawn_player_airborne() -> void:
	_replace_player()
	if player == null:
		return
	player.spawn_in_air(Vector3(0.0, SPAWN_ALT, 0.0), 0.0, SPAWN_KMH)
	_attach_player()


func _spawn_target() -> void:
	target = Aircraft.create(AIRCRAFT_ID, 1, false)
	if target == null:
		return
	add_child(target)
	target.spawn_in_air(Vector3(0.0, SPAWN_ALT, -TARGET_AHEAD), 0.0, SPAWN_KMH)


## Creates a fresh player aircraft and removes the old one (alive or wreck).
func _replace_player() -> void:
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = Aircraft.create(AIRCRAFT_ID, 0, true)
	if player == null:
		push_error("test_flight: cannot create the player aircraft")
		return
	add_child(player)


func _attach_player() -> void:
	controller.attach(player)
	camera.set_target(player)
	WorldOrigin.anchor = player


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	hud_label = Label.new()
	hud_label.name = "Readout"
	hud_label.position = Vector2(16.0, 12.0)
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hud_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(hud_label)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = HUD_HINT
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 16.0
	hint.offset_right = 1400.0
	hint.offset_top = -30.0
	hint.offset_bottom = -6.0
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.8))
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hint.add_theme_constant_override("outline_size", 3)
	layer.add_child(hint)


func _update_hud() -> void:
	if player == null or not is_instance_valid(player):
		hud_label.text = "no aircraft (N respawns)"
		return
	var tas := player.get_speed_kmh()
	var extra := ""
	if player.is_afterburner():
		extra += "  AB"
	if player.is_stalling():
		extra += "  STALL"
	if player.is_on_ground():
		extra += "  ON GROUND"
	if player.get_blackout() > 0.05:
		extra += "  BLACKOUT %d%%" % int(player.get_blackout() * 100.0)
	if player.get_redout() > 0.05:
		extra += "  REDOUT %d%%" % int(player.get_redout() * 100.0)
	var text := "SPD %d km/h (%d kt)   IAS %d km/h\n" % [int(tas), int(tas / 1.852), int(player.get_ias_kmh())]
	text += "ALT %d m   AGL %d m\n" % [int(player.get_altitude_m()), int(player.get_agl_m())]
	text += "G %.1f   AoA %.1f deg   M %.2f\n" % [player.get_g(), player.get_aoa_deg(), player.get_mach()]
	text += "THR %d%%   MODE %s   CAM %s%s\n" % [
		int(player.get_throttle() * 100.0), Settings.flight_mode.to_upper(), camera.get_mode_name(), extra]
	text += "FPS %d" % int(Engine.get_frames_per_second())
	hud_label.text = text


# ---------------------------------------------------------------------------------------------------------------
# Flight test: runs the flight model alone (no nodes), prints the numbers. Times are simulated seconds.
# ---------------------------------------------------------------------------------------------------------------

func run_flight_test() -> void:
	_test_data = AircraftData.load_id(AIRCRAFT_ID)
	if _test_data == null:
		push_error("flight test: no aircraft data for %s" % AIRCRAFT_ID)
		return
	var t0 := Time.get_ticks_msec()
	print(TAG + "F-16C flight model, realistic (no assists), fixed 1/60 s steps")
	_test_top_speed(TEST_TOP_ALT, 1200.0, false, 120.0, "mil power, sea level", "target ~%d kt" % int(TARGET_TOP_KT))
	_test_top_speed(TEST_TOP_ALT, 1300.0, true, 120.0, "afterburner, sea level", "")
	_test_top_speed(TEST_HIGH_ALT, 1900.0, true, 300.0, "afterburner, 15 km", "target Mach ~%.0f" % int(TARGET_HIGH_MACH))
	_test_stall()
	_test_roll_rate()
	_test_sustained_turn()
	_test_climb()
	print(TAG + "done in %d ms" % (Time.get_ticks_msec() - t0))


func _steps(seconds: float) -> int:
	return int(round(seconds * float(SIM_RATE)))


func _test_model(alt_m: float, kmh: float) -> FlightModel:
	var fm := FlightModel.new()
	fm.setup(_test_data, false)
	fm.place_airborne(Vector3(0.0, alt_m, 0.0), 0.0, kmh / 3.6)
	_gamma_valid = false
	_gamma_int = 0.0
	return fm


## Pitch stick that drives the flight-path angle toward gamma_want (rad, positive climbing).
func _gamma_stick(fm: FlightModel, gamma_want: float) -> float:
	var v := fm.velocity
	var gamma := atan2(v.y, Vector2(v.x, v.z).length())
	var gdot := 0.0
	if _gamma_valid:
		gdot = (gamma - _gamma_last) / TEST_DT
	_gamma_last = gamma
	_gamma_valid = true
	_gamma_int = clampf(_gamma_int + (gamma_want - gamma) * TEST_DT, -GAMMA_INT_MAX, GAMMA_INT_MAX)
	var cmd := PATH_KP * (gamma_want - gamma) + PATH_KI * _gamma_int - GDOT_KD * gdot
	return clampf(cmd / fm.data.pitch_rate_rad(), -1.0, 1.0)


## Pitch stick that holds altitude alt_want (metres) by way of the flight-path angle. The altitude error is
## turned into a flight-path angle scaled by speed, so the altitude loop is ALT_BW at any speed.
func _alt_stick(fm: FlightModel, alt_want: float) -> float:
	var spd := maxf(fm.velocity.length(), 30.0)
	var want := clampf(ALT_BW * (alt_want - fm.position.y) / spd, -ALT_GAMMA_MAX, ALT_GAMMA_MAX)
	return _gamma_stick(fm, want)


## Yaw stick that keeps the nose on the velocity vector (no sideslip), so turns are coordinated like a DFCS turn.
func _coord_stick(fm: FlightModel) -> float:
	return clampf(BETA_KP * fm.beta / fm.data.yaw_rate_rad(), -1.0, 1.0)


## Roll stick that holds bank_want (rad, positive right).
func _bank_stick(fm: FlightModel, bank_want: float) -> float:
	var cmd := BANK_KP * (bank_want - fm.bank_rad()) - BANK_KD * fm.rates.z
	return clampf(cmd / fm.data.roll_rate_rad(), -1.0, 1.0)


## Holds altitude at full throttle (mil or afterburner) for duration seconds. The top speed is the mean TAS over
## the last 5 s; the acceleration over those 5 s shows how close the run is to terminal speed.
func _test_top_speed(alt_m: float, start_kmh: float, ab: bool, duration: float, note: String, target_text: String) -> void:
	var fm := _test_model(alt_m, start_kmh)
	var c := ControlInput.new()
	c.throttle = 1.0 if ab else 0.998  # 0.999 and above lights the afterburner
	c.afterburner = ab
	var t_win := _steps(duration - 5.0)
	var v_win := 0.0
	var v_sum := 0.0
	var m_sum := 0.0
	var n := 0
	var steps := _steps(duration)
	for i in steps:
		c.pitch = _alt_stick(fm, alt_m)
		fm.step(c, TEST_DT)
		if fm.crashed:
			print(TAG + "top speed, %s: crashed" % note)
			return
		if i == t_win:
			v_win = fm.velocity.length()
		if i >= t_win:
			v_sum += fm.velocity.length()
			m_sum += fm.mach
			n += 1
	var v_mean := v_sum / float(n)
	var accel := (v_mean - v_win) / 5.0
	print(TAG + "top speed, %s, %d s: %d kt (%d km/h), Mach %.2f, accel %.2f m/s2  %s" % [
		note, int(duration), int(v_mean / 0.5144), int(v_mean * 3.6), m_sum / float(n), accel, target_text])


func _test_stall() -> void:
	var fm := _test_model(TEST_STALL_ALT, 350.0)
	var c := ControlInput.new()
	c.throttle = 0.0
	var warm := _steps(STALL_WARMUP_S)
	var window := _steps(3.0)
	var hist := PackedFloat64Array()
	var onset := false
	var ias_kmh := 0.0
	var aoa_deg := 0.0
	for i in _steps(90.0):
		c.pitch = _alt_stick(fm, TEST_STALL_ALT)
		fm.step(c, TEST_DT)
		if fm.crashed:
			break
		hist.append(fm.position.y)
		# onset: after the warm-up the aircraft cannot hold level (sinks more than 3 m in 3 s) or is stalled
		if i >= warm and (fm.stalled or hist[i] - hist[i - window] < -3.0):
			onset = true
			ias_kmh = fm.ias_ms * 3.6
			aoa_deg = rad_to_deg(fm.alpha)
			break
	var rho := FlightModel.air_density(TEST_STALL_ALT)
	var v_clmax := sqrt(2.0 * fm.mass() * 9.81 / (rho * _test_data.wing_area * _test_data.cl_max))
	print(TAG + "stall speed, level at %d m, CLmax %.2f, %d kg: %d km/h (CLmax limit)  target ~%d km/h" % [
		int(TEST_STALL_ALT), _test_data.cl_max, int(fm.mass()), int(v_clmax * 3.6), int(TARGET_STALL_KMH)])
	if onset:
		print(TAG + "stall onset, idle deceleration: sink begins at IAS %d km/h, AoA %.1f deg (altitude-hold limited)" % [
			int(ias_kmh), aoa_deg])
	else:
		print(TAG + "stall onset: not reached in 90 s")


func _test_roll_rate() -> void:
	var fm := _test_model(TEST_ROLL_ALT, 600.0)
	var c := ControlInput.new()
	c.throttle = 0.7
	var peak := 0.0
	for _i in _steps(1.5):
		c.roll = 1.0
		fm.step(c, TEST_DT)
		peak = maxf(peak, absf(fm.rates.z))
	print(TAG + "roll rate, 600 km/h at %d m, full stick: %d deg/s  target ~%d deg/s" % [
		int(TEST_ROLL_ALT), int(rad_to_deg(peak)), int(TARGET_ROLL_DEG_S)])


## Turn sweep at full afterburner with coordinated yaw and altitude hold. It starts at 700 km/h so the aircraft is
## near 900 km/h after the 8 s settle; the 4 s window after that is measured. A bank is sustained when the speed
## does not fall faster than 0.5 m/s2 and the altitude stays within 20 m. Reports the highest sustained mean g.
func _test_sustained_turn() -> void:
	var best_g := 0.0
	var best_bank := 0
	var best_kmh := 0.0
	var t_win := _steps(8.0)
	var t_end := _steps(12.0)
	for bank_deg in range(60, 86, 2):
		var fm := _test_model(TEST_TURN_ALT, 700.0)
		var c := ControlInput.new()
		c.throttle = 1.0
		c.afterburner = true
		var bank_want := deg_to_rad(float(bank_deg))
		var v0 := 0.0
		var h0 := 0.0
		var g_sum := 0.0
		var n := 0
		var crashed := false
		for i in t_end:
			c.pitch = _alt_stick(fm, TEST_TURN_ALT)
			c.roll = _bank_stick(fm, bank_want)
			c.yaw = _coord_stick(fm)
			fm.step(c, TEST_DT)
			if fm.crashed:
				crashed = true
				break
			if i == t_win:
				v0 = fm.velocity.length()
				h0 = fm.position.y
			if i >= t_win:
				g_sum += fm.g_load
				n += 1
		if crashed or n == 0:
			continue
		var dv_dt := (fm.velocity.length() - v0) / 4.0
		var dh := absf(fm.position.y - h0)
		var mean_g := g_sum / float(n)
		if dv_dt >= -0.5 and dh <= 20.0 and mean_g > best_g:
			best_g = mean_g
			best_bank = bank_deg
			best_kmh = (v0 + fm.velocity.length()) * 0.5 * 3.6
	if best_bank == 0:
		print(TAG + "sustained turn, afterburner at %d m: none sustained in 60..84 deg" % int(TEST_TURN_ALT))
	else:
		print(TAG + "sustained turn, %d km/h afterburner at %d m: %.1f g (bank %d deg)  target ~%d g" % [
			int(best_kmh), int(TEST_TURN_ALT), best_g, best_bank, int(TARGET_TURN_G)])


func _test_climb() -> void:
	var fm := _test_model(TEST_CLIMB_ALT, 600.0)
	var c := ControlInput.new()
	c.throttle = 1.0
	c.afterburner = true
	var gamma_want := deg_to_rad(TEST_CLIMB_GAMMA_DEG)
	var peak := 0.0
	var vs_sum := 0.0
	var n := 0
	var t20 := _steps(20.0)
	var h0 := fm.position.y
	var crashed := false
	for i in _steps(30.0):
		c.pitch = _gamma_stick(fm, gamma_want)
		fm.step(c, TEST_DT)
		if fm.crashed:
			crashed = true
			break
		peak = maxf(peak, fm.velocity.y)
		if i >= t20:
			vs_sum += fm.velocity.y
			n += 1
	if crashed or n == 0:
		print(TAG + "climb: crashed")
		return
	var mean_vs := vs_sum / float(n)
	print(TAG + "climb, afterburner from 600 km/h, gamma %d deg: peak %d m/min, last 10 s mean %d m/min, %d km/h at %d m (+%d m)" % [
		int(TEST_CLIMB_GAMMA_DEG), int(peak * 60.0), int(mean_vs * 60.0), int(fm.velocity.length() * 3.6),
		int(fm.position.y), int(fm.position.y - h0)])
