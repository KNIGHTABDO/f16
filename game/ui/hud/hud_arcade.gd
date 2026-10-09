class_name HUDArcade
extends Control
## Cleaner modern arcade flight overlay: aim reticle, lead indicator,
## target brackets with distance + health bar, off-screen target arrows,
## missile incoming arrows, simple speed/alt readouts, hit markers + kill feed.

var hud_color := Color("#3FD0FF")
var aircraft: Aircraft
var camera: FlightCamera
var controller: PlayerController
var units := "aviation"
var hud_scale := 1.0

# Targets & Combat data
var target_node: Node3D
var visible_targets: Array[Node3D] = []
var incoming_missiles: Array[Node3D] = []
var gun_lead_point := Vector3.ZERO
var lock_state := 0

# Hit marker state
var _hit_marker_time := 0.0
var _hit_marker_is_kill := false

# Kill feed entries: [{text, col, time}]
var _kill_feed: Array[Dictionary] = []

var _font: Font
var _pulse_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func trigger_hit_marker(is_kill: bool) -> void:
	_hit_marker_time = 0.3
	_hit_marker_is_kill = is_kill


func add_kill_feed(killer: String, victim: String, weapon: String) -> void:
	var text := "%s [%s] %s" % [killer.to_upper(), weapon.to_upper(), victim.to_upper()]
	_kill_feed.append({
		"text": text,
		"time": 4.0,
		"col": Color("#FFB020") if killer == "YOU" or killer == Settings.pilot_callsign else Color(0.9, 0.95, 1.0, 0.85)
	})
	if _kill_feed.size() > 5:
		_kill_feed.pop_front()


func update_data(delta: float) -> void:
	_pulse_timer += delta * 5.0
	if _hit_marker_time > 0.0:
		_hit_marker_time = maxf(0.0, _hit_marker_time - delta)

	# Update kill feed
	var i := _kill_feed.size() - 1
	while i >= 0:
		_kill_feed[i]["time"] -= delta
		if _kill_feed[i]["time"] <= 0.0:
			_kill_feed.remove_at(i)
		i -= 1

	queue_redraw()


func _draw() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return
	var cam: Camera3D = camera.get_camera() if camera != null else null
	if cam == null:
		return

	var vp_size := size
	var center := vp_size * 0.5
	var col := hud_color

	# 1. Aim Reticle
	_draw_aim_reticle(cam, center, col)

	# 2. Simple Speed / Alt Readouts
	_draw_simple_instruments(vp_size, col)

	# 3. Target Brackets & Lead Indicator
	_draw_targets(cam, vp_size, col)

	# 4. Incoming Missile Warning Arrows
	_draw_missile_warnings(cam, vp_size)

	# 5. Hit Markers
	if _hit_marker_time > 0.0:
		_draw_hit_marker(center)

	# 6. Kill Feed (Top Right)
	_draw_kill_feed(vp_size)


func _draw_aim_reticle(cam: Camera3D, screen_center: Vector2, col: Color) -> void:
	var reticle_pos := screen_center
	if controller != null and Settings.flight_mode == "arcade":
		var aim_world := aircraft.global_position + controller.get_aim_world() * 100.0
		if not cam.is_position_behind(aim_world):
			reticle_pos = cam.unproject_position(aim_world)

	var r := 22.0 * hud_scale
	# Outer circle with 4 notches
	draw_arc(reticle_pos, r, 0.0, TAU, 32, col, 1.8)
	draw_line(reticle_pos + Vector2(0, -r), reticle_pos + Vector2(0, -r - 6 * hud_scale), col, 2.0)
	draw_line(reticle_pos + Vector2(0, r), reticle_pos + Vector2(0, r + 6 * hud_scale), col, 2.0)
	draw_line(reticle_pos + Vector2(-r, 0), reticle_pos + Vector2(-r - 6 * hud_scale, 0), col, 2.0)
	draw_line(reticle_pos + Vector2(r, 0), reticle_pos + Vector2(r + 6 * hud_scale, 0), col, 2.0)
	# Center dot
	draw_circle(reticle_pos, 2.0 * hud_scale, col)

	# Lead indicator pip if locked target exists
	if gun_lead_point != Vector3.ZERO and not cam.is_position_behind(gun_lead_point):
		var lead_pos := cam.unproject_position(gun_lead_point)
		var lead_r := 12.0 * hud_scale
		var pip_col := Color("#3CFF6A") if reticle_pos.distance_to(lead_pos) < 20.0 else col
		draw_arc(lead_pos, lead_r, 0.0, TAU, 24, pip_col, 2.0)
		draw_circle(lead_pos, 2.5 * hud_scale, pip_col)
		# Dashed line connecting reticle to lead point
		draw_dashed_line(reticle_pos, lead_pos, Color(pip_col.r, pip_col.g, pip_col.b, 0.4), 1.2, 5.0)


func _draw_simple_instruments(vp_size: Vector2, col: Color) -> void:
	var fs_num := int(24.0 * hud_scale)
	var fs_unit := int(12.0 * hud_scale)

	# Left: Speed
	var spd_x := vp_size.x * 0.28
	var spd_y := vp_size.y * 0.5
	var spd_val := 0
	var spd_unit := "KM/H"
	match units:
		"aviation":
			spd_val = roundi(aircraft.get_ias_kmh() / 1.852)
			spd_unit = "KT"
		"metric":
			spd_val = roundi(aircraft.get_ias_kmh())
			spd_unit = "KM/H"
		"imperial":
			spd_val = roundi(aircraft.get_ias_kmh() / 1.60934)
			spd_unit = "MPH"

	draw_string(_font, Vector2(spd_x - 50 * hud_scale, spd_y), "%d" % spd_val, HORIZONTAL_ALIGNMENT_RIGHT, 80 * int(hud_scale), fs_num, col)
	draw_string(_font, Vector2(spd_x + 35 * hud_scale, spd_y), spd_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_unit, Color(col.r, col.g, col.b, 0.7))

	# Right: Altitude
	var alt_x := vp_size.x * 0.72
	var alt_y := vp_size.y * 0.5
	var alt_val := 0
	var alt_unit := "M"
	match units:
		"aviation", "imperial":
			alt_val = roundi(aircraft.get_altitude_m() * 3.28084)
			alt_unit = "FT"
		"metric":
			alt_val = roundi(aircraft.get_altitude_m())
			alt_unit = "M"

	draw_string(_font, Vector2(alt_x - 40 * hud_scale, alt_y), "%d" % alt_val, HORIZONTAL_ALIGNMENT_RIGHT, 90 * int(hud_scale), fs_num, col)
	draw_string(_font, Vector2(alt_x + 55 * hud_scale, alt_y), alt_unit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_unit, Color(col.r, col.g, col.b, 0.7))

	# Throttle bar on the left
	var thr_frac := aircraft.get_throttle()
	var thr_h := 80.0 * hud_scale
	var thr_w := 6.0 * hud_scale
	var thr_p := Vector2(spd_x - 70 * hud_scale, spd_y - thr_h * 0.5)
	draw_rect(Rect2(thr_p, Vector2(thr_w, thr_h)), Color(col.r, col.g, col.b, 0.2), true)
	var fill_h := thr_h * thr_frac
	var fill_col := Color("#FFAA00") if aircraft.is_afterburner() else col
	draw_rect(Rect2(thr_p.x, thr_p.y + thr_h - fill_h, thr_w, fill_h), fill_col, true)


func _draw_targets(cam: Camera3D, vp_size: Vector2, col: Color) -> void:
	var screen_margin := 40.0 * hud_scale
	var screen_rect := Rect2(screen_margin, screen_margin, vp_size.x - screen_margin * 2.0, vp_size.y - screen_margin * 2.0)
	var center := vp_size * 0.5

	# Draw all visible targets
	for tgt in visible_targets:
		if tgt == null or not is_instance_valid(tgt):
			continue
		var is_selected := (tgt == target_node)
		var is_behind := cam.is_position_behind(tgt.global_position)
		var screen_p := cam.unproject_position(tgt.global_position)
		var in_bounds := screen_rect.has_point(screen_p) and not is_behind

		var is_enemy := true
		if "team" in tgt:
			is_enemy = (int(tgt.get("team")) != aircraft.team)

		var t_col := Color("#FF4444") if is_enemy else Color("#3FD0FF")
		if is_selected:
			t_col = Color("#FFB020") if is_enemy else Color("#3CFF6A")

		var dist_m := aircraft.global_position.distance_to(tgt.global_position)
		var dist_str := "%.1f km" % (dist_m * 0.001)

		if in_bounds:
			# On-screen Tactical Bracket [ ]
			_draw_target_bracket(screen_p, tgt, t_col, is_selected, dist_str)
		elif is_enemy:
			# Off-screen Indicator Arrow
			_draw_offscreen_arrow(cam, tgt.global_position, vp_size, t_col, dist_str)


func _draw_target_bracket(p: Vector2, tgt: Node3D, col: Color, is_selected: bool, dist_str: String) -> void:
	var b_size := (24.0 if is_selected else 18.0) * hud_scale
	var tick := (8.0 if is_selected else 5.0) * hud_scale
	var thick := 2.5 if is_selected else 1.8

	# Top-left corner
	draw_line(p - Vector2(b_size, b_size), p - Vector2(b_size - tick, b_size), col, thick)
	draw_line(p - Vector2(b_size, b_size), p - Vector2(b_size, b_size - tick), col, thick)
	# Top-right corner
	draw_line(p + Vector2(b_size, -b_size), p + Vector2(b_size - tick, -b_size), col, thick)
	draw_line(p + Vector2(b_size, -b_size), p + Vector2(b_size, -b_size + tick), col, thick)
	# Bottom-left corner
	draw_line(p + Vector2(-b_size, b_size), p + Vector2(-b_size + tick, b_size), col, thick)
	draw_line(p + Vector2(-b_size, b_size), p + Vector2(-b_size, b_size - tick), col, thick)
	# Bottom-right corner
	draw_line(p + Vector2(b_size, b_size), p + Vector2(b_size - tick, b_size), col, thick)
	draw_line(p + Vector2(b_size, b_size), p + Vector2(b_size, b_size - tick), col, thick)

	# Health bar above bracket
	if "health" in tgt and "max_health" in tgt:
		var hp: float = float(tgt.get("health"))
		var max_hp: float = maxf(float(tgt.get("max_health")), 1.0)
		var hp_frac := clampf(hp / max_hp, 0.0, 1.0)

		var bar_w := b_size * 2.0
		var bar_h := 3.5 * hud_scale
		var bar_p := Vector2(p.x - b_size, p.y - b_size - 8 * hud_scale)
		draw_rect(Rect2(bar_p, Vector2(bar_w, bar_h)), Color(0.2, 0.2, 0.2, 0.6), true)
		var hp_col := Color("#3CFF6A").lerp(Color("#FF3838"), 1.0 - hp_frac)
		draw_rect(Rect2(bar_p, Vector2(bar_w * hp_frac, bar_h)), hp_col, true)

	# Distance label below bracket
	var fs := int(11.0 * hud_scale)
	draw_string(_font, Vector2(p.x - 25 * hud_scale, p.y + b_size + 14 * hud_scale), dist_str, HORIZONTAL_ALIGNMENT_CENTER, int(50 * hud_scale), fs, col)


func _draw_offscreen_arrow(cam: Camera3D, world_pos: Vector3, vp_size: Vector2, col: Color, dist_str: String) -> void:
	var center := vp_size * 0.5
	var cam_to_tgt := (world_pos - cam.global_position).normalized()

	# Project into camera local frame
	var cam_basis := cam.global_transform.basis
	var local_dir := cam_basis.inverse() * cam_to_tgt

	# Angle in screen space
	var angle := atan2(-local_dir.y, local_dir.x)
	var dir_2d := Vector2(cos(angle), sin(angle))

	# Clamp to edge
	var margin := 45.0 * hud_scale
	var max_x := center.x - margin
	var max_y := center.y - margin

	var scale_factor := 1.0
	if absf(dir_2d.x) * max_y > absf(dir_2d.y) * max_x:
		scale_factor = max_x / maxf(absf(dir_2d.x), 0.001)
	else:
		scale_factor = max_y / maxf(absf(dir_2d.y), 0.001)

	var arrow_pos := center + dir_2d * scale_factor

	# Draw chevron
	var tip := arrow_pos
	var left_wing := tip - dir_2d.rotated(0.55) * 16.0 * hud_scale
	var right_wing := tip - dir_2d.rotated(-0.55) * 16.0 * hud_scale
	draw_line(tip, left_wing, col, 2.5)
	draw_line(tip, right_wing, col, 2.5)

	# Distance text next to chevron
	var fs := int(10.0 * hud_scale)
	var text_offset := -dir_2d * 18.0 * hud_scale
	draw_string(_font, arrow_pos + text_offset - Vector2(20, -fs * 0.35), dist_str, HORIZONTAL_ALIGNMENT_CENTER, 40, fs, col)


func _draw_missile_warnings(cam: Camera3D, vp_size: Vector2) -> void:
	if incoming_missiles.is_empty():
		return

	var center := vp_size * 0.5
	var m_col := Color("#FF2020")
	var pulse := sin(_pulse_timer * 2.0) * 0.5 + 0.5
	m_col.a = lerpf(0.5, 1.0, pulse)

	for msl in incoming_missiles:
		if msl == null or not is_instance_valid(msl):
			continue
		var cam_to_msl := (msl.global_position - cam.global_position).normalized()
		var local_dir := cam.global_transform.basis.inverse() * cam_to_msl
		var angle := atan2(-local_dir.y, local_dir.x)
		var dir_2d := Vector2(cos(angle), sin(angle))

		var margin := 55.0 * hud_scale
		var max_x := center.x - margin
		var max_y := center.y - margin
		var scale_f := minf(max_x / maxf(absf(dir_2d.x), 0.001), max_y / maxf(absf(dir_2d.y), 0.001))
		var pos := center + dir_2d * scale_f

		# Flashing big red missile chevron
		var tip := pos
		var left_wing := tip - dir_2d.rotated(0.6) * 22.0 * hud_scale
		var right_wing := tip - dir_2d.rotated(-0.6) * 22.0 * hud_scale
		draw_line(tip, left_wing, m_col, 3.5)
		draw_line(tip, right_wing, m_col, 3.5)

		var fs := int(12.0 * hud_scale)
		draw_string(_font, pos - dir_2d * 24.0 * hud_scale - Vector2(30, -fs * 0.35), "MISSILE", HORIZONTAL_ALIGNMENT_CENTER, 60, fs, m_col)


func _draw_hit_marker(center: Vector2) -> void:
	var alpha := _hit_marker_time / 0.3
	var col := Color(1.0, 0.2, 0.2, alpha) if _hit_marker_is_kill else Color(1.0, 1.0, 1.0, alpha)
	var r := 16.0 * hud_scale
	var inner := 6.0 * hud_scale

	# 4 diagonal lines radiating from center
	draw_line(center + Vector2(-r, -r), center + Vector2(-inner, -inner), col, 2.5)
	draw_line(center + Vector2(r, -r), center + Vector2(inner, -inner), col, 2.5)
	draw_line(center + Vector2(-r, r), center + Vector2(-inner, inner), col, 2.5)
	draw_line(center + Vector2(r, r), center + Vector2(inner, inner), col, 2.5)


func _draw_kill_feed(vp_size: Vector2) -> void:
	var start_x := vp_size.x - 280.0 * hud_scale
	var start_y := 40.0 * hud_scale
	var line_h := 22.0 * hud_scale
	var fs := int(13.0 * hud_scale)

	for i in _kill_feed.size():
		var entry: Dictionary = _kill_feed[i]
		var col: Color = entry["col"]
		var t_left: float = entry["time"]
		if t_left < 0.5:
			col.a *= (t_left / 0.5)

		var y := start_y + i * line_h
		# Subtle background pill
		draw_rect(Rect2(start_x - 8, y - fs * 0.8, 270 * hud_scale, line_h - 2), Color(0.04, 0.08, 0.14, 0.65 * col.a), true)
		draw_string(_font, Vector2(start_x, y), entry["text"], HORIZONTAL_ALIGNMENT_LEFT, 260 * int(hud_scale), fs, col)
