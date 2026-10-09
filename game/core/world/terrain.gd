class_name Terrain
extends Node3D
## GPU geometry-clipmap terrain for the map loaded in Ground (call Ground.load_map(id) first).
##
## RING_COUNT square grids ("rings") follow the camera. Ring k has cell size BASE_CELL * 2^k and spans
## +-half_cells cells. All rings share one static index grid; terrain.gdshader places the vertices: it
## samples the R16 height grid exactly like Ground.world_height_at, morphs the outer band of each ring
## onto the next coarser lattice (no cracks, no popping) and discards the window that the next finer ring
## covers. Each ring is re-centred every frame on the camera's world position, snapped to its cell size,
## so the floating origin needs no special handling beyond WorldOrigin.offset.
##
## Close-range procedural detail (metres of value noise on slopes, faded out by DETAIL_END) is mirrored on
## the CPU by detail_height_at(), using the same integer hash as the shader.
##
## Place this node at the identity transform under the level's World node (the rings are positioned in
## its local space). It is not in the "floating" group: it positions its rings from WorldOrigin itself.

const SHADER := preload("res://core/world/terrain.gdshader")
const TEXTURE_DIR := "res://core/world/terrain_textures/"
## Detail layer order = the shader's layer index (see the land-cover mapping in terrain.gdshader).
const LAYER_NAMES := ["grass", "dry", "farm", "forest", "rock", "sand", "snow", "urban"]

const BASE_CELL := 4.0  # finest ring cell size, metres
const RING_COUNT := 12  # 4 m .. 8 km cells; 12 rings reach past the horizon seen from 10 km
const MORPH_BAND := 0.4  # outer fraction of each ring that morphs onto the next coarser ring
const TILE_A := 12.0  # detail texture tile sizes, metres (two scales, rotated against each other)
const TILE_B := 37.0
const DETAIL_END := 2000.0  # procedural detail fades out by this camera distance, metres
const DETAIL_RANGE := 0.75  # max |detail noise| / detail_amplitude (value noise is in [0, 1])
const HAZE_SCALE := 2500.0  # altitude scale of the aerial haze, metres
const AABB_MARGIN := 60.0  # vertical cull margin beyond the height range, metres

## Quality presets (Settings.graphics_preset). half_cells must be even so that ring edges align.
const PRESETS := {
	"low": {"half_cells": 24, "detail": false, "near": false, "color_end": 1200.0, "triplanar": false},
	"medium": {"half_cells": 40, "detail": true, "near": true, "color_end": 2600.0, "triplanar": true},
	"balanced": {"half_cells": 40, "detail": true, "near": true, "color_end": 2600.0, "triplanar": true},
	"high": {"half_cells": 56, "detail": true, "near": true, "color_end": 3400.0, "triplanar": true},
	"ultra": {"half_cells": 64, "detail": true, "near": true, "color_end": 4200.0, "triplanar": true},
}

## Aerial haze colour (sky horizon tone) and density per metre at sea level; thins with altitude.
var haze_color: Color = Color(0.62, 0.74, 0.86):
	set(value):
		haze_color = value
		_push_shared()
var haze_density: float = 0.0000167:
	set(value):
		haze_density = value
		_push_shared()
## Procedural detail amplitude, metres. Also used by detail_height_at(); max_detail_offset() bounds it.
var detail_amplitude: float = 2.5:
	set(value):
		detail_amplitude = value
		_push_shared()

var map_id := ""
var _half_cells := 40
var _detail_on := true
var _near_on := true
var _color_end := 2500.0
var _triplanar_on := true
var _land_n := 1
var _active := false
var _camera: Camera3D
var _cam_world := Vector2.ZERO
var _height_tex: ImageTexture
var _landcover_tex: ImageTexture
var _color_tex: ImageTexture
var _albedo_array: Texture2DArray
var _normal_array: Texture2DArray
var _ring_meshes: Array = []  # per ring: meshes for each finer-window offset, slot = (dx + 1) * 3 + (dz + 1)
var _hole_slot := PackedInt32Array()  # per ring: the slot in use
var _rings: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _centres := PackedVector2Array()  # last ring centres, world metres (float32 is exact here)


## Uploads the height, land-cover, satellite colour and detail textures for the map Ground has loaded,
## then builds the rings. Returns false (and logs an error) if Ground.load_map(id) did not run for this id.
func setup(id: String) -> bool:
	if not Ground.is_loaded() or Ground.map_id != id:
		push_error("Terrain.setup: Ground.load_map(\"%s\") must run first" % id)
		return false
	map_id = id
	var meta: Dictionary = Ground.meta
	if Ground.get_height_texture() != null:
		_height_tex = Ground.get_height_texture()
	else:
		var n := Ground.height_n
		var height_bytes := Ground.get_height_bytes()
		if height_bytes.is_empty():
			height_bytes = FileAccess.get_file_as_bytes(String(meta["height_file"]))
		_height_tex = ImageTexture.create_from_image(
				Image.create_from_data(n, n, false, Image.FORMAT_R16, height_bytes))

	var lc_img: Image
	_land_n = Ground.landcover_n
	if _land_n > 0:
		var lc_bytes := FileAccess.get_file_as_bytes(String(meta["landcover_file"]))
		lc_img = Image.create_from_data(_land_n, _land_n, false, Image.FORMAT_R8, lc_bytes)
	else:
		_land_n = 1
		lc_img = Image.create_from_data(1, 1, false, Image.FORMAT_R8, PackedByteArray([Ground.LC_GRASS]))
	_landcover_tex = ImageTexture.create_from_image(lc_img)

	_color_tex = ImageTexture.create_from_image(_load_rgb(String(meta.get("color_file", ""))))

	var albedo: Array[Image] = []
	var normals: Array[Image] = []
	for layer in LAYER_NAMES:
		albedo.append(_load_rgb(TEXTURE_DIR + "albedo/%s.jpg" % layer))
		normals.append(_load_rgb(TEXTURE_DIR + "normal/%s.jpg" % layer))
	_albedo_array = Texture2DArray.new()
	_albedo_array.create_from_images(albedo)
	_normal_array = Texture2DArray.new()
	_normal_array.create_from_images(normals)

	_active = true
	_build_rings()
	return true


## Chooses the quality preset ("low", "medium", "balanced", "high", "ultra"): ring resolution, procedural detail,
## and the distance out to which the close-range colour textures are used.
func apply_quality(preset: String) -> void:
	if preset == "medium":
		preset = "balanced"
	if not PRESETS.has(preset):
		push_warning("Terrain.apply_quality: unknown preset '%s', using balanced" % preset)
	var cfg: Dictionary = PRESETS.get(preset, PRESETS["balanced"])
	_half_cells = int(cfg["half_cells"])
	_detail_on = bool(cfg["detail"])
	_near_on = bool(cfg["near"])
	_color_end = float(cfg["color_end"])
	_triplanar_on = bool(cfg.get("triplanar", true))
	if _active:
		_build_rings()


## The camera that drives ring placement, detail fade and haze. The reference is kept; call once.
func set_camera(cam: Camera3D) -> void:
	_camera = cam


## The R16 height texture (null until setup). Ocean samples it for water depth.
func height_texture() -> ImageTexture:
	return _height_tex


## Terrain height plus the procedural detail, in metres ASL, at a local position.
func surface_height_at(local_x: float, local_z: float) -> float:
	return Ground.height_at(local_x, local_z) + detail_height_at(local_x, local_z)


## Procedural detail displacement (metres, added to Ground.height_at) at a local position. Reproduces the
## shader's detail exactly, including the slope mask and the distance fade from the last camera position
## (zero beyond DETAIL_END, and always zero when the preset disables detail).
func detail_height_at(local_x: float, local_z: float) -> float:
	if not _active or not _detail_on:
		return 0.0
	var w := Vector2(WorldOrigin.world_x(local_x), WorldOrigin.world_z(local_z))
	var dw := _detail_weight(w)
	if dw <= 0.001:
		return 0.0
	var s := dw * _slope_mask(w)
	if s <= 0.0:
		return 0.0
	return s * _detail_fn(w)


## Upper bound of |detail_height_at| (metres).
func max_detail_offset() -> float:
	return detail_amplitude * DETAIL_RANGE


func _process(_delta: float) -> void:
	if _active and is_instance_valid(_camera):
		_update_rings()


func _update_rings() -> void:
	var p := _camera.global_position
	var wx := WorldOrigin.world_x(p.x)
	var wz := WorldOrigin.world_z(p.z)
	_cam_world = Vector2(wx, wz)
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


## Builds the ring meshes (one per level, all sharing one grid) for the current quality.
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
	var y0 := minf(Ground.height_min, Ground.sea_level) - AABB_MARGIN
	var y1 := Ground.height_max + AABB_MARGIN + detail_amplitude
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
		# The vertex shader displaces the grid, so the mesh's own bounds are wrong: set the real ones.
		mi.custom_aabb = AABB(Vector3(-half, y0, -half), Vector3(2.0 * half, y1 - y0, 2.0 * half))
		mi.extra_cull_margin = 10000.0
		mi.ignore_occlusion_culling = true
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
		"landcover_tex": _landcover_tex,
		"color_tex": _color_tex,
		"albedo_array": _albedo_array,
		"normal_array": _normal_array,
		"u_map_size": Ground.size_m,
		"u_height_n": float(Ground.height_n),
		"u_land_n": float(_land_n),
		"u_hmin": Ground.height_min,
		"u_hmax": Ground.height_max,
		"u_sea": Ground.sea_level,
		"u_morph_band": MORPH_BAND,
		"u_detail_on": 1.0 if _detail_on else 0.0,
		"u_detail_amp": detail_amplitude,
		"u_detail_end": DETAIL_END,
		"u_near_on": 1.0 if _near_on else 0.0,
		"u_color_end": _color_end,
		"u_haze_color": _haze_linear(),
		"u_haze_density": haze_density,
		"u_haze_scale": HAZE_SCALE,
		"u_tile_a": TILE_A,
		"u_tile_b": TILE_B,
		"u_triplanar_on": 1.0 if _triplanar_on else 0.0,
	}
	for mat in _materials:
		for key in params:
			mat.set_shader_parameter(key, params[key])


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


## Decodes an image to RGB8 with mipmaps (layers of a Texture2DArray must match in size and format).
func _load_rgb(path: String) -> Image:
	# Decode from the file bytes: Image.load_from_file on res:// warns that it will not work on export.
	var img := Image.new()
	var bytes := FileAccess.get_file_as_bytes(path)
	var err := ERR_FILE_NOT_FOUND
	if not bytes.is_empty():
		if path.get_extension().to_lower() == "png":
			err = img.load_png_from_buffer(bytes)
		else:
			err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		push_error("Terrain: cannot load %s" % path)
		img = Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(0.4, 0.45, 0.35))
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	img.generate_mipmaps()
	return img


# ---- CPU mirror of terrain.gdshader's procedural detail (keep the two in step) ----

func _detail_weight(w: Vector2) -> float:
	var dc := w.distance_to(_cam_world)
	return 1.0 - smoothstep(0.6 * DETAIL_END, DETAIL_END, dc)


func _slope_mask(w: Vector2) -> float:
	var e := 30.0
	var gx := (Ground.world_height_at(w.x + e, w.y) - Ground.world_height_at(w.x - e, w.y)) / (2.0 * e)
	var gz := (Ground.world_height_at(w.x, w.y + e) - Ground.world_height_at(w.x, w.y - e)) / (2.0 * e)
	return smoothstep(0.02, 0.10, sqrt(gx * gx + gz * gz))


func _detail_fn(w: Vector2) -> float:
	var n1 := _vnoise(w / 24.0) - 0.5
	var n2 := _vnoise(w / 11.0 + Vector2(17.3, 5.1)) - 0.5
	return detail_amplitude * (n1 + 0.5 * n2)


func _vnoise(p: Vector2) -> float:
	var fl := p.floor()
	var ix := int(fl.x)
	var iy := int(fl.y)
	var f := p - fl
	var ux := f.x * f.x * (3.0 - 2.0 * f.x)
	var uy := f.y * f.y * (3.0 - 2.0 * f.y)
	var a := _lattice(ix, iy)
	var b := _lattice(ix + 1, iy)
	var c := _lattice(ix, iy + 1)
	var d := _lattice(ix + 1, iy + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uy)


## Same integer hash as terrain.gdshader's lattice_hash: 32-bit unsigned arithmetic, masked after each step.
func _lattice(px: int, py: int) -> float:
	var x := (px * 73856093) & 0xFFFFFFFF
	var y := (py * 19349663) & 0xFFFFFFFF
	var s := (((x ^ y) * 747796405) + 2891336453) & 0xFFFFFFFF
	var w := ((((s >> ((s >> 28) + 4)) ^ s) * 277803737)) & 0xFFFFFFFF
	return float((w >> 22) ^ w) * (1.0 / 4294967296.0)
