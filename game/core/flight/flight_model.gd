class_name FlightModel
extends RefCounted
## Pure flight dynamics for one aircraft. No nodes and no signals: the owning Aircraft copies
## `position` and `basis` into its transform every tick and reads the public state fields.
##
## Frames: local space (+X east, +Y up, -Z north). Y is altitude above sea level in meters.
## Body axes (columns of `basis`): +X right wing, +Y up, +Z tail. The nose is -Z.
## `rates` are body rates in rad/s, human convention: x = pitch up, y = yaw right, z = roll right.

const RHO0 := 1.225
const GRAVITY := 9.81
const SOS_SEA := 340.3
const SOS_MIN := 295.0
const SCALE_HEIGHT := 8500.0
const SUBSTEP_SPEED := 400.0  ## m/s above which the step is split in two

const GEAR_CONTACT_M := 1.9  ## CG height above ground with gear down
const BELLY_CONTACT_M := 1.0  ## CG height above ground with gear up
const LANDING_SINK_MS := 6.0
const LANDING_BANK := PI / 15.0  ## 12 deg, max bank at touchdown
const GROUND_BANK_LIMIT := PI / 9.0  ## 20 deg, wing strike
const TAIL_STRIKE_PITCH := PI * 4.0 / 45.0  ## 16 deg nose up
const NOSE_DOWN_LIMIT := -PI / 18.0  ## -10 deg at touchdown
const GROUND_YAW_RATE := 0.44  ## rad/s, nose wheel steering
const GROUND_LEVEL := 3.0  ## wheels hold the wings level
const ROLL_FRICTION := 0.025
const BRAKE_DECEL := 4.5  ## m/s^2 when braking on the ground
const LATERAL_GRIP := 6.0  ## 1/s, tires kill sideways slip
const GEAR_SPEED := 0.6  ## 1/s, gear animation
const AIRBRAKE_SPEED := 2.5  ## 1/s, airbrake animation

const ARCADE_LIFT_BOOST := 1.12
const ARCADE_AOA_DROP := 4.0  ## rad/s of nose drop per rad above max AoA
const ARCADE_LEVEL := 0.35  ## wings level when the stick is released
const ARCADE_MIN_SPEED_DROP := 0.8  ## rad/s nose drop at zero speed
const ARCADE_WEATHER := 3.0  ## coordinated turns, 1/s per rad of sideslip
const WEATHER_GAIN := 1.2  ## realistic weathervaning, 1/s per rad of sideslip
const PITCH_STAB := 0.5  ## nose relaxes toward the velocity vector
const STALL_PITCH := 1.2  ## realistic stall: nose drops
const STALL_ROLL := 0.8  ## realistic stall: one wing drops

const BLACKOUT_G := 7.0
const REDOUT_G := -1.0

# Public state (read by Aircraft and the HUD)
var data: AircraftData
var arcade := false  ## assists on (arcade mode and all AI)
var position := Vector3.ZERO  ## local meters, y = altitude ASL
var velocity := Vector3.ZERO  ## local m/s
var basis := Basis.IDENTITY  ## body axes as columns (right, up, back), local space
var rates := Vector3.ZERO  ## body rates (pitch up, yaw right, roll right), rad/s
var fuel_kg := 0.0
var gear_down := false
var gear_pos := 0.0  ## 0 up .. 1 down (animated)
var airbrake_pos := 0.0
var thrust_now := 0.0  ## spooled thrust before altitude lapse, N
var thrust_out := 0.0  ## thrust applied last substep, N
var afterburner := false
var on_ground := false
var crashed := false
var crash_pos := Vector3.ZERO
var touchdown_sink := 0.0  ## m/s, sink rate at the last touchdown
var rho := RHO0
var sos := SOS_SEA
var mach := 0.0
var ias_ms := 0.0
var alpha := 0.0  ## angle of attack, rad, positive nose above the flight path
var beta := 0.0  ## sideslip, rad, positive when the flight path is right of the nose
var cl_now := 0.0
var stalled := false
var g_load := 1.0  ## load factor along body up (accelerometer reading)
var blackout := 0.0  ## 0..1, realistic mode only
var redout := 0.0  ## 0..1, realistic mode only


func setup(aircraft_data: AircraftData, is_arcade: bool) -> void:
	data = aircraft_data
	arcade = is_arcade
	fuel_kg = data.mass_fuel


## Places the aircraft flying at speed_ms along heading_deg (0 = north, clockwise), gear up.
func place_airborne(pos: Vector3, heading_deg: float, speed_ms: float) -> void:
	position = pos
	basis = basis_for_heading(heading_deg)
	velocity = -basis.z * speed_ms
	rates = Vector3.ZERO
	gear_down = false
	gear_pos = 0.0
	airbrake_pos = 0.0
	on_ground = false
	crashed = false
	thrust_now = data.thrust_dry * 0.6
	fuel_kg = data.mass_fuel
	g_load = 1.0


## Places the aircraft on the ground at local (x, z) with the gear down, parked, nose along heading_deg.
func place_on_ground(pos: Vector3, heading_deg: float) -> void:
	basis = basis_for_heading(heading_deg)
	velocity = Vector3.ZERO
	rates = Vector3.ZERO
	gear_down = true
	gear_pos = 1.0
	airbrake_pos = 0.0
	crashed = false
	position = Vector3(pos.x, Ground.surface_at(pos.x, pos.z) + GEAR_CONTACT_M, pos.z)
	on_ground = true
	thrust_now = 0.0
	fuel_kg = data.mass_fuel
	g_load = 1.0


## Advances the aircraft by dt seconds. Substeps internally when fast.
func step(c: ControlInput, dt: float) -> void:
	if crashed or data == null:
		return
	if c.toggle_gear and data.has_gear:
		gear_down = not gear_down
	gear_pos = move_toward(gear_pos, 1.0 if gear_down else 0.0, GEAR_SPEED * dt)
	airbrake_pos = move_toward(airbrake_pos, 1.0 if c.airbrake else 0.0, AIRBRAKE_SPEED * dt)
	var substeps := 2 if velocity.length() > SUBSTEP_SPEED else 1
	var h := dt / float(substeps)
	for i in substeps:
		_substep(c, h)
		if crashed:
			return
	_update_pilot_effects(dt)


func get_nose() -> Vector3:
	return -basis.z


func heading_deg() -> float:
	var nose := get_nose()
	return fposmod(rad_to_deg(atan2(nose.x, -nose.z)), 360.0)


func pitch_rad() -> float:
	return asin(clampf(get_nose().y, -1.0, 1.0))


func bank_rad() -> float:
	return atan2(-basis.x.y, basis.y.y)


func speed() -> float:
	return velocity.length()


func fuel_frac() -> float:
	return clampf(fuel_kg / maxf(data.mass_fuel, 1.0), 0.0, 1.0)


func mass() -> float:
	return data.mass_empty + fuel_kg


static func basis_for_heading(heading_deg: float) -> Basis:
	var h := deg_to_rad(heading_deg)
	var nose := Vector3(sin(h), 0.0, -cos(h))
	var back := -nose
	var right := Vector3.UP.cross(back).normalized()
	return Basis(right, Vector3.UP, back)


static func air_density(altitude_m: float) -> float:
	return RHO0 * exp(-maxf(altitude_m, 0.0) / SCALE_HEIGHT)


static func speed_of_sound(altitude_m: float) -> float:
	return maxf(SOS_SEA - 0.0041 * maxf(altitude_m, 0.0), SOS_MIN)


## Lift coefficient vs AoA (rad). Linear to the knee, flat plateau at cl_max to the stall angle,
## then a smooth fall to 55% of cl_max at 40 deg and to zero at 90 deg. Antisymmetric about cl0.
static func lift_coefficient(aoa: float, d: AircraftData) -> float:
	var curve := _lift_curve(absf(aoa), d)
	if aoa >= 0.0:
		return curve
	return 2.0 * d.cl0 - curve


static func _lift_curve(a: float, d: AircraftData) -> float:
	var a_stall := d.alpha_stall_rad()
	var a_knee := (d.cl_max - d.cl0) / d.cl_alpha
	var a_fall := deg_to_rad(40.0)
	if a <= a_knee:
		return d.cl0 + d.cl_alpha * a
	if a <= a_stall:
		return d.cl_max
	if a <= a_fall:
		return lerpf(d.cl_max, d.cl_max * 0.55, smoothstep(a_stall, a_fall, a))
	if a < PI * 0.5:
		var t := (a - a_fall) / (PI * 0.5 - a_fall)
		return d.cl_max * 0.55 * cos(t * PI * 0.5)
	return 0.0


## Wave drag: ramps in from cd_wave_mach to cd_wave_max at Mach 1.1, then eases to half by Mach 2.
static func wave_drag(mach_number: float, d: AircraftData) -> float:
	if mach_number <= d.cd_wave_mach:
		return 0.0
	if mach_number < 1.1:
		return d.cd_wave_max * smoothstep(d.cd_wave_mach, 1.1, mach_number)
	return d.cd_wave_max * (1.0 - 0.5 * clampf((mach_number - 1.1) / 0.9, 0.0, 1.0))


func _substep(c: ControlInput, h: float) -> void:
	var d := data
	var spd := velocity.length()
	rho = air_density(position.y)
	sos = speed_of_sound(position.y)
	mach = spd / sos
	ias_ms = spd * sqrt(rho / RHO0)
	var vb := basis.transposed() * velocity
	if spd > 0.5:
		alpha = atan2(-vb.y, -vb.z)
		beta = asin(clampf(vb.x / spd, -1.0, 1.0))
	else:
		alpha = 0.0
		beta = 0.0

	# Aerodynamic and propulsive forces (N), gravity excluded.
	var throttle := clampf(c.throttle, 0.0, 1.0)
	var qs := 0.5 * rho * spd * spd * d.wing_area
	var cl := lift_coefficient(alpha, d)
	if arcade:
		cl *= ARCADE_LIFT_BOOST
	cl_now = cl
	stalled = absf(alpha) > d.alpha_stall_rad()
	var cd := d.cd0 + d.induced_k * cl * cl + wave_drag(mach, d) \
		+ d.cd_gear * gear_pos + d.cd_airbrake * airbrake_pos
	var force := Vector3.ZERO
	if spd > 0.5:
		var v_hat := velocity / spd
		var lift_dir := basis.y - v_hat * basis.y.dot(v_hat)
		if lift_dir.length_squared() > 1e-6:
			force += lift_dir.normalized() * (qs * cl)
		force -= v_hat * (qs * cd)
	force += basis.x * (-d.side_force * qs * beta)
	var thrust := _update_engine(c, h, spd, throttle)
	force += -basis.z * thrust

	# Rotation: stick -> commanded body rates, then first-order response.
	var cmd := _rate_command(c, spd, throttle)
	rates = rates.lerp(cmd, 1.0 - exp(-d.control_response * h))
	var w := Vector3(rates.x, -rates.y, -rates.z)
	var wl := w.length()
	if wl > 1e-9:
		basis = (basis * Basis(w / wl, wl * h)).orthonormalized()

	# Translation (semi-implicit Euler). g_load is the accelerometer reading along body up.
	var accel := force / mass()
	if not on_ground:
		g_load = accel.dot(basis.y) / GRAVITY
	velocity += (accel + Vector3(0.0, -GRAVITY, 0.0)) * h
	position += velocity * h

	# Ground and sea contact.
	var surface := Ground.surface_at(position.x, position.z)
	var contact := lerpf(BELLY_CONTACT_M, GEAR_CONTACT_M, gear_pos)
	if position.y - contact <= surface:
		_contact(surface, contact, h, throttle, c.airbrake)
	else:
		on_ground = false


func _contact(surface: float, contact: float, h: float, throttle: float, braking: bool) -> void:
	position.y = surface + contact
	var bank := bank_rad()
	if not on_ground:
		touchdown_sink = -velocity.y
		var pitch := pitch_rad()
		var bad := gear_pos < 0.98 or touchdown_sink > LANDING_SINK_MS \
			or absf(bank) > LANDING_BANK or pitch > TAIL_STRIKE_PITCH \
			or pitch < NOSE_DOWN_LIMIT or _over_water()
		if bad:
			_crash()
			return
	elif gear_pos < 0.98 or absf(bank) > GROUND_BANK_LIMIT or _over_water():
		_crash()
		return
	on_ground = true
	if velocity.y < 0.0:
		velocity.y = 0.0
	_ground_roll(h, braking or throttle <= 0.02)


func _ground_roll(h: float, braking: bool) -> void:
	var nose_h := Vector3(get_nose().x, 0.0, get_nose().z)
	if nose_h.length_squared() < 1e-8:
		return
	nose_h = nose_h.normalized()
	var v := Vector3(velocity.x, 0.0, velocity.z)
	var along := v.dot(nose_h)
	var lateral := v - nose_h * along
	lateral *= exp(-LATERAL_GRIP * h)
	var decel := ROLL_FRICTION * GRAVITY
	if braking:
		decel += BRAKE_DECEL
	along -= signf(along) * minf(absf(along), decel * h)
	velocity = nose_h * along + lateral + Vector3(0.0, velocity.y, 0.0)
	g_load = 1.0


func _crash() -> void:
	crashed = true
	crash_pos = position
	on_ground = false


func _over_water() -> bool:
	return Ground.is_loaded() and Ground.is_water(position.x, position.z)


func _update_engine(c: ControlInput, h: float, spd: float, throttle: float) -> float:
	var d := data
	var rho_ratio := rho / RHO0
	if d.engine == "prop":
		var power := d.prop_power_kw * 1000.0 * throttle * pow(rho_ratio, 0.8) if fuel_kg > 0.0 else 0.0
		var thrust := minf(power * d.prop_efficiency / maxf(spd, 30.0), mass() * GRAVITY * 2.5)
		fuel_kg = maxf(0.0, fuel_kg - d.fuel_burn_dry * throttle * h)
		afterburner = false
		thrust_out = thrust
		return thrust

	var has_fuel := fuel_kg > 0.0
	afterburner = has_fuel and d.has_afterburner and (c.afterburner or throttle >= 0.999)
	var cmd := 0.0
	if has_fuel:
		cmd = d.thrust_ab if afterburner else d.thrust_dry * lerpf(0.05, 1.0, throttle)
	var spool_rate := d.thrust_max() / maxf(d.engine_spool_s, 0.1)
	thrust_now = move_toward(thrust_now, cmd, spool_rate * h)
	var applied := thrust_now * pow(rho_ratio, d.thrust_altitude_lapse)
	var burn := 0.0
	if afterburner:
		burn = d.fuel_burn_ab * thrust_now / maxf(d.thrust_ab, 1.0)
	else:
		burn = d.fuel_burn_dry * thrust_now / maxf(d.thrust_dry, 1.0)
	fuel_kg = maxf(0.0, fuel_kg - burn * h)
	thrust_out = applied
	return applied


## Desired body rates (pitch up, yaw right, roll right), rad/s, from the sticks plus flight-model
## assists (arcade) or fly-by-wire limits and stall behaviour (realistic).
func _rate_command(c: ControlInput, spd: float, _throttle: float) -> Vector3:
	var d := data
	var stall_ms := d.stall_speed_ms()
	var pitch_in := clampf(c.pitch, -1.0, 1.0)
	var roll_in := clampf(c.roll, -1.0, 1.0)
	var yaw_in := clampf(c.yaw, -1.0, 1.0)
	if on_ground:
		var p_g := 0.0
		if pitch_rad() < TAIL_STRIKE_PITCH - 0.05 or pitch_in < 0.0:
			p_g = pitch_in * d.pitch_rate_rad()
		var y_g := yaw_in * GROUND_YAW_RATE * clampf(spd / 8.0, 0.0, 1.0)
		return Vector3(p_g, y_g, -GROUND_LEVEL * bank_rad())

	var auth := clampf((ias_ms / stall_ms - 0.8) / 0.8, 0.12, 1.0)
	var p := pitch_in * d.pitch_rate_rad() * auth
	var r := roll_in * d.roll_rate_rad() * auth
	var y := yaw_in * d.yaw_rate_rad()

	if arcade and spd > 1.0:
		var lim_up := minf(d.pitch_rate_rad(), d.max_g * GRAVITY / spd)
		var lim_dn := minf(d.pitch_rate_rad(), absf(d.min_g) * GRAVITY / spd)
		p = clampf(p, -lim_dn, lim_up)
		if p > 0.0:
			p *= clampf(1.0 - (g_load - d.max_g) * 2.0, 0.0, 1.0)

	if arcade or d.fly_by_wire:
		var over := alpha - d.max_aoa_rad()
		if over > 0.0:
			p = minf(p, 0.0)
			if arcade:
				p -= ARCADE_AOA_DROP * over
		var under := -alpha - d.max_aoa_rad()
		if under > 0.0:
			p = maxf(p, 0.0)
			if arcade:
				p += ARCADE_AOA_DROP * under

	if arcade:
		var low := clampf(1.0 - ias_ms / (stall_ms * 1.15), 0.0, 1.0)
		p -= ARCADE_MIN_SPEED_DROP * low
		r -= ARCADE_LEVEL * bank_rad() * (1.0 - absf(roll_in))
	elif stalled:
		var excess := absf(alpha) - d.alpha_stall_rad()
		p -= STALL_PITCH * excess * signf(alpha)
		r += STALL_ROLL * excess * (1.0 if beta >= 0.0 else -1.0)

	p -= PITCH_STAB * d.stability * alpha
	y += (ARCADE_WEATHER if arcade else WEATHER_GAIN) * d.stability * beta
	return Vector3(p, y, r)


func _update_pilot_effects(dt: float) -> void:
	if arcade:
		blackout = 0.0
		redout = 0.0
		return
	if g_load > BLACKOUT_G:
		blackout = minf(1.0, blackout + (g_load - BLACKOUT_G) * 0.4 * dt)
	else:
		blackout = maxf(0.0, blackout - 0.5 * dt)
	if g_load < REDOUT_G:
		redout = minf(1.0, redout + (REDOUT_G - g_load) * 0.4 * dt)
	else:
		redout = maxf(0.0, redout - 0.5 * dt)
