class_name FlightCamera
extends Node3D
## Follow camera for one aircraft at a time. Modes: chase (default), cockpit, orbit. look_back_held flips
## the view to face backwards (set it from the controller's look_back each tick). The camera root is the
## node in group "floating" (WorldOrigin shifts it); the Camera3D child carries the shake offset.

enum Mode { CHASE, COCKPIT, ORBIT }

const NEAR := 0.5
const FAR := 600000.0  ## the map is 256 km across; the far plane must cover the horizon of the ocean
const CHASE_POS_RATE := 7.0  ## 1/s spring rate for position
const CHASE_ROT_RATE := 9.0  ## 1/s slerp rate for orientation (lags in turns)
const LOOK_DISTANCE := 150.0
const ORBIT_DISTANCE := 26.0
const ORBIT_RAD_PER_PX := 0.006
const ORBIT_PITCH_LIMIT := 1.3
const GROUND_CLEARANCE := 1.5
const SHAKE_DECAY := 2.5  ## 1/s
const SHAKE_GUN := 0.05
const SHAKE_HIT := 0.5
const SHAKE_AB := 0.12  ## continuous rumble while afterburning
const SHAKE_G_GAIN := 0.04  ## shake per g above the threshold, per second
const SHAKE_G_START := 6.0
const SHAKE_MAX := 1.0
const SHAKE_BLAST := 0.6  ## shake from an explosion at point blank, falls off linearly to 0 at BLAST_RANGE
const BLAST_RANGE := 2500.0  ## m
const SHAKE_OFFSET := 0.35  ## m at full shake
const FOV_BASE := 68.0
const FOV_FAST := 82.0
const FOV_COCKPIT := 75.0
const FOV_LOOK_BACK := 70.0

var mode: Mode = Mode.CHASE
var look_back_held := false
var controller: PlayerController  ## optional: supplies the arcade aim direction

var _target: Aircraft
var _cam: Camera3D
var _orbit_yaw := 0.0
var _orbit_pitch := 0.25
var _shake := 0.0
var _rumble := 0.0
var _hid_visual := false
var _rng := RandomNumberGenerator.new()
var _snap := true


func _ready() -> void:
	add_to_group("floating")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved every render frame in _process
	Settings.set_cockpit_view(mode == Mode.COCKPIT)
	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.near = NEAR
	_cam.far = FAR
	_cam.fov = FOV_BASE
	add_child(_cam)
	_cam.current = true
	_rng.randomize()
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.damaged.connect(_on_damaged)
	Events.explosion.connect(_on_explosion)


func _exit_tree() -> void:
	if Events.weapon_fired.is_connected(_on_weapon_fired):
		Events.weapon_fired.disconnect(_on_weapon_fired)
	if Events.damaged.is_connected(_on_damaged):
		Events.damaged.disconnect(_on_damaged)
	if Events.explosion.is_connected(_on_explosion):
		Events.explosion.disconnect(_on_explosion)
	if mode == Mode.COCKPIT:
		Settings.set_cockpit_view(false)


func get_camera() -> Camera3D:
	return _cam


func get_target() -> Aircraft:
	return _target


func get_mode() -> Mode:
	return mode


func get_mode_name() -> String:
	return ["chase", "cockpit", "orbit"][mode]


## Sets the aircraft to follow. Snaps to the new pose on the next update.
func set_target(a: Aircraft) -> void:
	_set_visual_hidden(false)
	_target = a
	_snap = true


func cycle_mode() -> void:
	var next := (int(mode) + 1) % 3
	set_mode(next as Mode)


func set_mode(m: Mode) -> void:
	if m == mode:
		return
	_set_visual_hidden(false)
	mode = m
	_snap = true
	_orbit_yaw = 0.0
	_orbit_pitch = 0.25
	Settings.set_cockpit_view(mode == Mode.COCKPIT)


func set_look_back(on: bool) -> void:
	look_back_held = on


## Orbit mode: drag to swing the camera around the aircraft (pixels).
func orbit_drag(pixels: Vector2) -> void:
	_orbit_yaw -= pixels.x * ORBIT_RAD_PER_PX
	_orbit_pitch = clampf(_orbit_pitch + pixels.y * ORBIT_RAD_PER_PX, -ORBIT_PITCH_LIMIT, ORBIT_PITCH_LIMIT)


## Adds camera shake, 0..1 (gun fire, hits, afterburner and high g add to it).
func add_shake(amount: float) -> void:
	_shake = minf(SHAKE_MAX, _shake + amount)


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.ORBIT:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
			orbit_drag(mm.relative)
	elif event is InputEventScreenDrag:
		orbit_drag((event as InputEventScreenDrag).relative)


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_cam.position = Vector3.ZERO
		return
	# The plain transform, not the physics-interpolated one: after spawn_in_air the interpolated origin
	# sat ~56 km from the body, so the chase camera followed empty air and the aircraft was a speck.
	var xf := _target.global_transform
	var k_pos := 1.0 - exp(-CHASE_POS_RATE * delta)
	var k_rot := 1.0 - exp(-CHASE_ROT_RATE * delta)
	var speed := _target.get_speed_kmh()

	var want_pos: Vector3
	var want_basis: Basis
	match mode:
		Mode.CHASE:
			want_pos = xf * Vector3(0.0, _target.data.chase_height, _target.data.chase_distance * (-1.0 if look_back_held else 1.0))
			var look_at := xf.origin
			if not look_back_held:
				look_at = xf.origin + _aim_world(xf) * LOOK_DISTANCE
			want_basis = _look_basis(want_pos, look_at, xf.basis.y)
		Mode.COCKPIT:
			var g_drop := clampf(_target.get_g() - 1.0, 0.0, 6.0) * 0.035
			var eye := Vector3(_target.data.cockpit_eye.x, _target.data.cockpit_eye.y - g_drop, _target.data.cockpit_eye.z)
			want_pos = xf * eye
			var look_at := want_pos + _aim_world(xf) * LOOK_DISTANCE
			want_basis = _look_basis(want_pos, look_at, xf.basis.y)
		Mode.ORBIT:
			var dir := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch))
			want_pos = xf * (dir * ORBIT_DISTANCE)
			want_basis = _look_basis(want_pos, xf.origin, Vector3.UP)

	if _snap:
		global_transform = Transform3D(want_basis, want_pos)
		_snap = false
	elif mode == Mode.CHASE:
		var p := global_position.lerp(want_pos, k_pos)
		var q := Quaternion(global_transform.basis).slerp(Quaternion(want_basis), k_rot)
		global_transform = Transform3D(Basis(q), p)
	else:
		global_transform = Transform3D(want_basis, want_pos)
	_clamp_above_ground()

	_cam.fov = _fov_for(speed)
	_update_shake(delta)
	_set_visual_hidden(mode == Mode.COCKPIT)


func _fov_for(speed_kmh: float) -> float:
	if mode == Mode.COCKPIT:
		return FOV_COCKPIT
	if look_back_held:
		return FOV_LOOK_BACK
	return lerpf(FOV_BASE, FOV_FAST, clampf((speed_kmh - 350.0) / 900.0, 0.0, 1.0))


## Arcade follows the pilot's aim point; other modes and non-arcade flying use the nose.
func _aim_world(xf: Transform3D) -> Vector3:
	if controller != null and Settings.flight_mode == "arcade":
		return controller.get_aim_world()
	return xf.basis * Vector3.FORWARD


func _look_basis(from: Vector3, to: Vector3, up_hint: Vector3) -> Basis:
	var fwd := to - from
	if fwd.length_squared() < 1e-6:
		return global_transform.basis
	fwd = fwd.normalized()
	var up := up_hint
	if absf(fwd.dot(up)) > 0.98:
		up = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	return Basis.looking_at(fwd, up)


func _clamp_above_ground() -> void:
	var p := global_position
	var floor_y := Ground.surface_at(p.x, p.z) + GROUND_CLEARANCE
	if p.y < floor_y:
		global_position = Vector3(p.x, floor_y, p.z)


func _update_shake(delta: float) -> void:
	if _target != null and not _target.is_on_ground():
		var g := _target.get_g()
		if g > SHAKE_G_START:
			_rumble = minf(SHAKE_MAX, _rumble + (g - SHAKE_G_START) * SHAKE_G_GAIN * delta)
	_rumble = move_toward(_rumble, 0.0, delta * 0.5)
	var ab_rumble := SHAKE_AB if (_target != null and _target.is_afterburner()) else 0.0
	_shake = move_toward(_shake, 0.0, delta * SHAKE_DECAY)
	var amount := 0.0
	if Settings.camera_shake:
		amount = clampf(_shake + _rumble + ab_rumble, 0.0, SHAKE_MAX)
	if amount <= 0.001:
		_cam.position = Vector3.ZERO
		return
	_cam.position = Vector3(
		_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amount * SHAKE_OFFSET


func _set_visual_hidden(hide_it: bool) -> void:
	if _target == null or not is_instance_valid(_target) or _target.visual == null:
		return
	if hide_it and _target.visual.visible:
		_target.visual.visible = false
		_hid_visual = true
	elif not hide_it and _hid_visual:
		_target.visual.visible = true
		_hid_visual = false


func _on_weapon_fired(shooter: Node3D, _weapon_id: String) -> void:
	if shooter == _target:
		add_shake(SHAKE_GUN)


func _on_damaged(victim: Node3D, _amount: float, _source: Node) -> void:
	if victim == _target:
		add_shake(SHAKE_HIT)


## world_pos is in World space (this camera's parent), like every floating node.
func _on_explosion(world_pos: Vector3, size: float) -> void:
	var falloff := 1.0 - position.distance_to(world_pos) / BLAST_RANGE
	if falloff <= 0.0:
		return
	add_shake(SHAKE_BLAST * falloff * clampf(size / Aircraft.EXPLOSION_SIZE, 0.3, 2.0))
