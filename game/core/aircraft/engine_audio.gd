class_name EngineAudio
extends Node3D
## Engine sound for one aircraft: layered loops on this node, so the sound moves with the aircraft.
## Usage: add as a child of the aircraft, then call setup(aircraft). The aircraft is read dynamically; a missing
## method counts as idle: get_throttle() -> float 0..1, is_afterburner() -> bool, get_speed_kmh() -> float,
## and data.engine ("jet", "prop" or "heli", default "jet").
## Layers: core engine (pitch and volume follow throttle), afterburner roar (jet), wind (follows speed),
## and a distant jet rumble that crossfades in as the camera moves away (jet).

const NEAR_DISTANCE := 400.0  # closer than this: core engine only
const FAR_DISTANCE := 2500.0  # farther than this: distant rumble only
const FAR_MAX_DISTANCE := 12000.0
const FAR_BOOST_DB := 8.0  # the distant layer sits low under 3D attenuation, so lift it
const WIND_MIN_KMH := 80.0
const WIND_MAX_KMH := 900.0
const WIND_GAIN := 0.7
const SMOOTH_RATE := 2.5  # exponential smoothing per second (throttle, afterburner, speed, distance)
const SILENT_DB := -60.0
const CORE_SOUND := {"jet": "engine_jet", "prop": "engine_prop", "heli": "engine_heli"}
const PITCH_RANGE := {"jet": Vector2(0.8, 1.4), "prop": Vector2(0.85, 1.25), "heli": Vector2(0.9, 1.15)}

var _aircraft: Node3D
var _kind := "jet"
var _core: AudioStreamPlayer3D
var _afterburner: AudioStreamPlayer3D
var _wind: AudioStreamPlayer3D
var _far: AudioStreamPlayer3D
var _throttle := 0.0
var _ab := 0.0
var _speed := 0.0  # normalised 0..1
var _near := 1.0  # 1 = close (core engine), 0 = far (rumble)


## Binds to `aircraft` and builds the loops. Safe to call again; the old layers are freed first.
func setup(aircraft: Node3D) -> void:
	_clear_layers()
	_aircraft = aircraft
	_kind = _read_kind()
	_core = Sfx.attach_loop(CORE_SOUND[_kind], self, SILENT_DB)
	_wind = Sfx.attach_loop("wind", self, SILENT_DB)
	if _kind == "jet":
		_afterburner = Sfx.attach_loop("engine_jet_ab", self, SILENT_DB)
		_far = Sfx.attach_loop("engine_jet_far", self, SILENT_DB)
		if _far != null:
			_far.max_distance = FAR_MAX_DISTANCE


func _process(delta: float) -> void:
	if _aircraft == null or not is_instance_valid(_aircraft) or _core == null:
		return
	var k := 1.0 - exp(-SMOOTH_RATE * delta)
	_throttle = lerpf(_throttle, clampf(_call_float(&"get_throttle", 0.0), 0.0, 1.0), k)
	var ab_target := 1.0 if _call_bool(&"is_afterburner") else 0.0
	_ab = lerpf(_ab, ab_target, k)
	var speed_target := clampf(inverse_lerp(WIND_MIN_KMH, WIND_MAX_KMH, _call_float(&"get_speed_kmh", 0.0)), 0.0, 1.0)
	_speed = lerpf(_speed, speed_target, k)
	var near_target := clampf(inverse_lerp(FAR_DISTANCE, NEAR_DISTANCE, _listener_distance()), 0.0, 1.0)
	_near = lerpf(_near, near_target, k)
	_apply_levels()


func _apply_levels() -> void:
	var pitch_range: Vector2 = PITCH_RANGE.get(_kind, PITCH_RANGE["jet"])
	_core.volume_db = _to_db(lerpf(0.3, 1.0, _throttle) * lerpf(0.25, 1.0, _near))
	_core.pitch_scale = lerpf(pitch_range.x, pitch_range.y, _throttle)
	if _afterburner != null:
		_afterburner.volume_db = _to_db(_ab * lerpf(0.4, 1.0, _near))
		_afterburner.pitch_scale = lerpf(0.95, 1.05, _throttle)
	if _wind != null:
		_wind.volume_db = _to_db(_speed * WIND_GAIN)
		_wind.pitch_scale = lerpf(0.9, 1.2, _speed)
	if _far != null:
		_far.volume_db = _to_db((1.0 - _near) * lerpf(0.5, 1.0, _throttle)) + FAR_BOOST_DB
		_far.pitch_scale = lerpf(0.9, 1.05, _throttle)


## data.engine from the aircraft's data (Resource or Dictionary). Unknown or missing values mean a jet.
func _read_kind() -> String:
	var data: Variant = _aircraft.get("data")
	if data != null:
		var engine: Variant = data.get("engine")
		if engine is String and CORE_SOUND.has(engine):
			return engine
	return "jet"


func _call_float(method: StringName, fallback: float) -> float:
	if _aircraft.has_method(method):
		return float(_aircraft.call(method))
	return fallback


func _call_bool(method: StringName) -> bool:
	return _aircraft.has_method(method) and bool(_aircraft.call(method))


func _listener_distance() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	return cam.global_position.distance_to(global_position)


func _to_db(gain: float) -> float:
	return linear_to_db(maxf(gain, 0.001))


func _clear_layers() -> void:
	for player: AudioStreamPlayer3D in [_core, _afterburner, _wind, _far]:
		if player != null:
			player.queue_free()
	_core = null
	_afterburner = null
	_wind = null
	_far = null
