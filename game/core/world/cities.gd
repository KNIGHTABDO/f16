class_name Cities
extends Node3D
## Procedural 3D buildings for towns, cities, and LC_URBAN landcover areas.
## Uses a MultiMesh of BoxMeshes with a Moroccan stucco facade shader.
##
## Group: "floating"
## Public API: setup(places, preset, avoid_rects), update(delta, cam_world), set_night(night)

const CELL := 512.0
const CAP := 40
const BUDGET := 4
const SHADER := preload("res://core/world/city_facade.gdshader")
const SENTINEL := Vector2i(2147483647, 0)

var grid := 11
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _slot_key: Array[Vector2i] = []
var _avoid: Array[Rect2] = []
var _places_cache: Array[Dictionary] = []
var _primed := false


func setup(places: Array, preset: String, avoid_rects: Array = []) -> void:
	grid = 7 if preset == "low" else (11 if preset == "balanced" else 13)
	add_to_group("floating")
	position = WorldOrigin.to_local(Vector3.ZERO)

	for r in avoid_rects:
		_avoid.append(r)

	_places_cache.clear()
	for p in places:
		var pop: float = float(p.get("population", 10000))
		var is_city: bool = p.get("kind", "town") == "city"
		var radius: float = clampf(sqrt(pop) * (3.8 if is_city else 2.6), 800.0, 5500.0)
		_places_cache.append({
			"pos": Vector2(float(p["x"]), float(p["z"])),
			"pop": pop,
			"radius": radius,
			"is_city": is_city,
			"name": p.get("name", "")
		})

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER

	var n := grid * grid * CAP
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	_mm.mesh = box
	_mm.instance_count = n
	_mm.custom_aabb = AABB(Vector3(-5.0e5, -2.0e4, -5.0e5), Vector3(1.0e6, 4.0e4, 1.0e6))

	for i in n:
		_mm.set_instance_transform(i, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))

	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

	_slot_key.resize(grid * grid)
	for i in grid * grid:
		_slot_key[i] = SENTINEL
	_primed = false


func set_night(night: float) -> void:
	if _mat != null:
		_mat.set_shader_parameter("night", night)


func update(_delta: float, cam_world: Vector3) -> void:
	if not Ground.is_loaded():
		return
	var cx := floori(cam_world.x / CELL)
	var cz := floori(cam_world.z / CELL)
	var budget := BUDGET if _primed else grid * grid
	_primed = true

	for sz in grid:
		for sx in grid:
			var slot := sz * grid + sx
			var key := _window_key(sx, sz, cx, cz)
			if _slot_key[slot] == key:
				continue
			if budget <= 0:
				return
			_fill(slot, key)
			budget -= 1


func _window_key(sx: int, sz: int, cx: int, cz: int) -> Vector2i:
	var x0 := cx - grid / 2
	var z0 := cz - grid / 2
	return Vector2i(x0 + posmod(sx - x0, grid), z0 + posmod(sz - z0, grid))


func _fill(slot: int, key: Vector2i) -> void:
	_slot_key[slot] = key
	_rng.seed = ((key.x * 61728391) ^ (key.y * 39281741) ^ 0x3F1A7C55) & 0x7fffffff

	var base := slot * CAP
	var used := 0

	var cell_center_w := Vector2((key.x + 0.5) * CELL, (key.y + 0.5) * CELL)
	var lx_c := cell_center_w.x - WorldOrigin.offset_x
	var lz_c := cell_center_w.y - WorldOrigin.offset_z
	var lc := Ground.landcover_at(lx_c, lz_c)

	# Find closest place
	var closest_dist := 1.0e9
	var closest_place: Dictionary = {}
	for p in _places_cache:
		var d: float = cell_center_w.distance_to(p["pos"])
		if d < closest_dist:
			closest_dist = d
			closest_place = p

	var in_place := not closest_place.is_empty() and closest_dist < float(closest_place.get("radius", 0.0))
	var is_urban := (lc == Ground.LC_URBAN) or in_place

	if not is_urban:
		for i in CAP:
			_mm.set_instance_transform(base + i, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))
		return

	# Determine density and target height
	var center_factor := 0.0
	var pop_scale := 1.0
	if in_place:
		var rad: float = float(closest_place["radius"])
		center_factor = clampf(1.0 - closest_dist / rad, 0.0, 1.0)
		pop_scale = clampf(sqrt(float(closest_place["pop"])) / 300.0, 0.8, 3.2)

	var cand_count := int(lerpf(16.0, float(CAP), center_factor * 0.8 + 0.2))

	for k in cand_count:
		if used >= CAP:
			break
		var wx := key.x * CELL + _rng.randf() * CELL
		var wz := key.y * CELL + _rng.randf() * CELL
		var lx := wx - WorldOrigin.offset_x
		var lz := wz - WorldOrigin.offset_z

		if _avoided(wx, wz):
			continue
		if Ground.is_water(lx, lz):
			continue

		var h := Ground.world_height_at(wx, wz)
		if h <= Ground.sea_level + 2.0:
			continue
		if Ground.normal_at(lx, lz, 25.0).y < 0.78:
			continue

		# Building dimensions
		var is_minaret := false
		var b_w := _rng.randf_range(12.0, 24.0)
		var b_d := _rng.randf_range(12.0, 24.0)
		var b_h := _rng.randf_range(7.0, 14.0) * (1.0 + center_factor * pop_scale * 0.7)

		# 3% chance of a minaret in dense urban areas
		if center_factor > 0.3 and _rng.randf() < 0.04:
			is_minaret = true
			b_w = _rng.randf_range(6.0, 8.0)
			b_d = _rng.randf_range(6.0, 8.0)
			b_h = _rng.randf_range(28.0, 42.0)

		b_h = clampf(b_h, 6.0, 48.0)
		var yaw := _rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(b_w, b_h, b_d))
		var pos_center := Vector3(wx, h + b_h * 0.5, wz)

		_mm.set_instance_transform(base + used, Transform3D(b, pos_center))
		var tint := _rng.randf()
		_mm.set_instance_custom_data(base + used, Color(tint, 1.0 if is_minaret else 0.0, _rng.randf(), 0.0))
		used += 1

	for i in range(used, CAP):
		_mm.set_instance_transform(base + i, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))


func _avoided(wx: float, wz: float) -> bool:
	var p := Vector2(wx, wz)
	for r in _avoid:
		if r.has_point(p):
			return true
	return false
