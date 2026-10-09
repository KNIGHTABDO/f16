class_name Vegetation
extends Node3D
## Trees and scrub on 512 m toroidal cells around the camera, drawn as one MultiMesh of crossed
## alpha-tested quads (the species picks a column of tree_atlas.png). Instance transforms are world
## coordinates under this floating node, placed at to_local(0,0), so shifts need no per-instance work.
##
## Public API: setup(preset, avoid_rects), update(delta, cam_world). avoid_rects: Array of Rect2 in
## world metres (airport areas), no vegetation is placed inside them.

const CELL := 512.0
const CAP := 56
const BUDGET := 4
const ATLAS := preload("res://assets/textures/world/tree_atlas.png")
const SHADER := preload("res://core/world/vegetation.gdshader")
const PINE := 0
const OLIVE := 1
const PALM := 2
const SHRUB := 3
const SENTINEL := Vector2i(2147483647, 0)

var grid := 9
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _slot_key: Array[Vector2i] = []
var _avoid: Array[Rect2] = []
var _primed := false


func setup(preset: String, avoid_rects: Array = []) -> void:
	grid = 7 if preset == "low" else (9 if preset == "balanced" else 13)
	add_to_group("floating")
	position = WorldOrigin.to_local(Vector3.ZERO)
	for r in avoid_rects:
		_avoid.append(r)

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("atlas", ATLAS)

	var n := grid * grid * CAP
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _crossed_mesh()
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
	_rng.seed = ((key.x * 83492791) ^ (key.y * 19349669) ^ 0x2545F491) & 0x7fffffff
	var base := slot * CAP
	var used := 0
	var centre_lc := Ground.landcover_at(
		(key.x + 0.5) * CELL - WorldOrigin.offset_x, (key.y + 0.5) * CELL - WorldOrigin.offset_z)
	var cand := 60 if centre_lc == Ground.LC_TREES else (28 if centre_lc == Ground.LC_SHRUB else 0)
	for k in cand:
		if used >= CAP:
			break
		var wx := key.x * CELL + _rng.randf() * CELL
		var wz := key.y * CELL + _rng.randf() * CELL
		var lx := wx - WorldOrigin.offset_x
		var lz := wz - WorldOrigin.offset_z
		var lc := Ground.landcover_at(lx, lz)
		var shrub := lc == Ground.LC_SHRUB
		if lc != Ground.LC_TREES and not shrub:
			continue
		if _rng.randf() > (0.5 if shrub else 0.85):
			continue
		var h := Ground.world_height_at(wx, wz)
		if h <= Ground.sea_level + 3.0:
			continue
		if Ground.normal_at(lx, lz, 30.0).y < 0.72:
			continue
		if _avoided(wx, wz):
			continue

		var sp := SHRUB
		var height := _rng.randf_range(1.0, 1.8)
		var ratio := 1.4
		if not shrub:
			var r := _rng.randf()
			if h < 35.0 and _coastal(lx, lz) and r < 0.45:
				sp = PALM
				height = _rng.randf_range(6.0, 9.0)
				ratio = 0.95
			elif h > 300.0 or r < 0.35:
				sp = PINE
				height = _rng.randf_range(8.0, 13.0)
				ratio = 0.6
			else:
				sp = OLIVE
				height = _rng.randf_range(4.5, 7.0)
				ratio = 0.85
		var yaw := _rng.randf() * TAU
		var b := Basis(Vector3.UP, yaw).scaled(Vector3(height * ratio, height, height * ratio))
		_mm.set_instance_transform(base + used, Transform3D(b, Vector3(wx, h, wz)))
		_mm.set_instance_custom_data(base + used, Color((sp + 0.5) / 4.0, _rng.randf(), 0.0, 0.0))
		used += 1
	for i in range(used, CAP):
		_mm.set_instance_transform(base + i, Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO))


func _avoided(wx: float, wz: float) -> bool:
	var p := Vector2(wx, wz)
	for r in _avoid:
		if r.has_point(p):
			return true
	return false


## True if sea (or lake) is within about 180 m in any axis direction.
func _coastal(lx: float, lz: float) -> bool:
	const D := 180.0
	return Ground.is_water(lx + D, lz) or Ground.is_water(lx - D, lz) \
		or Ground.is_water(lx, lz + D) or Ground.is_water(lx, lz - D)


func _crossed_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0), Vector3(0.5, 1.0, 0.0), Vector3(-0.5, 1.0, 0.0),
		Vector3(0.0, 0.0, -0.5), Vector3(0.0, 0.0, 0.5), Vector3(0.0, 1.0, 0.5), Vector3(0.0, 1.0, -0.5),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
	])
	var normals := PackedVector3Array()
	normals.resize(8)
	normals.fill(Vector3.UP)
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
