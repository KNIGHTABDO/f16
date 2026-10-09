class_name Clouds
extends Node3D
## Cumulus clouds and a cirrus deck.
##
## Puffs are MultiMesh camera-facing impostors laid out in toroidal CELL-metre cells around the
## camera. Instance transforms are stored in world coordinates; this node sits at to_local(0,0)
## and is in group "floating", so a floating-origin shift needs no per-instance work. A cell slot
## is regenerated (within BUDGET cells per frame) when the camera crosses a cell border.
##
## Public API: setup(preset), set_cover(cover, dark), update(delta, cam_world, sun_dir, sun_col,
## shade_col), inside_factor() (0..1, feeds WorldSky.set_inside_cloud).

const CELL := 3000.0
const CLUSTERS := 3
const PUFFS := 8
const PER_CELL := CLUSTERS * PUFFS
const BUDGET := 4
const CIRRUS_ALT := 9000.0
const CIRRUS_SIZE := 60000.0
const NOISE := preload("res://assets/textures/world/cloud_noise.png")
const CUMULUS_SHADER := preload("res://core/world/clouds.gdshader")
const CIRRUS_SHADER := preload("res://core/world/cirrus.gdshader")

var grid := 11
var _rng := RandomNumberGenerator.new()
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _cirrus: MeshInstance3D
var _cirrus_mat: ShaderMaterial
var _slot_key: Array[Vector2i] = []
var _primed := false
var _cover := 0.5
var _inside := 0.0


func setup(preset: String) -> void:
	grid = 9 if preset == "low" else (11 if preset == "balanced" else 13)
	add_to_group("floating")
	position = WorldOrigin.to_local(Vector3.ZERO)

	_mat = ShaderMaterial.new()
	_mat.shader = CUMULUS_SHADER
	_mat.set_shader_parameter("noise_tex", NOISE)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = grid * grid * PER_CELL
	_mm.custom_aabb = AABB(Vector3(-5.0e5, -2.0e4, -5.0e5), Vector3(1.0e6, 4.0e4, 1.0e6))
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

	_cirrus_mat = ShaderMaterial.new()
	_cirrus_mat.shader = CIRRUS_SHADER
	_cirrus_mat.set_shader_parameter("noise_tex", NOISE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(CIRRUS_SIZE, CIRRUS_SIZE)
	_cirrus = MeshInstance3D.new()
	_cirrus.mesh = plane
	_cirrus.material_override = _cirrus_mat
	_cirrus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cirrus)

	_slot_key.resize(grid * grid)
	for i in grid * grid:
		_slot_key[i] = Vector2i(2147483647, 0)
	_primed = false


## cover: fraction of cloud clusters present (0..1). dark: storm base darkening (0..1).
func set_cover(cover: float, dark: float) -> void:
	_cover = clampf(cover, 0.0, 1.0)
	_mat.set_shader_parameter("cover", _cover)
	_mat.set_shader_parameter("dark", clampf(dark, 0.0, 1.0))
	_cirrus_mat.set_shader_parameter("amount", clampf(0.25 + 0.4 * _cover, 0.0, 0.8))


func inside_factor() -> float:
	return _inside


## cam_world: camera position in world metres. sun_dir: world direction towards the sun.
func update(delta: float, cam_world: Vector3, sun_dir: Vector3, sun_col: Color, shade_col: Color) -> void:
	_mat.set_shader_parameter("sun_dir", sun_dir)
	_mat.set_shader_parameter("sun_col", Vector3(sun_col.r, sun_col.g, sun_col.b))
	_mat.set_shader_parameter("sky_col", Vector3(shade_col.r, shade_col.g, shade_col.b))
	_cirrus_mat.set_shader_parameter("col", Vector3(sun_col.r, sun_col.g, sun_col.b) * 0.5 + Vector3(shade_col.r, shade_col.g, shade_col.b) * 0.5 + Vector3(0.05, 0.05, 0.05))
	_cirrus_mat.set_shader_parameter("center", Vector2(cam_world.x, cam_world.z))
	# Clouds sits at -offset in Godot space, so local = world on the cirrus plane.
	_cirrus.position = Vector3(cam_world.x, CIRRUS_ALT, cam_world.z)
	_refresh(cam_world)
	var target := _inside_test(cam_world)
	_inside = lerpf(_inside, target, 1.0 - exp(-delta * 4.0))


func _window_key(sx: int, sz: int, cx: int, cz: int) -> Vector2i:
	var x0 := cx - grid / 2
	var z0 := cz - grid / 2
	return Vector2i(x0 + posmod(sx - x0, grid), z0 + posmod(sz - z0, grid))


func _refresh(cam_world: Vector3) -> void:
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


func _fill(slot: int, key: Vector2i) -> void:
	_slot_key[slot] = key
	_rng.seed = ((key.x * 73856093) ^ (key.y * 19349663) ^ 0x5bd1e995) & 0x7fffffff
	var patch := _rng.randf()  # regional cloudiness, makes cover clumpy
	var x0 := key.x * CELL
	var z0 := key.y * CELL
	for c in CLUSTERS:
		var cxw := x0 + _rng.randf() * CELL
		var czw := z0 + _rng.randf() * CELL
		var ground := Ground.world_height_at(cxw, czw) if Ground.is_loaded() else 0.0
		var base := maxf(1100.0 + _rng.randf() * 1500.0, ground + 700.0)
		var cluster_r := 380.0 + _rng.randf() * 620.0
		var height := 260.0 + _rng.randf() * 520.0
		var thresh := clampf(patch * 0.55 + _rng.randf() * 0.45, 0.0, 1.0)
		for p in PUFFS:
			var ang := _rng.randf() * TAU
			var dist := cluster_r * sqrt(_rng.randf()) * 0.85
			var t := dist / cluster_r
			var px := cxw + cos(ang) * dist
			var pz := czw + sin(ang) * dist
			var py := base + (1.0 - t) * height * _rng.randf_range(0.4, 1.0)
			var rad := _rng.randf_range(110.0, 230.0) * (1.0 - 0.35 * t)
			var idx := slot * PER_CELL + c * PUFFS + p
			_mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, Vector3(px, py, pz)))
			_mm.set_instance_custom_data(idx, Color(_rng.randf(), rad, thresh, 0.0))


## True-ish (1.0) when the camera is inside an active puff, using the cells around the camera.
func _inside_test(cam: Vector3) -> float:
	if cam.y < 700.0 or cam.y > 4200.0:
		return 0.0
	var cx := floori(cam.x / CELL)
	var cz := floori(cam.z / CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			var slot := posmod(key.y, grid) * grid + posmod(key.x, grid)
			if _slot_key[slot] != key:
				continue
			for i in PER_CELL:
				var idx := slot * PER_CELL + i
				var c := _mm.get_instance_custom_data(idx)
				if c.b >= _cover:
					continue
				var centre := _mm.get_instance_transform(idx).origin
				if cam.distance_to(centre) < c.g * 0.85:
					return 1.0
	return 0.0
