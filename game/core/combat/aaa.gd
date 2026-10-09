class_name AAA
extends CombatUnit
## Anti-Aircraft Artillery (ZSU-23-4 Shilka / Bofors 40mm).
## Computes target lead, fires bursts of autocannon rounds via BulletPool,
## and spawns flak airbursts for heavy caliber AAA.

const RADAR_SCAN_SPEED := 3.0
const LOS_RAY_STEP := 50.0

var weapon_id: String = "zu23"
var wdata: Dictionary = {}
var max_range_m: float = 2500.0
var min_range_m: float = 100.0

var current_target: Node3D = null
var reaction_delay: float = 1.0
var burst_time: float = 0.0
var burst_cooldown: float = 0.0
var is_firing: bool = false

var _turret_node: Node3D
var _gun_mount: Node3D
var _dish_node: Node3D
var _pool: BulletPool
var _acc: float = 0.0
var _round_count: int = 0
var _rng := RandomNumberGenerator.new()
var _weapons_dict: Dictionary = {}


func _ready() -> void:
	super._ready()
	_rng.randomize()
	_load_weapon_data()
	_find_model_nodes()


func setup_aaa(p_kind: String, p_team: int, p_weapon_id: String = "") -> void:
	setup_unit(p_kind, p_team)
	if p_weapon_id != "":
		weapon_id = p_weapon_id
	else:
		match p_kind:
			"aaa_zsu": weapon_id = "zu23"
			"aaa_bofors": weapon_id = "bofors40"
			_: weapon_id = "zu23"
	_load_weapon_data()


func _load_weapon_data() -> void:
	if _weapons_dict.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/weapons.json")
		if txt != "":
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				_weapons_dict = parsed
	wdata = _weapons_dict.get(weapon_id, {})
	max_range_m = float(wdata.get("range", 2500.0))


func _find_model_nodes() -> void:
	if visual == null:
		return
	_turret_node = visual.find_child("Turret", true, false) as Node3D
	_gun_mount = visual.find_child("GunMount", true, false) as Node3D
	_dish_node = visual.find_child("RadarDish", true, false) as Node3D


func unit_tick(dt: float) -> void:
	if not alive:
		return

	if _dish_node != null and is_instance_valid(_dish_node):
		_dish_node.rotation.y += RADAR_SCAN_SPEED * dt

	if burst_cooldown > 0.0:
		burst_cooldown -= dt

	if current_target == null or not _is_target_valid(current_target):
		is_engaging = false
		_search_targets()
		return

	is_engaging = true
	_track_and_engage(dt)


func _get_difficulty_multiplier() -> float:
	var diff := GameState.difficulty
	match diff:
		"easy": return 1.5
		"hard": return 0.7
		"ace": return 0.5
		_: return 1.0


func _search_targets() -> void:
	current_target = null
	var best_target: Node3D = null
	var best_dist := INF

	for node in get_tree().get_nodes_in_group("damageable"):
		var candidate := node as Node3D
		if candidate == null or not is_instance_valid(candidate) or candidate == self:
			continue
		if int(candidate.get("team")) == team:
			continue
		if "alive" in candidate and not candidate.alive:
			continue
		var kind: String = candidate.call("get_target_kind") if candidate.has_method("get_target_kind") else ""
		if kind != "air" and kind != "helicopter":
			continue

		var dist := global_position.distance_to(candidate.global_position)
		if dist < min_range_m or dist > max_range_m:
			continue

		if not _has_line_of_sight(candidate.global_position):
			continue

		if dist < best_dist:
			best_dist = dist
			best_target = candidate

	if best_target != null:
		current_target = best_target
		reaction_delay = randf_range(0.8, 1.4) * _get_difficulty_multiplier()


func _track_and_engage(dt: float) -> void:
	var mv := float(wdata.get("muzzle_velocity", 950.0))
	var muzzle_pos := global_position + Vector3.UP * (size.y * 0.7)
	var tgt_pos := current_target.global_position
	var tgt_vel := Targeting.velocity_of(current_target)

	var aim_point := Targeting.lead_point(muzzle_pos, velocity, tgt_pos, tgt_vel, mv)
	_aim_at(aim_point, dt)

	if reaction_delay > 0.0:
		reaction_delay -= dt
		return

	if burst_cooldown <= 0.0:
		# Check if barrel is reasonably on target (within 12 degrees)
		var to_aim := (aim_point - muzzle_pos).normalized()
		var barrel_fwd := -global_transform.basis.z
		if _gun_mount != null and is_instance_valid(_gun_mount):
			barrel_fwd = -_gun_mount.global_transform.basis.z

		if barrel_fwd.angle_to(to_aim) < deg_to_rad(12.0):
			_fire_step(dt, muzzle_pos, barrel_fwd, tgt_pos)
			burst_time += dt
			var max_burst := 1.8 if weapon_id == "zu23" else 0.8
			if burst_time >= max_burst:
				burst_time = 0.0
				burst_cooldown = randf_range(1.2, 2.2) * _get_difficulty_multiplier()


func _aim_at(aim_point: Vector3, dt: float) -> void:
	var to_aim := aim_point - global_position
	if _turret_node != null and is_instance_valid(_turret_node):
		var target_yaw := atan2(to_aim.x, -to_aim.z)
		_turret_node.rotation.y = rotate_toward(_turret_node.rotation.y, target_yaw, 3.5 * dt)

	if _gun_mount != null and is_instance_valid(_gun_mount):
		var horiz_dist := Vector2(to_aim.x, to_aim.z).length()
		var target_pitch := -clampf(atan2(to_aim.y, horiz_dist), deg_to_rad(5.0), deg_to_rad(85.0))
		_gun_mount.rotation.x = rotate_toward(_gun_mount.rotation.x, target_pitch, 3.0 * dt)


func _fire_step(dt: float, muzzle_pos: Vector3, forward_dir: Vector3, tgt_pos: Vector3) -> void:
	if _pool == null:
		_pool = BulletPool.get_pool(self)

	var rate := float(wdata.get("rpm", 1500.0)) / 60.0
	_acc += dt * rate
	var count := mini(int(_acc), 12)
	_acc -= floorf(_acc)

	if count <= 0:
		return

	var mv := float(wdata.get("muzzle_velocity", 950.0))
	var spread := float(wdata.get("spread_mrad", 5.0)) * 0.001
	var tracer_every := int(wdata.get("tracer_every", 2))
	var dmg := float(wdata.get("damage", 15.0))
	var life := max_range_m / mv * 1.1
	var is_flak: bool = bool(wdata.get("flak", false))
	var excl: Array = [hitbox.get_rid()] if hitbox != null else []

	for k in count:
		_round_count += 1
		var dir := forward_dir
		var side := global_transform.basis.x
		var up := global_transform.basis.y
		dir = (dir + side * _rng.randfn(0.0, spread * 0.5) + up * _rng.randfn(0.0, spread * 0.5)).normalized()
		var vel := velocity + dir * mv
		var is_tracer := _round_count % maxi(tracer_every, 1) == 0

		_pool.spawn(muzzle_pos, vel, life, dmg, is_tracer, self, excl)

		if is_flak:
			# Flak airburst near target distance
			var dist := muzzle_pos.distance_to(tgt_pos)
			var flight_time := dist / mv + randf_range(-0.15, 0.15)
			var burst_pos := muzzle_pos + dir * dist + Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
			get_tree().create_timer(flight_time).timeout.connect(func() -> void:
				if is_instance_valid(self):
					Events.explosion.emit(burst_pos, 0.5)
					Targeting.blast(get_tree(), burst_pos, 8.0, 30.0, self, team, 0.5)
			)

	Vfx.muzzle_flash(self, to_local(muzzle_pos), 1.2 if is_flak else 0.8)
	if _round_count % 3 == 0:
		Sfx.play_3d(str(wdata.get("sound", "gun_30mm")), muzzle_pos, -4.0)


func _is_target_valid(tgt: Node3D) -> bool:
	if tgt == null or not is_instance_valid(tgt):
		return false
	if "alive" in tgt and not tgt.alive:
		return false
	var dist := global_position.distance_to(tgt.global_position)
	if dist > max_range_m * 1.2:
		return false
	return _has_line_of_sight(tgt.global_position)


func _has_line_of_sight(target_pos: Vector3) -> bool:
	if not Ground.is_loaded():
		return true
	var origin := global_position + Vector3.UP * 2.5
	var hit := Ground.raycast(origin, target_pos, LOS_RAY_STEP)
	return hit.is_empty()
