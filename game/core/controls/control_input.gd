class_name ControlInput
extends RefCounted
## Per-tick control state for one aircraft, written by a controller (player or AI), read by Aircraft.
##
## Two ways to steer:
## - use_aim = true  -> the aircraft's built-in instructor flies toward `aim_direction`
##   (War Thunder "mouse aim" style; used by Arcade mode, gyro aiming and all AI pilots).
## - use_aim = false -> pitch/roll/yaw are direct stick deflections (Realistic mode, controller).

var pitch := 0.0  # -1..1, positive = nose up
var roll := 0.0  # -1..1, positive = roll right
var yaw := 0.0  # -1..1, positive = nose right
var throttle := 0.7  # 0..1
var afterburner := false  # only for jets that have one; on also when throttle >= 1.0

var use_aim := false
var aim_direction := Vector3.FORWARD  # LOCAL-space unit vector the pilot wants the nose to point

var fire_gun := false  # held
var fire_weapon := false  # true for one tick = launch/drop selected weapon
var cycle_weapon := false  # one tick
var cycle_target := false  # one tick
var drop_flares := false  # one tick
var airbrake := false  # held
var toggle_gear := false  # one tick


## Clears one-tick flags; controllers call this at the start of each tick.
func clear_triggers() -> void:
	fire_weapon = false
	cycle_weapon = false
	cycle_target = false
	drop_flares = false
	toggle_gear = false
