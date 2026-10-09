class_name TouchControls
extends Control
## Landscape multi-touch flight controls overlay.
## Features virtual analog stick with floating/fixed mode, throttle slider with afterburner detent,
## weapon fire, target cycling, flares, airbrake, gear, camera toggle, and pause.
## Multi-touch tracking, haptic feedback, customizable layout from Settings, and auto-hide with gamepad.

## Warm rims on the fire buttons; everything else keeps the cyan glass look.
const FIRE_RIM := {"gun": Color(1.0, 0.42, 0.3), "weapon": Color(1.0, 0.72, 0.3), "flares": Color(1.0, 0.85, 0.45)}
const BUTTON_CAPTION := {
	"gun": "GUN", "weapon": "MISSILE", "flares": "FLARES", "cycle_target": "TARGET", "cycle_weapon": "WEAPON",
	"airbrake": "BRAKE", "gear": "GEAR"
}

var _controller: PlayerController
var _camera: FlightCamera

# Active touches: touch_index -> control_id ("stick", "throttle", "aim", or button key)
var _active_touches: Dictionary = {}

# Stick state
var _stick_center := Vector2.ZERO
var _stick_drag_pos := Vector2.ZERO
var _stick_radius := 65.0
var _stick_touch_index := -1

# Throttle state
var _throttle_rect := Rect2()
var _throttle_val := 0.7
var _throttle_touch_index := -1
var _ab_detent := 0.85
var _ab_detent_tripped := false

# Layout cache: button_key -> {rect, center, radius, scale, opacity, label, icon}
var _button_specs: Dictionary = {}
var _icons: Dictionary = {}
var _font: Font
var _fade_alpha := 1.0


func setup(controller: PlayerController, camera: FlightCamera) -> void:
	_controller = controller
	_camera = camera


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = ThemeDB.fallback_font
	_load_icons()
	_rebuild_layout()
	Settings.changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


func _load_icons() -> void:
	var paths := {
		"gun": "res://assets/ui/icons/gun.png",
		"weapon": "res://assets/ui/icons/missile.png",
		"cycle_weapon": "res://assets/ui/icons/rocket.png",
		"cycle_target": "res://assets/ui/icons/radar.png",
		"flares": "res://assets/ui/icons/flare.png",
		"gear": "res://assets/ui/icons/gear.png",
		"camera": "res://assets/ui/icons/camera.png",
		"pause": "res://assets/ui/icons/pause.png",
		"radio": "res://assets/ui/icons/radio.png"
	}
	for k in paths:
		if ResourceLoader.exists(paths[k]):
			_icons[k] = load(paths[k])


func _on_settings_changed(_key: String) -> void:
	_rebuild_layout()


func _process(delta: float) -> void:
	# Auto-hide when gamepad is connected
	var pad_connected := Input.get_connected_joypads().size() > 0 and Settings.gamepad_enabled
	var target_alpha := 0.0 if pad_connected else 1.0
	_fade_alpha = move_toward(_fade_alpha, target_alpha, delta * 4.0)
	modulate.a = _fade_alpha

	if _controller != null:
		# Sync held states
		_controller.touch_gun = _is_held("gun")
		_controller.set_airbrake(_is_held("airbrake"))
		_controller.set_look_back(_is_held("look"))

		# Sync throttle from aircraft if not actively touched
		if _throttle_touch_index < 0 and _controller.aircraft != null and is_instance_valid(_controller.aircraft):
			_throttle_val = _controller.aircraft.get_throttle()

	queue_redraw()


func _rebuild_layout() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return

	var layout := HUDLayout.active_touch_layout(Settings.touch_layout)
	var rect := HUDLayout.safe_rect(vp)
	var is_left_handed := Settings.left_handed
	var stick_sz_mult := Settings.stick_size
	_button_specs.clear()

	for k in HUDLayout.TOUCH_DEFAULTS:
		var cfg: Dictionary = layout[k]
		var frac: Array = cfg.get("pos", [0.5, 0.5])
		var b_scale: float = float(cfg.get("scale", 1.0))
		var b_op: float = float(cfg.get("opacity", 0.6))
		var pos := HUDLayout.to_px(frac, rect, is_left_handed)

		if k == "stick":
			_stick_center = pos
			_stick_radius = HUDLayout.TOUCH_RADIUS["stick"] * b_scale * stick_sz_mult
			_button_specs[k] = {
				"center": pos,
				"radius": _stick_radius,
				"scale": b_scale,
				"opacity": b_op
			}
		elif k == "throttle":
			var tsz := HUDLayout.THROTTLE_SIZE * b_scale
			_throttle_rect = Rect2(pos - tsz * 0.5, tsz)
			_button_specs[k] = {
				"rect": _throttle_rect,
				"scale": b_scale,
				"opacity": b_op
			}
		else:
			var btn_r: float = HUDLayout.TOUCH_RADIUS[k] * b_scale
			_button_specs[k] = {
				"center": pos,
				"radius": btn_r,
				"scale": b_scale,
				"opacity": b_op
			}


func _input(event: InputEvent) -> void:
	if _controller == null or _fade_alpha <= 0.05:
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_touch_down(st.index, st.position)
		else:
			_on_touch_up(st.index)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_on_touch_drag(sd.index, sd.position, sd.relative)


func _on_touch_down(index: int, pos: Vector2) -> void:
	var hit_id := _hit_test(pos)
	if hit_id == "":
		# Tap on open screen: arcade aim drag
		_active_touches[index] = "aim"
		return

	_active_touches[index] = hit_id
	get_viewport().set_input_as_handled()

	match hit_id:
		"stick":
			_stick_touch_index = index
			_stick_drag_pos = pos
			_update_stick_deflection(pos)
			_haptic(0.4, 20)
		"throttle":
			_throttle_touch_index = index
			_update_throttle_position(pos)
			_haptic(0.4, 20)
		"gun":
			_controller.touch_gun = true
			_haptic(0.8, 30)
		"weapon":
			_controller.press_weapon()
			_haptic(0.7, 35)
		"cycle_weapon":
			_controller.press_cycle_weapon()
			_haptic(0.5, 25)
		"cycle_target":
			_controller.press_cycle_target()
			_haptic(0.5, 25)
		"flares":
			_controller.press_flares()
			_haptic(0.6, 30)
		"airbrake":
			_controller.set_airbrake(true)
			_haptic(0.5, 25)
		"gear":
			_controller.press_gear()
			_haptic(0.5, 25)
		"camera":
			_controller.press_camera()
			_haptic(0.5, 25)
		"look":
			_controller.set_look_back(true)
			_haptic(0.5, 25)
		"pause":
			_controller.pause_requested = true
			_haptic(0.6, 30)
		"radio":
			_on_radio_button_pressed()
			_haptic(0.5, 25)


func _on_touch_drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var id: String = _active_touches.get(index, "")
	match id:
		"aim":
			if _controller.aim_drag_enabled:
				_controller.add_aim_drag(rel)
		"stick":
			get_viewport().set_input_as_handled()
			_update_stick_deflection(pos)
		"throttle":
			get_viewport().set_input_as_handled()
			_update_throttle_position(pos)
		_:
			if id != "":
				get_viewport().set_input_as_handled()


func _on_touch_up(index: int) -> void:
	var id: String = _active_touches.get(index, "")
	if id == "":
		return

	_active_touches.erase(index)
	if id != "aim":
		get_viewport().set_input_as_handled()

	match id:
		"stick":
			_stick_touch_index = -1
			_stick_drag_pos = _stick_center
			_controller.touch_stick = Vector2.ZERO
			_controller.touch_stick_active = false
		"throttle":
			_throttle_touch_index = -1
			_controller.touch_throttle = -1.0  # Release back to keyboard/current setting
			_ab_detent_tripped = false
		"gun":
			_controller.touch_gun = false
		"airbrake":
			_controller.set_airbrake(false)
		"look":
			_controller.set_look_back(false)


func _hit_test(pos: Vector2) -> String:
	# Check stick
	if Settings.control_scheme != "gyro":
		if pos.distance_to(_stick_center) <= _stick_radius * 1.3:
			return "stick"

	# Check throttle
	if _throttle_rect.grow(16.0).has_point(pos):
		return "throttle"

	# Check other buttons
	for k in _button_specs:
		if k == "stick" or k == "throttle":
			continue
		var spec: Dictionary = _button_specs[k]
		var c: Vector2 = spec["center"]
		var r: float = spec["radius"]
		if pos.distance_to(c) <= r * 1.25:
			return k

	return ""


func _update_stick_deflection(pos: Vector2) -> void:
	var delta := pos - _stick_center
	var dist := delta.length()
	var max_r := _stick_radius

	if dist > max_r:
		delta = delta.normalized() * max_r

	_stick_drag_pos = _stick_center + delta
	var norm_x := delta.x / max_r
	var norm_y := -delta.y / max_r  # Positive = nose UP

	_controller.touch_stick = Vector2(norm_x, norm_y)
	_controller.touch_stick_active = true


func _update_throttle_position(pos: Vector2) -> void:
	var frac := 1.0 - (pos.y - _throttle_rect.position.y) / maxf(_throttle_rect.size.y, 1.0)
	frac = clampf(frac, 0.0, 1.0)
	_throttle_val = frac
	_controller.touch_throttle = frac

	# Afterburner detent haptic trip
	if frac >= _ab_detent and not _ab_detent_tripped:
		_ab_detent_tripped = true
		_haptic(0.9, 40)
		if _controller.aircraft != null and not _controller.aircraft.is_afterburner():
			_controller.toggle_afterburner()
	elif frac < _ab_detent - 0.05 and _ab_detent_tripped:
		_ab_detent_tripped = false


func _is_held(id: String) -> bool:
	return _active_touches.values().has(id)


func _haptic(strength: float, duration_ms: int) -> void:
	if Settings.haptics:
		Input.vibrate_handheld(duration_ms, strength * Settings.haptic_intensity)


func _on_radio_button_pressed() -> void:
	if Radio != null:
		Radio.toggle()


func _draw() -> void:
	if _fade_alpha <= 0.02:
		return

	# 1. Virtual Stick
	if Settings.control_scheme != "gyro" and _button_specs.has("stick"):
		_draw_stick()

	# 2. Throttle Slider with Afterburner Detent
	if _button_specs.has("throttle"):
		_draw_throttle()

	# 3. Action Buttons
	for k in _button_specs:
		if k == "stick" or k == "throttle":
			continue
		_draw_action_button(k)


func _draw_stick() -> void:
	var spec: Dictionary = _button_specs["stick"]
	var c := _stick_center
	var r := _stick_radius
	var op: float = spec["opacity"] * _fade_alpha

	# Base ring
	draw_circle(c, r, Color(0.02, 0.06, 0.07, 0.35 * op))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.45, 0.9, 1.0, 0.45 * op), 2.0, true)
	draw_arc(c, r * 0.5, 0.0, TAU, 48, Color(0.25, 0.82, 1.0, 0.18 * op), 1.0, true)

	# Crosshair axes
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.25, 0.82, 1.0, 0.15 * op), 1.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.25, 0.82, 1.0, 0.15 * op), 1.0)

	# Stick Knob
	var knob_p := _stick_drag_pos if _stick_touch_index >= 0 else _stick_center
	var knob_r := r * 0.42
	var knob_col := Color(0.35, 0.9, 0.55, 0.7 * op) if _stick_touch_index >= 0 else Color(0.25, 0.82, 1.0, 0.6 * op)
	draw_circle(knob_p, knob_r, knob_col)
	draw_arc(knob_p, knob_r, 0.0, TAU, 40, Color(1, 1, 1, 0.75 * op), 2.0, true)


func _draw_throttle() -> void:
	var spec: Dictionary = _button_specs["throttle"]
	var rect: Rect2 = _throttle_rect
	var op: float = spec["opacity"] * _fade_alpha

	# Background track
	draw_rect(rect, Color(0.02, 0.06, 0.07, 0.4 * op), true)
	draw_rect(rect, Color(0.45, 0.9, 1.0, 0.35 * op), false, 1.5)

	# Fill bar based on throttle value
	var fill_h := rect.size.y * _throttle_val
	var is_ab := (_throttle_val >= _ab_detent) or (_controller.aircraft != null and _controller.aircraft.is_afterburner())
	var fill_col := Color(1.0, 0.6, 0.1, 0.7 * op) if is_ab else Color(0.25, 0.82, 1.0, 0.6 * op)
	var fill_rect := Rect2(rect.position.x, rect.position.y + rect.size.y - fill_h, rect.size.x, fill_h)
	draw_rect(fill_rect, fill_col, true)

	# Afterburner Detent line (at 85%)
	var detent_y := rect.position.y + rect.size.y * (1.0 - _ab_detent)
	draw_line(Vector2(rect.position.x - 4, detent_y), Vector2(rect.position.x + rect.size.x + 4, detent_y), Color(1.0, 0.3, 0.2, 0.9 * op), 2.5)

	# Knob handle
	var knob_y := rect.position.y + rect.size.y - fill_h
	var knob_rect := Rect2(rect.position.x - 6, knob_y - 6, rect.size.x + 12, 12)
	draw_rect(knob_rect, Color(1, 1, 1, 0.85 * op), true)

	# Label
	var fs := int(12.0 * spec["scale"])
	var label_str := "AB" if is_ab else "THR"
	draw_string(_font, Vector2(rect.position.x, rect.position.y - 8), label_str, HORIZONTAL_ALIGNMENT_CENTER, int(rect.size.x), fs, Color(1, 1, 1, op))


func _draw_action_button(k: String) -> void:
	var spec: Dictionary = _button_specs[k]
	var c: Vector2 = spec["center"]
	var r: float = spec["radius"]
	var op: float = spec["opacity"] * _fade_alpha
	var held := _is_held(k)

	# Translucent glass disc with a soft inner ring; fire buttons get a warm rim so the thumb finds them blind
	var rim: Color = FIRE_RIM.get(k, Color(0.45, 0.9, 1.0))
	var bg_col := Color(rim.r * 0.35, rim.g * 0.35, rim.b * 0.35, 0.55 * op) if held else Color(0.02, 0.05, 0.07, 0.42 * op)
	var border_col := Color(rim, 0.95 * op) if held else Color(rim, 0.55 * op)

	draw_circle(c, r, bg_col)
	draw_arc(c, r, 0.0, TAU, 48, border_col, 2.0, true)
	draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(rim, 0.12 * op), 1.0, true)

	# Icon or short label
	var icon_tex: Texture2D = _icons.get(k)
	if icon_tex != null:
		var icon_sz := r * 1.0
		var icon_rect := Rect2(c - Vector2(icon_sz * 0.5, icon_sz * 0.5), Vector2(icon_sz, icon_sz))
		var icon_mod := Color(1, 1, 1, 0.95 * op) if held else Color(0.9, 0.95, 1.0, 0.8 * op)
		draw_texture_rect(icon_tex, icon_rect, false, icon_mod)
	else:
		var fs := int(maxf(r * 0.38, 11.0))
		var lbl: String = BUTTON_CAPTION.get(k, k.to_upper().substr(0, 4))
		draw_string(_font, Vector2(c.x - r, c.y + fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_CENTER, int(r * 2.0), fs, Color(1, 1, 1, 0.9 * op))
		return

	# Caption under the combat buttons (utility buttons in the top row are self-explanatory)
	if BUTTON_CAPTION.has(k):
		var cfs := 11
		draw_string(_font, Vector2(c.x - r, c.y + r + cfs + 3.0), BUTTON_CAPTION[k], HORIZONTAL_ALIGNMENT_CENTER, int(r * 2.0), cfs, Color(0.85, 0.95, 1.0, 0.75 * op))
