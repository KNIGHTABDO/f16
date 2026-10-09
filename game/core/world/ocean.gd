class_name Ocean
extends Node3D
## Sea surface at Ground.sea_level. A geometry clipmap (same scheme as Terrain, with 8 m finest cells and
## 13 rings out to the horizon) carries four vertical sine waves that fade out between 1.5 and 3.2 km from
## the camera. Water depth comes from the terrain height texture (shared with Terrain when passed to setup),
## giving turquoise shallows over the shelf and deep blue offshore, with white foam at the shoreline and on
## wave crests. Two scrolling normal maps at different scales hide the tiling; Godot's PBR specular gives the
## sun glint and the sky reflection (fresnel). Terrain below sea level is hidden by the opaque surface.
##
## Like Terrain, place it at the identity transform under the World node.

const SHADER := preload("res://core/world/ocean.gdshader")

const BASE_CELL := 8.0  # finest ring cell size, metres
const RING_COUNT := 13  # 8 m .. 32 km cells; the outer rings reach past the horizon seen from 10 km
const MORPH_BAND := 0.4
const WAVE_FADE := Vector2(1500.0, 3200.0)  # waves vanish between these camera distances, metres
const WAVE_HEIGHT_MAX := 1.8  # sum of the wave amplitudes, metres (vertical cull bounds)
const HAZE_SCALE := 2500.0  # altitude scale of the aerial haze, metres
const NOISE_SIZE := 512  # seamless noise texture size
const DEEP_COLOR := Color(0.006, 0.040, 0.085)  # linear albedo offshore
const SHALLOW_COLOR := Color(0.05, 0.36, 0.34)  # linear albedo over the shelf

## Half-width of each ring in cells (must be even). Presets trade vertex count for edge quality.
const PRESETS := {"low": 12, "balanced": 16, "high": 20, "ultra": 24}

## Aerial haze colour (sky horizon tone) and density per metre at sea level.
var haze_color: Color = Color(0.62, 0.74, 0.86):
	set(value):
		haze_color = value
		_push_shared()
var haze_density: float = 0.0000167:
	set(value):
		haze_density = value
		_push_shared()
## Scales the wave heights (1.0 = design amplitude, about 1.8 m in total).
var wave_strength: float = 1.0:
	set(value):
		wave_strength = value
		_push_shared()

var map_id := ""
var _half_cells := 16
var _active := false
var _camera: Camera3D
var _height_tex: Texture2D
var _normal_tex: NoiseTexture2D
var _foam_tex: NoiseTexture2D
var _ring_meshes: Array = []  # per ring: meshes for each finer-window offset, slot = (dx + 1) * 3 + (dz + 1)
var _hole_slot := PackedInt32Array()  # per ring: the slot in use
var _rings: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _centres := PackedVector2Array()


## Builds the sea surface for the map Ground has loaded. Pass the Terrain of the same map to share its
## height texture (otherwise the height grid is uploaded again). Returns false if the map is not loaded.
func setup(id: String, terrain: Terrain = null) -> bool:
	if not Ground.is_loaded() or Ground.map_id != id:
		push_error("Ocean.setup: Ground.load_map(\"%s\") must run first" % id)
		return false
	map_id = id
	if terrain != null and terrain.height_texture() != null:
		_height_tex = terrain.height_texture()
	else:
		var n := Ground.height_n
		_height_tex = ImageTexture.create_from_image(
				Image.create_from_data(n, n, false, Image.FORMAT_R16, Ground.get_height_bytes()))
	_normal_tex = _noise_texture(true)
	_foam_tex = _noise_texture(false)
	_active = true
	_build_rings()
	return true


## Chooses the quality preset ("low", "balanced", "high", "ultra"): ring resolution.
func apply_quality(preset: String) -> void:
	if not PRESETS.has(preset):
		push_warning("Ocean.apply_quality: unknown preset '%s', using balanced" % preset)
	_half_cells = int(PRESETS.get(preset, PRESETS["balanced"]))
	if _active:
		_build_rings()


## The camera that drives ring placement, wave fade and haze. The reference is kept; call once.
func set_camera(cam: Camera3D) -> void:
	_camera = cam


func _process(_delta: float) -> void:
	if _active and is_instance_valid(_camera):
		_update_rings()


func _update_rings() -> void:
	var p := _camera.global_position
	var wx := WorldOrigin.world_x(p.x)
	var wz := WorldOrigin.world_z(p.z)
	var cam3 := Vector3(wx, p.y, wz)
	for k in range(RING_COUNT):
		var cell := BASE_CELL * float(1 << k)
		var snap := cell * 2.0
		var centre := Vector2(roundf(wx / snap) * snap, roundf(wz / snap) * snap)
		var mat := _materials[k]
		_rings[k].position = Vector3(centre.x - WorldOrigin.offset_x, 0.0, centre.y - WorldOrigin.offset_z)
		if centre != _centres[k]:
			_centres[k] = centre
			mat.set_shader_parameter("u_centre", centre)
			mat.set_shader_parameter("u_cell", cell)
			mat.set_shader_parameter("u_half", cell * float(_half_cells))
		if k > 0:
			# The finer ring's window relative to this ring's centre: a whole number of this ring's cells
			# (both centres are multiples of this ring's cell), so the mesh variant is exact.
			var hole := (_centres[k - 1] - centre) / cell
			var slot := (clampi(roundi(hole.x), -1, 1) + 1) * 3 + (clampi(roundi(hole.y), -1, 1) + 1)
			if slot != _hole_slot[k]:
				_hole_slot[k] = slot
				_rings[k].mesh = _ring_meshes[k][slot]
		mat.set_shader_parameter("u_cam", cam3)


func _build_rings() -> void:
	for ring in _rings:
		remove_child(ring)
		ring.queue_free()
	_rings.clear()
	_materials.clear()
	_ring_meshes.clear()
	_centres.resize(RING_COUNT)
	_centres.fill(Vector2.INF)
	_hole_slot.resize(RING_COUNT)
	var grid := _grid_vertices(_half_cells)
	var y0 := Ground.sea_level - WAVE_HEIGHT_MAX - 1.0
	var y1 := Ground.sea_level + WAVE_HEIGHT_MAX + 1.0
	for k in range(RING_COUNT):
		var half := BASE_CELL * float(1 << k) * float(_half_cells)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		# Ring 0 has nothing finer inside it. Other rings get one mesh per window offset; slot 4 is no offset.
		var meshes: Array[ArrayMesh] = []
		if k == 0:
			meshes.append(_make_ring_mesh(grid, _half_cells, Vector2i.ZERO, false))
		else:
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					meshes.append(_make_ring_mesh(grid, _half_cells, Vector2i(dx, dz), true))
		_ring_meshes.append(meshes)
		var slot := 0 if k == 0 else 4
		_hole_slot[k] = slot
		var mi := MeshInstance3D.new()
		mi.name = "Ring%02d" % k
		mi.mesh = meshes[slot]
		mi.material_override = mat
		mi.custom_aabb = AABB(Vector3(-half, y0, -half), Vector3(2.0 * half, y1 - y0, 2.0 * half))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mi)
		_rings.append(mi)
		_materials.append(mat)
	_push_shared()


## The haze is written to EMISSION in linear light; the sky's colours are authored in sRGB, so convert.
func _haze_linear() -> Vector3:
	var c := haze_color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b)


func _push_shared() -> void:
	if _materials.is_empty() or _height_tex == null:
		return
	var params := {
		"height_tex": _height_tex,
		"normal_tex": _normal_tex,
		"foam_tex": _foam_tex,
		"u_map_size": Ground.size_m,
		"u_height_n": float(Ground.height_n),
		"u_hmin": Ground.height_min,
		"u_hmax": Ground.height_max,
		"u_sea": Ground.sea_level,
		"u_morph_band": MORPH_BAND,
		"u_wave_amp": wave_strength,
		"u_wave_fade0": WAVE_FADE.x,
		"u_wave_fade1": WAVE_FADE.y,
		"u_haze_color": _haze_linear(),
		"u_haze_density": haze_density,
		"u_haze_scale": HAZE_SCALE,
		"u_deep": Vector3(DEEP_COLOR.r, DEEP_COLOR.g, DEEP_COLOR.b),
		"u_shallow": Vector3(SHALLOW_COLOR.r, SHALLOW_COLOR.g, SHALLOW_COLOR.b),
	}
	for mat in _materials:
		for key in params:
			mat.set_shader_parameter(key, params[key])


## Seamless fBm noise, as a normal map (water ripples) or as a greyscale mask (foam).
func _noise_texture(as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.03
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = NOISE_SIZE
	tex.height = NOISE_SIZE
	tex.seamless = true
	tex.noise = noise
	if as_normal:
		tex.as_normal_map = true
		tex.bump_strength = 4.0
	return tex


## Vertices of the (2n+1)^2 grid at integer cell indices (x = column, z = row, relative to the ring centre).
func _grid_vertices(n: int) -> PackedVector3Array:
	var side := 2 * n + 1
	var verts := PackedVector3Array()
	verts.resize(side * side)
	for j in range(side):
		for i in range(side):
			verts[j * side + i] = Vector3(float(i - n), 0.0, float(j - n))
	return verts


## One ring's triangles over the grid: two clockwise triangles per cell. With a hole, the cells inside the
## finer ring's window are left out. The window is the central square of half-width n/2 cells, offset by d
## cells. Its edges fall on cell edges, so every kept cell lies wholly outside it. (Discarding vertices
## instead would leave half-cells whose triangles are clipped into slivers.)
func _make_ring_mesh(grid: PackedVector3Array, n: int, d: Vector2i, with_hole: bool) -> ArrayMesh:
	var side := 2 * n + 1
	var h := n >> 1
	var idx := PackedInt32Array()
	idx.resize(2 * n * 2 * n * 6)
	var t := 0
	for j in range(2 * n):
		var z0 := j - n
		for i in range(2 * n):
			var x0 := i - n
			if with_hole and x0 >= d.x - h and x0 + 1 <= d.x + h and z0 >= d.y - h and z0 + 1 <= d.y + h:
				continue
			var a := j * side + i
			var b := a + 1
			var c := a + side
			var dd := c + 1
			idx[t] = a
			idx[t + 1] = b
			idx[t + 2] = c
			idx[t + 3] = b
			idx[t + 4] = dd
			idx[t + 5] = c
			t += 6
	idx.resize(t)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = grid
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
