class_name Airbase
extends Node3D
## Airbase representation: runways with ICAO markings, taxiways, apron,
## control tower, hangars, shelters, and night edge lighting.
##
## Group: "floating"
## API: get_runways() -> Array (each {start, end, width, heading_deg, name})
##      get_avoid_rect() -> Rect2 (world-space bounding box)
##      set_night(k: float)

const RUNWAY_SHADER := preload("res://core/world/runway.gdshader")
const ASPHALT_TEX := preload("res://assets/textures/world/asphalt.png")
const DIGITS_TEX := preload("res://assets/textures/world/runway_digits.png")

var team: int = 0
var airport_name: String = ""
var icao: String = ""
var runways_data: Array = []

var _avoid_rect: Rect2
var _runway_materials: Array[ShaderMaterial] = []
var _lights_mm: MultiMesh
var _lights_mmi: MultiMeshInstance3D
var _lights_mat: StandardMaterial3D


func setup(airport_dict: Dictionary, is_main: bool = false) -> void:
	add_to_group("floating")
	airport_name = airport_dict.get("name", "Airbase")
	icao = airport_dict.get("icao", "")
	team = 0 if is_main else 1
	runways_data = airport_dict.get("runways", [])

	# Base node sits at to_local(Vector3.ZERO) so child vertices are in world coordinates
	position = WorldOrigin.to_local(Vector3.ZERO)

	var min_x := 1.0e9
	var max_x := -1.0e9
	var min_z := 1.0e9
	var max_z := -1.0e9

	var all_lights: Array[Dictionary] = [] # {pos: Vector3, col: Color}

	for rw in runways_data:
		var x1 := float(rw["x1"])
		var z1 := float(rw["z1"])
		var x2 := float(rw["x2"])
		var z2 := float(rw["z2"])
		var width := float(rw.get("width_m", 45.0))
		var elev := float(rw.get("elevation_m", 0.0))
		if Ground.is_loaded() and elev <= 0.0:
			elev = Ground.world_height_at((x1 + x2) * 0.5, (z1 + z2) * 0.5)

		min_x = minf(min_x, minf(x1, x2) - 150.0)
		max_x = maxf(max_x, maxf(x1, x2) + 150.0)
		min_z = minf(min_z, minf(z1, z2) - 150.0)
		max_z = maxf(max_z, maxf(z1, z2) + 150.0)

		_build_runway(rw, elev, all_lights)
		_build_taxiway_and_buildings(rw, elev, all_lights)

	_avoid_rect = Rect2(min_x, min_z, max_x - min_x, max_z - min_z)
	_build_edge_lights(all_lights)


func get_runways() -> Array:
	var out: Array = []
	for rw in runways_data:
		var x1 := float(rw["x1"])
		var z1 := float(rw["z1"])
		var x2 := float(rw["x2"])
		var z2 := float(rw["z2"])
		var elev := float(rw.get("elevation_m", 0.0))
		if Ground.is_loaded() and elev <= 0.0:
			elev = Ground.world_height_at((x1 + x2) * 0.5, (z1 + z2) * 0.5)
		var start_w := Vector3(x1, elev + 0.5, z1)
		var end_w := Vector3(x2, elev + 0.5, z2)
		out.append({
			"start": WorldOrigin.to_local(start_w),
			"end": WorldOrigin.to_local(end_w),
			"world_start": start_w,
			"world_end": end_w,
			"width": float(rw.get("width_m", 45.0)),
			"heading_deg": float(rw.get("heading_deg", 0.0)),
			"name": String(rw.get("ref", "RWY")),
			"elevation": elev
		})
	return out


func get_avoid_rect() -> Rect2:
	return _avoid_rect


func set_night(night: float) -> void:
	for mat in _runway_materials:
		mat.set_shader_parameter("night", night)
	if _lights_mat != null:
		_lights_mat.emission_energy_multiplier = night * 4.0
		if _lights_mmi != null:
			_lights_mmi.visible = night > 0.01


func _build_runway(rw: Dictionary, elev: float, lights_out: Array[Dictionary]) -> void:
	var x1 := float(rw["x1"])
	var z1 := float(rw["z1"])
	var x2 := float(rw["x2"])
	var z2 := float(rw["z2"])
	var length := float(rw.get("length_m", 2500.0))
	var width := float(rw.get("width_m", 45.0))
	var ref := String(rw.get("ref", "09/27"))

	var fwd := Vector3(x2 - x1, 0.0, z2 - z1).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x).normalized()

	var p_start := Vector3(x1, elev + 0.15, z1)
	var p_end := Vector3(x2, elev + 0.15, z2)

	var p0 := p_start - right * (width * 0.5)
	var p1 := p_start + right * (width * 0.5)
	var p2 := p_end + right * (width * 0.5)
	var p3 := p_end - right * (width * 0.5)

	var verts := PackedVector3Array([p0, p1, p2, p0, p2, p3])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0),
		Vector2(0.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
	])
	var normals := PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP
	])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = RUNWAY_SHADER
	mat.set_shader_parameter("asphalt_tex", ASPHALT_TEX)
	mat.set_shader_parameter("digits_tex", DIGITS_TEX)
	mat.set_shader_parameter("runway_length", length)
	mat.set_shader_parameter("runway_width", width)

	var d1 := Vector2(1.0, 0.0)
	var d2 := Vector2(2.0, 8.0)
	var parts := ref.split("/")
	if parts.size() >= 2:
		var s1 := parts[0].strip_edges()
		var s2 := parts[1].strip_edges()
		if s1.length() >= 2:
			d1 = Vector2(float(s1.substr(0, 1)), float(s1.substr(1, 1)))
		elif s1.length() == 1:
			d1 = Vector2(0.0, float(s1))
		if s2.length() >= 2:
			d2 = Vector2(float(s2.substr(0, 1)), float(s2.substr(1, 1)))
		elif s2.length() == 1:
			d2 = Vector2(0.0, float(s2))
	mat.set_shader_parameter("num_d1", d1)
	mat.set_shader_parameter("num_d2", d2)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_runway_materials.append(mat)

	# Generate runway edge lights:
	# White lights along sides every 60m
	var steps := maxi(2, int(length / 60.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var center_pt := p_start.lerp(p_end, t)
		var col := Color(1.0, 0.95, 0.85) # warm white
		if i == 0:
			col = Color(0.2, 1.0, 0.3) # green threshold
		elif i == steps:
			col = Color(1.0, 0.15, 0.15) # red end
		var l_pt := center_pt - right * (width * 0.5 + 1.5) + Vector3(0, 0.3, 0)
		var r_pt := center_pt + right * (width * 0.5 + 1.5) + Vector3(0, 0.3, 0)
		lights_out.append({"pos": l_pt, "col": col})
		lights_out.append({"pos": r_pt, "col": col})


func _build_taxiway_and_buildings(rw: Dictionary, elev: float, lights_out: Array[Dictionary]) -> void:
	var x1 := float(rw["x1"])
	var z1 := float(rw["z1"])
	var x2 := float(rw["x2"])
	var z2 := float(rw["z2"])
	var length := float(rw.get("length_m", 2500.0))
	var rw_width := float(rw.get("width_m", 45.0))

	var fwd := Vector3(x2 - x1, 0.0, z2 - z1).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x).normalized()

	# Place taxiway on the positive 'right' side offset by 120m
	var tw_offset := right * 110.0
	var tw_width := 23.0
	var p_start := Vector3(x1, elev + 0.12, z1) + tw_offset
	var p_end := Vector3(x2, elev + 0.12, z2) + tw_offset

	# Taxiway parallel strip
	var tp0 := p_start - right * (tw_width * 0.5)
	var tp1 := p_start + right * (tw_width * 0.5)
	var tp2 := p_end + right * (tw_width * 0.5)
	var tp3 := p_end - right * (tw_width * 0.5)

	# Connectors between runway and taxiway at 20%, 50%, 80%
	var tw_verts := PackedVector3Array([tp0, tp1, tp2, tp0, tp2, tp3])
	for f in [0.15, 0.5, 0.85]:
		var r_mid := Vector3(x1, elev + 0.12, z1).lerp(Vector3(x2, elev + 0.12, z2), f)
		var t_mid := p_start.lerp(p_end, f)
		var c0 := r_mid - fwd * 12.0
		var c1 := r_mid + fwd * 12.0
		var c2 := t_mid + fwd * 12.0
		var c3 := t_mid - fwd * 12.0
		tw_verts.append_array([c0, c1, c2, c0, c2, c3])

	# Apron (ramp area) midway along taxiway: 200m x 100m
	var apron_mid := p_start.lerp(p_end, 0.5) + right * 70.0
	var ap0 := apron_mid - fwd * 100.0 - right * 50.0
	var ap1 := apron_mid - fwd * 100.0 + right * 50.0
	var ap2 := apron_mid + fwd * 100.0 + right * 50.0
	var ap3 := apron_mid + fwd * 100.0 - right * 50.0
	tw_verts.append_array([ap0, ap1, ap2, ap0, ap2, ap3])

	var tw_normals := PackedVector3Array()
	tw_normals.resize(tw_verts.size())
	tw_normals.fill(Vector3.UP)
	var tw_uvs := PackedVector2Array()
	tw_uvs.resize(tw_verts.size())
	for i in tw_verts.size():
		tw_uvs[i] = Vector2(tw_verts[i].x * 0.1, tw_verts[i].z * 0.1)

	var tw_arrays: Array = []
	tw_arrays.resize(Mesh.ARRAY_MAX)
	tw_arrays[Mesh.ARRAY_VERTEX] = tw_verts
	tw_arrays[Mesh.ARRAY_TEX_UV] = tw_uvs
	tw_arrays[Mesh.ARRAY_NORMAL] = tw_normals

	var tw_mesh := ArrayMesh.new()
	tw_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tw_arrays)

	var tw_mat := StandardMaterial3D.new()
	tw_mat.albedo_texture = ASPHALT_TEX
	tw_mat.albedo_color = Color(0.2, 0.2, 0.22)
	tw_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	tw_mat.roughness = 0.88

	var tw_mi := MeshInstance3D.new()
	tw_mi.mesh = tw_mesh
	tw_mi.material_override = tw_mat
	tw_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tw_mi)

	# Taxiway edge lights (blue)
	var tw_steps := maxi(2, int(length / 80.0))
	for i in range(tw_steps + 1):
		var t := float(i) / float(tw_steps)
		var center_pt := p_start.lerp(p_end, t)
		var l_pt := center_pt - right * (tw_width * 0.5 + 1.2) + Vector3(0, 0.25, 0)
		var r_pt := center_pt + right * (tw_width * 0.5 + 1.2) + Vector3(0, 0.25, 0)
		lights_out.append({"pos": l_pt, "col": Color(0.2, 0.4, 1.0)})
		lights_out.append({"pos": r_pt, "col": Color(0.2, 0.4, 1.0)})

	# Control Tower
	var tower_pos := apron_mid + right * 65.0 - fwd * 80.0
	_build_control_tower(tower_pos, elev)

	# Hangars & Shelters
	for k in range(3):
		var h_pos := apron_mid + right * 70.0 + fwd * (-30.0 + float(k) * 55.0)
		_build_hangar(h_pos, elev, fwd, right)


func _build_control_tower(pos: Vector3, elev: float) -> void:
	var tower_node := Node3D.new()
	tower_node.position = Vector3(pos.x, elev, pos.z)

	var mat_concrete := StandardMaterial3D.new()
	mat_concrete.albedo_color = Color(0.85, 0.83, 0.8)
	mat_concrete.roughness = 0.75

	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.1, 0.2, 0.25)
	mat_glass.metallic = 0.8
	mat_glass.roughness = 0.2

	# Shaft
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.0
	cyl.bottom_radius = 5.0
	cyl.height = 28.0
	shaft.mesh = cyl
	shaft.material_override = mat_concrete
	shaft.position = Vector3(0.0, 14.0, 0.0)
	tower_node.add_child(shaft)

	# Cab (glass observation deck)
	var cab := MeshInstance3D.new()
	var cab_mesh := CylinderMesh.new()
	cab_mesh.top_radius = 6.5
	cab_mesh.bottom_radius = 5.2
	cab_mesh.height = 5.0
	cab.mesh = cab_mesh
	cab.material_override = mat_glass
	cab.position = Vector3(0.0, 29.5, 0.0)
	tower_node.add_child(cab)

	# Roof and antenna radome
	var radome := MeshInstance3D.new()
	var rad_mesh := SphereMesh.new()
	rad_mesh.radius = 2.5
	rad_mesh.height = 3.5
	radome.mesh = rad_mesh
	radome.material_override = mat_concrete
	radome.position = Vector3(0.0, 33.5, 0.0)
	tower_node.add_child(radome)

	add_child(tower_node)


func _build_hangar(pos: Vector3, elev: float, fwd: Vector3, right: Vector3) -> void:
	var hangar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(36.0, 11.0, 42.0)
	hangar.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.75, 0.78)
	mat.roughness = 0.65
	hangar.material_override = mat

	var basis := Basis(right, Vector3.UP, -fwd)
	hangar.transform = Transform3D(basis, Vector3(pos.x, elev + 5.5, pos.z))
	add_child(hangar)


func _build_edge_lights(lights: Array[Dictionary]) -> void:
	if lights.is_empty():
		return
	var n := lights.size()
	_lights_mm = MultiMesh.new()
	_lights_mm.transform_format = MultiMesh.TRANSFORM_3D
	_lights_mm.use_colors = true
	_lights_mm.mesh = QuadMesh.new()
	(_lights_mm.mesh as QuadMesh).size = Vector2(0.8, 0.8)
	_lights_mm.instance_count = n

	for i in n:
		var p: Vector3 = lights[i]["pos"]
		var c: Color = lights[i]["col"]
		_lights_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
		_lights_mm.set_instance_color(i, c)

	_lights_mat = StandardMaterial3D.new()
	_lights_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lights_mat.vertex_color_use_as_albedo = true
	_lights_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_lights_mat.emission_enabled = true
	_lights_mat.emission = Color.WHITE
	_lights_mat.emission_energy_multiplier = 0.0

	_lights_mmi = MultiMeshInstance3D.new()
	_lights_mmi.multimesh = _lights_mm
	_lights_mmi.material_override = _lights_mat
	_lights_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lights_mmi.visible = false
	add_child(_lights_mmi)
