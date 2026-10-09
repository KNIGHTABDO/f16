class_name FlightOverlay
extends Control
## TEMPORARY minimal in-flight controls and HUD, so the first build is testable on a phone: a stick (thumb, left;
## right when Settings.left_handed), a throttle bar (opposite edge), a grid of buttons (fire, weapon, flares, gear,
## afterburner, airbrake, look back), a top row (menu, camera, gyro calibrate), and speed / altitude / g / heading text.
## Touch arrives through _input, so several fingers work at once. Touches that land on no control drag the aim point
## (arcade) and are left to the camera in orbit mode. The keyboard and mouse are handled by PlayerController.
## Layout units: u = a fraction of the screen height, so the controls scale with the phone.

const STICK_CENTER := Vector2(2.2, 2.2)  ## from the thumb-side corner, units u (x from left, y from bottom)
const STICK_RADIUS := 1.25  ## u
const STICK_RANGE := 0.8  ## knob travel, u
const KNOB_RADIUS := 0.42  ## u
const THROTTLE_X := 0.6  ## throttle track centre from the throttle-side edge, u
const THROTTLE_WIDTH := 0.5  ## u
const THROTTLE_TOP := 1.8  ## track top from the top edge, u
const THROTTLE_BOTTOM := 0.6  ## track bottom from the bottom edge, u
const HIT_SLOP := 0.15  ## extra margin around each button, u

## Buttons. x is from the right edge (negative = leftward), or from the left edge when Settings.left_handed.
## y is up from the bottom when "bottom" is true, down from the top otherwise. Units u.
const BUTTONS := [
	{"id": "fire", "label": "FIRE", "x": -2.0, "y": 1.4, "bottom": true, "r": 0.95},
	{"id": "wpn", "label": "WPN", "x": -3.9, "y": 1.4, "bottom": true, "hw": 0.7, "hh": 0.45},
	{"id": "gear", "label": "GEAR", "x": -5.8, "y": 1.4, "bottom": true, "hw": 0.7, "hh": 0.45},
	{"id": "flr", "label": "FLR", "x": -2.0, "y": 3.3, "bottom": true, "hw": 0.7, "hh": 0.45},
	{"id": "ab", "label": "AB", "x": -3.9, "y": 3.3, "bottom": true, "hw": 0.7, "hh": 0.45},
	{"id": "brk", "label": "BRK", "x": -5.8, "y": 3.3, "bottom": true, "hw": 0.7, "hh": 0.45},
	{"id": "menu", "label": "MENU", "x": -0.9, "y": 0.8, "bottom": false, "hw": 0.6, "hh": 0.45},
	{"id": "cam", "label": "CAM", "x": -2.7, "y": 0.8, "bottom": false, "hw": 0.7, "hh": 0.45},
	{"id": "cal", "label": "CAL", "x": -4.5, "y": 0.8, "bottom": false, "hw": 0.7, "hh": 0.45},
	{"id": "lb", "label": "LB", "x": -6.3, "y": 0.8, "bottom": false, "hw": 0.7, "hh": 0.45},
]

const TEXT_COLOR := Color(0.9, 0.97, 0.94, 0.92)
const LINE_COLOR := Color(1.0, 1.0, 1.0, 0.4)
const FILL_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const HELD_COLOR := Color(1.0, 1.0, 1.0, 0.42)
const ACTIVE_COLOR := Color(0.35, 0.9, 0.55, 0.42)
const WARN_COLOR := Color(1.0, 0.45, 0.35, 0.95)

var respawn_in := -1.0  ## set by the level: seconds until respawn while the player is down, -1 otherwise

var _controller: PlayerController
var _camera: FlightCamera
var _u := 60.0
var _stick_c := Vector2.ZERO
var _throttle_rect := Rect2()
var _layout_cache: Array[Dictionary] = []  ## button specs with their screen centre and size, rebuilt each frame
var _touches: Dictionary = {}  ## finger index -> "stick", "throttle", "aim" or a button id
var _font: Font


func setup(controller: PlayerController, camera: FlightCamera) -> void:
	_controller = controller
	_camera = camera


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	set_process_input(true)


func _process(_delta: float) -> void:
	_layout()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _controller == null:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_touch_drag(d.index, d.position, d.relative)


func _draw() -> void:
	if _controller == null:
		return
	var target: Aircraft = _camera.get_target() if _camera != null else null
	_draw_stick()
	_draw_throttle(target)
	for b in _layout_cache:
		_draw_button(b, target)
	_draw_hud(target)
	_draw_respawn()


## Recomputes the control positions from the current size and the handedness setting.
func _layout() -> void:
	var s := size
	_u = clampf(s.y / 6.5, 48.0, 120.0)
	var lh := Settings.left_handed
	var stick_x := (s.x - STICK_CENTER.x * _u) if lh else STICK_CENTER.x * _u
	_stick_c = Vector2(stick_x, s.y - STICK_CENTER.y * _u)
	var track_x := (THROTTLE_X * _u) if lh else (s.x - THROTTLE_X * _u)
	_throttle_rect = Rect2(
		track_x - THROTTLE_WIDTH * _u * 0.5, THROTTLE_TOP * _u,
		THROTTLE_WIDTH * _u, s.y - (THROTTLE_TOP + THROTTLE_BOTTOM) * _u)
	_layout_cache.clear()
	for spec: Dictionary in BUTTONS:
		var b := spec.duplicate()
		var bx: float = float(spec.x)
		var by: float = float(spec.y)
		var cx := (-bx * _u) if lh else (s.x + bx * _u)
		var cy := (s.y + by * _u) if bool(spec.bottom) else by * _u
		b["c"] = Vector2(cx, cy)
		b["r"] = float(spec.get("r", 0.0)) * _u
		b["half"] = Vector2(float(spec.get("hw", 0.0)), float(spec.get("hh", 0.0))) * _u
		_layout_cache.append(b)


func _hit(p: Vector2) -> String:
	if p.distance_to(_stick_c) <= (STICK_RADIUS + HIT_SLOP) * _u:
		return "stick"
	if _throttle_rect.grow(HIT_SLOP * _u).has_point(p):
		return "throttle"
	for b in _layout_cache:
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		if r > 0.0:
			if p.distance_to(c) <= r + HIT_SLOP * _u:
				return String(b["id"])
		else:
			var half: Vector2 = b["half"] + Vector2.ONE * HIT_SLOP * _u
			if absf(p.x - c.x) <= half.x and absf(p.y - c.y) <= half.y:
				return String(b["id"])
	return ""


func _touch_down(index: int, p: Vector2) -> void:
	var id := _hit(p)
	if id == "":
		_touches[index] = "aim"
		return
	_touches[index] = id
	get_viewport().set_input_as_handled()
	match id:
		"stick":
			_set_stick(p)
		"throttle":
			_set_throttle(p)
		"wpn":
			_controller.press_weapon()
		"flr":
			_controller.press_flares()
		"gear":
			_controller.press_gear()
		"ab":
			_controller.toggle_afterburner()
		"cam":
			_controller.press_camera()
		"cal":
			_controller.calibrate_gyro()
		"menu":
			_controller.pause_requested = true
	_sync_held()


func _touch_drag(index: int, p: Vector2, rel: Vector2) -> void:
	var id: String = _touches.get(index, "")
	match id:
		"":
			return
		"aim":
			if _controller.aim_drag_enabled:
				_controller.add_aim_drag(rel)
		"stick":
			get_viewport().set_input_as_handled()
			_set_stick(p)
		"throttle":
			get_viewport().set_input_as_handled()
			_set_throttle(p)
		_:
			get_viewport().set_input_as_handled()


func _touch_up(index: int) -> void:
	var id: String = _touches.get(index, "")
	if id == "":
		return
	_touches.erase(index)
	if id != "aim":
		get_viewport().set_input_as_handled()
	if id == "stick":
		_controller.touch_stick = Vector2.ZERO
	elif id == "throttle":
		_controller.touch_throttle = -1.0  ## hand the throttle back to the keys, it keeps its value
	_sync_held()


## Pushes the hold-type controls (fire, airbrake, look back, stick) from the current touches to the controller.
func _sync_held() -> void:
	_controller.touch_gun = _held("fire")
	_controller.set_airbrake(_held("brk"))
	_controller.set_look_back(_held("lb"))
	_controller.touch_stick_active = _held("stick")


func _held(id: String) -> bool:
	return _touches.values().has(id)


func _set_stick(p: Vector2) -> void:
	var d := (p - _stick_c) / (STICK_RANGE * _u)
	if d.length() > 1.0:
		d = d.normalized()
	_controller.touch_stick = Vector2(d.x, -d.y)  ## x = roll right, y = pitch up
	_controller.touch_stick_active = true


func _set_throttle(p: Vector2) -> void:
	var frac := 1.0 - (p.y - _throttle_rect.position.y) / maxf(_throttle_rect.size.y, 1.0)
	_controller.touch_throttle = clampf(frac, 0.0, 1.0)


func _draw_stick() -> void:
	var r := STICK_RADIUS * _u
	draw_circle(_stick_c, r, FILL_COLOR)
	draw_arc(_stick_c, r, 0.0, TAU, 48, LINE_COLOR, 2.0)
	var knob := _stick_c
	if _held("stick") and _controller.touch_stick_active:
		var s := _controller.touch_stick
		knob = _stick_c + Vector2(s.x, -s.y) * STICK_RANGE * _u
	draw_circle(knob, KNOB_RADIUS * _u, HELD_COLOR if _held("stick") else FILL_COLOR)


func _draw_throttle(target: Aircraft) -> void:
	var r := _throttle_rect
	draw_rect(r, FILL_COLOR, true)
	var frac := target.get_throttle() if target != null and is_instance_valid(target) else 0.0
	var fill_h := r.size.y * frac
	var fill := Rect2(r.position.x, r.position.y + r.size.y - fill_h, r.size.x, fill_h)
	var lit := target != null and target.is_afterburner()
	draw_rect(fill, ACTIVE_COLOR if lit else HELD_COLOR, true)
	draw_rect(r, LINE_COLOR, false, 2.0)
	_text("THR", Vector2(r.position.x + r.size.x * 0.5, r.position.y - 0.25 * _u), 14.0, TEXT_COLOR, r.size.x * 2.0)


func _draw_button(b: Dictionary, target: Aircraft) -> void:
	var id := String(b["id"])
	var c: Vector2 = b["c"]
	var r: float = b["r"]
	var half: Vector2 = b["half"]
	var fill := FILL_COLOR
	if _held(id):
		fill = HELD_COLOR
	elif _is_active(id, target):
		fill = ACTIVE_COLOR
	var fs := _font_size(0.24)
	if r > 0.0:
		draw_circle(c, r, fill)
		draw_arc(c, r, 0.0, TAU, 40, LINE_COLOR, 2.0)
		_text(String(b["label"]), c, fs, TEXT_COLOR, r * 2.0)
	else:
		var rect := Rect2(c - half, half * 2.0)
		draw_rect(rect, fill, true)
		draw_rect(rect, LINE_COLOR, false, 2.0)
		_text(String(b["label"]), c, fs, TEXT_COLOR, half.x * 2.0)


func _is_active(id: String, target: Aircraft) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	match id:
		"ab":
			return target.is_afterburner()
		"gear":
			return target.is_gear_down()
	return false


func _draw_hud(target: Aircraft) -> void:
	if target == null or not is_instance_valid(target):
		return
	var fs := _font_size(0.26)
	var line_h := fs * 1.35
	var x := 16.0
	var y := fs + 12.0
	var lines: Array[String] = [
		"IAS %d km/h   M %.2f" % [target.get_ias_kmh(), target.get_mach()],
		"ALT %d m ASL   AGL %d m" % [target.get_altitude_m(), target.get_agl_m()],
		"G %.1f   AOA %d deg   HDG %03d" % [target.get_g(), target.get_aoa_deg(), target.get_heading_deg()],
		"THR %d%%" % roundi(target.get_throttle() * 100.0),
	]
	for line in lines:
		_text(line, Vector2(x, y), fs, TEXT_COLOR, -1.0, HORIZONTAL_ALIGNMENT_LEFT)
		y += line_h
	var flags := PackedStringArray()
	flags.append("GEAR DOWN" if target.is_gear_down() else "GEAR UP")
	if target.is_afterburner():
		flags.append("AB")
	if target.is_stalling():
		flags.append("STALL")
	var flag_color := WARN_COLOR if target.is_stalling() else TEXT_COLOR
	_text(" ".join(flags), Vector2(x, y), fs, flag_color, -1.0, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_respawn() -> void:
	if respawn_in < 0.0:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.36)
	_text("DOWN", c, _font_size(0.5), WARN_COLOR, -1.0)
	_text("RESPAWN IN %d" % ceili(respawn_in), c + Vector2(0.0, _u * 0.7), _font_size(0.3), WARN_COLOR, -1.0)


func _font_size(scale_u: float) -> float:
	return clampf(_u * scale_u, 13.0, 56.0)


## Text centred on pos (or left-aligned from pos when align is LEFT). width -1 = no wrap.
func _text(s: String, pos: Vector2, fs: float, color: Color, width: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		var w := width if width > 0.0 else _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
		var origin := Vector2(pos.x - w * 0.5, pos.y + fs * 0.35)
		draw_string(_font, origin, s, HORIZONTAL_ALIGNMENT_CENTER, w, int(fs), color)
	else:
		draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), color)
