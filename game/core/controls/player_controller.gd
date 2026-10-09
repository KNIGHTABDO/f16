class_name PlayerController
extends Node
## Turns player input into aircraft.controls once per physics tick. Sources, highest priority first:
## gamepad > touch > keyboard/mouse (gyro acts like touch). Arcade: the aim point (stored as yaw/elevation
## relative to the nose, so the camera can follow it) is moved by mouse drag, right stick, touch drag or gyro,
## and the instructor flies the aircraft toward it. Stick input overrides the aim and the aim drifts back to
## the nose. Realistic: direct sticks with expo and Settings.stick_sensitivity.
##
## Touch API for the HUD: touch_stick (x = roll right, y = pitch up, -1..1), touch_stick_active,
## add_aim_drag(pixels), touch_throttle (0..1, -1 = unused), touch_gun, press_weapon(), press_flares(),
## press_cycle_weapon(), press_cycle_target(), press_gear(), press_camera(), set_airbrake(on), set_look_back(on),
## toggle_afterburner(), calibrate_gyro().
## One-shot flags pause_requested and camera_requested stay true until the reader sets them back to false.

const DEADZONE := 0.12
const STICK_EXPO := 0.35  ## 0 = linear, 1 = cubic
const AIM_STICK_RATE := 2.4  ## rad/s at full right stick
const AIM_ELEVATION_LIMIT := 1.45  ## rad, just under 90 degrees
const AIM_RETURN_RATE := 5.0  ## rad/s the aim drifts back to the nose while sticks override it
const MOUSE_RAD_PER_PX := 0.0028
const THROTTLE_RATE := 0.6  ## per second, keys
const THROTTLE_PAD_RATE := 0.8  ## per second at full trigger
const GYRO_DEADZONE := 0.03  ## rad/s
const GYRO_TILT_FULL := 4.0  ## m/s^2 of gravity shift for a full stick from tilt
const TRIGGER_DEADZONE := 0.05

var aircraft: Aircraft
var touch_stick := Vector2.ZERO
var touch_stick_active := false
var touch_throttle := -1.0
var touch_gun := false
var pause_requested := false
var camera_requested := false
var look_back := false  ## held: camera should look back (C key, touch or pad)
var aim_drag_enabled := true  ## false while the camera orbits, so mouse drag only moves the camera

var _aim_az := 0.0  ## rad, positive right of the nose
var _aim_el := 0.0  ## rad, positive up
var _afterburner := false
var _touch_airbrake := false
var _touch_look_back := false
var _gyro_neutral := Vector3.ZERO
var _q_weapon := false
var _q_cycle_weapon := false
var _q_cycle_target := false
var _q_flares := false
var _q_gear := false
var _pad_prev: Dictionary = {}


func _ready() -> void:
	_ensure_actions()
	calibrate_gyro()


## Hands the controller an aircraft. The controller writes its controls every physics tick.
func attach(a: Aircraft) -> void:
	aircraft = a


func _physics_process(delta: float) -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var c := aircraft.controls
	c.clear_triggers()
	var pad := _pad_index()
	var arcade := Settings.flight_mode == "arcade"
	var pitch_sign := -1.0 if Settings.invert_pitch else 1.0

	# Stick sources, lowest priority first.
	var pitch := _axis("fc_pitch_up", "fc_pitch_down")
	var roll := _axis("fc_roll_right", "fc_roll_left")
	var yaw := _axis("fc_yaw_right", "fc_yaw_left")
	if touch_stick_active:
		pitch = touch_stick.y
		roll = touch_stick.x
	if not arcade and Settings.control_scheme == "gyro":
		var tilt := _gyro_tilt()
		roll = tilt.x
		pitch = tilt.y
	if pad >= 0:
		var lx := _deadzone(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
		var ly := _deadzone(-Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if lx != 0.0 or ly != 0.0:
			roll = lx
			pitch = ly
		if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER) != Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER):
			yaw = 1.0 if Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER) else -1.0
		if not arcade:
			var rx := _deadzone(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X))
			if rx != 0.0:
				yaw = rx
	pitch = _expo(pitch) * pitch_sign
	roll = _expo(roll)
	yaw = _expo(yaw)

	# Pad buttons are edge-detected here; keyboard and touch set their flags in _unhandled_input / press_*.
	if pad >= 0:
		if _pad_edge(pad, JOY_BUTTON_B):
			_q_weapon = true
		if _pad_edge(pad, JOY_BUTTON_X):
			_q_flares = true
		if _pad_edge(pad, JOY_BUTTON_Y):
			_q_cycle_weapon = true
		if _pad_edge(pad, JOY_BUTTON_DPAD_UP):
			camera_requested = true
		if _pad_edge(pad, JOY_BUTTON_DPAD_DOWN):
			_q_gear = true

	var direct := absf(pitch) > 0.02 or absf(roll) > 0.02 or absf(yaw) > 0.02
	if arcade:
		_update_aim(pad, delta, direct, pitch_sign)
	if arcade and not direct:
		c.use_aim = true
		c.aim_direction = get_aim_direction()
		c.pitch = 0.0
		c.roll = 0.0
		c.yaw = 0.0
	else:
		c.use_aim = false
		c.pitch = pitch
		c.roll = roll
		c.yaw = yaw

	c.throttle = _update_throttle(c.throttle, pad, delta)
	c.afterburner = _afterburner
	c.fire_gun = Input.is_action_pressed("fc_gun") or touch_gun or (pad >= 0 and Input.is_joy_button_pressed(pad, JOY_BUTTON_A))
	c.airbrake = Input.is_action_pressed("fc_airbrake") or _touch_airbrake
	look_back = Input.is_action_pressed("fc_look_back") or _touch_look_back
	c.fire_weapon = _q_weapon
	c.cycle_weapon = _q_cycle_weapon
	c.cycle_target = _q_cycle_target
	c.drop_flares = _q_flares
	c.toggle_gear = _q_gear
	_q_weapon = false
	_q_cycle_weapon = false
	_q_cycle_target = false
	_q_flares = false
	_q_gear = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var held := (mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0
		# On touch devices the mouse motion is emulated from touch; the HUD sends those through add_aim_drag.
		if aim_drag_enabled and not DisplayServer.is_touchscreen_available() and (held or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
			add_aim_drag(mm.relative)
		return
	if event.is_action_pressed("fc_weapon", false):
		_q_weapon = true
	elif event.is_action_pressed("fc_cycle_weapon", false):
		_q_cycle_weapon = true
	elif event.is_action_pressed("fc_cycle_target", false):
		_q_cycle_target = true
	elif event.is_action_pressed("fc_flares", false):
		_q_flares = true
	elif event.is_action_pressed("fc_gear", false):
		_q_gear = true
	elif event.is_action_pressed("fc_afterburner", false):
		toggle_afterburner()
	elif event.is_action_pressed("fc_camera", false):
		camera_requested = true
	elif event.is_action_pressed("fc_pause", false):
		pause_requested = true


## Touch and drag: moves the arcade aim point by pixels (dragging right moves the aim right).
func add_aim_drag(pixels: Vector2) -> void:
	if Settings.flight_mode != "arcade":
		return
	var k := MOUSE_RAD_PER_PX * Settings.stick_sensitivity
	var pitch_sign := -1.0 if Settings.invert_pitch else 1.0
	_aim_az += pixels.x * k
	_aim_el -= pixels.y * k * pitch_sign
	_clamp_aim()


func press_weapon() -> void:
	_q_weapon = true


func press_flares() -> void:
	_q_flares = true


func press_cycle_weapon() -> void:
	_q_cycle_weapon = true


func press_cycle_target() -> void:
	_q_cycle_target = true


func press_gear() -> void:
	_q_gear = true


func press_camera() -> void:
	camera_requested = true


func set_airbrake(on: bool) -> void:
	_touch_airbrake = on


func set_look_back(on: bool) -> void:
	_touch_look_back = on


func toggle_afterburner() -> void:
	_afterburner = not _afterburner


## Re-zeroes the gyro: the current gravity reading becomes neutral tilt.
func calibrate_gyro() -> void:
	_gyro_neutral = Input.get_gravity()


## Arcade aim direction in the aircraft's LOCAL frame (nose -Z, right +X, up +Y). Use for the HUD aim circle.
func get_aim_direction() -> Vector3:
	var ce := cos(_aim_el)
	return Vector3(sin(_aim_az) * ce, sin(_aim_el), -cos(_aim_az) * ce)


## Same as get_aim_direction() in world axes (aircraft rotation applied).
func get_aim_world() -> Vector3:
	if aircraft == null:
		return Vector3.FORWARD
	return aircraft.global_transform.basis * get_aim_direction()


func _update_aim(pad: int, delta: float, direct: bool, pitch_sign: float) -> void:
	var sens := Settings.stick_sensitivity
	if pad >= 0:
		var rx := _deadzone(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X))
		var ry := _deadzone(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
		_aim_az += rx * AIM_STICK_RATE * delta * sens
		_aim_el -= ry * AIM_STICK_RATE * delta * sens * pitch_sign
	if Settings.control_scheme == "gyro":
		var rates := _gyro_aim_rates()
		_aim_az += rates.x * delta * Settings.gyro_sensitivity
		_aim_el += rates.y * delta * Settings.gyro_sensitivity * pitch_sign
	if direct:
		_aim_az = move_toward(_aim_az, 0.0, AIM_RETURN_RATE * delta)
		_aim_el = move_toward(_aim_el, 0.0, AIM_RETURN_RATE * delta)
	_clamp_aim()


func _clamp_aim() -> void:
	_aim_az = wrapf(_aim_az, -PI, PI)
	_aim_el = clampf(_aim_el, -AIM_ELEVATION_LIMIT, AIM_ELEVATION_LIMIT)


func _update_throttle(current: float, pad: int, delta: float) -> float:
	if touch_throttle >= 0.0:
		return clampf(touch_throttle, 0.0, 1.0)
	var rate := (Input.get_action_strength("fc_throttle_up") - Input.get_action_strength("fc_throttle_down")) * THROTTLE_RATE
	if pad >= 0:
		var rt := _trigger(pad, JOY_AXIS_TRIGGER_RIGHT)
		var lt := _trigger(pad, JOY_AXIS_TRIGGER_LEFT)
		rate += (rt - lt) * THROTTLE_PAD_RATE
	return clampf(current + rate * delta, 0.0, 1.0)


## Gyro rates in aim units: x = yaw right (rad/s), y = pitch up (rad/s). Uses gravity to find the vertical.
func _gyro_aim_rates() -> Vector2:
	var g := Input.get_gravity()
	if g.length_squared() < 0.01:
		return Vector2.ZERO
	var gy := Input.get_gyroscope()
	var yaw_rate := gy.dot(g.normalized())  # rotation about the down axis: positive turns right
	var pitch_rate := gy.y if _is_landscape() else gy.x
	return Vector2(_gyro_dz(yaw_rate), _gyro_dz(pitch_rate))


## Gyro as realistic stick deflection: device tilt from the calibrated neutral. Vector2(roll, pitch).
func _gyro_tilt() -> Vector2:
	var g := Input.get_gravity()
	var n := _gyro_neutral
	var along := (g.y - n.y) if _is_landscape() else (g.x - n.x)
	var fore := g.z - n.z
	return Vector2(clampf(along / GYRO_TILT_FULL, -1.0, 1.0), clampf(fore / GYRO_TILT_FULL, -1.0, 1.0))


func _gyro_dz(v: float) -> float:
	return 0.0 if absf(v) < GYRO_DEADZONE else v


func _is_landscape() -> bool:
	var o := DisplayServer.screen_get_orientation()
	return o == DisplayServer.SCREEN_LANDSCAPE or o == DisplayServer.SCREEN_REVERSE_LANDSCAPE


func _pad_index() -> int:
	var pads: Array = Input.get_connected_joypads()
	return int(pads[0]) if pads.size() > 0 else -1


## True once when the button goes down. Call exactly once per tick for each button.
func _pad_edge(pad: int, button: int) -> bool:
	var now := Input.is_joy_button_pressed(pad, button)
	var was: bool = _pad_prev.get(button, false)
	_pad_prev[button] = now
	return now and not was


func _trigger(pad: int, axis: int) -> float:
	var v := Input.get_joy_axis(pad, axis)
	return v if v > TRIGGER_DEADZONE else 0.0


func _axis(positive: String, negative: String) -> float:
	return Input.get_action_strength(positive) - Input.get_action_strength(negative)


func _deadzone(v: float) -> float:
	if absf(v) < DEADZONE:
		return 0.0
	return signf(v) * (absf(v) - DEADZONE) / (1.0 - DEADZONE)


func _expo(v: float) -> float:
	var x := clampf(v, -1.0, 1.0)
	return clampf(((1.0 - STICK_EXPO) * x + STICK_EXPO * x * x * x) * Settings.stick_sensitivity, -1.0, 1.0)


## Creates the fc_* input actions at runtime (keyboard, physical keys) if the project does not define them.
func _ensure_actions() -> void:
	var keys := {
		"fc_pitch_up": KEY_W, "fc_pitch_down": KEY_S,
		"fc_roll_left": KEY_A, "fc_roll_right": KEY_D,
		"fc_yaw_left": KEY_Q, "fc_yaw_right": KEY_E,
		"fc_throttle_up": KEY_SHIFT, "fc_throttle_down": KEY_CTRL,
		"fc_afterburner": KEY_TAB, "fc_gun": KEY_SPACE,
		"fc_weapon": KEY_ENTER, "fc_cycle_weapon": KEY_F,
		"fc_cycle_target": KEY_T, "fc_flares": KEY_X,
		"fc_airbrake": KEY_B, "fc_gear": KEY_G,
		"fc_camera": KEY_V, "fc_look_back": KEY_C,
		"fc_pause": KEY_ESCAPE,
	}
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
