class_name HUDRealistic
extends Control
## F-16 style collimated green HUD drawn with _draw() projected to the camera.
## Renders pitch ladder, flight path marker, heading tape, speed + altitude tapes,
## G, Mach, AOA, waterline, gun funnel / lead pip, missile seeker + lock diamond,
## target box + range + closure rate, and bomb CCIP pipper.

var hud_color := Color("#3CFF6A")
var aircraft: Aircraft
var camera: FlightCamera
var units := "aviation"  # "aviation", "metric", "imperial"
var hud_scale := 1.0
var is_cockpit := false
var hud_glass_rect := Rect2()

# Combat / duck-typed inputs
var target_node: Node3D
var lock_state := 0  # 0 none, 1 seeking, 2 locking, 3 locked
var lock_progress := 0.0
var gun_lead_point := Vector3.ZERO
var ccip_point := Vector3.INF
var closure_rate := 0.0
var selected_weapon_type := "gun"  # "gun", "missile", "bomb", "rocket"
var selected_weapon_name := "M61A1"
var in_range := false

var _font: Font
var _blink_timer := 0.0
var _blink_state := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func update_data(delta: float) -> void:
	_blink_timer += delta * 6.0
	_blink_state = int(_blink_timer) % 2 == 0
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

	# Waterline / Aircraft boresight reference
	var nose_world := aircraft.global_position + aircraft.get_nose() * 100.0
	var waterline_screen := center
	var waterline_valid := false
	if not cam.is_position_behind(nose_world):
		waterline_screen = cam.unproject_position(nose_world)
		waterline_valid = true

	# Flight Path Marker (Velocity Vector)
	var vel := aircraft.get_velocity()
	var fpm_screen := waterline_screen
	var fpm_valid := false
	if vel.length() > 5.0:
		var fpm_world := aircraft.global_position + vel.normalized() * 100.0
		if not cam.is_position_behind(fpm_world):
			fpm_screen = cam.unproject_position(fpm_world)
			fpm_valid = true

	# Clip rect if in cockpit optical glass
	if is_cockpit and hud_glass_rect.size.x > 0:
		# Draw subtle optical glass boundary
		draw_rect(hud_glass_rect, Color(col.r, col.g, col.b, 0.03), true)
		draw_rect(hud_glass_rect, Color(col.r, col.g, col.b, 0.25), false, 1.5)

	# 1. Waterline symbol (_/\_)
	if waterline_valid:
		_draw_waterline(waterline_screen, col)

	# 2. Flight Path Marker (FPM)
	if fpm_valid:
		_draw_fpm(fpm_screen, col)

	# 3. Pitch Ladder
	var pitch_center := fpm_screen if fpm_valid else waterline_screen
	_draw_pitch_ladder(cam, pitch_center, col)

	# 4. Heading Tape (top of HUD, under the status line)
	_draw_heading_tape(vp_size, col)

	# 5. Speed & altitude tapes at fixed screen positions, with G / Mach / AOA and radar altimeter
	_draw_tapes(vp_size, col)

	# 7. Weapons cues: Gun lead pip / funnel, Missile seeker / diamond, Bomb CCIP
	_draw_weapons_overlay(cam, waterline_screen, fpm_screen, col)

	# 8. Target box & Range & Closure rate
	if target_node != null and is_instance_valid(target_node):
		_draw_target_cue(cam, col)


func _draw_waterline(pos: Vector2, col: Color) -> void:
	var w := 14.0 * hud_scale
	var wing := 16.0 * hud_scale
	var h := 7.0 * hud_scale
	# Left bar
	draw_line(pos + Vector2(-w - wing, 0), pos + Vector2(-w, 0), col, 2.0)
	# Center chevron _/\_
	draw_line(pos + Vector2(-w, 0), pos + Vector2(0, -h), col, 2.0)
	draw_line(pos + Vector2(0, -h), pos + Vector2(w, 0), col, 2.0)
	# Right bar
	draw_line(pos + Vector2(w, 0), pos + Vector2(w + wing, 0), col, 2.0)


func _draw_fpm(pos: Vector2, col: Color) -> void:
	var r := 9.0 * hud_scale
	var fin := 13.0 * hud_scale
	# Circle
	draw_arc(pos, r, 0.0, TAU, 24, col, 2.0)
	# Left wing
	draw_line(pos + Vector2(-r, 0), pos + Vector2(-r - fin, 0), col, 2.0)
	# Right wing
	draw_line(pos + Vector2(r, 0), pos + Vector2(r + fin, 0), col, 2.0)
	# Top rudder fin
	draw_line(pos + Vector2(0, -r), pos + Vector2(0, -r - fin * 0.75), col, 2.0)


func _draw_pitch_ladder(cam: Camera3D, ref_pos: Vector2, col: Color) -> void:
	var roll_deg := aircraft.get_roll_deg()
	var pitch_deg := aircraft.get_pitch_deg()
	var roll_rad := deg_to_rad(roll_deg)
	var cos_r := cos(-roll_rad)
	var sin_r := sin(-roll_rad)

	# Pixel scale per degree of pitch based on camera vertical FOV
	var fov_rad := deg_to_rad(cam.fov)
	var px_per_deg := (size.y * 0.5) / tan(fov_rad * 0.5) * deg_to_rad(1.0)
	px_per_deg *= hud_scale

	# Horizon Line (0 deg)
	var horizon_y_offset := -pitch_deg * px_per_deg
	var h_center := ref_pos + Vector2(-sin_r * horizon_y_offset, cos_r * horizon_y_offset)
	var h_half := 130.0 * hud_scale
	var gap := 24.0 * hud_scale

	var dir_x := Vector2(cos_r, sin_r)
	# Left horizon line
	draw_line(h_center - dir_x * h_half, h_center - dir_x * gap, col, 2.5)
	# Right horizon line
	draw_line(h_center + dir_x * gap, h_center + dir_x * h_half, col, 2.5)

	# Draw ladder rungs every 5 degrees between -85 and +85
	var min_rung := clampi(int(pitch_deg - 25.0) / 5 * 5, -85, 85)
	var max_rung := clampi(int(pitch_deg + 25.0) / 5 * 5, -85, 85)

	for deg in range(min_rung, max_rung + 1, 5):
		if deg == 0:
			continue
		var delta_pitch := float(deg) - pitch_deg
		var y_off := -delta_pitch * px_per_deg
		var rung_center := ref_pos + Vector2(-sin_r * y_off, cos_r * y_off)

		# Screen boundary clamp check
		if rung_center.distance_to(ref_pos) > 280.0 * hud_scale:
			continue

		var rung_len := 75.0 * hud_scale
		var rung_gap := 20.0 * hud_scale
		var notch_h := (7.0 if deg > 0 else -7.0) * hud_scale
		var notch_dir := Vector2(-sin_r, cos_r) * (1.0 if deg > 0 else -1.0)

		# Positive = solid lines angled slightly toward horizon. Negative = dashed lines
		if deg > 0:
			# Positive pitch rung (left and right)
			var p_l_in := rung_center - dir_x * rung_gap
			var p_l_out := rung_center - dir_x * rung_len
			var p_r_in := rung_center + dir_x * rung_gap
			var p_r_out := rung_center + dir_x * rung_len

			draw_line(p_l_in, p_l_out, col, 1.8)
			draw_line(p_r_in, p_r_out, col, 1.8)
			# Downward notches toward horizon
			draw_line(p_l_out, p_l_out + notch_dir * 8.0, col, 1.8)
			draw_line(p_r_out, p_r_out + notch_dir * 8.0, col, 1.8)
		else:
			# Negative pitch rung (dashed)
			var segments := 3
			var step := (rung_len - rung_gap) / float(segments)
			for s in segments:
				var t0 := rung_gap + step * (s + 0.15)
				var t1 := rung_gap + step * (s + 0.85)
				draw_line(rung_center - dir_x * t0, rung_center - dir_x * t1, col, 1.8)
				draw_line(rung_center + dir_x * t0, rung_center + dir_x * t1, col, 1.8)
			# Upward notches toward horizon
			var p_l_out := rung_center - dir_x * rung_len
			var p_r_out := rung_center + dir_x * rung_len
			draw_line(p_l_out, p_l_out + notch_dir * 8.0, col, 1.8)
			draw_line(p_r_out, p_r_out + notch_dir * 8.0, col, 1.8)

		# Pitch number at outer ends
		var num_str := str(abs(deg))
		var fs := int(12.0 * hud_scale)
		draw_string(_font, rung_center - dir_x * (rung_len + 18.0 * hud_scale) + Vector2(0, fs * 0.35), num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)
		draw_string(_font, rung_center + dir_x * (rung_len + 8.0 * hud_scale) + Vector2(0, fs * 0.35), num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)

	# Zenith (+90 deg) & Nadir (-90 deg)
	if absf(pitch_deg - 90.0) < 30.0:
		var z_off := -(90.0 - pitch_deg) * px_per_deg
		var z_pos := ref_pos + Vector2(-sin_r * z_off, cos_r * z_off)
		draw_circle(z_pos, 8.0 * hud_scale, Color(col.r, col.g, col.b, 0.3))
		draw_arc(z_pos, 8.0 * hud_scale, 0.0, TAU, 16, col, 1.8)
		draw_line(z_pos - Vector2(12, 0), z_pos + Vector2(12, 0), col, 1.5)
		draw_line(z_pos - Vector2(0, 12), z_pos + Vector2(0, 12), col, 1.5)
	elif absf(pitch_deg - (-90.0)) < 30.0:
		var n_off := -(-90.0 - pitch_deg) * px_per_deg
		var n_pos := ref_pos + Vector2(-sin_r * n_off, cos_r * n_off)
		draw_arc(n_pos, 8.0 * hud_scale, 0.0, TAU, 16, col, 1.8)
		draw_circle(n_pos, 2.5 * hud_scale, col)


func _draw_heading_tape(vp_size: Vector2, col: Color) -> void:
	var hdg := aircraft.get_heading_deg()
	var tape_y := HUDLayout.safe_rect(vp_size).position.y + 52.0 * hud_scale
	var tape_w := 340.0 * hud_scale
	var tape_left := (vp_size.x - tape_w) * 0.5
	var tape_center_x := vp_size.x * 0.5
	var px_per_deg := 6.5 * hud_scale

	# Center index inverted caret (^)
	var caret_p := Vector2(tape_center_x, tape_y + 12.0 * hud_scale)
	draw_line(caret_p, caret_p + Vector2(-6, 8) * hud_scale, col, 2.0)
	draw_line(caret_p, caret_p + Vector2(6, 8) * hud_scale, col, 2.0)
	draw_line(caret_p + Vector2(-6, 8) * hud_scale, caret_p + Vector2(6, 8) * hud_scale, col, 2.0)

	# Main horizontal baseline
	draw_line(Vector2(tape_left, tape_y), Vector2(tape_left + tape_w, tape_y), col, 1.8)

	# Ticks & labels
	var f_hdg := hdg
	var min_deg := int(f_hdg - 25.0)
	var max_deg := int(f_hdg + 25.0)

	for d in range(min_deg, max_deg + 1):
		var deg_norm := int(wrapf(float(d), 0.0, 360.0))
		if deg_norm % 5 != 0:
			continue
		var offset_x := (float(d) - f_hdg) * px_per_deg
		var tick_x := tape_center_x + offset_x
		if tick_x < tape_left or tick_x > tape_left + tape_w:
			continue

		var is_major := deg_norm % 10 == 0
		var tick_h := (12.0 if is_major else 6.0) * hud_scale
		draw_line(Vector2(tick_x, tape_y), Vector2(tick_x, tape_y - tick_h), col, 1.8)

		if is_major:
			var label := "%02d" % (deg_norm / 10)
			var fs := int(12.0 * hud_scale)
			draw_string(_font, Vector2(tick_x - 10 * hud_scale, tape_y - tick_h - 4 * hud_scale), label, HORIZONTAL_ALIGNMENT_CENTER, 20 * int(hud_scale), fs, col)


## Speed and altitude tapes at fixed side positions (mid-height), same layout as the arcade HUD.
## Radar altimeter sits under the altitude tape; M / G / AOA stack under the speed tape.
func _draw_tapes(vp_size: Vector2, col: Color) -> void:
	var s := hud_scale
	var tape_h := 240.0 * s
	var tape_w := 76.0 * s
	# Inboard of the gear and cycle buttons, and above the middle so the lower-right buttons stay clear
	var mid := vp_size.y * 0.42
	var spd_rect := Rect2(vp_size.x * 0.28 - tape_w * 0.5, mid - tape_h * 0.5, tape_w, tape_h)
	var alt_rect := Rect2(vp_size.x * 0.72 - tape_w * 0.5, mid - tape_h * 0.5, tape_w, tape_h)

	if Settings.hud_show_tapes:
		HUDTapes.draw_speed(self, _font, spd_rect, HUDTapes.speed_value(aircraft.get_ias_kmh(), units), units, col, s)
		HUDTapes.draw_altitude(self, _font, alt_rect, HUDTapes.alt_value(aircraft.get_altitude_m(), units), units, col, s)

	# Radar altimeter below the altitude tape (when below 1500 m / 5000 ft)
	var agl_m := aircraft.get_agl_m()
	if agl_m <= 1500.0 and agl_m >= 0.0:
		var r_fs := int(13.0 * s)
		draw_string(_font, Vector2(alt_rect.position.x, alt_rect.end.y + 16.0 * s), "R %d" % roundi(HUDTapes.alt_value(agl_m, units)), HORIZONTAL_ALIGNMENT_CENTER, int(tape_w), r_fs, col)

	# Flight parameters stacked under the speed tape
	var fs := int(14.0 * s)
	var line_h := fs * 1.3
	var left_x := spd_rect.position.x
	var left_y := spd_rect.end.y + 22.0 * s
	draw_string(_font, Vector2(left_x, left_y), "M %.2f" % aircraft.get_mach(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(_font, Vector2(left_x, left_y + line_h), "G %.1f" % aircraft.get_g(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(_font, Vector2(left_x, left_y + line_h * 2), "α %.1f°" % aircraft.get_aoa_deg(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_weapons_overlay(cam: Camera3D, waterline: Vector2, fpm: Vector2, col: Color) -> void:
	match selected_weapon_type:
		"gun":
			# Gun funnel or lead pip
			if gun_lead_point != Vector3.ZERO and not cam.is_position_behind(gun_lead_point):
				var pip_screen := cam.unproject_position(gun_lead_point)
				# Lead pip: circle with center dot
				draw_circle(pip_screen, 2.5 * hud_scale, col)
				draw_arc(pip_screen, 12.0 * hud_scale, 0.0, TAU, 24, col, 2.0)
				# Small connecting cue line from waterline to pip
				draw_line(waterline, pip_screen, Color(col.r, col.g, col.b, 0.4), 1.0)
			else:
				# Default gun funnel lines (funnel wingspan narrowing toward range)
				var f_top := waterline + Vector2(0, 15 * hud_scale)
				var f_bot := waterline + Vector2(0, 120 * hud_scale)
				draw_line(f_top + Vector2(-35, 0) * hud_scale, f_bot + Vector2(-12, 0) * hud_scale, col, 1.5)
				draw_line(f_top + Vector2(35, 0) * hud_scale, f_bot + Vector2(12, 0) * hud_scale, col, 1.5)

		"missile":
			# Missile Seeker Circle (Boresight or target-cued)
			var seeker_center := waterline
			if target_node != null and is_instance_valid(target_node):
				if not cam.is_position_behind(target_node.global_position):
					seeker_center = cam.unproject_position(target_node.global_position)

			var seeker_r := 60.0 * hud_scale
			draw_arc(seeker_center, seeker_r, 0.0, TAU, 36, col, 1.8)

			# Lock diamond around target
			if lock_state >= 2:
				var diamond_r := 18.0 * hud_scale
				var d_col := col
				if lock_state == 2 and not _blink_state:
					d_col = Color(col.r, col.g, col.b, 0.3)  # Blinking while acquiring

				var pts := PackedVector2Array([
					seeker_center + Vector2(0, -diamond_r),
					seeker_center + Vector2(diamond_r, 0),
					seeker_center + Vector2(0, diamond_r),
					seeker_center + Vector2(-diamond_r, 0),
					seeker_center + Vector2(0, -diamond_r)
				])
				draw_polyline(pts, d_col, 2.2)

				# Range launch bar (DLZ) on right of diamond
				var dlz_x := seeker_center.x + diamond_r + 14 * hud_scale
				var dlz_top := seeker_center.y - 30 * hud_scale
				var dlz_bot := seeker_center.y + 30 * hud_scale
				draw_line(Vector2(dlz_x, dlz_top), Vector2(dlz_x, dlz_bot), col, 1.5)
				# Rmax, Rtr, Rmin notches
				draw_line(Vector2(dlz_x, dlz_top), Vector2(dlz_x + 6, dlz_top), col, 1.5)
				draw_line(Vector2(dlz_x, dlz_top + 20 * hud_scale), Vector2(dlz_x + 6, dlz_top + 20 * hud_scale), col, 1.5)
				draw_line(Vector2(dlz_x, dlz_bot), Vector2(dlz_x + 6, dlz_bot), col, 1.5)

				if lock_state == 3:
					# Solid lock: SHOOT cue
					var shoot_fs := int(15.0 * hud_scale)
					draw_string(_font, Vector2(seeker_center.x - 30 * hud_scale, seeker_center.y + diamond_r + 18 * hud_scale), "SHOOT", HORIZONTAL_ALIGNMENT_CENTER, int(60 * hud_scale), shoot_fs, col)

		"bomb", "guided_bomb", "rocket":
			# CCIP Pipper (Continuously Computed Impact Point)
			if ccip_point != Vector3.INF and not cam.is_position_behind(ccip_point):
				var ccip_screen := cam.unproject_position(ccip_point)
				# Bomb fall line: connecting FPM to CCIP pipper
				draw_dashed_line(fpm, ccip_screen, col, 1.8, 6.0 * hud_scale)
				# Pipper circle + dot
				draw_circle(ccip_screen, 3.0 * hud_scale, col)
				draw_arc(ccip_screen, 14.0 * hud_scale, 0.0, TAU, 24, col, 2.0)
				# Crosshairs on pipper
				draw_line(ccip_screen - Vector2(18, 0) * hud_scale, ccip_screen + Vector2(18, 0) * hud_scale, col, 1.5)
				draw_line(ccip_screen - Vector2(0, 18) * hud_scale, ccip_screen + Vector2(0, 18) * hud_scale, col, 1.5)


func _draw_target_cue(cam: Camera3D, col: Color) -> void:
	if cam.is_position_behind(target_node.global_position):
		return
	var tgt_pos := cam.unproject_position(target_node.global_position)
	var box_half := 18.0 * hud_scale

	# Target Box with corner ticks
	var b_rect := Rect2(tgt_pos - Vector2(box_half, box_half), Vector2(box_half * 2.0, box_half * 2.0))
	draw_rect(b_rect, col, false, 2.0)

	# Distance to target
	var dist_m := aircraft.global_position.distance_to(target_node.global_position)
	var dist_str := ""
	if units == "metric":
		dist_str = "%.1f KM" % (dist_m * 0.001)
	else:
		dist_str = "%.1f NM" % (dist_m / 1852.0)

	var fs := int(12.0 * hud_scale)
	draw_string(_font, Vector2(tgt_pos.x - 30 * hud_scale, tgt_pos.y + box_half + 14 * hud_scale), dist_str, HORIZONTAL_ALIGNMENT_CENTER, int(60 * hud_scale), fs, col)

	# Closure Rate (Vc)
	var vc_str := "VC %+.0f" % closure_rate
	draw_string(_font, Vector2(tgt_pos.x - 35 * hud_scale, tgt_pos.y - box_half - 4 * hud_scale), vc_str, HORIZONTAL_ALIGNMENT_CENTER, int(70 * hud_scale), fs, col)
