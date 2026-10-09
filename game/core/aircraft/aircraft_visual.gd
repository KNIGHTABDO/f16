class_name AircraftVisual
extends Node3D
## Visual model of an aircraft. Uses the GLB at AircraftData.model when it exists, otherwise builds a
## low-poly jet from the data's length and wing_span. Also owns the nav lights, afterburner flame,
## shock diamonds and the engine loop. Body frame: nose -Z, right +X, up +Y.
## The aircraft calls set_state() each physics tick; flicker, strobing and engine pitch run in _process.

const TOP_COLOR := Color(0.66, 0.68, 0.7)
const BELLY_COLOR := Color(0.36, 0.38, 0.41)
const CANOPY_COLOR := Color(0.04, 0.06, 0.1)
const NOZZLE_COLOR := Color(0.12, 0.12, 0.13)
const INTAKE_COLOR := Color(0.07, 0.07, 0.08)
const FLAME_COLOR := Color(1.0, 0.5, 0.12, 0.6)
const FLAME_CORE_COLOR := Color(0.75, 0.88, 1.0, 0.8)
const DIAMOND_COLOR := Color(1.0, 0.95, 0.8, 0.9)
const RED_COLOR := Color(1.0, 0.1, 0.08)
const GREEN_COLOR := Color(0.1, 1.0, 0.25)
const WHITE_COLOR := Color(1.0, 1.0, 1.0)
const STROBE_PERIOD := 1.25
const STROBE_ON := 0.07
const DIAMOND_COUNT := 4
const ENGINE_DB_IDLE := -18.0
const ENGINE_DB_FULL := -4.0
const AB_EASE_RATE := 3.0  ## 1/s, how fast the flame lights and goes out

var data: AircraftData
var throttle := 0.0
var afterburner := false

var _model: Node3D
var _fx: Node3D
var _flame: MeshInstance3D
var _flame_core: MeshInstance3D
var _diamonds: Array[MeshInstance3D] = []
var _tail_light: MeshInstance3D
var _engine_loop: AudioStreamPlayer3D
var _time := 0.0
var _ab_mix := 0.0  ## 0..1 eased afterburner intensity
var _rng := RandomNumberGenerator.new()
var _length := 15.0
var _span := 10.0
var _rx := 0.6  ## fuselage radii, metres
var _ry := 0.75


## Builds the model and effects from the aircraft data. Safe to call before the node enters the tree.
func setup(d: AircraftData) -> void:
	data = d
	_length = d.length
	_span = d.wing_span
	_rx = d.length * 0.042
	_ry = d.length * 0.05
	_rng.randomize()
	if d.model != "" and ResourceLoader.exists(d.model):
		var packed := load(d.model) as PackedScene
		if packed != null:
			_model = packed.instantiate() as Node3D
			if _model != null:
				_model.name = "Model"
				_model.scale = Vector3.ONE * d.model_scale
				_model.rotation_degrees = d.model_rotation_deg
				_model.position = d.model_offset
				add_child(_model)
	if _model == null:
		_model = _build_procedural()
		add_child(_model)
	_build_effects()


func _ready() -> void:
	if data != null and data.engine_sound != "":
		_engine_loop = Sfx.attach_loop(data.engine_sound, self, ENGINE_DB_IDLE)


## Called every physics tick by the aircraft: throttle 0..1 and whether the afterburner is lit.
func set_state(new_throttle: float, lit: bool) -> void:
	throttle = clampf(new_throttle, 0.0, 1.0)
	afterburner = lit


## Silences the flame and engine, e.g. when the aircraft is destroyed.
func stop_effects() -> void:
	set_state(0.0, false)
	if _engine_loop != null and is_instance_valid(_engine_loop):
		_engine_loop.stop()
	_engine_loop = null


func _process(delta: float) -> void:
	_time += delta
	_ab_mix = move_toward(_ab_mix, 1.0 if afterburner else 0.0, delta * AB_EASE_RATE)
	_update_flame()
	if _tail_light != null:
		_tail_light.visible = fmod(_time, STROBE_PERIOD) < STROBE_ON
	_update_engine()


func _update_flame() -> void:
	if _flame == null:
		return
	var lit := _ab_mix > 0.01
	_flame.visible = lit
	_flame_core.visible = lit
	for d in _diamonds:
		d.visible = lit
	if not lit:
		return
	var flicker := 1.0 + 0.06 * sin(_time * 53.0) + _rng.randf_range(-0.04, 0.04)
	var flame_len := _length * (0.22 + 0.16 * throttle) * _ab_mix * flicker
	var tail_z := 0.5 * _length
	_flame.position = Vector3(0.0, 0.0, tail_z + flame_len * 0.5)
	_flame.scale = Vector3(1.0, flame_len, 1.0)
	_flame_core.position = Vector3(0.0, 0.0, tail_z + flame_len * 0.3)
	_flame_core.scale = Vector3(1.0, flame_len * 0.6, 1.0)
	var size_f := lerpf(0.5, 1.0, throttle) * _ab_mix
	for k in _diamonds.size():
		var f := size_f * (1.0 - 0.18 * k) * _rng.randf_range(0.85, 1.1)
		_diamonds[k].scale = Vector3(_rx * 0.6, _rx * 0.6, _rx * 0.8) * f


func _update_engine() -> void:
	if _engine_loop == null or not is_instance_valid(_engine_loop):
		return
	var power := clampf(throttle * 0.8 + 0.2 * _ab_mix, 0.0, 1.0)
	_engine_loop.pitch_scale = lerpf(0.75, 1.3, power)
	_engine_loop.volume_db = lerpf(ENGINE_DB_IDLE, ENGINE_DB_FULL, power)


## Procedural airframe: a lofted fuselage with a glossy canopy, trapezoid wings and tails, an intake
## and a nozzle. Everything is sized from the aircraft length and wing span.
func _build_procedural() -> Node3D:
	var root := Node3D.new()
	root.name = "Procedural"
	var l := _length
	var s := _span
	var airframe := _airframe_material()

	var body := _loft([
		Vector3(-0.50 * l, 0.04, 0.0),
		Vector3(-0.44 * l, 0.45, 0.0),
		Vector3(-0.34 * l, 0.85, 0.0),
		Vector3(-0.20 * l, 1.0, 0.0),
		Vector3(0.10 * l, 1.0, 0.0),
		Vector3(0.28 * l, 0.92, 0.0),
		Vector3(0.40 * l, 0.80, 0.0),
		Vector3(0.50 * l, 0.62, 0.0)], _rx, _ry, 12)
	_mesh_inst(body, airframe, root, Vector3.ZERO, Vector3.ZERO)

	var canopy := _loft([
		Vector3(-0.27 * l, 0.10, 0.035 * l),
		Vector3(-0.21 * l, 0.70, 0.035 * l),
		Vector3(-0.13 * l, 1.00, 0.035 * l),
		Vector3(-0.05 * l, 0.90, 0.035 * l),
		Vector3(0.02 * l, 0.50, 0.035 * l),
		Vector3(0.06 * l, 0.10, 0.035 * l)], _rx * 0.85, _ry * 1.0, 10)
	_mesh_inst(canopy, _std(CANOPY_COLOR, 0.3, 0.05), root, Vector3.ZERO, Vector3.ZERO)

	for side in [1.0, -1.0]:
		var wing := _plate([
			Vector3(side * 0.03 * l, 0.0, -0.12 * l),
			Vector3(side * 0.5 * s, 0.0, -0.02 * l),
			Vector3(side * 0.5 * s, 0.0, 0.10 * l),
			Vector3(side * 0.03 * l, 0.0, 0.14 * l)])
		_mesh_inst(wing, airframe, root, Vector3.ZERO, Vector3.ZERO)
		var stab := _plate([
			Vector3(side * 0.03 * l, 0.0, 0.28 * l),
			Vector3(side * 0.3 * s, 0.0, 0.36 * l),
			Vector3(side * 0.3 * s, 0.0, 0.46 * l),
			Vector3(side * 0.03 * l, 0.0, 0.46 * l)])
		_mesh_inst(stab, airframe, root, Vector3.ZERO, Vector3.ZERO)

	var fin := _plate([
		Vector3(0.0, 0.02 * l, 0.30 * l),
		Vector3(0.0, 0.30 * l, 0.37 * l),
		Vector3(0.0, 0.30 * l, 0.44 * l),
		Vector3(0.0, 0.02 * l, 0.46 * l)])
	_mesh_inst(fin, airframe, root, Vector3.ZERO, Vector3.ZERO)

	var intake := BoxMesh.new()
	intake.size = Vector3(_rx * 1.3, _ry * 0.9, 0.34 * l)
	_mesh_inst(intake, _std(INTAKE_COLOR, 0.0, 0.8), root, Vector3(0.0, -_ry * 0.7, -0.16 * l), Vector3.ZERO)

	var nozzle := CylinderMesh.new()
	nozzle.top_radius = _rx * 0.45
	nozzle.bottom_radius = _rx * 0.62
	nozzle.height = 0.08 * l
	nozzle.radial_segments = 14
	nozzle.rings = 1
	_mesh_inst(nozzle, _std(NOZZLE_COLOR, 0.8, 0.35), root, Vector3(0.0, 0.0, 0.46 * l), Vector3(90.0, 0.0, 0.0))
	return root


## Flame, shock diamonds and nav lights. Positions are in body coordinates, so they work with a GLB too.
func _build_effects() -> void:
	_fx = Node3D.new()
	_fx.name = "Fx"
	add_child(_fx)
	var l := _length
	var s := _span

	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = _rx * 0.08
	flame_mesh.bottom_radius = _rx * 0.55
	flame_mesh.height = 1.0
	flame_mesh.radial_segments = 12
	flame_mesh.rings = 1
	_flame = _mesh_inst(flame_mesh, _additive(FLAME_COLOR), _fx, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false

	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = _rx * 0.03
	core_mesh.bottom_radius = _rx * 0.3
	core_mesh.height = 1.0
	core_mesh.radial_segments = 10
	core_mesh.rings = 1
	_flame_core = _mesh_inst(core_mesh, _additive(FLAME_CORE_COLOR), _fx, Vector3.ZERO, Vector3(90.0, 0.0, 0.0))
	_flame_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame_core.visible = false

	var diamond_mesh := SphereMesh.new()
	diamond_mesh.radius = 0.5
	diamond_mesh.height = 1.0
	diamond_mesh.radial_segments = 8
	diamond_mesh.rings = 4
	var diamond_mat := _additive(DIAMOND_COLOR)
	for k in DIAMOND_COUNT:
		var dm := _mesh_inst(diamond_mesh, diamond_mat, _fx, Vector3(0.0, 0.0, (0.5 + 0.05 + 0.08 * k) * l), Vector3.ZERO)
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dm.visible = false
		_diamonds.append(dm)

	var lamp_r := s * 0.012
	var lamp_mesh := _sphere(lamp_r)
	var red := _mesh_inst(lamp_mesh, _lamp(RED_COLOR), _fx, Vector3(-0.5 * s, 0.05, -0.02 * l), Vector3.ZERO)
	var green := _mesh_inst(lamp_mesh, _lamp(GREEN_COLOR), _fx, Vector3(0.5 * s, 0.05, -0.02 * l), Vector3.ZERO)
	red.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	green.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail_light = _mesh_inst(lamp_mesh, _lamp(WHITE_COLOR), _fx, Vector3(0.0, 0.30 * l + 0.05, 0.44 * l), Vector3.ZERO)
	_tail_light.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Lofts a closed tube along Z. stations: Vector3(z, scale, y_offset), nose (-Z) to tail (+Z).
## Each ring is an ellipse with radii rx*scale and ry*scale. Top vertices get TOP_COLOR, belly BELLY_COLOR.
func _loft(stations: Array, rx: float, ry: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev: Array = _ring(stations[0], rx, ry, sides)
	for k in range(1, stations.size()):
		var cur: Array = _ring(stations[k], rx, ry, sides)
		for i in sides:
			_tri(st, prev[i], cur[i], prev[i + 1])
			_tri(st, prev[i + 1], cur[i], cur[i + 1])
		prev = cur
	st.generate_normals()
	return st.commit()


## One ring as Vector4(x, y, z, top_factor) per vertex; the last vertex repeats the first (seam).
func _ring(station: Vector3, rx: float, ry: float, sides: int) -> Array:
	var ring: Array = []
	var sc := station.y
	for i in sides + 1:
		var a := TAU * float(i) / float(sides)
		var c := cos(a)
		var sn := sin(a)
		ring.append(Vector4(c * rx * sc, sn * ry * sc + station.z, station.x, sn * 0.5 + 0.5))
	return ring


func _tri(st: SurfaceTool, a: Vector4, b: Vector4, c: Vector4) -> void:
	_vert(st, a)
	_vert(st, b)
	_vert(st, c)


func _vert(st: SurfaceTool, v: Vector4) -> void:
	st.set_color(BELLY_COLOR.lerp(TOP_COLOR, v.w))
	st.add_vertex(Vector3(v.x, v.y, v.z))


## Flat double-sided polygon (convex, given in order) in the airframe's top colour.
func _plate(pts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size() - 1):
		for idx in [0, i, i + 1]:
			st.set_color(TOP_COLOR)
			st.add_vertex(pts[idx])
	st.generate_normals()
	return st.commit()


func _mesh_inst(mesh: Mesh, mat: Material, parent: Node3D, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


func _airframe_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.25
	m.roughness = 0.42
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _std(color: Color, metallic := 0.0, roughness := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _lamp(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	return m
