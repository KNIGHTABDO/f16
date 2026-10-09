class_name SamSite
extends CombatUnit
## Surface-to-Air Missile site (SA-6, SA-2, SA-15, SA-18 MANPADS).
## Operates search & tracking radars, engages enemy aircraft within realistic envelopes,
## and exposes radar lock state to HUD via group "radars" and is_tracking(target).

enum State { IDLE, SEARCH, TRACK, LAUNCH }

const RADAR_SCAN_SPEED := 2.5  # radians per sec
const LOS_RAY_STEP := 100.0

var weapon_id: String = "sa6"
var wdata: Dictionary = {}
var min_range_m: float = 3000.0
var max_range_m: float = 25000.0
var min_alt_m: float = 30.0
var max_alt_m: float = 16000.0

var state: State = State.SEARCH
var current_target: Node3D = null

var lock_timer: float = 0.0
var lock_required_s: float = 3.0
var reload_timer: float = 0.0
var reload_interval_s: float = 12.0
var missiles_remaining: int = 6

var _dish_node: Node3D
var _turret_node: Node3D
var _arm_node: Node3D
var _weapons_dict: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("radars")
	_load_weapon_data()
	_find_model_nodes()


func setup_sam(p_kind: String, p_team: int, p_weapon_id: String = "") -> void:
	setup_unit(p_kind, p_team)
	if p_weapon_id != "":
		weapon_id = p_weapon_id
	else:
		match p_kind:
			"sam_sa6": weapon_id = "sa6"
			"sam_sa2": weapon_id = "sa2"
			"sam_sa15": weapon_id = "sa15"
			"manpads": weapon_id = "sa18"
			_: weapon_id = "sa6"
	_load_weapon_data()


func _load_weapon_data() -> void:
	if _weapons_dict.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/weapons.json")
		if txt != "":
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				_weapons_dict = parsed
	wdata = _weapons_dict.get(weapon_id, {})
	min_range_m = float(wdata.get("min_range", 3000.0))
	max_range_m = float(wdata.get("range", 25000.0))

	match weapon_id:
		"sa2":
			min_alt_m = 300.0
			max_alt_m = 25000.0
			lock_required_s = 4.5
			reload_interval_s = 18.0
			missiles_remaining = 3
		"sa6":
			min_alt_m = 50.0
			max_alt_m = 14000.0
			lock_required_s = 3.2
			reload_interval_s = 12.0
			missiles_remaining = 6
		"sa15":
			min_alt_m = 15.0
			max_alt_m = 9000.0
			lock_required_s = 1.8
			reload_interval_s = 6.0
			missiles_remaining = 8
		"sa18":
			min_alt_m = 10.0
			max_alt_m = 4000.0
			lock_required_s = 2.0
			reload_interval_s = 10.0
			missiles_remaining = 3


func _find_model_nodes() -> void:
	if visual == null:
		return
	_dish_node = visual.find_child("RadarDish", true, false) as Node3D
	_turret_node = visual.find_child("Turret", true, false) as Node3D
	_arm_node = visual.find_child("LauncherArm", true, false) as Node3D


func is_tracking(target: Node) -> bool:
	return alive and (state == State.TRACK or state == State.LAUNCH) and current_target == target


func unit_tick(dt: float) -> void:
	if not alive:
		return

	if reload_timer > 0.0:
		reload_timer -= dt

	# Rotate search radar dish if present
	if _dish_node != null and is_instance_valid(_dish_node):
		_dish_node.rotation.y += RADAR_SCAN_SPEED * dt

	match state:
		State.IDLE, State.SEARCH:
			is_engaging = false
			_search_targets()
		State.TRACK:
			is_engaging = true
			_track_target(dt)
		State.LAUNCH:
			is_engaging = true
			_attempt_launch()


func _get_difficulty_multiplier() -> float:
	var diff := GameState.difficulty
	match diff:
		"easy": return 1.6
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
		var cand_team := int(candidate.get("team"))
		if cand_team == team:
			continue
		if "alive" in candidate and not candidate.alive:
			continue
		var kind: String = candidate.call("get_target_kind") if candidate.has_method("get_target_kind") else ""
		if kind != "air" and kind != "helicopter":
			continue

		var dist := global_position.distance_to(candidate.global_position)
		if dist < min_range_m or dist > max_range_m:
			continue

		var alt := candidate.global_position.y
		if alt < min_alt_m or alt > max_alt_m:
			continue

		# Check line of sight
		if not _has_line_of_sight(candidate.global_position):
			continue

		if dist < best_dist:
			best_dist = dist
			best_target = candidate

	if best_target != null:
		current_target = best_target
		state = State.TRACK
		lock_timer = lock_required_s * _get_difficulty_multiplier()


func _track_target(dt: float) -> void:
	if not _is_target_valid(current_target):
		_abort_track()
		return

	_aim_launcher_at(current_target.global_position, dt)

	lock_timer -= dt
	if lock_timer <= 0.0:
		state = State.LAUNCH


func _attempt_launch() -> void:
	if not _is_target_valid(current_target):
		_abort_track()
		return

	if reload_timer <= 0.0 and missiles_remaining > 0:
		_fire_missile()
		missiles_remaining -= 1
		reload_timer = reload_interval_s * _get_difficulty_multiplier()
		state = State.TRACK
		lock_timer = 2.0 * _get_difficulty_multiplier()
	else:
		state = State.TRACK


func _fire_missile() -> void:
	var world: Node = null
	if get_tree().current_scene != null:
		world = get_tree().current_scene.find_child("World", true, false)
	if world == null:
		world = get_parent()

	var launch_pos := global_position + Vector3.UP * (size.y * 0.8)
	var to_tgt := (current_target.global_position - launch_pos).normalized()
	# Upward angle for ground-to-air launch
	var fwd := (to_tgt + Vector3.UP * 0.35).normalized()
	var up := Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT
	var xform := Transform3D(Basis.looking_at(fwd, up), launch_pos)
	var init_vel := fwd * 40.0

	Missile.launch(world, self, weapon_id, wdata, current_target, xform, init_vel)
	Events.explosion.emit(launch_pos, 0.4)


func _aim_launcher_at(target_pos: Vector3, dt: float) -> void:
	var to_tgt := target_pos - global_position
	if _turret_node != null and is_instance_valid(_turret_node):
		var target_yaw := atan2(to_tgt.x, -to_tgt.z)
		_turret_node.rotation.y = rotate_toward(_turret_node.rotation.y, target_yaw, 2.0 * dt)
	if _arm_node != null and is_instance_valid(_arm_node):
		var horiz_dist := Vector2(to_tgt.x, to_tgt.z).length()
		var target_pitch := -clampf(atan2(to_tgt.y, horiz_dist), deg_to_rad(10.0), deg_to_rad(75.0))
		_arm_node.rotation.x = rotate_toward(_arm_node.rotation.x, target_pitch, 2.0 * dt)


func _abort_track() -> void:
	current_target = null
	state = State.SEARCH
	is_engaging = false


func _is_target_valid(tgt: Node3D) -> bool:
	if tgt == null or not is_instance_valid(tgt):
		return false
	if "alive" in tgt and not tgt.alive:
		return false
	var dist := global_position.distance_to(tgt.global_position)
	if dist > max_range_m * 1.15 or dist < min_range_m * 0.7:
		return false
	return _has_line_of_sight(tgt.global_position)


func _has_line_of_sight(target_pos: Vector3) -> bool:
	if not Ground.is_loaded():
		return true
	var origin := global_position + Vector3.UP * 3.0
	var hit := Ground.raycast(origin, target_pos, LOS_RAY_STEP)
	return hit.is_empty()
