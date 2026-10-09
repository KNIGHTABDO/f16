class_name FlareFx
extends Node3D
## One decoy flare: a blinding burning ball that falls under gravity and drag, leaves a smoke trail and burns out.
## Pooled through Vfx.flare(). It sits under World in group "floating" and "flares" (seekers look for that group).

const BALL_SIZE := 3.2
const GRAVITY := 9.8
const DRAG := 0.012  # drag acceleration = DRAG * speed^2 (m/s^2), so the flare sheds aircraft speed quickly

var _pool: FxPool
var _trail: Node3D
var _mat: ShaderMaterial
var _ball: MeshInstance3D
var _vel := Vector3.ZERO
var _age := 0.0
var _life := 4.0
var _active := false


func _ready() -> void:
	if _ball == null:
		_build()


func _build() -> void:
	_mat = VfxAssets.shader_material("fireball.gdshader")
	_mat.set_shader_parameter("hot_color", Color(1.0, 0.97, 0.86))
	_mat.set_shader_parameter("mid_color", Color(1.0, 0.56, 0.2))
	_mat.set_shader_parameter("smoke_color", Color(0.3, 0.28, 0.26))
	_mat.set_shader_parameter("steady", 1.0)
	_mat.set_shader_parameter("progress", 0.25)
	_ball = MeshInstance3D.new()
	_ball.mesh = VfxAssets.quad()
	_ball.material_override = _mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)


## Starts the flare. Must be in the tree. Set the smoke trail with set_trail() after this call.
func start(pool: FxPool, world_pos: Vector3, velocity: Vector3, life: float) -> void:
	if _ball == null:
		_build()
	_pool = pool
	_trail = null
	_vel = velocity
	_life = maxf(life, 0.1)
	_age = 0.0
	_active = true
	global_position = world_pos
	add_to_group("floating")
	add_to_group("flares")
	visible = true
	_mat.set_shader_parameter("seed", randf() * 10.0)
	reset_physics_interpolation()


## The smoke trail from Vfx. It is stopped when the flare ends.
func set_trail(trail: Node3D) -> void:
	_trail = trail


## Ends the flare now (used when too many are active).
func burn_out() -> void:
	_age = _life


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	var speed := _vel.length()
	_vel += (Vector3.DOWN * GRAVITY - _vel * (DRAG * speed)) * delta
	global_position += _vel * delta

	var heat := clampf(1.0 - _age / _life, 0.0, 1.0)
	_mat.set_shader_parameter("intensity", 0.4 + 1.6 * sqrt(heat))
	_mat.set_shader_parameter("progress", clampf(0.25 + 0.5 * _age / _life, 0.0, 1.0))
	_ball.scale = Vector3.ONE * BALL_SIZE * (0.65 + 0.35 * heat)
	if _age >= _life:
		_finish()


func _finish() -> void:
	_active = false
	remove_from_group("flares")
	remove_from_group("floating")
	if _trail != null and is_instance_valid(_trail):
		(_trail as TrailFx).stop()
	_trail = null
	visible = false
	if _pool != null:
		_pool.give(self)
	_pool = null
