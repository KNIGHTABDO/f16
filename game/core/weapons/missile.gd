class_name Missile
extends Node3D
## Guided missile (IR, radar or air-to-ground) for the combat game. Own kinematics: drop, motor boost, coast with
## drag, proportional navigation, seeker cone, flare / chaff decoys, proximity fuze and blast damage.
## Created by WeaponSystem via Missile.launch(); a direct child of the level's World node.

const GRAVITY := 9.81
const DROP_TIME := 0.3
const DROP_PUSH := 6.0  ## m/s of ejection velocity downward
const COAST_DRAG := 4.0e-5  ## drag acceleration = k * speed^2
const TURN_BLEED := 0.015  ## fraction of speed lost per g-second while manoeuvring
const AUTHORITY_SPEED := 220.0  ## below this speed the fins lose authority (max_g scaled down)
const SEEK_INTERVAL := 0.1  ## seeker / decoy logic runs at 10 Hz
const LOFT_START := 12000.0  ## radar missiles loft above this range
const LOFT_PER_M := 0.15
const LOFT_MAX := 2500.0
const FLARE_RANGE := 3500.0
const FLARE_REACQUIRE_DEG := 12.0
const WARN_INTERVAL := 1.0
const SPAWN_ARM_TIME := 0.5  ## fuze is safe this long after launch
const BLAST_SIZE_AIR := 1.2
const GROUND_BLAST_SIZE_SCALE := 1.0 / 16.0

enum Phase { DROP, BOOST, COAST }

signal detonated(missile: Missile)

var weapon_id := ""
var data: Dictionary = {}
var type := ""
var shooter: Node3D
var target: Node3D
var team := 0
var velocity := Vector3.ZERO
var phase := Phase.DROP

var _age := 0.0
var _seek_t := 0.0
var _warn_t := 0.0
var _speed_max := 900.0
var _boost_s := 5.0
var _accel := 300.0
var _max_g := 30.0
var _nav := 4.0
var _seeker_half := 0.0
var _lifetime := 25.0
var _proximity := 9.0
var _damage := 100.0
var _blast_radius := 25.0
var _is_ground := false
var _trail: Node3D
var _seen_flares := {}
var _decoyed := false  # seeker was spoofed by a decoy; never re-acquires
var _registered_on: Node
var _prev_pos := Vector3.ZERO
var _target_valid_kinds: Array = []
var _flyby_done := false
var _dead := false


## Creates, places and starts a missile. `world` is the level's World node. `tgt` may be null (boresight launch).
static func launch(world: Node, shooter_node: Node3D, id: String, wdata: Dictionary, tgt: Node3D,
		xform: Transform3D, start_velocity: Vector3) -> Missile:
	var m := Missile.new()
	m.weapon_id = id
	m.data = wdata
	m.type = str(wdata.get("type", "ir_missile"))
	m.shooter = shooter_node
	m.team = int(shooter_node.get("team")) if shooter_node != null else 0
	m.target = tgt
	m.velocity = start_velocity
	m._configure()
	world.add_child(m)
	m.global_transform = xform
	m.reset_physics_interpolation()
	m._start()
	return m


func _configure() -> void:
	_speed_max = float(data.get("speed_max", 900.0))
	_boost_s = float(data.get("boost_s", 5.0))
	_accel = float(data.get("accel", 300.0))
	_max_g = float(data.get("max_g", 30.0))
	_nav = float(data.get("nav_gain", 4.0))
	_seeker_half = deg_to_rad(float(data.get("seeker_fov_deg", 90.0)) * 0.5)
	_lifetime = float(data.get("lifetime", 25.0))
	_proximity = float(data.get("proximity", 9.0))
	_damage = float(data.get("damage", 100.0))
	_is_ground = type == "ag_missile"
	_blast_radius = float(data.get("blast_radius", Targeting.AIR_BLAST_RADIUS)) if _is_ground \
			else Targeting.AIR_BLAST_RADIUS
	_target_valid_kinds = data.get("targets", [])


func _ready() -> void:
	add_to_group("floating")
	add_to_group("missiles")
	add_child(WeaponModels.build(weapon_id, data))


func _start() -> void:
	_prev_pos = global_position
	if target != null and "weapons" in target and target.weapons != null \
			and target.weapons.has_method("add_incoming"):
		target.weapons.call("add_incoming", self)
		_registered_on = target
	Events.missile_launched.emit(self, shooter, target)
	Events.flares_dropped.connect(_on_flares_dropped)
	WorldOrigin.shifted.connect(_on_shifted)


func _on_shifted(delta: Vector3) -> void:
	_prev_pos -= delta


func get_velocity() -> Vector3:
	return velocity


func is_guiding_on(n: Node) -> bool:
	return target == n and not _dead


func _physics_process(dt: float) -> void:
	if _dead:
		return
	_age += dt
	_prev_pos = global_position
	_update_phase()
	_seek_t -= dt
	if _seek_t <= 0.0 and phase != Phase.DROP:
		_seek_t = SEEK_INTERVAL
		_seeker_update()
	var pos := global_position
	var speed := velocity.length()
	var a := Vector3.ZERO
	var fwd := velocity / maxf(speed, 0.001)
	if phase == Phase.DROP:
		velocity += Vector3(0, -GRAVITY, 0) * dt
		velocity += Vector3.DOWN * DROP_PUSH * dt / DROP_TIME
	else:
		if phase == Phase.BOOST and speed < _speed_max:
			velocity += fwd * _accel * dt
		elif phase == Phase.COAST:
			velocity -= fwd * (COAST_DRAG * speed * speed) * dt
		velocity += Vector3(0, -GRAVITY, 0) * dt
		if target != null and is_instance_valid(target):
			a = _guidance(pos, fwd, speed)
		var lim := _max_g * GRAVITY * clampf(speed / AUTHORITY_SPEED, 0.2, 1.0)
		if a.length() > lim:
			a = a.normalized() * lim
		if a != Vector3.ZERO:
			var before := velocity.length()
			velocity += a * dt
			var nl := velocity.length()
			if nl > 0.001:
				var bleed := 1.0 - TURN_BLEED * (a.length() / GRAVITY) * dt
				velocity = velocity / nl * minf(before, _speed_max * 1.05) * bleed
		if velocity.length() > _speed_max * 1.05:
			velocity = velocity.normalized() * _speed_max * 1.05
	pos += velocity * dt
	global_position = pos
	if velocity.length_squared() > 1.0:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		global_transform.basis = Basis.looking_at(velocity.normalized(), up)
	_check_hits(pos, dt)
	_warn_t -= dt
	if _warn_t <= 0.0 and target != null and _registered_on != null:
		_warn_t = WARN_INTERVAL
		Events.missile_warning.emit(self, _registered_on)
	_flyby_check()
	if _age >= _lifetime and not _dead:
		_detonate(pos, true)


func _update_phase() -> void:
	if phase == Phase.DROP and _age >= DROP_TIME:
		phase = Phase.BOOST
		_trail = Vfx.attach_trail(self, "missile", Vector3(0, 0, WeaponModels.length_of(data) * 0.5))
	elif phase == Phase.BOOST and _age >= DROP_TIME + _boost_s:
		phase = Phase.COAST


## Proportional navigation acceleration (m/s^2, perpendicular to the flight path) with gravity compensation.
func _guidance(pos: Vector3, fwd: Vector3, speed: float) -> Vector3:
	var aim := target.global_position
	var r := aim - pos
	var dist := r.length()
	if dist < 0.5:
		return Vector3.ZERO
	var tvel := Targeting.velocity_of(target)
	if type == "radar_missile" and dist > LOFT_START and phase != Phase.COAST:
		var lift := minf((dist - LOFT_START) * LOFT_PER_M, LOFT_MAX)
		aim.y += lift
		r = aim - pos
		dist = r.length()
	var los := r / dist
	var vrel := tvel - velocity
	var omega := r.cross(vrel) / (dist * dist)
	var vc := -los.dot(vrel)
	var a := omega.cross(fwd) * (_nav * maxf(vc, speed * 0.5))
	# Remove any component along the velocity (lateral steering only) and add gravity compensation.
	a -= fwd * a.dot(fwd)
	var up_perp := Vector3.UP - fwd * Vector3.UP.dot(fwd)
	a += up_perp * GRAVITY
	# Lead pursuit fallback while closing slowly / being fed bad rate data.
	if vc < 1.0:
		var want := los - fwd * los.dot(fwd)
		a += want * 4.0 * GRAVITY
	return a


func _valid_kind(n: Node3D) -> bool:
	return _target_valid_kinds.has(Targeting.kind_of(n))


func _in_seeker(n: Node3D) -> bool:
	var d := n.global_position - global_position
	return d.length() > 0.5 and (-global_transform.basis.z).angle_to(d) <= _seeker_half


func _seeker_update() -> void:
	# Current target validity.
	if target != null:
		var is_flare := target.is_in_group("flares")
		if not is_instance_valid(target) or (is_flare and not _flare_live(target)) \
				or (not is_flare and not Targeting.is_valid_target(target, team)):
			_set_target(null)
		elif not _in_seeker(target):
			_set_target(null)
	if type == "ir_missile":
		_flare_roll()
	if target == null and not _decoyed:
		_acquire()


func _flare_live(f: Node3D) -> bool:
	return f.has_method("is_active") and f.call("is_active")


func _flare_roll() -> void:
	if target != null and target.is_in_group("flares"):
		return
	var resist := float(data.get("flare_resist", 0.7))
	for f in get_tree().get_nodes_in_group("flares"):
		var fl := f as Node3D
		if fl == null or not _flare_live(fl):
			continue
		var id := fl.get_instance_id()
		if _seen_flares.has(id):
			continue
		if global_position.distance_to(fl.global_position) > FLARE_RANGE or not _in_seeker(fl):
			continue
		_seen_flares[id] = true
		if randf() > resist:
			_decoyed = true  # a spoofed seeker does not find its way back to the aircraft
			_set_target(fl)
			return


func _acquire() -> void:
	var best: Node3D = null
	var best_ang := deg_to_rad(FLARE_REACQUIRE_DEG) if shooter == null else _seeker_half
	if _age > 3.0:
		best_ang = deg_to_rad(FLARE_REACQUIRE_DEG)
	var nose := -global_transform.basis.z
	var range_max := float(data.get("range", 10000.0))
	for n in get_tree().get_nodes_in_group("damageable"):
		var c := n as Node3D
		if c == null or not Targeting.is_valid_target(c, team) or not _valid_kind(c):
			continue
		var d := c.global_position - global_position
		var dist := d.length()
		if dist > range_max or dist < 1.0:
			continue
		var ang := nose.angle_to(d)
		if ang < best_ang:
			best_ang = ang
			best = c
	if best != null:
		_set_target(best)


func _set_target(n: Node3D) -> void:
	if _registered_on != null and is_instance_valid(_registered_on) and _registered_on != n:
		var ws: Variant = _registered_on.get("weapons")
		if ws != null and ws.has_method("remove_incoming"):
			ws.call("remove_incoming", self)
		_registered_on = null
	target = n
	if n != null and _registered_on == null and "weapons" in n and n.weapons != null \
			and n.weapons.has_method("add_incoming"):
		n.weapons.call("add_incoming", self)
		_registered_on = n


func _on_flares_dropped(aircraft: Node3D) -> void:
	# Chaff: radar missiles guiding on the dropping aircraft may be defeated.
	if type != "radar_missile" or _dead or aircraft != target or phase == Phase.DROP:
		return
	if randf() > float(data.get("chaff_resist", 0.7)):
		_decoyed = true
		_set_target(null)


func _check_hits(pos: Vector3, dt: float) -> void:
	# Proximity fuze against the tracked target: closest approach within this tick's segment.
	if target != null and is_instance_valid(target) and _age > SPAWN_ARM_TIME:
		var tp := target.global_position
		var tv := Targeting.velocity_of(target)
		var rel_p := _prev_pos - (tp - tv * dt)
		var rel_v := velocity - tv
		var vv := rel_v.length_squared()
		var t := clampf(-rel_p.dot(rel_v) / maxf(vv, 0.001), 0.0, dt)
		var closest := rel_p + rel_v * t
		var fuze := _proximity
		if target.has_method("get_hit_radius"):
			fuze += float(target.call("get_hit_radius")) * 0.4
		if closest.length() <= fuze:
			var at := _prev_pos + velocity * t
			var live := not target.is_in_group("flares")
			_detonate(at, not live)
			return
	# Terrain impact.
	var surf := Ground.surface_at(pos.x, pos.z)
	if pos.y - surf < velocity.length() * dt * 2.0 + 30.0:
		var hit := Ground.raycast(_prev_pos, pos, 40.0)
		if not hit.is_empty():
			_detonate(hit.position, false)


func _detonate(at: Vector3, harmless: bool) -> void:
	if _dead:
		return
	_dead = true
	global_position = at
	if harmless:
		Events.explosion.emit(at, 0.5)
	elif _is_ground:
		Targeting.blast(get_tree(), at, _blast_radius, _damage, shooter, team,
				clampf(_blast_radius * GROUND_BLAST_SIZE_SCALE * 1.4, 0.8, 3.0))
	else:
		Targeting.blast(get_tree(), at, _blast_radius, _damage, shooter, team, BLAST_SIZE_AIR)
	detonated.emit(self)
	_cleanup()


func _flyby_check() -> void:
	if _flyby_done:
		return
	var p := GameState.player
	if p == null or not is_instance_valid(p) or p == shooter:
		return
	if global_position.distance_to(p.global_position) < 220.0:
		_flyby_done = true
		Sfx.play_3d("missile_flyby", global_position)


func _cleanup() -> void:
	if _trail != null and is_instance_valid(_trail):
		Vfx.stop_trail(_trail)
	_trail = null
	if _registered_on != null and is_instance_valid(_registered_on):
		var ws: Variant = _registered_on.get("weapons")
		if ws != null and ws.has_method("remove_incoming"):
			ws.call("remove_incoming", self)
	_registered_on = null
	if Events.flares_dropped.is_connected(_on_flares_dropped):
		Events.flares_dropped.disconnect(_on_flares_dropped)
	if WorldOrigin.shifted.is_connected(_on_shifted):
		WorldOrigin.shifted.disconnect(_on_shifted)
	remove_from_group("missiles")
	queue_free()
