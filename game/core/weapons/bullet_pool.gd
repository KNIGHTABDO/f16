class_name BulletPool
extends Node3D
## Shared pool for all gun rounds in the level. One MultiMeshInstance3D draws every visible tracer.
## Rounds are simulated each physics tick (gravity, drag), tested against Hitbox areas with intersect_ray and
## against the terrain every 3rd tick. Get the pool with BulletPool.get_pool(node).

const MAX_BULLETS := 600
const MAX_TRACERS := 300
const GRAVITY := 9.81
const DRAG_K := 2.0e-5  ## drag acceleration = DRAG_K * speed^2
const HIT_MASK := 2 | 4 | 8  ## physics layers 2, 3, 4 as bitmask values
const GROUND_CHECK_EVERY := 3
const TRACER_LENGTH := 16.0
const TRACER_WIDTH := 0.7
const SOUND_EVERY := 4  ## play one hit sound per this many hits

const SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform;
uniform float len = 16.0;
uniform float width = 0.7;
uniform vec3 color : source_color = vec3(1.0, 0.75, 0.3);
varying float along;
void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - center);
	vec3 side = normalize(cross(axis, to_cam));
	vec3 w = center + axis * VERTEX.z * len + side * VERTEX.x * width;
	along = VERTEX.z + 0.5;
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
}
void fragment() {
	float core = 1.0 - abs(UV.x - 0.5) * 2.0;
	float tail = smoothstep(0.0, 1.0, along);
	ALBEDO = color * (0.6 + 1.6 * core) * tail;
}
"""

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _prev_ground := PackedVector3Array()
var _life := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _tracer := PackedByteArray()
var _shooter: Array = []
var _exclude: Array = []
var _count := 0
var _tick := 0
var _hits := 0
var _query := PhysicsRayQueryParameters3D.new()
var _mm: MultiMesh
var _buf := PackedFloat32Array()


static func get_pool(from: Node) -> BulletPool:
	var tree := from.get_tree()
	var existing := tree.get_first_node_in_group("bullet_pool")
	if existing != null and is_instance_valid(existing):
		return existing as BulletPool
	var host: Node = null
	if tree.current_scene != null:
		host = tree.current_scene.find_child("World", true, false)
	if host == null:
		host = from.get_parent()
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	host.add_child(pool)
	return pool


func _ready() -> void:
	add_to_group("bullet_pool")
	_pos.resize(MAX_BULLETS)
	_vel.resize(MAX_BULLETS)
	_prev_ground.resize(MAX_BULLETS)
	_life.resize(MAX_BULLETS)
	_damage.resize(MAX_BULLETS)
	_tracer.resize(MAX_BULLETS)
	_shooter.resize(MAX_BULLETS)
	_exclude.resize(MAX_BULLETS)
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	_query.collision_mask = HIT_MASK
	_buf.resize(MAX_TRACERS * 12)
	var mesh := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sh := Shader.new()
	sh.code = SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("len", TRACER_LENGTH)
	sm.set_shader_parameter("width", TRACER_WIDTH)
	mesh.surface_set_material(0, sm)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = mesh
	_mm.instance_count = MAX_TRACERS
	_mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = _mm
	inst.custom_aabb = AABB(Vector3(-20000, -20000, -20000), Vector3(40000, 40000, 40000))
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	WorldOrigin.shifted.connect(_on_shifted)


func _on_shifted(delta: Vector3) -> void:
	for i in _count:
		_pos[i] -= delta
		_prev_ground[i] -= delta


## Adds one round. `exclude` = RIDs of the shooter's own hitbox. Returns false when the pool is full.
func spawn(pos: Vector3, vel: Vector3, life: float, damage: float, is_tracer: bool,
		shooter: Node, exclude: Array) -> bool:
	if _count >= MAX_BULLETS:
		return false
	var i := _count
	_pos[i] = pos
	_vel[i] = vel
	_prev_ground[i] = pos
	_life[i] = life
	_damage[i] = damage
	_tracer[i] = 1 if is_tracer else 0
	_shooter[i] = shooter
	_exclude[i] = exclude
	_count += 1
	return true


func _physics_process(delta: float) -> void:
	_tick += 1
	if _count == 0:
		return
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _count:
		var p0 := _pos[i]
		var v := _vel[i]
		var speed := v.length()
		v += (Vector3(0.0, -GRAVITY, 0.0) - v * (DRAG_K * speed)) * delta
		var p1 := p0 + v * delta
		_vel[i] = v
		_pos[i] = p1
		_life[i] -= delta
		var dead := _life[i] <= 0.0
		var shooter: Node = _shooter[i]
		if shooter != null and not is_instance_valid(shooter):
			shooter = null
		_query.from = p0
		_query.to = p1
		_query.exclude = _exclude[i]
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_hit_target(hit.collider, hit.position, v, _damage[i], shooter)
			dead = true
		elif (i + _tick) % GROUND_CHECK_EVERY == 0:
			var g := Ground.raycast(_prev_ground[i], p1, 40.0)
			_prev_ground[i] = p1
			if not g.is_empty():
				_hit_ground(g.position, g.normal)
				dead = true
		if dead:
			_remove(i)
		else:
			i += 1


func _hit_target(collider: Object, hp: Vector3, v: Vector3, dmg: float, shooter: Node) -> void:
	var hb := collider as Hitbox
	if hb == null:
		return
	hb.apply_damage(dmg, shooter, hp)
	_hits += 1
	Vfx.impact(hp, -v.normalized(), "metal")
	if _hits % SOUND_EVERY == 0:
		Sfx.play_3d("bullet_hit_metal", hp, -6.0)
	if shooter is Aircraft and (shooter as Aircraft).is_player:
		Sfx.play_2d("hit_marker", -4.0)
		Sfx.haptic(0.3, 15)


func _hit_ground(hp: Vector3, normal: Vector3) -> void:
	_hits += 1
	if Ground.is_water(hp.x, hp.z):
		Vfx.impact(hp, Vector3.UP, "water")
	else:
		Vfx.impact(hp, normal, "ground")
		if _hits % (SOUND_EVERY * 2) == 0:
			Sfx.play_3d("bullet_hit_ground", hp, -8.0)


func _remove(i: int) -> void:
	var last := _count - 1
	if i != last:
		_pos[i] = _pos[last]
		_vel[i] = _vel[last]
		_prev_ground[i] = _prev_ground[last]
		_life[i] = _life[last]
		_damage[i] = _damage[last]
		_tracer[i] = _tracer[last]
		_shooter[i] = _shooter[last]
		_exclude[i] = _exclude[last]
	_shooter[last] = null
	_count -= 1


func _process(_delta: float) -> void:
	var frac := Engine.get_physics_interpolation_fraction()
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var n := 0
	for i in _count:
		if _tracer[i] == 0:
			continue
		if n >= MAX_TRACERS:
			break
		var v := _vel[i]
		var dir := v.normalized()
		var c := _pos[i] - v * dt * (1.0 - frac)
		var b := n * 12
		_buf[b] = 1.0
		_buf[b + 1] = 0.0
		_buf[b + 2] = 0.0
		_buf[b + 3] = c.x
		_buf[b + 4] = 0.0
		_buf[b + 5] = 1.0
		_buf[b + 6] = 0.0
		_buf[b + 7] = c.y
		_buf[b + 8] = dir.x
		_buf[b + 9] = dir.y
		_buf[b + 10] = dir.z
		_buf[b + 11] = c.z
		n += 1
	_mm.visible_instance_count = n
	if n > 0:
		_mm.buffer = _buf
