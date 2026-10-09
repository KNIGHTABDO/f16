class_name Aircraft
extends Node3D
## A flying, damageable aircraft (player or AI). Build with Aircraft.create(id, team, is_player), add it
## under the level's World node, then place it with spawn_in_air() or spawn_on_ground().
## Public API follows docs/ARCHITECTURE.md ("Aircraft public API"). Physics lives in FlightModel.

signal destroyed(killer: Node)
signal damaged(amount: float, source: Node)

const AIRCRAFT_LAYER := 2  ## physics layer 2 (aircraft), as a bitmask value
const WEAPON_SCRIPT := "res://core/weapons/weapon_system.gd"
const OVERG_DAMAGE_RATE := 60.0  ## hp/s per unit of over-g ratio (realistic mode only)
const OVERG_LIMIT := 1.15  ## structural limit as a multiple of max_g / min_g
const WRECK_FREE_DELAY := 3.0  ## seconds from ground impact to queue_free
const EXPLOSION_SIZE := 14.0
const GROUND_EXPLODE_HEIGHT := 1.0  ## wreck explodes when its CG is this close to the ground
const GRAVITY := 9.81
const SMOKE_AMOUNT := 40

var aircraft_id := ""
var data: AircraftData
var team := 0
var is_player := false
var alive := true
var health := 100.0
var max_health := 100.0
var controls := ControlInput.new()
var velocity := Vector3.ZERO  ## local m/s
var flight: FlightModel
var visual: AircraftVisual
var weapons: Node  ## WeaponSystem child named "Weapons" when core/weapons exists, else null
var instructor := Instructor.new()

var _max_rates := Vector3.ZERO  ## full-stick rates (pitch, yaw, roll), rad/s
var _hitbox: Hitbox
var _smoke: GPUParticles3D
var _wreck_spin := Vector3.ZERO
var _exploded := false
var _free_timer := WRECK_FREE_DELAY
var _rng := RandomNumberGenerator.new()


## Builds an aircraft from data/aircraft/<aircraft_id>.json. Returns null if the data cannot be loaded.
static func create(aircraft_id_arg: String, team_id: int, player: bool) -> Aircraft:
	var d := AircraftData.load_id(aircraft_id_arg)
	if d == null:
		return null
	var a := Aircraft.new()
	a.aircraft_id = aircraft_id_arg
	a.data = d
	a.team = team_id
	a.is_player = player
	a.max_health = d.health
	a.health = d.health
	a._max_rates = Vector3(d.pitch_rate_rad(), d.yaw_rate_rad(), d.roll_rate_rad())
	a.flight = FlightModel.new()
	a.flight.setup(d, a._uses_arcade())
	a.name = "%s_%d" % [aircraft_id_arg, team_id]
	a._build()
	return a


func _build() -> void:
	_rng.randomize()
	_hitbox = Hitbox.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = AIRCRAFT_LAYER
	_hitbox.collision_mask = 0
	_hitbox.target = self
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(2.0, data.wing_span * 0.3)
	capsule.height = maxf(data.length, capsule.radius * 2.0)
	shape.shape = capsule
	shape.rotation.x = PI * 0.5  # capsule axis from Y to Z (nose to tail)
	_hitbox.add_child(shape)
	add_child(_hitbox)

	visual = AircraftVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.setup(data)

	_smoke = _make_smoke()
	add_child(_smoke)


func _ready() -> void:
	add_to_group("aircraft")
	add_to_group("damageable")
	add_to_group("floating")
	add_to_group("team_%d" % team)
	_setup_weapons()


## Places the aircraft flying at speed_kmh along heading_deg (0 = north, clockwise), gear up.
func spawn_in_air(local_pos: Vector3, heading_deg: float, speed_kmh: float) -> void:
	flight.arcade = _uses_arcade()
	flight.place_airborne(local_pos, heading_deg, speed_kmh / 3.6)
	_sync_transform()
	reset_physics_interpolation()


## Parks the aircraft on the ground at local_pos (height comes from Ground), gear down, heading_deg.
func spawn_on_ground(local_pos: Vector3, heading_deg: float) -> void:
	flight.arcade = _uses_arcade()
	flight.place_on_ground(local_pos, heading_deg)
	_sync_transform()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not alive:
		_update_wreck(delta)
		return
	flight.arcade = _uses_arcade()
	flight.position = position  # the floating origin may have moved us since last tick
	if controls.use_aim:
		var s := instructor.update(controls.aim_direction, flight.rates, flight.bank_rad(), _max_rates)
		controls.pitch = s.x
		controls.roll = s.y
		controls.yaw = s.z
	flight.step(controls, delta)
	if flight.crashed:
		_crash_impact()
		return
	_sync_transform()
	visual.set_state(controls.throttle, flight.afterburner)
	_check_overg(delta)
	if weapons and weapons.has_method("tick"):
		weapons.call("tick", controls, delta)


func take_damage(amount: float, source: Node, _hit_pos: Vector3) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	damaged.emit(amount, source)
	Events.damaged.emit(self, amount, source)
	if health <= 0.0:
		_die(source)


func get_target_kind() -> String:
	return "air"


func get_velocity() -> Vector3:
	return velocity


func get_hit_radius() -> float:
	return data.hit_radius


func get_speed_kmh() -> float:
	return velocity.length() * 3.6


func get_ias_kmh() -> float:
	return flight.ias_ms * 3.6


func get_mach() -> float:
	return flight.mach


func get_altitude_m() -> float:
	return position.y


func get_agl_m() -> float:
	return position.y - Ground.surface_at(position.x, position.z)


func get_g() -> float:
	return flight.g_load


func get_aoa_deg() -> float:
	return rad_to_deg(flight.alpha)


func get_heading_deg() -> float:
	return flight.heading_deg()


func get_pitch_deg() -> float:
	return rad_to_deg(flight.pitch_rad())


func get_roll_deg() -> float:
	return rad_to_deg(flight.bank_rad())


func get_nose() -> Vector3:
	return flight.get_nose()


func get_throttle() -> float:
	return controls.throttle


func is_afterburner() -> bool:
	return flight.afterburner


func get_fuel_frac() -> float:
	return flight.fuel_frac()


func is_stalling() -> bool:
	return flight.stalled


func is_gear_down() -> bool:
	return flight.gear_down


func is_on_ground() -> bool:
	return flight.on_ground


## 0..1 pilot blackout (realistic mode only, always 0 in arcade).
func get_blackout() -> float:
	return flight.blackout


## 0..1 pilot redout (realistic mode only, always 0 in arcade).
func get_redout() -> float:
	return flight.redout


func _uses_arcade() -> bool:
	return not is_player or Settings.flight_mode == "arcade"


func _sync_transform() -> void:
	transform = Transform3D(flight.basis, flight.position)
	velocity = flight.velocity


func _setup_weapons() -> void:
	if not ResourceLoader.exists(WEAPON_SCRIPT):
		return
	var script: Script = load(WEAPON_SCRIPT)
	var w := script.new() as Node
	if w == null:
		return
	w.name = "Weapons"
	add_child(w)
	weapons = w
	if w.has_method("setup"):
		var loadout := GameState.selected_loadout if is_player else ""
		w.call("setup", self, loadout)


func _check_overg(delta: float) -> void:
	if flight.arcade:
		return
	var g := flight.g_load
	var over := 0.0
	if g > 0.0:
		over = g / (data.max_g * OVERG_LIMIT) - 1.0
	else:
		over = g / (data.min_g * OVERG_LIMIT) - 1.0
	if over > 0.0:
		take_damage(OVERG_DAMAGE_RATE * over * delta, null, position)


func _die(killer: Node) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	remove_from_group("damageable")
	_hitbox.monitorable = false
	_wreck_spin = Vector3(
		_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-3.0, 3.0))
	_smoke.emitting = true
	visual.stop_effects()
	destroyed.emit(killer)
	Events.aircraft_destroyed.emit(self, killer)
	Events.target_destroyed.emit(self, killer)


## Flew into the ground or sea: destroyed on impact.
func _crash_impact() -> void:
	position = flight.crash_pos
	_sync_transform()
	_die(null)
	_explode()


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_free_timer = WRECK_FREE_DELAY
	_smoke.emitting = false
	visual.visible = false
	Events.explosion.emit(position, EXPLOSION_SIZE)


## Destroyed aircraft fall ballistically while spinning and trailing smoke, then explode on impact.
func _update_wreck(delta: float) -> void:
	if _exploded:
		_free_timer -= delta
		if _free_timer <= 0.0:
			queue_free()
		return
	velocity += Vector3(0.0, -GRAVITY, 0.0) * delta
	position += velocity * delta
	var spin := _wreck_spin.length() * delta
	if spin > 0.0:
		transform.basis = (transform.basis * Basis(_wreck_spin.normalized(), spin)).orthonormalized()
	if position.y <= Ground.surface_at(position.x, position.z) + GROUND_EXPLODE_HEIGHT:
		_explode()


func _make_smoke() -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = SMOKE_AMOUNT
	smoke.lifetime = 3.0
	smoke.local_coords = true
	smoke.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 25.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0.0, 0.5, 0.0)
	mat.scale_min = 1.5
	mat.scale_max = 3.5
	mat.color = Color(0.12, 0.12, 0.13, 0.85)
	smoke.process_material = mat
	var puff := SphereMesh.new()
	puff.radius = 0.6
	puff.height = 1.2
	puff.radial_segments = 8
	puff.rings = 4
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.material = puff_mat
	smoke.draw_pass_1 = puff
	return smoke
