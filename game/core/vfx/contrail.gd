class_name Contrail
extends Node3D
## Condensation trails from both wingtips and (balanced preset and up) the engine exhaust. Drawn while the
## aircraft pulls more than CONTRAIL_G or flies above CONTRAIL_ALT (metres, ASL). One MeshInstance3D with one
## ribbon per trail (one draw call). This node is a child of World, in group "floating", with identity basis:
## points are stored relative to it, so WorldOrigin shifts need no fix-up.
## Usage: add to World, call setup(), then call update(speed_mach, g, aoa, alt) every frame.
## update() only sets the state; sampling, ageing and the ribbon rebuild run in _process().
## aoa (radians) is accepted for the shared aircraft-effect signature but is not used by contrails.

const CONTRAIL_G := 4.0
const CONTRAIL_ALT := 8000.0
const CONTRAIL_MIN_MACH := 0.3
const MAX_POINTS := 60
const SAMPLE_INTERVAL := 0.08
const LIFE := 8.0
const HALF_WIDTH := 0.45
const TAPER := 0.25
const STRENGTH_RATE := 1.5  # per second, fade in/out
const ALPHA := 0.85


class Track:
	var local := Vector3.ZERO
	var pts := PackedVector3Array()  # oldest first; positions relative to this node
	var birth := PackedFloat32Array()  # emit time of each point (seconds since build)


var _aircraft: Node3D
var _tracks: Array[Track] = []
var _want := false
var _was_want := false
var _retiring := false
var _strength := 0.0
var _time := 0.0
var _sample_timer := 0.0
var _mesh: ArrayMesh
var _mesh_inst: MeshInstance3D
var _mat: ShaderMaterial
var _built := false


func _ready() -> void:
	if not _built:
		_build()


func _build() -> void:
	_built = true
	_mesh = ArrayMesh.new()
	_mat = VfxAssets.shader_material("ribbon.gdshader")
	_mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 1.0))
	_mat.set_shader_parameter("half_width", HALF_WIDTH)
	_mat.set_shader_parameter("taper", TAPER)
	_mat.set_shader_parameter("alpha_mul", 1.0)
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _mesh
	_mesh_inst.material_override = _mat
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.custom_aabb = AABB(Vector3(-2000.0, -2000.0, -2000.0), Vector3(4000.0, 4000.0, 4000.0))
	_mesh_inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mesh_inst)


## Binds the trail to an aircraft. wing_half_span: distance from the fuselage to each wingtip (m).
## engine_offset: exhaust position in the aircraft's local space. Must be in the tree.
func setup(aircraft: Node3D, wing_half_span: float, engine_offset: Vector3) -> void:
	if not _built:
		_build()
	_aircraft = aircraft
	_tracks.clear()
	_tracks.append(_new_track(Vector3(-wing_half_span, 0.0, 0.0)))
	_tracks.append(_new_track(Vector3(wing_half_span, 0.0, 0.0)))
	if VfxAssets.amount_scale() >= 0.7:
		_tracks.append(_new_track(engine_offset))
	_want = false
	_was_want = false
	_retiring = false
	_strength = 0.0
	global_position = aircraft.global_position
	add_to_group("floating")
	reset_physics_interpolation()


## Called every frame by the aircraft.
func update(speed_mach: float, g: float, _aoa: float, alt: float) -> void:
	_want = not _retiring and _aircraft != null and speed_mach > CONTRAIL_MIN_MACH \
			and (g > CONTRAIL_G or alt > CONTRAIL_ALT)


## Stops new points; the existing trail fades out and the node frees itself.
func retire() -> void:
	_want = false
	_retiring = true


func _new_track(local: Vector3) -> Track:
	var t := Track.new()
	t.local = local
	return t


func _process(delta: float) -> void:
	_time += delta
	if _aircraft == null or not is_instance_valid(_aircraft):
		_want = false
		_retiring = true
	if _want and not _was_want:
		_sample_timer = 0.0
	_was_want = _want

	if _want:
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = SAMPLE_INTERVAL
			_sample()
	var target := 1.0 if _want else 0.0
	_strength = move_toward(_strength, target, STRENGTH_RATE * delta)

	var any_points := false
	for tr in _tracks:
		while tr.pts.size() > 0 and (_time - tr.birth[0]) / LIFE >= 1.0:
			tr.pts.remove_at(0)
			tr.birth.remove_at(0)
		if tr.pts.size() > 0:
			any_points = true

	if _retiring and not any_points and _strength <= 0.0:
		remove_from_group("floating")
		queue_free()
		return
	if any_points or _strength > 0.0:
		_mesh_inst.visible = true
		_rebuild()
	else:
		_mesh_inst.visible = false


func _sample() -> void:
	var xf := _aircraft.global_transform
	for tr in _tracks:
		var rel := xf * tr.local - global_position
		tr.pts.append(rel)
		tr.birth.append(_time)
		if tr.pts.size() > MAX_POINTS:
			tr.pts.remove_at(0)
			tr.birth.remove_at(0)


## One ribbon per track, newest point first, the live head included. Two vertices per point:
## UV.y 0/1 across, UV.x 0 at the head .. 1 at the tail, NORMAL = direction of travel, COLOR alpha = age fade.
func _rebuild() -> void:
	var xf := _aircraft.global_transform if _aircraft != null and is_instance_valid(_aircraft) else global_transform
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	for tr in _tracks:
		var pos := PackedVector3Array()
		var ages := PackedFloat32Array()
		pos.append(xf * tr.local - global_position)
		ages.append(0.0)
		for i in range(tr.pts.size() - 1, -1, -1):
			pos.append(tr.pts[i])
			ages.append((_time - tr.birth[i]) / LIFE)
		var m := pos.size()
		if m < 2:
			continue
		var base := verts.size()
		for i in m:
			var newer: Vector3 = pos[maxi(i - 1, 0)]
			var older: Vector3 = pos[mini(i + 1, m - 1)]
			var tangent := newer - older
			if tangent.length_squared() < 1e-8:
				tangent = Vector3.FORWARD
			var alpha := pow(clampf(1.0 - ages[i], 0.0, 1.0), 1.5) * _strength * ALPHA
			var c := Color(1.0, 1.0, 1.0, alpha)
			var u := float(i) / float(m - 1)
			for side in 2:
				verts.append(pos[i])
				norms.append(tangent.normalized())
				uvs.append(Vector2(u, float(side)))
				cols.append(c)
		for i in m - 1:
			var a0 := base + 2 * i
			var b0 := a0 + 1
			var a1 := a0 + 2
			var b1 := a0 + 3
			idx.append(a0)
			idx.append(b0)
			idx.append(a1)
			idx.append(b0)
			idx.append(b1)
			idx.append(a1)

	_mesh.clear_surfaces()
	if verts.is_empty():
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
