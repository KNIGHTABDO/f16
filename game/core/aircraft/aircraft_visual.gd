class_name AircraftVisual
extends Node3D
## Visual model of an aircraft. Uses the GLB at AircraftData.model when it exists, otherwise builds a
## low-poly jet from the data's length and wing_span. With a GLB, control surfaces, gear, gear doors and
## the steerable nose wheel are animated from data/model_info.json (hinge, axis, max_deg per node name).
## Owns one AfterburnerFx per nozzle, a VaporFx shell, nozzle glows and the nav and strobe lights.
## Engine sound is not here (see EngineAudio). Body frame: nose -Z, right +X, up +Y.
## bind() links the visual to its Aircraft (controls, flight state); set_state() is called every tick.

const MODEL_INFO_PATH := "res://data/model_info.json"
const TOP_COLOR := Color(0.66, 0.68, 0.7)
const BELLY_COLOR := Color(0.36, 0.38, 0.41)
const CANOPY_COLOR := Color(0.04, 0.06, 0.1)
const NOZZLE_COLOR := Color(0.12, 0.12, 0.13)
const INTAKE_COLOR := Color(0.07, 0.07, 0.08)
const GLOW_COLOR := Color(1.0, 0.55, 0.2, 0.8)
const RED_COLOR := Color(1.0, 0.1, 0.08)
const GREEN_COLOR := Color(0.1, 1.0, 0.25)
const WHITE_COLOR := Color(1.0, 1.0, 1.0)
const STROBE_PERIOD := 1.25
const STROBE_ON := 0.07
const AB_EASE_RATE := 3.0  ## 1/s, how fast the plumes light and go out
const SURFACE_RATE := 10.0  ## 1/s, smoothing of control surface and steering motion
const DOOR_OPEN_RAD := 1.2  ## gear doors swing this far at mid-transit (the model's max_deg is a multi-turn value)
const FLAP_CMD_GEAR := 0.5  ## flaperons droop to this fraction of full when the gear is down
const FRONT_RETRACT_DESIRED := Vector3(0.0, 0.3, -1.0)  ## nose gear and main gear retract forward
const INNER_OUTER_DESIRED := Vector3(0.0, 1.0, 0.0)  ## gear braces fold upward

const ROLE_SURFACE := 0
const ROLE_GEAR := 1
const ROLE_DOOR := 2


## One animated GLB node. Placed as Transform3D(Basis(axis, angle), pivot), then, for steered nodes,
## multiplied by Transform3D(Basis(steer_axis, steer), rest_pos - pivot).
class Part extends RefCounted:
	var node: Node3D
	var role := 0
	var pivot := Vector3.ZERO  ## hinge point in model coordinates
	var axis := Vector3.ZERO  ## unit hinge axis
	var rest_pos := Vector3.ZERO  ## node origin at rest (equals pivot unless steered)
	var max_rad := 0.0
	var dir := 1.0  ## +1 or -1: makes a positive input move the part the intended way
	var cmd := ""  ## surfaces: "roll", "pitch", "yaw", "brake" or "flap"
	var steer := false
	var steer_axis := Vector3.ZERO
	var steer_max := 0.0
	var cur := 0.0  ## smoothed surface angle, rad
	var cur_steer := 0.0


var data: AircraftData
var throttle := 0.0
var afterburner := false

var _aircraft: Aircraft
var _model: Node3D
var _root_xf := Transform3D.IDENTITY  ## model root transform (scale, rotation, offset) into body space
var _info: Dictionary = {}  ## model_info.json entry for this aircraft
var _parts: Array[Part] = []
var _fx: Node3D
var _plumes: Array[AfterburnerFx] = []
var _glows: Array[MeshInstance3D] = []
var _tail_light: MeshInstance3D
var _vapor: VaporFx
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
	_info = _load_model_info(d.id)
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
				_root_xf = _model.transform
				_collect_parts()
	if _model == null:
		_model = _build_procedural()
		add_child(_model)
	_build_effects()


## Links the visual to its aircraft so it can read the controls, gear and airbrake state each frame.
func bind(aircraft: Aircraft) -> void:
	_aircraft = aircraft


## Called every physics tick by the aircraft: throttle 0..1 and whether the afterburner is lit.
func set_state(new_throttle: float, lit: bool) -> void:
	throttle = clampf(new_throttle, 0.0, 1.0)
	afterburner = lit


## Silences the plumes, e.g. when the aircraft is destroyed.
func stop_effects() -> void:
	set_state(0.0, false)


func _process(delta: float) -> void:
	_time += delta
	_ab_mix = move_toward(_ab_mix, 1.0 if afterburner else 0.0, delta * AB_EASE_RATE)
	var mach := 0.0
	var g := 1.0
	var aoa := 0.0
	var alt := 0.0
	if _aircraft != null and is_instance_valid(_aircraft):
		mach = _aircraft.get_mach()
		g = _aircraft.get_g()
		aoa = _aircraft.flight.alpha
		alt = _aircraft.get_altitude_m()
	for ab in _plumes:
		ab.set_intensity(_ab_mix)
		ab.update(mach, g, aoa, alt)
	var lit := _ab_mix > 0.01
	for glow in _glows:
		glow.visible = lit
	if _tail_light != null:
		_tail_light.visible = fmod(_time, STROBE_PERIOD) < STROBE_ON
	_update_parts(delta)
	if _vapor != null:
		_vapor.update(mach, g, aoa, alt)


## Loads one model_info.json entry by aircraft id. Empty dictionary when missing.
func _load_model_info(id: String) -> Dictionary:
	var f := FileAccess.open(MODEL_INFO_PATH, FileAccess.READ)
	if f == null:
		return {}
	var all: Variant = JSON.parse_string(f.get_as_text())
	if typeof(all) != TYPE_DICTIONARY:
		return {}
	var entry: Variant = (all as Dictionary).get(id, {})
	return entry as Dictionary if typeof(entry) == TYPE_DICTIONARY else {}


func _cs() -> Dictionary:
	return _info.get("control_surfaces", {}) as Dictionary


func _vec(a: Variant) -> Vector3:
	var arr := a as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _hinge(node_name: String) -> Vector3:
	var cs := _cs()
	return _vec(cs[node_name]["hinge"]) if cs.has(node_name) else Vector3.ZERO


## Sign that makes `desired` the direction a positive rotation about `axis` moves point `d`.
func _sign_for(axis: Vector3, d: Vector3, desired: Vector3) -> float:
	return 1.0 if axis.cross(d).dot(desired) >= 0.0 else -1.0


## Centre of a node's mesh in the node's own space (union of its MeshInstance3D children).
func _local_center(n: Node3D) -> Vector3:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).get_aabb().get_center()
	var box := AABB()
	var first := true
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var b: AABB = mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return Vector3.ZERO if first else box.get_center()


## Model-space point to body space (the model root transform: scale, rotation, offset).
func _to_body(p: Vector3) -> Vector3:
	return _root_xf * p


func _collect_parts() -> void:
	var cs := _cs()
	if cs.is_empty():
		return
	# Control surfaces: rotation axis from the model; dir from the aft (+Z) point moving toward the
	# trailing-edge direction that a positive command should produce.
	var surfaces := {
		"aileron_l": ["roll", Vector3(0, -1, 0)],
		"aileron_r": ["roll", Vector3(0, 1, 0)],
		"elevator_l": ["pitch", Vector3(0, -1, 0)],
		"elevator_r": ["pitch", Vector3(0, -1, 0)],
		"rudder": ["yaw", Vector3(-1, 0, 0)],
		"flap_l": ["flap", Vector3(0, -1, 0)],
		"flap_r": ["flap", Vector3(0, -1, 0)],
		"speedbrake_l": ["brake", Vector3(0, 1, 0)],
		"speedbrake_r": ["brake", Vector3(0, 1, 0)],
	}
	for key in surfaces:
		var node := _model.find_child(key, true, false) as Node3D
		if node == null or not cs.has(key):
			continue
		var info: Dictionary = cs[key]
		var p := Part.new()
		p.node = node
		p.role = ROLE_SURFACE
		p.cmd = surfaces[key][0]
		p.pivot = _vec(info["hinge"])
		p.rest_pos = p.pivot
		p.axis = _vec(info["axis"]).normalized()
		p.max_rad = deg_to_rad(float(info["max_deg"]))
		p.dir = _sign_for(p.axis, Vector3(0, 0, 1), surfaces[key][1])
		_parts.append(p)

	# Gear legs. Each chain shares one direction, taken from its reference (wheel or lower brace).
	var front_axis := _vec(cs["gear_FrontUpperStrut"]["axis"]).normalized() if cs.has("gear_FrontUpperStrut") else Vector3.RIGHT
	var front_pivot := _hinge("gear_FrontUpperStrut")
	_add_chain(["gear_FrontAftStrut", "gear_FrontUpperStrut", "gear_FrontLowerStrut", "gear_FrontTire"],
			"gear_FrontTire", front_pivot, front_axis, 112.0, FRONT_RETRACT_DESIRED,
			["gear_FrontLowerStrut", "gear_FrontTire"])
	for side in ["Left", "Right"]:
		var lower := "gear_%sLowerMainStrut" % side
		var axis := _vec(cs[lower]["axis"]).normalized() if cs.has(lower) else Vector3.RIGHT
		_add_chain(["gear_%sLowerMainStrut" % side, "gear_%sUpperMainStrut" % side, "gear_%sMainTire" % side],
				"gear_%sMainTire" % side, _hinge(lower), axis, 95.0, FRONT_RETRACT_DESIRED, [])
		_add_chain(["gear_%sInnerStrut" % side], "gear_%sInnerStrut" % side,
				_hinge("gear_%sInnerStrut" % side), _axis_of("gear_%sInnerStrut" % side), 20.0,
				INNER_OUTER_DESIRED, [])
		var outer := "gear_%sOuterLowerStrut" % side
		_add_chain(["gear_%sOuterLowerStrut" % side, "gear_%sOuterUpperStrut" % side], outer,
				_hinge(outer), _axis_of(outer), 10.0, INNER_OUTER_DESIRED, [])

	# Gear doors swing open at mid-transit and are shut when the gear is fully up or down.
	for door in ["gear_ExternalFrontGearDoor", "gear_InternalFrontGearDoor",
			"gear_ExternalLeftMainDoor", "gear_ExternalRightMainDoor"]:
		var node := _model.find_child(door, true, false) as Node3D
		if node == null or not cs.has(door):
			continue
		var hinge := _hinge(door)
		var p := Part.new()
		p.node = node
		p.role = ROLE_DOOR
		p.pivot = hinge
		p.rest_pos = hinge
		p.axis = _axis_of(door)
		p.max_rad = DOOR_OPEN_RAD
		p.dir = _sign_for(p.axis, _local_center(node), Vector3(signf(hinge.x), -1.0, 0.0))
		_parts.append(p)


func _axis_of(node_name: String) -> Vector3:
	var cs := _cs()
	return _vec(cs[node_name]["axis"]).normalized() if cs.has(node_name) else Vector3.RIGHT


## One retracting gear leg. names: every node in the chain. ref_name: node whose mesh sets the direction.
func _add_chain(names: Array, ref_name: String, pivot: Vector3, axis: Vector3, max_deg: float,
		desired: Vector3, steer_names: Array) -> void:
	var ref := _model.find_child(ref_name, true, false) as Node3D
	if ref == null or not _cs().has(ref_name):
		return
	var dir := _sign_for(axis, _hinge(ref_name) - pivot + _local_center(ref), desired)
	for n in names:
		var node_name := String(n)
		var node := _model.find_child(node_name, true, false) as Node3D
		if node == null or not _cs().has(node_name):
			continue
		var p := Part.new()
		p.node = node
		p.role = ROLE_GEAR
		p.pivot = pivot
		p.axis = axis
		p.rest_pos = _hinge(node_name)
		p.max_rad = deg_to_rad(max_deg)
		p.dir = dir
		if steer_names.has(node_name):
			var info: Dictionary = _cs()[node_name]
			p.steer = true
			p.steer_axis = _vec(info["axis"]).normalized()
			p.steer_max = deg_to_rad(float(info["max_deg"]))
		_parts.append(p)


func _gear_pos() -> float:
	return _aircraft.flight.gear_pos if _aircraft != null and is_instance_valid(_aircraft) else 1.0


func _cmd_value(cmd: String, g: float) -> float:
	if _aircraft == null or not is_instance_valid(_aircraft):
		return 0.0
	match cmd:
		"roll":
			return clampf(_aircraft.controls.roll, -1.0, 1.0)
		"pitch":
			return clampf(_aircraft.controls.pitch, -1.0, 1.0)
		"yaw":
			return clampf(_aircraft.controls.yaw, -1.0, 1.0)
		"brake":
			return _aircraft.flight.airbrake_pos
		"flap":
			return FLAP_CMD_GEAR * g
	return 0.0


func _update_parts(delta: float) -> void:
	if _parts.is_empty():
		return
	var g := _gear_pos()
	var k := 1.0 - exp(-SURFACE_RATE * delta)
	var steer_in := 0.0
	if _aircraft != null and is_instance_valid(_aircraft) and _aircraft.is_on_ground():
		steer_in = clampf(_aircraft.controls.yaw, -1.0, 1.0)
	for p in _parts:
		match p.role:
			ROLE_SURFACE:
				var target := p.dir * p.max_rad * _cmd_value(p.cmd, g)
				p.cur = lerpf(p.cur, target, k)
				_place(p, p.cur, 0.0)
			ROLE_GEAR:
				p.cur_steer = lerpf(p.cur_steer, steer_in * p.steer_max, k)
				_place(p, p.dir * p.max_rad * (1.0 - g), p.cur_steer)
			_:
				_place(p, p.dir * p.max_rad * sin(g * PI), 0.0)


func _place(p: Part, angle: float, steer_angle: float) -> void:
	var t := Transform3D(Basis(p.axis, angle), p.pivot)
	if p.steer:
		t = t * Transform3D(Basis(p.steer_axis, steer_angle), p.rest_pos - p.pivot)
	p.node.transform = t


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


## Plumes (one per nozzle), nozzle glows, shell and nav lights. Positions are in body coordinates.
func _build_effects() -> void:
	_fx = Node3D.new()
	_fx.name = "Fx"
	add_child(_fx)
	var l := _length
	var s := _span
	var has_info := not _info.is_empty() and _info.has("nozzles")

	var nozzles: Array = []
	if has_info:
		for n in _info["nozzles"]:
			nozzles.append({"pos": _to_body(_vec(n["pos"])), "radius": float(n["radius"])})
	else:
		nozzles.append({"pos": Vector3(0.0, 0.0, 0.46 * l), "radius": _rx * 0.62})
	for spec in nozzles:
		var holder := Node3D.new()
		holder.name = "Nozzle"
		holder.position = spec["pos"]
		_fx.add_child(holder)
		var radius: float = spec["radius"]
		var plume := AfterburnerFx.new()
		plume.name = "Plume"
		holder.add_child(plume)
		plume.setup(radius * 1.2)
		_plumes.append(plume)
		var glow_mesh := CylinderMesh.new()
		glow_mesh.top_radius = radius * 0.9
		glow_mesh.bottom_radius = radius * 0.9
		glow_mesh.height = 0.12
		glow_mesh.radial_segments = 16
		glow_mesh.rings = 1
		var glow := _mesh_inst(glow_mesh, _additive(GLOW_COLOR), holder, Vector3(0.0, 0.0, 0.04), Vector3(90.0, 0.0, 0.0))
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.visible = false
		_glows.append(glow)

	_vapor = VaporFx.new()
	_vapor.name = "Vapor"
	add_child(_vapor)
	_vapor.setup(l * 0.8, maxf(_rx, _ry) * 1.1, _to_body(Vector3.ZERO))

	var lamp_r := s * 0.012
	var lamp_mesh := _sphere(lamp_r)
	var left_tip := Vector3(-0.5 * s, 0.05, -0.02 * l)
	var right_tip := Vector3(0.5 * s, 0.05, -0.02 * l)
	var tail := Vector3(0.0, 0.30 * l + 0.05, 0.44 * l)
	if has_info and _info.has("wingtips"):
		var tips: Array = _info["wingtips"]
		left_tip = _to_body(_vec(tips[0]))
		right_tip = _to_body(_vec(tips[1]))
		tail = _to_body(Vector3(0.0, 2.3, 6.4))
	var red := _mesh_inst(lamp_mesh, _lamp(RED_COLOR), _fx, left_tip, Vector3.ZERO)
	var green := _mesh_inst(lamp_mesh, _lamp(GREEN_COLOR), _fx, right_tip, Vector3.ZERO)
	red.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	green.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tail_light = _mesh_inst(lamp_mesh, _lamp(WHITE_COLOR), _fx, tail, Vector3.ZERO)
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
