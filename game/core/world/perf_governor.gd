class_name PerfGovernor
extends Node
## Frame-time driven 3D render scale. Scale steps down while frames run long and back up with headroom,
## between Settings.dynamic_resolution_min and Settings.render_scale (the ceiling).
## Thermal: Godot 4.7 has no thermal-state API on iOS, so sustained overload at the minimum scale is the
## signal. After THROTTLE_AFTER seconds there the frame cap drops to 30 fps and is probed again every PROBE_AFTER.

const OVER := 1.12  # frame time above target by this factor counts as overloaded
const UNDER := 0.85  # below target by this factor counts as headroom
const DOWN_STEP := 0.05
const UP_STEP := 0.025
const DOWN_COOLDOWN := 0.4  # seconds between steps down
const UP_COOLDOWN := 1.5  # seconds between steps up
const HEADROOM_AFTER := 3.0  # seconds of headroom before stepping up
const THROTTLE_AFTER := 8.0  # seconds overloaded at the minimum scale before the 30 fps cap
const PROBE_AFTER := 60.0  # seconds under the cap before the full cap is tried again

var scale := 1.0
var throttled := false
var frame_ms := 16.7  # smoothed frame time, ms

var _over_at_min := 0.0
var _headroom := 0.0
var _cooldown := 0.0
var _throttle_t := 0.0


func _ready() -> void:
	_set_scale(clampf(Settings.render_scale, 0.5, 1.0))


func _process(delta: float) -> void:
	var dt := minf(delta, 0.1)  # ignore stalls (app resume, breakpoints)
	frame_ms = lerpf(frame_ms, dt * 1000.0, 0.1)
	var ceiling := clampf(Settings.render_scale, 0.5, 1.0)
	var floor_scale := clampf(Settings.dynamic_resolution_min, 0.5, ceiling)
	if not Settings.dynamic_resolution or scale > ceiling:
		_set_scale(ceiling)
		_set_cap()
		if not Settings.dynamic_resolution:
			return
	var fps := 30.0 if Settings.battery_saver else float(Settings.fps_target)
	var target_ms := 1000.0 / fps
	_cooldown -= dt
	if frame_ms > target_ms * OVER:
		_headroom = 0.0
		if scale > floor_scale + 0.001:
			_over_at_min = 0.0
			if _cooldown <= 0.0:
				_set_scale(maxf(floor_scale, scale - DOWN_STEP))
				_cooldown = DOWN_COOLDOWN
		else:
			_over_at_min += dt
			if _over_at_min > THROTTLE_AFTER and not throttled:
				throttled = true
				_throttle_t = 0.0
	elif frame_ms < target_ms * UNDER:
		_over_at_min = 0.0
		_headroom += dt
		if _headroom > HEADROOM_AFTER and scale < ceiling - 0.001 and _cooldown <= 0.0:
			_set_scale(minf(ceiling, scale + UP_STEP))
			_cooldown = UP_COOLDOWN
	else:
		_over_at_min = 0.0
		_headroom = 0.0
	if throttled:
		_throttle_t += dt
		if _throttle_t > PROBE_AFTER:
			throttled = false
			_over_at_min = 0.0
	_set_cap()


func _exit_tree() -> void:
	# Leaving the world: give the viewport back its configured ceiling and frame cap.
	_set_scale(clampf(Settings.render_scale, 0.5, 1.0))
	Engine.max_fps = 30 if Settings.battery_saver else Settings.fps_target


func _set_scale(value: float) -> void:
	scale = value
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = scale


func _set_cap() -> void:
	Engine.max_fps = 30 if (throttled or Settings.battery_saver) else Settings.fps_target
