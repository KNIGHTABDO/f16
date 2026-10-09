class_name Weather
extends Node3D
## Storm rain (MultiMesh streaks wrapped in a camera-local box), lightning flashes, wind and
## turbulence. The rain node is top-level and follows the camera, so it needs no floating-origin
## handling. Clouds and the sky take their state from WorldBuilder, which reads this node.
##
## Public API: setup(camera, preset), set_state(name), update(delta), wind (Vector3, m/s, world),
## turbulence() (0..1), flash_level() (0..1, feeds WorldSky.set_flash), rain_strength() (0..1).

const BOX := Vector3(70.0, 45.0, 70.0)
const RAIN_SHADER := preload("res://core/world/rain.gdshader")
const FALL_SPEED := 18.0  # m/s
const WIND_DIR := Vector3(1.0, 0.0, -0.25)  # westerly, blowing east (world: +X east, -Z north)
const WIND_SPEED := {"clear": 2.5, "scattered": 4.0, "overcast": 7.0, "storm": 14.0, "haze": 1.5}
const TURBULENCE := {"clear": 0.04, "scattered": 0.10, "overcast": 0.22, "storm": 0.70, "haze": 0.05}
const RAIN := {"storm": 1.0, "overcast": 0.12}  # rain strength by state, missing = 0

var wind := Vector3.ZERO  # m/s, world
var state := "clear"
var _camera: Camera3D
var _rain: MultiMeshInstance3D
var _mm: MultiMesh
var _mat: ShaderMaterial
var _strength := 0.0
var _flash := 0.0
var _flash_timer := 3.0
var _gust_t := 0.0
var _gust := 1.0
var _rng := RandomNumberGenerator.new()


func setup(camera: Camera3D, preset: String) -> void:
	_camera = camera
	_rng.seed = 7
	var n := 500 if preset == "low" else (1000 if preset == "balanced" else 1600)

	_mat = ShaderMaterial.new()
	_mat.shader = RAIN_SHADER
	_mat.set_shader_parameter("box", BOX)
	_mat.set_shader_parameter("strength", 0.0)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = n
	_mm.custom_aabb = AABB(Vector3(-200.0, -200.0, -200.0), Vector3(400.0, 400.0, 400.0))
	for i in n:
		_mm.set_instance_transform(i, Transform3D.IDENTITY)
		_mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), 0.0))

	_rain = MultiMeshInstance3D.new()
	_rain.multimesh = _mm
	_rain.material_override = _mat
	_rain.top_level = true
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visible = false
	add_child(_rain)


func set_state(weather_name: String) -> void:
	state = weather_name if WIND_SPEED.has(weather_name) else "clear"


func turbulence() -> float:
	return float(TURBULENCE[state]) * (0.8 + 0.2 * _gust)


func flash_level() -> float:
	return _flash


func rain_strength() -> float:
	return _strength


func update(delta: float) -> void:
	# Rain ramps in and out over a few seconds.
	var target := float(RAIN.get(state, 0.0))
	_strength = move_toward(_strength, target, delta * 0.3)
	_rain.visible = _strength > 0.01
	if _camera != null and is_instance_valid(_camera):
		_rain.global_transform = Transform3D(Basis.IDENTITY, _camera.global_position)

	# Wind: base speed for the state, slow gusts on top.
	_gust_t += delta
	_gust = 1.0 + 0.25 * sin(_gust_t * 0.31) + 0.15 * sin(_gust_t * 0.83 + 1.7)
	wind = WIND_DIR.normalized() * float(WIND_SPEED[state]) * _gust
	_mat.set_shader_parameter("strength", _strength)
	var fall := Vector3(wind.x, -FALL_SPEED, wind.z)
	_mat.set_shader_parameter("fall", fall)
	_mat.set_shader_parameter("streak", 0.5 + 0.05 * FALL_SPEED + 0.02 * wind.length())

	# Lightning: random strikes in storms, flash decays over about a third of a second.
	_flash = maxf(0.0, _flash - delta * 3.0)
	if state == "storm":
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash = 1.0
			_flash_timer = _rng.randf_range(4.0, 18.0)
	else:
		_flash_timer = _rng.randf_range(2.0, 6.0)
