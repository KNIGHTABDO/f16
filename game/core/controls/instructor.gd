class_name Instructor
extends RefCounted
## Aim assist ("mouse aim" autopilot used by arcade mode and AI pilots). Turns a desired direction into
## stick inputs. Works in the body frame: far targets are reached by rolling so the target sits in the
## vertical plane above the nose ("bank, then pull"); near targets are reached by direct pitch and yaw;
## the wings level when the nose is on target. Each axis is a PD loop on the target angle with rate
## damping, so it converges without overshoot and has no integrator windup.

const ROLL_KP := 3.0  ## 1/s, roll angle error to roll rate command
const ROLL_KD := 0.3  ## rate damping (dimensionless)
const PITCH_KP := 2.6
const PITCH_KD := 0.45
const YAW_KP := 3.0
const YAW_KD := 0.4
const NEAR_START := 0.15  ## rad off boresight: below this, direct pitch/yaw only
const NEAR_END := 0.6  ## rad off boresight: above this, bank then pull

## Returns sticks as Vector3(pitch, roll, yaw), each -1..1 (positive = nose up, roll right, nose right).
## desired: direction to aim at, in the aircraft's LOCAL body frame (nose is -Z, right is +X, up is +Y).
## rates: current body rates (pitch up, yaw right, roll right), rad/s.
## bank: current bank angle, rad, positive right.
## max_rates: full-stick rates (pitch, yaw, roll) in rad/s, used to scale rate commands into sticks.
func update(desired: Vector3, rates: Vector3, bank: float, max_rates: Vector3) -> Vector3:
	var d := desired.normalized() if desired.length_squared() > 1e-8 else Vector3(0.0, 0.0, -1.0)
	var off := acos(clampf(-d.z, -1.0, 1.0))  # angle from the nose to the target
	var far := smoothstep(NEAR_START, NEAR_END, off)
	var hyp := Vector2(d.x, d.y).length()

	# Roll: far targets, roll the target above the nose; near targets, level the wings.
	var bank_to_target := atan2(d.x, d.y) if hyp > 1e-5 else 0.0
	var roll_err := bank_to_target * far - bank * (1.0 - far)

	# Pitch: body elevation when near; once rolled over, elevation in the bank plane when far.
	var elevation_near := atan2(d.y, -d.z)
	var elevation_far := atan2(hyp, -d.z) * cos(bank_to_target)
	var pitch_err := lerpf(elevation_near, elevation_far, far)

	# Yaw: fine aim only when the target is close to the nose.
	var azimuth := atan2(d.x, -d.z)
	var yaw_err := azimuth * (1.0 - far)

	var pitch_cmd := PITCH_KP * pitch_err - PITCH_KD * rates.x
	var roll_cmd := ROLL_KP * roll_err - ROLL_KD * rates.z
	var yaw_cmd := YAW_KP * yaw_err - YAW_KD * rates.y

	return Vector3(
		clampf(pitch_cmd / maxf(max_rates.x, 0.01), -1.0, 1.0),
		clampf(roll_cmd / maxf(max_rates.z, 0.01), -1.0, 1.0),
		clampf(yaw_cmd / maxf(max_rates.y, 0.01), -1.0, 1.0))
