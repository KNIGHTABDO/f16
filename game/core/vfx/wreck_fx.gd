class_name WreckFx
extends Node3D
## Lingering wreck: a tall dark smoke column rising from a small burning base. Column particles are in local
## coordinates (they move with the World shift), the base is one fireball quad. Pooled through Vfx.wreck_smoke().
## duration: seconds of burning; the column keeps rising for COLUMN_LIFE after that. cut() fades it early
## (Vfx does this to the oldest wreck when too many are active).

const COLUMN_LIFE := 9.0
const FADE_TIME := 4.0
const LIFE_PAD := 0.5
const MAX_DURATION := 600.0

var _pool: FxPool
var _smoke: GPUParticles3D
var _fire: MeshInstance3D
var _fire_mat: ShaderMaterial
var _size := 1.0
var _duration := 90.0
var _age := 0.0
var _cut_flag := false
var _active := false


func _ready() -> void:
	if _smoke == null:
		_build()


func _build() -> void:
	_smoke = VfxAssets.make_particles(1, COLUMN_LIFE, VfxAssets.quad(),
			VfxAssets.sprite_material("smoke_flipbook.png", false, BaseMaterial3D.BILLBOARD_PARTICLES, 4, 4))
	_smoke.one_shot = false
	add_child(_smoke)

	_fire_mat = VfxAssets.shader_material("fireball.gdshader")
	_fire_mat.set_shader_parameter("hot_color", Color(1.0, 0.9, 0.6))
	_fire_mat.set_shader_parameter("mid_color", Color(1.0, 0.42, 0.12))
	_fire_mat.set_shader_parameter("smoke_color", Color(0.1, 0.09, 0.08))
	_fire_mat.set_shader_parameter("steady", 1.0)
	_fire_mat.set_shader_parameter("progress", 0.5)
	_fire = MeshInstance3D.new()
	_fire.mesh = VfxAssets.quad()
	_fire.material_override = _fire_mat
	_fire.position = Vector3(0.0, 1.5, 0.0)
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fire)


## Starts the wreck. Must be in the tree.
func configure(pool: FxPool, size: float, duration: float) -> void:
	if _smoke == null:
		_build()
	_pool = pool
	_size = clampf(size, 0.3, 4.0)
	_duration = clampf(duration, 1.0, MAX_DURATION)
	_age = 0.0
	_cut_flag = false
	_active = true
	var k := sqrt(_size)

	_smoke.amount = VfxAssets.scaled(int(roundf(18.0 + 14.0 * _size)))
	_smoke.lifetime = COLUMN_LIFE
	var pm := _smoke.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.5 * k
	pm.direction = Vector3.UP
	pm.spread = 6.0
	pm.initial_velocity_min = 6.0 * k
	pm.initial_velocity_max = 8.0 * k
	pm.gravity = Vector3(1.2, 0.3, 0.0)
	pm.damping_min = 0.25
	pm.damping_max = 0.6
	pm.scale_min = 3.5 * k
	pm.scale_max = 5.0 * k
	pm.scale_curve = VfxAssets.curve("wreck_scale", PackedVector2Array([Vector2(0, 0.5), Vector2(1, 1.6)]))
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.color_ramp = VfxAssets.ramp("wreck_smoke",
			PackedColorArray([Color(0.12, 0.11, 0.1, 0.0), Color(0.12, 0.11, 0.1, 0.8), Color(0.16, 0.15, 0.14, 0.55), Color(0.2, 0.19, 0.18, 0.0)]),
			PackedFloat32Array([0.0, 0.2, 0.65, 1.0]))
	var reach := 6.0 * k
	_smoke.visibility_aabb = VfxAssets.big_aabb(reach, 70.0 * k)

	_fire.scale = Vector3.ONE * 5.0 * k
	_fire.visible = true
	_fire_mat.set_shader_parameter("seed", randf() * 10.0)
	_fire_mat.set_shader_parameter("intensity", 1.0)

	_smoke.restart()
	_smoke.emitting = true
	visible = true
	add_to_group("floating")
	reset_physics_interpolation()


## Fades this wreck out over FADE_TIME (the column keeps rising, then the node frees itself).
func cut() -> void:
	if not _active or _cut_flag:
		return
	_cut_flag = true
	_duration = minf(_duration, _age + FADE_TIME)


func is_cut() -> bool:
	return _cut_flag


func is_finished() -> bool:
	return not _active


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _smoke.emitting and _age >= _duration:
		_smoke.emitting = false
	var fire_k := clampf((_duration - _age) / FADE_TIME, 0.0, 1.0)
	_fire.visible = fire_k > 0.01
	_fire_mat.set_shader_parameter("intensity", fire_k)
	if _age >= _duration + COLUMN_LIFE + LIFE_PAD:
		_finish()


func _finish() -> void:
	_active = false
	_smoke.emitting = false
	remove_from_group("floating")
	visible = false
	if _pool != null:
		_pool.give(self)
	_pool = null
