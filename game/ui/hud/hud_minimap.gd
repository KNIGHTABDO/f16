class_name HUDMinimap
extends Control
## Tactical minimap rendering map satellite color texture, units, and targets.
## Rotates with aircraft heading and supports zoom levels.

var hud_color := Color("#3CFF6A")
var aircraft: Aircraft
var hud_scale := 1.0

var _map_texture: Texture2D
var _map_id := ""
var _units_cache: Array[Dictionary] = []
var _scan_timer := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(138, 138)
	size = custom_minimum_size
	_load_map_texture()


func _load_map_texture() -> void:
	var id := Ground.map_id if Ground.map_id != "" else GameState.selected_map
	if id == "" or id == _map_id:
		return
	_map_id = id
	var path := "res://assets/maps/%s/color.jpg" % id
	if ResourceLoader.exists(path):
		_map_texture = load(path)
	elif Ground.meta.has("color_file") and ResourceLoader.exists(Ground.meta["color_file"]):
		_map_texture = load(Ground.meta["color_file"])


func update_minimap(delta: float) -> void:
	if not Settings.hud_show_minimap:
		visible = false
		return
	visible = true

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.25  # 4 Hz unit scan
		_scan_units()

	queue_redraw()


func _scan_units() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		_units_cache.clear()
		return

	var units: Array[Dictionary] = []
	var own_pos := aircraft.global_position
	var own_team := aircraft.team

	# Scan damageables
	for node in get_tree().get_nodes_in_group("damageable"):
		if not is_instance_valid(node) or node == aircraft:
			continue
		var n3d := node as Node3D
		if n3d == null:
			continue

		var pos := n3d.global_position
		var delta_pos := pos - own_pos
		var dist := delta_pos.length()
		if dist > 35000.0:
			continue

		var team: int = int(node.get("team")) if "team" in node else 1
		var is_enemy := (team != own_team)
		var is_air := true
		if node.has_method("get_target_kind"):
			is_air = (node.get_target_kind() == "air" or node.get_target_kind() == "helicopter")

		units.append({
			"node": node,
			"pos": pos,
			"is_enemy": is_enemy,
			"is_air": is_air
		})

	_units_cache = units


func _draw() -> void:
	if aircraft == null or not is_instance_valid(aircraft):
		return

	var r := (minf(size.x, size.y) * 0.5 - 6.0) * hud_scale
	var center := size * 0.5
	var col := hud_color

	# Map Range based on zoom setting
	var zoom := Settings.hud_minimap_zoom
	var range_m := 16000.0 / maxf(zoom, 0.2)

	# 1. Background dark circle
	draw_circle(center, r, Color(0.01, 0.04, 0.03, 0.8))

	# 2. Draw satellite terrain texture (UV rotated by heading)
	if _map_texture != null and Ground.size_m > 0.0:
		_draw_satellite_map(center, r, range_m)

	# 3. Outer Ring and Distance Ticks
	draw_arc(center, r, 0.0, TAU, 48, col, 2.0)
	draw_arc(center, r * 0.5, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.35), 1.0)

	# 4. Compass Cardinal Direction Marks (N, E, S, W) rotated with heading
	var hdg_rad := deg_to_rad(aircraft.get_heading_deg())
	var cardinals: Array[Dictionary] = [
		{"label": "N", "angle": 0.0, "col": Color("#FF4444")},
		{"label": "E", "angle": PI * 0.5, "col": col},
		{"label": "S", "angle": PI, "col": col},
		{"label": "W", "angle": PI * 1.5, "col": col}
	]
	var fs := int(11.0 * hud_scale)
	for c in cardinals:
		var rel_ang: float = c["angle"] - hdg_rad
		var p := center + Vector2(sin(rel_ang), -cos(rel_ang)) * (r - 12 * hud_scale)
		draw_string(_font, p - Vector2(5, -fs * 0.35), c["label"], HORIZONTAL_ALIGNMENT_CENTER, 10, fs, c["col"])

	# 5. Draw Blips for Units and Targets
	var ac_basis := aircraft.global_transform.basis
	for u in _units_cache:
		var u_pos: Vector3 = u["pos"]
		var delta_pos := u_pos - aircraft.global_position
		# Transform to aircraft local coordinates (nose = -Z, right = +X)
		var local_vec := ac_basis.inverse() * delta_pos
		var map_offset := Vector2(local_vec.x, local_vec.z) / range_m * r

		var is_clamped := map_offset.length() > r - 6.0
		if is_clamped:
			map_offset = map_offset.normalized() * (r - 6.0)

		var blip_pos := center + map_offset
		var is_enemy: bool = u["is_enemy"]
		var b_col := Color("#FF3838") if is_enemy else Color("#3FD0FF")

		if u["is_air"]:
			# Airplane chevron / diamond
			draw_circle(blip_pos, 3.5 * hud_scale, b_col)
		else:
			# Ground unit square
			draw_rect(Rect2(blip_pos - Vector2(3, 3) * hud_scale, Vector2(6, 6) * hud_scale), b_col, true)

	# 6. Own Aircraft Chevron in Center (pointing UP)
	var own_pts := PackedVector2Array([
		center + Vector2(0, -8 * hud_scale),
		center + Vector2(6 * hud_scale, 6 * hud_scale),
		center + Vector2(0, 3 * hud_scale),
		center + Vector2(-6 * hud_scale, 6 * hud_scale)
	])
	draw_colored_polygon(own_pts, Color("#FFFFFF"))
	draw_polyline(own_pts, col, 1.5)


func _draw_satellite_map(center: Vector2, r: float, range_m: float) -> void:
	var wx := WorldOrigin.world_x(aircraft.position.x)
	var wz := WorldOrigin.world_z(aircraft.position.z)
	var size_m := Ground.size_m

	var u_center := (wx / size_m) + 0.5
	var v_center := (wz / size_m) + 0.5
	var uv_radius := range_m / size_m

	var hdg_rad := deg_to_rad(aircraft.get_heading_deg())

	# Create a circular mesh of textured triangles inside the radius
	var segments := 24
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()

	# Center vertex
	pts.append(center)
	uvs.append(Vector2(u_center, v_center))
	colors.append(Color(1, 1, 1, 0.45))

	for i in range(segments + 1):
		var theta := float(i) / float(segments) * TAU
		var p_screen := center + Vector2(sin(theta), -cos(theta)) * r
		pts.append(p_screen)

		# Rotate UV sampling by aircraft heading
		var uv_theta := theta + hdg_rad
		var u := u_center + sin(uv_theta) * uv_radius
		var v := v_center + cos(uv_theta) * uv_radius
		uvs.append(Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0)))
		colors.append(Color(1, 1, 1, 0.45))

	# Draw triangle fan
	var indices := PackedInt32Array()
	for i in range(1, segments + 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)

	draw_polygon(pts, colors, uvs, _map_texture)
