class_name HUDRWR
extends Control
## Radar Warning Receiver (RWR) tactical scope.
## Tracks threats from group "radars" and incoming missiles.
## Displays 360-degree relative threat azimuth and plays audio warnings via Sfx.

var hud_color := Color("#3CFF6A")
var aircraft: Aircraft
var hud_scale := 1.0

# Active threats list: [{node, az, dist, kind, tracking, launched}]
var _threats: Array[Dictionary] = []
var _incoming_missiles: Array[Node3D] = []

var _scan_timer := 0.0
var _audio_ping_timer := 0.0
var _blink_timer := 0.0
var _blink_on := false
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(128, 128)
	size = custom_minimum_size


## True while any radar is painting us or a missile is inbound; the scope is hidden otherwise.
func has_threats() -> bool:
	return not _threats.is_empty() or not _incoming_missiles.is_empty()


func set_incoming_missiles(missiles: Array[Node3D]) -> void:
	_incoming_missiles = missiles


func update_rwr(delta: float) -> void:
	_blink_timer += delta * 6.0
	_blink_on = int(_blink_timer) % 2 == 0

	_audio_ping_timer = maxf(0.0, _audio_ping_timer - delta)
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.2  # 5 Hz threat scan to conserve CPU
		_scan_threats()

	queue_redraw()


func _scan_threats() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		_threats.clear()
		return

	var new_threats: Array[Dictionary] = []
	var has_new_lock := false

	# Query nodes in group 'radars'
	var radar_nodes := get_tree().get_nodes_in_group("radars")
	var own_pos := aircraft.global_position
	var ac_basis := aircraft.global_transform.basis

	for node in radar_nodes:
		if not is_instance_valid(node):
			continue
		var alive: bool = node.get("alive") if "alive" in node else true
		if not alive:
			continue

		# Check team if present
		if "team" in node and int(node.get("team")) == aircraft.team:
			continue

		var n3d := node as Node3D
		if n3d == null:
			continue

		var t_pos := n3d.global_position
		var delta_pos := t_pos - own_pos
		var dist := delta_pos.length()
		if dist > 45000.0:
			continue  # Out of RWR detection range

		# Calculate relative azimuth in aircraft frame (nose is -Z)
		var local_vec := ac_basis.inverse() * delta_pos
		var az := atan2(local_vec.x, -local_vec.z)  # 0 = ahead, PI/2 = right, PI = behind, -PI/2 = left

		var kind: String = "S"
		if node.has_method("get_target_kind"):
			var k: String = node.get_target_kind()
			match k:
				"sam": kind = "S"
				"aaa": kind = "A"
				"air": kind = "F"
				"ship": kind = "SH"
				_: kind = "R"

		var is_tracking: bool = node.get("tracking_player") if "tracking_player" in node else (dist < 15000.0)
		var is_launching: bool = node.get("launching_missile") if "launching_missile" in node else false

		new_threats.append({
			"node": node,
			"az": az,
			"dist": dist,
			"kind": kind,
			"tracking": is_tracking,
			"launching": is_launching
		})

		if is_tracking and _audio_ping_timer <= 0.0:
			has_new_lock = true

	_threats = new_threats

	# Audio ping on radar lock
	if has_new_lock and _audio_ping_timer <= 0.0:
		_audio_ping_timer = 2.5
		Sfx.play_2d("rwr_ping", -3.0)


func _draw() -> void:
	var r := (minf(size.x, size.y) * 0.5 - 6.0) * hud_scale
	var center := size * 0.5
	var col := hud_color

	# Scope Background circle
	draw_circle(center, r, Color(0.02, 0.06, 0.04, 0.65))

	# 3 Concentric Rings: Search (outer), Track (mid), Critical (inner)
	draw_arc(center, r, 0.0, TAU, 36, col, 1.8)
	draw_arc(center, r * 0.66, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.5), 1.2)
	draw_arc(center, r * 0.33, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 1.2)

	# Crosshairs (dashed)
	draw_dashed_line(center - Vector2(r, 0), center + Vector2(r, 0), Color(col.r, col.g, col.b, 0.35), 1.0, 4.0)
	draw_dashed_line(center - Vector2(0, r), center + Vector2(0, r), Color(col.r, col.g, col.b, 0.35), 1.0, 4.0)

	# Center Own Aircraft Chevron (pointing UP)
	var own_p := center
	var chev_pts := PackedVector2Array([
		own_p + Vector2(0, -6 * hud_scale),
		own_p + Vector2(5 * hud_scale, 5 * hud_scale),
		own_p + Vector2(0, 2 * hud_scale),
		own_p + Vector2(-5 * hud_scale, 5 * hud_scale)
	])
	draw_colored_polygon(chev_pts, col)

	# Draw Radar Threats
	var fs := int(12.0 * hud_scale)
	for t in _threats:
		var az: float = t["az"]
		var dist: float = t["dist"]
		var kind: String = t["kind"]
		var is_tracking: bool = t["tracking"]
		var is_launching: bool = t["launching"]

		# Determine ring placement based on threat status and distance
		var ring_frac := 0.85
		if is_launching:
			ring_frac = 0.25
		elif is_tracking:
			ring_frac = 0.52
		else:
			ring_frac = clampf(dist / 40000.0, 0.68, 0.92)

		var pos_2d := center + Vector2(sin(az), -cos(az)) * (r * ring_frac)
		var t_col := col
		if is_launching:
			t_col = Color("#FF2020")
		elif is_tracking:
			t_col = Color("#FFAA00")

		if is_launching and not _blink_on:
			continue  # Flashing critical threat

		# Draw threat symbol & surrounding diamond/box
		draw_rect(Rect2(pos_2d - Vector2(8, 8) * hud_scale, Vector2(16, 16) * hud_scale), t_col, false, 1.5)
		draw_string(_font, pos_2d - Vector2(7, -fs * 0.35), kind, HORIZONTAL_ALIGNMENT_CENTER, 14, fs, t_col)

		# If launching, draw strobe line to center
		if is_launching:
			draw_line(pos_2d, center, Color(1.0, 0.2, 0.2, 0.7), 1.5)

	# Draw Incoming Missiles
	for msl in _incoming_missiles:
		if msl == null or not is_instance_valid(msl):
			continue
		var m_delta := msl.global_position - aircraft.global_position
		var m_local := aircraft.global_transform.basis.inverse() * m_delta
		var m_az := atan2(m_local.x, -m_local.z)
		var m_pos := center + Vector2(sin(m_az), -cos(m_az)) * (r * 0.3)

		var m_col := Color("#FF2020")
		if _blink_on:
			draw_circle(m_pos, 7.0 * hud_scale, Color(1.0, 0.1, 0.1, 0.4))
			draw_arc(m_pos, 7.0 * hud_scale, 0.0, TAU, 16, m_col, 2.0)
			draw_string(_font, m_pos - Vector2(6, -fs * 0.35), "M", HORIZONTAL_ALIGNMENT_CENTER, 12, fs, m_col)
			draw_line(m_pos, center, m_col, 2.0)
