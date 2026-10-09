class_name TrailFx
extends Node3D
## Persistent trail that follows a node (missile, rocket, burning or smoking aircraft, flare) and fades out
## after stop(). Positions are sampled at a fixed interval into a ring buffer, stored relative to this node.
## This node sits under World in group "floating", so WorldOrigin shifts move it and the stored points stay
## valid without any fix-up. Per trail: one MultiMesh of smoke puffs, one ArrayMesh ribbon core, and one
## motor glow quad (about 3 draw calls). Pooled through Vfx; use Vfx.attach_trail / Vfx.stop_trail.

const MAX_POINTS := 64
static var HIDDEN := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
const LIFE_PAD := 0.15
const CULL_BOX := 800.0

## kind -> tuning. life: seconds a puff lives; size0/size1: puff size at birth and death (m);
## ribbon: half width (0 = no ribbon core); motor: glow quad size (0 = none); flame: motor uses fire colours.
const PRESETS := {
	"missile": {"life": 2.0, "size0": 2.0, "size1": 5.5, "puff": Color(0.95, 0.96, 0.98), "alpha": 0.78,
		"ribbon": 0.34, "ribbon_color": Color(1.0, 0.97, 0.9), "ribbon_alpha": 0.9,
		"motor": 3.6, "hot": Color(1.0, 1.0, 1.0), "mid": Color(0.6, 0.8, 1.0), "smoke": Color(0.6, 0.6, 0.6)},
	"rocket": {"life": 1.3, "size0": 1.2, "size1": 3.0, "puff": Color(0.92, 0.92, 0.92), "alpha": 0.7,
		"ribbon": 0.16, "ribbon_color": Color(1.0, 0.96, 0.88), "ribbon_alpha": 0.8,
		"motor": 2.6, "hot": Color(1.0, 0.95, 0.75), "mid": Color(1.0, 0.6, 0.2), "smoke": Color(0.3, 0.3, 0.3)},
	"fire": {"life": 2.8, "size0": 1.6, "size1": 4.6, "puff": Color(0.12, 0.11, 0.1), "alpha": 0.72,
		"ribbon": 0.0, "ribbon_color": Color(0.1, 0.1, 0.1), "ribbon_alpha": 0.0,
		"motor": 4.2, "hot": Color(1.0, 0.93, 0.66), "mid": Color(1.0, 0.44, 0.12), "smoke": Color(0.1, 0.09, 0.08)},
	"smoke_light": {"life": 7.0, "size0": 2.4, "size1": 9.0, "puff": Color(0.66, 0.66, 0.66), "alpha": 0.5,
		"ribbon": 0.0, "ribbon_color": Color(0.7, 0.7, 0.7), "ribbon_alpha": 0.0,
		"motor": 0.0, "hot": Color(1, 1, 1), "mid": Color(1, 1, 1), "smoke": Color(1, 1, 1)},
	"smoke_heavy": {"life": 10.0, "size0": 3.0, "size1": 12.0, "puff": Color(0.1, 0.095, 0.09), "alpha": 0.78,
		"ribbon": 0.0, "ribbon_color": Color(0.1, 0.1, 0.1), "ribbon_alpha": 0.0,
		"motor": 0.0, "hot": Color(1, 1, 1), "mid": Color(1, 1, 1), "smoke": Color(1, 1, 1)},
	"flare": {"life": 3.0, "size0": 1.0, "size1": 3.6, "puff": Color(0.9, 0.9, 0.9), "alpha": 0.5,
		"ribbon": 0.0, "ribbon_color": Color(1, 1, 1), "ribbon_alpha": 0.0,
		"motor": 0.0, "hot": Color(1, 1, 1), "mid": Color(1, 1, 1), "smoke": Color(1, 1, 1)},
}

var _pool: FxPool
var _follow: Node3D
var _offset := Vector3.ZERO
var _kind := "smoke_light"
var _life := 4.0
var _size0 := 1.0
var _size1 := 3.0
var _puff_color := Color.WHITE
var _puff_alpha := 0.5
var _ribbon_width := 0.0
var _ribbon_color := Color.WHITE
var _ribbon_alpha := 0.0
var _motor_size := 0.0
var _interval := 0.05

var _emitting := false
var _time := 0.0
var _stop_time := 0.0
var _emit_timer := 0.0
var _head_rel := Vector3.ZERO
var _built := false

var _pts := PackedVector3Array()
var _birth := PackedFloat32Array()
var _rnd := PackedFloat32Array()
var _newest := 0
var _count := 0

var _puffs: MultiMeshInstance3D
var _multimesh: MultiMesh
var _ribbon: MeshInstance3D
var _ribbon_mesh: ArrayMesh
var _ribbon_mat: ShaderMaterial
var _motor: MeshInstance3D
var _motor_mat: ShaderMaterial


func _ready() -> void:
	if not _built:
		_build()


func _build() -> void:
	_built = true
	_pts.resize(MAX_POINTS)
	_birth.resize(MAX_POINTS)
	_rnd.resize(MAX_POINTS)

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = VfxAssets.quad()
	_multimesh.instance_count = MAX_POINTS
	_puffs = MultiMeshInstance3D.new()
	_puffs.multimesh = _multimesh
	_puffs.material_override = VfxAssets.sprite_material("puff.png", false, BaseMaterial3D.BILLBOARD_ENABLED)
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.custom_aabb = AABB(Vector3(-CULL_BOX, -CULL_BOX, -CULL_BOX), Vector3(CULL_BOX * 2.0, CULL_BOX * 2.0, CULL_BOX * 2.0))
	# Rebuilt from _process every frame, so physics interpolation must not run on it.
	_puffs.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_puffs)

	_ribbon_mesh = ArrayMesh.new()
	_ribbon_mat = VfxAssets.shader_material("ribbon.gdshader")
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	_ribbon.material_override = _ribbon_mat
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ribbon)

	_motor_mat = VfxAssets.shader_material("fireball.gdshader")
	_motor_mat.set_shader_parameter("steady", 1.0)
	_motor_mat.set_shader_parameter("progress", 0.3)
	_motor = MeshInstance3D.new()
	_motor.mesh = VfxAssets.quad()
	_motor.material_override = _motor_mat
	_motor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motor)


## Starts a trail. Must be called after the node is in the tree (it is placed at the follow node).
func setup(pool: FxPool, follow: Node3D, kind: String, offset: Vector3) -> void:
	if not _built:
		_build()
	_pool = pool
	_follow = follow
	_offset = offset
	_kind = kind
	var pr: Dictionary = PRESETS.get(kind, PRESETS["smoke_light"])
	_life = pr["life"]
	_size0 = pr["size0"]
	_size1 = pr["size1"]
	_puff_color = pr["puff"]
	_puff_alpha = pr["alpha"]
	_ribbon_width = pr["ribbon"]
	_ribbon_color = pr["ribbon_color"]
	_ribbon_alpha = pr["ribbon_alpha"]
	_motor_size = pr["motor"]
	_interval = _life / float(MAX_POINTS)
	_ribbon_mat.set_shader_parameter("half_width", _ribbon_width)
	_ribbon_mat.set_shader_parameter("taper", 0.55)
	_motor_mat.set_shader_parameter("hot_color", pr["hot"])
	_motor_mat.set_shader_parameter("mid_color", pr["mid"])
	_motor_mat.set_shader_parameter("smoke_color", pr["smoke"])
	_motor_mat.set_shader_parameter("seed", randf() * 10.0)

	_time = 0.0
	_emit_timer = _interval
	_count = 0
	_newest = 0
	_emitting = true
	_stop_time = 0.0
	_head_rel = Vector3.ZERO
	for i in MAX_POINTS:
		_multimesh.set_instance_transform(i, HIDDEN)
	_ribbon.visible = false
	_motor.visible = _motor_size > 0.0
	add_to_group("floating")
	global_position = _follow.global_position + _offset
	reset_physics_interpolation()


## Ends emission; the trail fades out over its life, then the node returns to its pool.
func stop() -> void:
	if not _emitting:
		return
	_emitting = false
	_stop_time = _time
	_motor.visible = false


func is_emitting() -> bool:
	return _emitting


func _process(delta: float) -> void:
	_time += delta
	if _emitting:
		if _follow == null or not is_instance_valid(_follow):
			stop()
		else:
			_head_rel = _follow.global_position + _offset - global_position
			_emit_timer += delta
			if _emit_timer >= _interval:
				_emit_timer = 0.0
				_push_point(_head_rel)
			if _motor.visible:
				var flick := 0.88 + 0.12 * sin(_time * 41.0) * sin(_time * 13.0)
				_motor.position = _head_rel
				_motor.scale = Vector3.ONE * _motor_size * flick
	_update_puffs()
	if _ribbon_width > 0.0:
		_rebuild_ribbon()
	if not _emitting and _time - _stop_time >= _life + LIFE_PAD:
		_finish()


func _push_point(rel: Vector3) -> void:
	_newest = (_newest + 1) % MAX_POINTS
	_pts[_newest] = rel
	_birth[_newest] = _time
	_rnd[_newest] = randf()
	if _count < MAX_POINTS:
		_count += 1


## Index of the i-th newest point (0 = newest).
func _slot(i: int) -> int:
	return (_newest - i + MAX_POINTS) % MAX_POINTS


func _update_puffs() -> void:
	for s in _count:
		var age := (_time - _birth[s]) / _life
		if age >= 1.0:
			_multimesh.set_instance_transform(s, HIDDEN)
			continue
		var size := lerpf(_size0, _size1, age) * (0.8 + 0.4 * _rnd[s])
		var fade := pow(1.0 - age, 1.4) * smoothstep(0.0, 0.08, age)
		_multimesh.set_instance_transform(s, Transform3D(Basis.from_scale(Vector3.ONE * size), _pts[s]))
		_multimesh.set_instance_color(s, Color(_puff_color.r, _puff_color.g, _puff_color.b, _puff_alpha * fade))


## Ribbon through the head (live) and the stored points, newest first. Two vertices per point:
## UV.y 0/1 across the ribbon, UV.x 0 at the head .. 1 at the tail, NORMAL = travel direction.
func _rebuild_ribbon() -> void:
	var n := 1
	while n <= _count and n < MAX_POINTS:
		var s := _slot(n - 1)
		if (_time - _birth[s]) / _life >= 1.0:
			break
		n += 1
	if n < 2:
		_ribbon.visible = false
		return
	_ribbon.visible = true

	var pos := PackedVector3Array()
	var ages := PackedFloat32Array()
	pos.resize(n)
	ages.resize(n)
	pos[0] = _head_rel
	ages[0] = 0.0
	for i in range(1, n):
		var s := _slot(i - 1)
		pos[i] = _pts[s]
		ages[i] = (_time - _birth[s]) / _life

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(2 * n)
	norms.resize(2 * n)
	uvs.resize(2 * n)
	cols.resize(2 * n)
	for i in n:
		var newer: Vector3 = pos[maxi(i - 1, 0)]
		var older: Vector3 = pos[mini(i + 1, n - 1)]
		var tangent := newer - older
		if tangent.length_squared() < 1e-8:
			tangent = Vector3.FORWARD
		var a := ages[i]
		var alpha := pow(1.0 - a, 1.5) * _ribbon_alpha
		var c := Color(_ribbon_color.r, _ribbon_color.g, _ribbon_color.b, alpha)
		var u := float(i) / float(maxi(n - 1, 1))
		for side in 2:
			var k := 2 * i + side
			verts[k] = pos[i]
			norms[k] = tangent.normalized()
			uvs[k] = Vector2(u, float(side))
			cols[k] = c
	for i in n - 1:
		var a0 := 2 * i
		var b0 := 2 * i + 1
		var a1 := 2 * i + 2
		var b1 := 2 * i + 3
		idx.append(a0)
		idx.append(b0)
		idx.append(a1)
		idx.append(b0)
		idx.append(b1)
		idx.append(a1)

	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	_ribbon_mesh.clear_surfaces()
	_ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


func _finish() -> void:
	_emitting = false
	_follow = null
	visible = false
	remove_from_group("floating")
	if _pool != null:
		_pool.give(self)
	_pool = null
