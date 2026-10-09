class_name AIPilot
extends Node
## AI pilot, child of an Aircraft. Decides at 10 Hz (perception of the target is refreshed at the pilot's
## reaction time) and writes aircraft.controls every physics tick, before the aircraft integrates. The pilot
## mostly commands `use_aim` + `aim_direction` + throttle, so it flies the same physics as the player's arcade mode.
##
## API: setup(aircraft, skill, role), set_patrol(points, altitude_m), set_target(node), set_escort(node),
## set_strike(nodes), order(cmd), get_state(). Roles: "fighter", "attacker", "bomber", "wingman", "helicopter".
## Terrain avoidance always overrides the state machine. Everything is guarded so the pilot degrades to plain
## flying when the weapon system or combat units are missing.

enum State { TAKEOFF, PATROL, INTERCEPT, MISSILE_ATTACK, DOGFIGHT, GUN_ATTACK, EVADE, GROUND_ATTACK, RTB, FORMATION, ESCORT }
enum Wing { COVER, ATTACK, FREE, FORM }
enum Run { INGRESS, DIVE, PULLOUT, EGRESS }

const STATE_NAMES: Array[String] = ["takeoff", "patrol", "intercept", "missile_attack", "dogfight", "gun_attack",
		"evade", "ground_attack", "rtb", "formation", "escort"]

const DECISION_DT := 0.1  ## 10 Hz decisions
const ACQUIRE_PERIOD := 1.0
const LOADOUT_PERIOD := 1.0
const LOCKED := 3  ## WeaponSystem.Lock.LOCKED

# Terrain
const FLOOR_AGL := {"fighter": 180.0, "attacker": 150.0, "bomber": 350.0, "wingman": 180.0, "helicopter": 35.0}
const TERRAIN_LOOK_S := 4.5
const TERRAIN_LOOK_DIVE_S := 2.2
const TERRAIN_STEP := 40.0
const AVOID_HOLD := 1.2
const PULLUP_N := 5.0  ## g assumed when sizing a pull-out
const BOUNDS_MARGIN := 2500.0

# Air combat
const INTERCEPT_DIST := 6000.0
const GUN_RANGE := 900.0
const GUN_CONE := 0.35  ## rad off the nose to even consider the gun
const BURST_LEN := 1.0
const BURST_PAUSE := 0.55
const GUN_MUZZLE := 1000.0
const OVERSHOOT_DIST := 520.0
const OVERSHOOT_CLOSURE := 70.0
const MISSILE_COOLDOWN_SLOW := 13.0
const MISSILE_COOLDOWN_FAST := 6.5
const MISSILE_SHOT_RESET := 25.0
const SELF_DEFENCE_RANGE := 5000.0
const HELI_DEFENCE_RANGE := 3000.0
const COVER_RANGE := 5000.0
const ATTACK_LEADER_RANGE := 15000.0
const ESCORT_DEFEND_RANGE := 10000.0
const DETECT_RANGE_LOW := 12000.0
const DETECT_RANGE_HIGH := 20000.0

# Defence
const MISSILE_DETECT := 8000.0
const FLARE_DIST := 2500.0
const BREAK_DIST := 1000.0
const BREAK_FLIP_S := 0.8
const SCISSOR_FLIP_S := 1.7
const SCISSOR_DIST := 600.0

# Energy
const CORNER_FACTOR := 2.1
const CRUISE_FRACTION := 0.55
const STALL_MARGIN := 1.18

# Ground attack
const GROUND_SEEK_RANGE := 12000.0
const PULLOUT_TIME := 3.2
const GROUND_GUN_RANGE := 1000.0

# Formation
const FORM_KP := 0.45  ## 1/s, slot position error to velocity correction
const FORM_MAX_CORR := 70.0  ## m/s
const FORM_SPACING_MIN := 45.0

# Patrol
const PATROL_REACH := 1500.0
const HELI_PATROL_REACH := 300.0
const ORBIT_RADIUS := 3000.0
const HELI_ORBIT_RADIUS := 800.0

## Total microseconds spent in AI physics ticks and the tick count, for the test scene's cost report.
static var debug_cost_usec := 0
static var debug_ticks := 0

var aircraft: Aircraft
var weapons: WeaponSystem
var skill := 0.5
var role := "fighter"
var group: FlightGroup  ## set by FlightGroup.add_member
var formation_slot := 0

var _state := State.PATROL
var _wing := Wing.COVER
var _run := Run.INGRESS
var _bound := false
var _clock := 0.0
var _decide_t := 0.0
var _acq_t := 0.0
var _loadout_t := 0.0

# Derived from skill and aircraft data
var _reaction := 0.4
var _g_tol := 7.5
var _gun_tol_cos := 0.99
var _stall_ms := 60.0
var _max_ms := 300.0
var _cruise_ms := 200.0
var _corner_ms := 150.0
var _floor := 180.0
var _spacing := 50.0
var _flare_dist := FLARE_DIST
var _flare_max := 2
var _mslfrac := 0.5
var _max_shots := 2

# Orders
var _patrol: Array[Vector3] = []
var _patrol_i := 0
var _patrol_alt := 0.0
var _home := Vector3.ZERO
var _forced: Node3D
var _leader: Node3D
var _strike: Array[Node3D] = []

# Target perception
var _tgt: Node3D
var _snap_pos := Vector3.ZERO
var _snap_vel := Vector3.ZERO
var _snap_t := -99.0

# Plan outputs
var _aim_point := Vector3.ZERO
var _throttle := 0.7
var _ab := false
var _airbrake := false
var _gun_want := false
var _spd_i := 0.0
var _speed := 0.0
var _agl := 1000.0

# Terrain avoidance
var _avoid_t := 0.0
var _avoid_dir := Vector3.UP

# Weapons
var _n_air := 0
var _has_ir := false
var _has_bvr := false
var _ir_range := 0.0
var _ir_min := 0.0
var _bvr_range := 0.0
var _bvr_min := 0.0
var _ground_type := ""
var _ground_range := 0.0
var _ground_min := 0.0
var _has_gun := false
var _has_weapons := true
var _cycle_cd := 0.0
var _shots := 0
var _last_msl := -99.0
var _burst_t := 0.0
var _burst_cd := 0.0
var _gear_cd := 0.0

# Defence state
var _threat_seen := -1.0
var _flare_cd := 0.0
var _flare_presses := 0
var _evade_side := 1.0
var _jink_v := 1.0
var _jink_t := 0.0
var _break_side := 1.0
var _break_t := 0.0

# Ground attack state
var _run_t := 0.0
var _released := 0
var _rel_cd := 0.0
var _fire_stamp := -99.0
var _pass_shots := 0

var _rng := RandomNumberGenerator.new()


## skill 0..1 (pass -1 to take it from GameState.difficulty), role as documented above.
func setup(ac: Aircraft, skill_value: float, role_name: String) -> void:
	aircraft = ac
	role = role_name
	skill = AITactics.skill_for_difficulty(GameState.difficulty) if skill_value < 0.0 else clampf(skill_value, 0.0, 1.0)
	_rng.randomize()
	_decide_t = _rng.randf() * DECISION_DT  # spread the decisions of many pilots over the ticks
	var d := ac.data
	_reaction = AITactics.reaction_time(skill)
	_g_tol = AITactics.g_tolerance(skill)
	_gun_tol_cos = cos(AITactics.gun_tolerance_rad(skill))
	_stall_ms = d.stall_speed_ms()
	_max_ms = d.max_speed_kmh / 3.6
	_cruise_ms = clampf(_max_ms * CRUISE_FRACTION, _stall_ms * 1.7, _max_ms * 0.8)
	_corner_ms = clampf(_stall_ms * CORNER_FACTOR, _cruise_ms * 0.8, _max_ms * 0.7)
	_floor = float(FLOOR_AGL.get(role, 180.0))
	_spacing = maxf(FORM_SPACING_MIN, d.wing_span * 2.5)
	_flare_dist = FLARE_DIST + (_rng.randf() - 0.5) * 2.0 * (1.0 - skill) * 1200.0
	_flare_max = 2 + int(skill * 3.0)
	_mslfrac = lerpf(0.35, 0.6, skill)
	_max_shots = 2 + (1 if skill > 0.7 else 0)
	if role == "wingman":
		_wing = Wing.COVER


func set_patrol(points: Array[Vector3], altitude_m: float) -> void:
	_patrol = points.duplicate()
	_patrol_i = 0
	_patrol_alt = altitude_m


## Forces the target (cleared automatically when it dies).
func set_target(node: Node3D) -> void:
	_forced = node
	_acq_t = 0.0


## Follow and defend `node`. Wingmen fly tight formation, other roles loiter loosely near it and engage threats.
func set_escort(node: Node3D) -> void:
	_leader = node


func set_strike(target_nodes: Array) -> void:
	_strike.clear()
	for n in target_nodes:
		if n is Node3D:
			_strike.append(n)
	_acq_t = 0.0


## Wingman orders: "attack_my_target", "cover_me", "engage_free", "rejoin".
func order(cmd: String) -> void:
	match cmd:
		"attack_my_target":
			_wing = Wing.ATTACK
		"cover_me":
			_wing = Wing.COVER
		"engage_free":
			_wing = Wing.FREE
		"rejoin":
			_wing = Wing.FORM
			_forced = null
		_:
			return
	_set_tgt(null)
	_acq_t = 0.0


func get_state() -> String:
	return STATE_NAMES[_state]


func get_target() -> Node3D:
	return _tgt if _tgt != null and is_instance_valid(_tgt) else null


func is_avoiding_terrain() -> bool:
	return _avoid_t > 0.0


func get_leader() -> Node3D:
	return _leader


func _ready() -> void:
	process_physics_priority = -50  # before the aircraft integrates


func _physics_process(delta: float) -> void:
	if aircraft == null or not aircraft.alive:
		return
	var t0 := Time.get_ticks_usec()
	if not _bound:
		_bind()
	_clock += delta
	var c := aircraft.controls
	c.clear_triggers()
	_decide_t -= delta
	if _decide_t <= 0.0:
		_decide_t += DECISION_DT
		_decide()
	_apply(c, delta)
	debug_cost_usec += Time.get_ticks_usec() - t0
	debug_ticks += 1


func _bind() -> void:
	_bound = true
	weapons = aircraft.weapons as WeaponSystem
	_home = aircraft.position
	if _patrol_alt <= 0.0:
		var ground := Ground.surface_at(_home.x, _home.z)
		_patrol_alt = ground + (120.0 if role == "helicopter" else maxf(_home.y - ground, 1200.0))
	if aircraft.is_on_ground():
		_state = State.TAKEOFF
	_refresh_loadout()


# ----------------------------------------------------------------------------------------------------------------
# Decisions (10 Hz)
# ----------------------------------------------------------------------------------------------------------------

func _decide() -> void:
	var pos := aircraft.position
	var vel := aircraft.velocity
	_speed = vel.length()
	_agl = pos.y - Ground.surface_at(pos.x, pos.z)
	_cycle_cd = maxf(_cycle_cd - DECISION_DT, 0.0)
	_flare_cd = maxf(_flare_cd - DECISION_DT, 0.0)
	_gear_cd = maxf(_gear_cd - DECISION_DT, 0.0)
	_rel_cd = maxf(_rel_cd - DECISION_DT, 0.0)
	_loadout_t -= DECISION_DT
	if _loadout_t <= 0.0:
		_loadout_t = LOADOUT_PERIOD
		_refresh_loadout()
	_gun_want = false
	_airbrake = false
	_ab = false
	_scan_terrain(pos, vel)

	if _state == State.TAKEOFF:
		if _plan_takeoff(pos):
			return
	if _scan_missiles(pos, vel):
		_plan_evade(pos, vel)
		_after_plan(pos)
		return
	_refresh_target()
	if _needs_rtb():
		_plan_rtb(pos)
	elif _tgt != null:
		_update_snapshot()
		if AITactics.is_air_kind(Targeting.kind_of(_tgt)):
			_plan_air(pos, vel)
		else:
			_plan_ground(pos, vel)
	elif _leader != null and _leader_flying():
		_plan_follow(pos, vel)
	else:
		_plan_patrol(pos, vel)
	_after_plan(pos)


## Common post-processing: map bounds, low-energy bias, stall recovery.
func _after_plan(pos: Vector3) -> void:
	if Ground.is_loaded() and not Ground.in_bounds(pos, BOUNDS_MARGIN) and _state != State.EVADE:
		var centre := WorldOrigin.to_local(Vector3.ZERO)
		_aim_point = Vector3(centre.x, maxf(pos.y, _patrol_alt), centre.z)
		_throttle = _hold_speed(_cruise_ms)
		_gun_want = false
	var dive_ok := _state == State.INTERCEPT or _state == State.DOGFIGHT or _state == State.MISSILE_ATTACK
	if dive_ok and _agl > _floor * 3.0:
		var low := clampf((_corner_ms * 0.9 - _speed) / (_corner_ms * 0.4), 0.0, 1.0)
		if low > 0.0:
			_aim_point += Vector3.DOWN * (low * 600.0)
			_throttle = 1.0
			_ab = true


func _hold_speed(target_ms: float) -> float:
	var err := target_ms - _speed
	_spd_i = clampf(_spd_i + err * 0.0006, -0.3, 0.45)
	return clampf(0.5 + _spd_i + err * 0.01, 0.2, 1.0)


func _scan_terrain(pos: Vector3, vel: Vector3) -> void:
	if _speed < 5.0 or (_state == State.TAKEOFF and _agl < 60.0):
		return
	var diving := _state == State.GROUND_ATTACK and _run == Run.DIVE
	var look := TERRAIN_LOOK_DIVE_S if diving else TERRAIN_LOOK_S
	var r := AITactics.terrain_ahead(pos, vel, look, TERRAIN_STEP)
	if is_inf(r.x):
		return
	var f := clampf(r.x / look, 0.0, 1.0)
	var pitch := lerpf(1.1, 0.4, f)
	_avoid_dir = AITactics.climb_direction(vel, Vector3(r.y, r.z, r.w), pitch)
	_avoid_t = maxf(_avoid_t, AVOID_HOLD)


func _plan_takeoff(pos: Vector3) -> bool:
	_state = State.TAKEOFF
	var fwd := AITactics.flat(-aircraft.transform.basis.z)
	var rotating := _speed > aircraft.data.takeoff_speed_kmh / 3.6
	var pitch := 0.2 if rotating else 0.0
	if not aircraft.is_on_ground():
		pitch = 0.22
		if _agl > 40.0 and aircraft.is_gear_down() and _gear_cd <= 0.0:
			aircraft.controls.toggle_gear = true
			_gear_cd = 3.0
		if _agl > 150.0 and not aircraft.is_gear_down():
			_state = State.PATROL
			return false
	_aim_point = pos + (fwd * cos(pitch) + Vector3.UP * sin(pitch)) * 1000.0
	_throttle = 1.0
	_ab = true
	return true


func _leader_flying() -> bool:
	if not is_instance_valid(_leader):
		return false
	if "alive" in _leader and not _leader.alive:
		return false
	return not ("flight" in _leader and _leader.is_on_ground())


# ----- target selection -----

func _set_tgt(n: Node3D) -> void:
	if n == _tgt:
		return
	_tgt = n
	_shots = 0
	_snap_t = -99.0
	_run = Run.INGRESS
	_released = 0
	_pass_shots = 0
	if weapons != null:
		weapons.set_target(n)


func _valid(n: Node3D) -> bool:
	return n != null and Targeting.is_valid_target(n, aircraft.team)


func _refresh_target() -> void:
	if _forced != null:
		if _valid(_forced):
			_set_tgt(_forced)
			return
		_forced = null
	if _tgt != null and not _valid(_tgt):
		_set_tgt(null)
	_acq_t -= DECISION_DT
	if _acq_t > 0.0:
		return
	_acq_t = ACQUIRE_PERIOD
	if weapons == null:
		return
	var pos := aircraft.global_position
	var detect := lerpf(DETECT_RANGE_LOW, DETECT_RANGE_HIGH, skill)
	var pick: Node3D = null
	match role:
		"fighter":
			if _leader != null and is_instance_valid(_leader):
				pick = _pick_air(_leader.global_position, ESCORT_DEFEND_RANGE)
			else:
				pick = _pick_air(pos, detect)
		"wingman":
			pick = _pick_wingman(pos, detect)
		"bomber":
			pick = _pick_ground(pos)
		_:
			pick = _pick_ground(pos)
			if pick == null:
				pick = _pick_air(pos, HELI_DEFENCE_RANGE if role == "helicopter" else SELF_DEFENCE_RANGE)
	_set_tgt(pick)


func _pick_wingman(pos: Vector3, detect: float) -> Node3D:
	var have_leader := _leader != null and is_instance_valid(_leader)
	var lp := _leader.global_position if have_leader else pos
	match _wing:
		Wing.FORM:
			return null
		Wing.COVER:
			return _pick_air(lp, COVER_RANGE) if have_leader else _pick_air(pos, detect)
		Wing.ATTACK:
			var lt := _leader_target()
			if lt != null:
				return lt
			return _pick_air(lp, ATTACK_LEADER_RANGE) if have_leader else _pick_air(pos, detect)
		_:
			var a := _pick_air(pos, detect)
			if a != null:
				return a
			return _pick_ground(pos)
	return null


func _leader_target() -> Node3D:
	if _leader == null or not is_instance_valid(_leader):
		return null
	var w: Variant = _leader.get("weapons")
	if w is WeaponSystem:
		var t: Node3D = w.get_target()
		if _valid(t):
			return t
	return null


func _pick_air(center: Vector3, max_range: float) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var pos := aircraft.global_position
	for n in weapons.get_visible_targets():
		if not _valid(n) or not AITactics.is_air_kind(Targeting.kind_of(n)):
			continue
		var p := n.global_position
		var d := p.distance_to(center)
		if d > max_range:
			continue
		var score := d + 0.3 * p.distance_to(pos)
		if group != null:
			score += 2500.0 * group.load_of(n, self)
		if n == _tgt:
			score *= 0.7
		if score < best_score:
			best_score = score
			best = n
	return best


func _pick_ground(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var i := _strike.size() - 1
	while i >= 0:
		var n := _strike[i]
		if not is_instance_valid(n):
			_strike.remove_at(i)
		elif _valid(n):
			var d := n.global_position.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = n
		i -= 1
	if best != null or not _strike.is_empty():
		return best
	if weapons == null or (_ground_type == "" and not _has_gun):
		return null
	var seek := GROUND_SEEK_RANGE
	for n in weapons.get_visible_targets():
		if not _valid(n) or not AITactics.is_ground_kind(Targeting.kind_of(n)):
			continue
		var d := n.global_position.distance_to(pos)
		if d < seek:
			seek = d
			best = n
	return best


func _update_snapshot() -> void:
	if _clock - _snap_t >= _reaction * 1.1:
		_snap_pos = _tgt.global_position
		_snap_vel = Targeting.velocity_of(_tgt)
		_snap_t = _clock


# ----- weapons bookkeeping -----

func _refresh_loadout() -> void:
	_n_air = 0
	_has_ir = false
	_has_bvr = false
	_ground_type = ""
	_has_gun = false
	if weapons == null:
		_has_weapons = false
		return
	var db := WeaponSystem.weapon_db()
	var best := 99
	for it in weapons.get_weapon_list():
		var cnt := int(it.count)
		if cnt <= 0:
			continue
		var t := str(it.type)
		var wd: Dictionary = db.get(str(it.id), {})
		var rng := float(wd.get("range", 8000.0))
		var mn := float(wd.get("min_range", 300.0))
		if AITactics.air_missile_type(t):
			_n_air += cnt
			if t == "radar_missile":
				_has_bvr = true
				_bvr_range = rng
				_bvr_min = mn
			else:
				_has_ir = true
				_ir_range = rng
				_ir_min = mn
		else:
			var rank := AITactics.ground_weapon_rank(t)
			if rank < best:
				best = rank
				_ground_type = t
				_ground_range = rng
				_ground_min = mn
	_has_gun = weapons.gun != null and weapons.gun.ammo > 0
	_has_weapons = _n_air > 0 or _has_gun or _ground_type != ""


## Makes `type` the selected weapon (cycling at most every 0.35 s). True once it is selected and has ammo.
func _ensure_selected(type: String) -> bool:
	var sel := weapons.get_selected()
	if str(sel.type) == type and int(sel.count) > 0:
		if weapons.get_target() != _tgt:
			weapons.set_target(_tgt)
		return true
	if _cycle_cd <= 0.0:
		aircraft.controls.cycle_weapon = true
		_cycle_cd = 0.35
	return false


func _needs_rtb() -> bool:
	if aircraft.get_fuel_frac() < 0.12:
		return true
	return not _has_weapons and role != "helicopter"


# ----- missiles incoming -----

func _scan_missiles(pos: Vector3, _vel: Vector3) -> bool:
	if weapons == null:
		return false
	var inc := weapons.get_incoming_missiles()
	if inc.is_empty():
		_threat_seen = -1.0
		_flare_presses = 0
		return false
	var nearest: Node3D = null
	var nd := MISSILE_DETECT
	for m in inc:
		var d := m.global_position.distance_to(pos)
		if d < nd:
			nd = d
			nearest = m
	if nearest == null:
		return false
	if _threat_seen < 0.0:
		_threat_seen = _clock
		_evade_side = 1.0 if _rng.randf() < 0.5 else -1.0
	if _clock - _threat_seen < _reaction:
		return false
	_evade_m = nearest
	_evade_d = nd
	return true


var _evade_m: Node3D
var _evade_d := 0.0


func _plan_evade(pos: Vector3, vel: Vector3) -> void:
	_state = State.EVADE
	var mp := _evade_m.global_position
	var rel := mp - pos
	var d := maxf(_evade_d, 1.0)
	var los := rel / d
	var perp := los.cross(Vector3.UP)
	if perp.length_squared() < 1e-4:
		perp = (-aircraft.transform.basis.z).cross(Vector3.UP)
	perp = perp.normalized()
	if _clock >= _break_t:
		_break_t = _clock + 1.2
		if perp.dot(vel) * _evade_side < 0.0:
			_evade_side = -_evade_side if _rng.randf() < 0.15 else _evade_side
	var beam := perp * _evade_side
	var dir := beam
	if d > BREAK_DIST:
		dir.y = -0.35 if _agl > 700.0 else 0.15  # dive for ground clutter when high enough
	else:
		if _clock >= _jink_t:
			_jink_t = _clock + BREAK_FLIP_S
			_jink_v = 1.0 if (_agl < 600.0 or _rng.randf() < 0.5) else -1.0
			if _rng.randf() < 0.35 * skill:
				_evade_side = -_evade_side
		dir = beam * 0.55 + Vector3.UP * _jink_v * 0.85
	_aim_point = pos + dir.normalized() * 1000.0
	_throttle = 1.0
	_ab = true
	if d < _flare_dist and weapons.flares > 0 and _flare_cd <= 0.0 and _flare_presses < _flare_max:
		aircraft.controls.drop_flares = true
		_flare_presses += 1
		_flare_cd = lerpf(1.2, 0.6, skill)


# ----- air combat -----

func _plan_air(pos: Vector3, vel: Vector3) -> void:
	var tv := _snap_vel
	var tp := _snap_pos + tv * (_clock - _snap_t)
	var rel := tp - pos
	var dist := maxf(rel.length(), 1.0)
	var los := rel / dist
	var nose := aircraft.get_nose()
	var ata := nose.angle_to(los)
	var tspeed := tv.length()
	var tdir := tv / tspeed if tspeed > 5.0 else los
	var closure := (vel - tv).dot(los)
	var threat := tdir.dot(-los) > 0.82 and dist < 3500.0  # target nose within ~35 degrees of me
	var up := Vector3.UP
	var aim: Vector3
	var thr := 1.0

	var missile_busy := _try_air_missile(dist, ata)
	_state = State.MISSILE_ATTACK if missile_busy else (State.INTERCEPT if dist > INTERCEPT_DIST else State.DOGFIGHT)

	if threat and ata > 1.0 and dist < 2200.0:
		# Defensive: break across his line of sight, scissors when he is close behind.
		var perp := los.cross(up)
		if perp.length_squared() < 1e-4:
			perp = nose.cross(up)
		perp = perp.normalized()
		var flip := SCISSOR_FLIP_S if dist < SCISSOR_DIST else 4.0
		if _clock >= _break_t:
			_break_t = _clock + flip
			_break_side = -_break_side if (dist < SCISSOR_DIST or _rng.randf() < 0.3) else _break_side
		var vert := 1.0 if _speed > _corner_ms * 1.2 else -1.0
		if _agl < _floor * 3.0:
			vert = 1.0
		aim = pos + (perp * _break_side * 0.85 + up * vert * 0.5).normalized() * 1000.0
		thr = 0.65 if (dist < SCISSOR_DIST and _speed > _corner_ms) else 1.0
		_state = State.DOGFIGHT
	else:
		if dist > INTERCEPT_DIST:
			aim = tp + tv * minf(dist / maxf(_speed + tspeed * 0.5, 100.0), 20.0)
		elif missile_busy and dist > 1500.0:
			aim = tp  # point at him to hold the lock
		elif dist < 1400.0:
			aim = Targeting.lead_point(pos, vel, tp, tv, GUN_MUZZLE)
			if dist < 900.0 and ata > 0.7:
				aim = tp  # pure pursuit when the lead point is out of reach: keeps energy
		else:
			aim = tp + tv * clampf(dist / maxf(_speed, 150.0), 0.0, 6.0) * 0.8
		if dist < OVERSHOOT_DIST and closure > OVERSHOOT_CLOSURE and ata < 0.7 and tdir.dot(nose) > 0.5:
			aim = pos + (up * 0.9 + los * 0.45).normalized() * 1000.0  # high yo-yo
			thr = 0.5
			_airbrake = closure > 150.0
		_gun_want = _has_gun and dist < GUN_RANGE and ata < GUN_CONE
		if _gun_want and ata < 0.17 and not missile_busy:
			_state = State.GUN_ATTACK
	_aim_point = aim
	_throttle = thr
	_ab = thr >= 0.99


## Locks and shoots air-to-air missiles inside the envelope. True while a missile attack is in progress.
func _try_air_missile(dist: float, ata: float) -> bool:
	if _n_air <= 0 or weapons == null:
		return false
	if _clock - _last_msl > MISSILE_SHOT_RESET:
		_shots = 0
	var want := "ir_missile"
	var rng := _ir_range
	var mn := _ir_min
	if _has_bvr and (dist > 6500.0 or not _has_ir):
		want = "radar_missile"
		rng = _bvr_range
		mn = _bvr_min
	elif not _has_ir:
		return false
	var max_fire := rng * _mslfrac
	if dist > max_fire * 1.15 or dist < mn * 1.5 or _shots >= _max_shots:
		return false
	if not _ensure_selected(want):
		return true
	var cone := deg_to_rad(60.0 if want == "radar_missile" else 30.0)
	if ata > cone:
		return false
	var cooldown := lerpf(MISSILE_COOLDOWN_SLOW, MISSILE_COOLDOWN_FAST, skill)
	var reserve_ok := _n_air > 1 or dist < rng * 0.3
	if weapons.get_lock_state() == LOCKED and dist <= max_fire and reserve_ok and _clock - _last_msl >= cooldown:
		aircraft.controls.fire_weapon = true
		_last_msl = _clock
		_shots += 1
	return true


# ----- ground attack -----

func _plan_ground(pos: Vector3, vel: Vector3) -> void:
	_state = State.GROUND_ATTACK
	var tp := _tgt.global_position
	var to_t := tp - pos
	var dh := Vector2(to_t.x, to_t.z).length()
	var dist := to_t.length()
	var w := _ground_type
	var standoff := w == "ag_missile" or w == "guided_bomb"
	var level := w == "bomb" and role == "bomber"
	var dive_alt := 450.0
	var start := 1200.0
	if w == "bomb":
		dive_alt = 1200.0
		start = 3200.0
	elif w == "rocket":
		dive_alt = 700.0
		start = 1900.0
	if role == "helicopter":
		dive_alt = 120.0
	var cruise_alt := maxf(_patrol_alt, tp.y + 700.0)
	var ing_alt := cruise_alt if (standoff or level) else tp.y + dive_alt
	var away := AITactics.flat(pos - tp)
	if dh < 100.0:
		away = AITactics.flat(vel)
	_throttle = _hold_speed(_cruise_ms * (1.0 if (standoff or level) else 1.15))
	var aim := Vector3(tp.x, ing_alt, tp.z)
	var vy_down := minf(vel.y, 0.0)
	var pull_agl := _floor + 1.6 * vy_down * vy_down / (2.0 * PULLUP_N * 9.81)

	match _run:
		Run.INGRESS:
			if not standoff and not level and dh <= start:
				_run = Run.DIVE
			elif standoff:
				_ground_standoff(w, dist)
			elif level:
				_ground_bomb(tp, dh, 1.6)
				if _released >= 4:
					_end_pass(Run.EGRESS, 5.0)
		Run.DIVE:
			aim = tp
			if w == "bomb":
				var ccip := _ground_bomb(tp, dh, 1.0)
				if ccip.is_finite():
					var corr := Vector3(tp.x - ccip.x, 0.0, tp.z - ccip.z)
					if corr.length() > 600.0:
						corr = corr.normalized() * 600.0
					aim = tp + corr * 0.8
				if _released >= 2:
					_end_pass(Run.PULLOUT, PULLOUT_TIME)
			elif w == "rocket":
				_ground_rocket(dist, to_t.normalized())
				if _released > 0 and _clock - _fire_stamp > 0.9:
					_end_pass(Run.PULLOUT, PULLOUT_TIME)
			_gun_want = _has_gun and dist < GROUND_GUN_RANGE
			if _agl < pull_agl or dh < 120.0 or (_agl < _floor * 2.0 and _speed > 1.0):
				_end_pass(Run.PULLOUT, PULLOUT_TIME)
		Run.PULLOUT:
			aim = pos + AITactics.flat(vel) * 700.0 + Vector3.UP * 700.0
			_throttle = 1.0
			if _clock >= _run_t:
				_run = Run.EGRESS
				_run_t = _clock + 25.0
		Run.EGRESS:
			aim = pos + away * 3000.0
			aim.y = ing_alt
			if standoff or level:
				if _clock >= _run_t:
					_run = Run.INGRESS
					_pass_shots = 0
			elif dh > start + 1500.0 or _clock >= _run_t:
				_run = Run.INGRESS
				_released = 0
				_pass_shots = 0
	if _run == Run.INGRESS or _run == Run.EGRESS:
		aim = _limit_climb(pos, aim, 0.4, 0.5)
	_aim_point = aim
	_ab = _throttle >= 0.99


func _end_pass(next: Run, seconds: float) -> void:
	_run = next
	_run_t = _clock + seconds
	_released = 0
	_pass_shots = 0


func _ground_standoff(w: String, dist: float) -> void:
	if weapons == null or not _ensure_selected(w):
		return
	if weapons.get_lock_state() == LOCKED and dist < _ground_range * 0.85 and dist > _ground_min * 1.3 \
			and _rel_cd <= 0.0:
		aircraft.controls.fire_weapon = true
		_rel_cd = 3.5
		_pass_shots += 1
		if _pass_shots >= 2:
			_end_pass(Run.EGRESS, 12.0)


## Releases unguided bombs when the CCIP is on the target. Returns the CCIP (INF when unavailable).
func _ground_bomb(tp: Vector3, _dh: float, tol_scale: float) -> Vector3:
	if weapons == null or not _ensure_selected("bomb"):
		return Vector3.INF
	var ccip := weapons.get_ccip_point()
	if not ccip.is_finite():
		return ccip
	var tol := lerpf(110.0, 45.0, skill) * tol_scale
	var err := Vector2(ccip.x - tp.x, ccip.z - tp.z).length()
	if err < tol and _rel_cd <= 0.0:
		aircraft.controls.fire_weapon = true
		_released += 1
		_rel_cd = 0.5
	return ccip


func _ground_rocket(dist: float, dir_to: Vector3) -> void:
	if weapons == null or _released > 0 or not _ensure_selected("rocket"):
		return
	var ang := aircraft.get_nose().angle_to(dir_to)
	if dist < minf(_ground_range * 0.8, 1800.0) and ang < lerpf(0.09, 0.04, skill):
		aircraft.controls.fire_weapon = true
		_released = 1
		_fire_stamp = _clock


func _limit_climb(pos: Vector3, aim: Vector3, up_slope: float, down_slope: float) -> Vector3:
	var d := aim - pos
	var h := Vector2(d.x, d.z).length()
	if h < 1.0:
		return aim
	d.y = clampf(d.y, -h * down_slope, h * up_slope)
	return pos + d


# ----- patrol, rtb, formation -----

func _plan_patrol(pos: Vector3, vel: Vector3) -> void:
	_state = State.PATROL
	if _patrol.is_empty():
		_orbit(pos, vel, _home, _patrol_alt)
	else:
		var p := _patrol[_patrol_i]
		var reach := HELI_PATROL_REACH if role == "helicopter" else PATROL_REACH
		if Vector2(p.x - pos.x, p.z - pos.z).length() < reach:
			_patrol_i = (_patrol_i + 1) % _patrol.size()
			p = _patrol[_patrol_i]
		var alt := maxf(_patrol_alt, Ground.surface_at(p.x, p.z) + _floor + 200.0)
		_aim_point = _limit_climb(pos, Vector3(p.x, alt, p.z), 0.3, 0.25)
	_throttle = _hold_speed(_cruise_ms)


func _plan_rtb(pos: Vector3) -> void:
	_state = State.RTB
	_set_tgt(null)
	var alt := maxf(_patrol_alt, Ground.surface_at(_home.x, _home.z) + 600.0)
	if Vector2(_home.x - pos.x, _home.z - pos.z).length() < ORBIT_RADIUS * 1.5:
		_orbit(pos, aircraft.velocity, _home, alt)
	else:
		_aim_point = _limit_climb(pos, Vector3(_home.x, alt, _home.z), 0.3, 0.25)
	_throttle = _hold_speed(_cruise_ms)


func _orbit(pos: Vector3, vel: Vector3, centre: Vector3, alt: float) -> void:
	var radius := HELI_ORBIT_RADIUS if role == "helicopter" else ORBIT_RADIUS
	var rel := Vector3(pos.x - centre.x, 0.0, pos.z - centre.z)
	var d := rel.length()
	var radial := rel / d if d > 1.0 else AITactics.flat(vel)
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	var p := centre + radial * radius + tangent * radius * 0.4
	var a := maxf(alt, Ground.surface_at(p.x, p.z) + _floor + 200.0)
	_aim_point = _limit_climb(pos, Vector3(p.x, a, p.z), 0.3, 0.25)


func _plan_follow(pos: Vector3, vel: Vector3) -> void:
	var tight := role == "wingman"
	_state = State.FORMATION if tight else State.ESCORT
	var lv := Targeting.velocity_of(_leader)
	var lp := _leader.global_position
	var lspd := lv.length()
	if lspd < _stall_ms * 0.8:
		_orbit(pos, vel, lp, maxf(lp.y + 300.0, _patrol_alt))
		_throttle = _hold_speed(_cruise_ms)
		return
	var fwd := AITactics.flat(lv)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var off := AITactics.slot_offset(formation_slot, _spacing)
	if not tight:
		off = Vector3(off.x * 4.0, 120.0, off.z * 3.0)
	var desired := lp + right * off.x + Vector3.UP * off.y - fwd * off.z
	var corr := (desired - pos) * FORM_KP
	if corr.length() > FORM_MAX_CORR:
		corr = corr.normalized() * FORM_MAX_CORR
	var vdes := lv + corr
	var vlen := maxf(vdes.length(), 1.0)
	_aim_point = _limit_climb(pos, pos + vdes / vlen * 800.0, 0.5, 0.5)
	var ts := clampf(vlen, _stall_ms * 1.25, _max_ms * 0.9)
	_throttle = _hold_speed(ts)
	_airbrake = _speed > ts + 30.0
	_ab = _throttle >= 0.99


# ----------------------------------------------------------------------------------------------------------------
# Control (60 Hz)
# ----------------------------------------------------------------------------------------------------------------

func _apply(c: ControlInput, delta: float) -> void:
	var pos := aircraft.position
	var vel := aircraft.velocity
	var nose := aircraft.get_nose()
	var airborne := not aircraft.is_on_ground()

	# Immediate ground proximity check: plan-independent, never skipped.
	if airborne and _state != State.TAKEOFF:
		var agl := pos.y - Ground.surface_at(pos.x, pos.z)
		var vy := minf(vel.y, 0.0)
		if agl < _floor * 0.5 + 1.3 * vy * vy / (2.0 * PULLUP_N * 9.81) and (vy < -2.0 or agl < _floor * 0.3):
			_avoid_dir = AITactics.climb_direction(vel, Vector3.UP, 0.9)
			_avoid_t = maxf(_avoid_t, AVOID_HOLD)

	var dir: Vector3
	var thr := _throttle
	var ab := _ab
	var brake := _airbrake
	if _avoid_t > 0.0 and airborne:
		_avoid_t -= delta
		dir = _avoid_dir
		thr = 1.0
		ab = true
		brake = false
		_gun_want = false
	else:
		dir = _aim_point - pos
		if dir.length_squared() < 1.0:
			dir = nose
		dir = dir.normalized()
		var g := aircraft.get_g()
		if g > _g_tol and _state != State.EVADE:
			dir = dir.lerp(nose, clampf((g - _g_tol) * 0.25, 0.0, 0.7)).normalized()
		if airborne and (_state != State.TAKEOFF or _agl > 100.0) \
				and (aircraft.is_stalling() or _speed < _stall_ms * STALL_MARGIN):
			# Recover: unload, nose slightly down when there is room, full power.
			var level := AITactics.flat(vel)
			dir = (level * 0.94 + Vector3.DOWN * (0.3 if _agl > 400.0 else -0.1)).normalized()
			thr = 1.0
			ab = true
			brake = false
	c.use_aim = true
	c.aim_direction = aircraft.transform.basis.transposed() * dir
	c.throttle = thr
	c.afterburner = ab and aircraft.data.has_afterburner
	c.airbrake = brake
	_fire_gun(c, pos, nose, delta)


func _fire_gun(c: ControlInput, pos: Vector3, nose: Vector3, delta: float) -> void:
	c.fire_gun = false
	if _burst_cd > 0.0:
		_burst_cd -= delta
		return
	if not _gun_want or weapons == null or _tgt == null:
		_burst_t = 0.0
		return
	var to_lead := weapons.get_gun_lead_point() - pos
	var dist := to_lead.length()
	if dist < 1.0 or dist > minf(GROUND_GUN_RANGE if _state == State.GROUND_ATTACK else GUN_RANGE, weapons.get_gun_range()):
		return
	if nose.dot(to_lead / dist) < _gun_tol_cos:
		return
	c.fire_gun = true
	_burst_t += delta
	if _burst_t >= BURST_LEN:
		_burst_t = 0.0
		_burst_cd = BURST_PAUSE * lerpf(1.4, 0.8, skill)
