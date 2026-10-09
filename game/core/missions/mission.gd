class_name Mission
extends Node
## One mission run inside a Level: the rules, objectives, kill and hit counts, score, lives, time limit and the result.
## The level builds the plan with MissionGenerator, spawns it with MissionSpawner, then calls setup() and begin(). Mode
## scripts in core/missions/modes/ extend this class and override the hooks (_prepare, _on_begin, _tick, _on_target_down,
## _on_time_up). finished(result) fires once, when the mission is won or lost.

signal finished(result: Dictionary)

const RTB_GRACE_S := 240.0  ## s after the objectives are met to land at a base for the bonus
const RTB_RADIUS_M := 1800.0  ## a touchdown counts within this distance of a base point
const RTB_MAX_KMH := 150.0  ## speed under which a touchdown counts as a landing
const RTB_BONUS := 1500.0  ## score bonus for landing at base, before the difficulty multiplier
const GROUND_PTS := 150.0  ## points for a ground kill the mode did not track
const MODE_DIR := "res://core/missions/modes/"
const FALLBACK_MODE := "free_flight"

var plan: Dictionary = {}  ## the MissionGenerator plan
var nodes: Dictionary = {}  ## spawned nodes: units, convoys, ships, aircraft (from MissionSpawner.spawn_all)
var tuning: Dictionary = {}  ## the mode's tuning values from the plan
var objectives := Objectives.new()
var over := false  ## true once finish() has run
var won := false
var reason := ""
var lives := -1  ## aircraft the player has left, -1 for unlimited
var score_mult := 1.0
var time_limit := 0.0  ## s, 0 for none
var elapsed := 0.0  ## s since begin()
var air_kills := 0
var ground_kills := 0
var shots := 0  ## firing frames of the player's weapons
var hits := 0  ## firing frames that scored a hit on another aircraft or unit
var score := 0.0
var rtb_bonus := 0
var victory_pending := false  ## objectives met, waiting for the RTB landing or the grace timer

var _level  ## the Level node. Untyped: level.gd has no class_name, so its members are read as Variants
var _started := false
var _rtb_enabled := false
var _rtb_left := 0.0
var _victory_reason := ""
var _bases: Array = []  ## friendly runway midpoints, world Vector3
var _points := {}  ## instance id -> points for a tracked target
var _down := {}  ## instance id -> true once the target has been destroyed
var _signature := ""
var _last_shot_frame := -1
var _last_hit_frame := -1


## Loads the mode script for mode_id, falling back to free flight for an unknown mode. Mode scripts are loaded by path, so
## a missing one does not stop the rest of the game from loading.
static func create(mode_id: String) -> Mission:
	var path := MODE_DIR + mode_id + ".gd"
	if not ResourceLoader.exists(path):
		path = MODE_DIR + FALLBACK_MODE + ".gd"
	var script := load(path) as Script
	if script == null:
		return Mission.new()
	return script.new() as Mission


## Binds the mission to its level and spawned nodes, sets the rules from the plan and runs the mode's _prepare().
func setup(level: Node3D, mission_plan: Dictionary, spawned: Dictionary) -> void:
	_level = level
	plan = mission_plan
	nodes = spawned
	tuning = plan.get("tuning", {})
	lives = int(plan["lives"])
	score_mult = float(plan["score_mult"])
	time_limit = float(plan["time_limit"])
	_rtb_enabled = bool(plan["rtb_enabled"])
	_bases = plan["base_points"]
	Events.aircraft_destroyed.connect(_on_aircraft_destroyed)
	Events.target_destroyed.connect(_on_target_destroyed)
	Events.damaged.connect(_on_damaged)
	Events.weapon_fired.connect(_on_weapon_fired)
	_prepare()
	_flush_objectives()


func _exit_tree() -> void:
	if Events.aircraft_destroyed.is_connected(_on_aircraft_destroyed):
		Events.aircraft_destroyed.disconnect(_on_aircraft_destroyed)
	if Events.target_destroyed.is_connected(_on_target_destroyed):
		Events.target_destroyed.disconnect(_on_target_destroyed)
	if Events.damaged.is_connected(_on_damaged):
		Events.damaged.disconnect(_on_damaged)
	if Events.weapon_fired.is_connected(_on_weapon_fired):
		Events.weapon_fired.disconnect(_on_weapon_fired)


## Starts the clock. The level calls this once the world is built and the player is placed.
func begin() -> void:
	if _started or over:
		return
	_started = true
	_on_begin()
	_flush_objectives()


## Per-frame update from the level. Runs the clock, the time limit, the RTB flow, the mode's _tick and the objective payload.
func update(delta: float) -> void:
	if over or not _started:
		return
	elapsed += delta
	if time_limit > 0.0 and elapsed >= time_limit:
		_on_time_up()
		if over:
			return
	if victory_pending:
		_update_rtb(delta)
		if over:
			return
	_tick(delta)
	if not over and objectives.signature() != _signature:
		_flush_objectives()


## Called by a mode once its objectives are met. With RTB on, the player has RTB_GRACE_S to land at the nearest base for
## the bonus. Otherwise the mission is won now.
func victory(why := "Objectives complete") -> void:
	if over or victory_pending:
		return
	victory_pending = true
	_victory_reason = why
	if not _rtb_enabled or _bases.is_empty():
		finish(true, why)
		return
	_rtb_left = RTB_GRACE_S
	var p = _player()
	var here := WorldOrigin.to_world(p.position) if p != null else Vector3.ZERO
	objectives.add("rtb", "Land at a base for the bonus", _nearest_base(here), null, true)
	say("Objectives complete. Return to base and land for the bonus.", 6.0)


## Ends the mission once. finished(result) goes to the level's results screen; Events.mission_ended goes to the rest.
func finish(did_win: bool, why: String) -> void:
	if over:
		return
	over = true
	won = did_win
	reason = why
	var result := result_dict()
	finished.emit(result)
	Events.mission_ended.emit(won, result)


## Called by the level when the player's aircraft is destroyed. Returns true if the player may respawn. The last aircraft
## lost ends the mission.
func on_player_destroyed() -> bool:
	if over:
		return false
	if lives < 0:
		return true
	lives -= 1
	if lives <= 0:
		finish(false, "No aircraft left")
		return false
	return true


## Adds points, scaled by the difficulty's score multiplier.
func add_score(pts: float) -> void:
	score += pts * score_mult


func say(text: String, duration := 5.0) -> void:
	Events.mission_message.emit(text, duration)


## Registers a spawned node for scoring: its kill pays `points`, and its loss reaches _on_target_down.
func track(node: Node, points: float) -> void:
	if is_instance_valid(node):
		_points[node.get_instance_id()] = points


func track_all(list: Array, points: float) -> void:
	for node in list:
		track(node, points)


func is_down(node: Node) -> bool:
	return _down.has(node.get_instance_id())


## Spawned nodes tagged with `role` (MissionSpawner sets the meta), from every list in `nodes`.
func by_role(role: String) -> Array:
	var out: Array = []
	for key in nodes:
		for node in nodes[key]:
			if is_instance_valid(node) and node.get_meta("role", "") == role:
				out.append(node)
	return out


## How many of `list` are still standing: valid nodes whose alive flag is not false.
func count_alive(list: Array) -> int:
	var n := 0
	for node in list:
		if is_instance_valid(node) and node.get("alive") != false:
			n += 1
	return n


func result_dict() -> Dictionary:
	var accuracy := 0.0 if shots == 0 else minf(float(hits) / float(shots), 1.0)
	return {
		"mode": String(plan.get("mode", "")),
		"map": String(plan.get("map", "")),
		"title": String(plan.get("title", "")),
		"difficulty": String(plan.get("difficulty", "")),
		"won": won,
		"reason": reason,
		"time_s": elapsed,
		"air_kills": air_kills,
		"ground_kills": ground_kills,
		"shots": shots,
		"hits": hits,
		"accuracy": accuracy,
		"score": int(round(score)),
		"rtb_bonus": rtb_bonus,
		"practice": bool(plan.get("practice", false)),
		"seed": int(plan.get("seed", 0)),
		"options": (plan.get("options", {}) as Dictionary).duplicate(),
	}


## RTB flow: a touchdown at a base within RTB_RADIUS_M wins with the bonus. The grace timer ends it as a plain win.
func _update_rtb(delta: float) -> void:
	var p = _player()
	if p != null and p.is_on_ground() and p.get_speed_kmh() <= RTB_MAX_KMH and _at_base(WorldOrigin.to_world(p.position)):
		rtb_bonus = int(round(RTB_BONUS * score_mult))
		score += rtb_bonus
		finish(true, "Landed at base")
		return
	_rtb_left -= delta
	if _rtb_left <= 0.0:
		finish(true, _victory_reason)


func _flush_objectives() -> void:
	_signature = objectives.signature()
	Events.objective_updated.emit(objectives.to_array())


func _on_aircraft_destroyed(aircraft: Node3D, killer: Node) -> void:
	_handle_down(aircraft, killer, true)


func _on_target_destroyed(target: Node3D, killer: Node) -> void:
	if target is Aircraft:  # aircraft_destroyed reports those
		return
	_handle_down(target, killer, false)


## One destroyed target: counts a kill when the player fired the shot, then tells the mode. Each target counts once.
func _handle_down(node: Node, killer: Node, air: bool) -> void:
	if over or not is_instance_valid(node) or _is_player(node):
		return
	var id := node.get_instance_id()
	if _down.has(id):
		return
	_down[id] = true
	var by_player := _is_player(killer)
	if by_player:
		var pts := _points_for(node, float(tuning.get("air_kill", 500.0)) if air else GROUND_PTS)
		if air:
			air_kills += 1
		else:
			ground_kills += 1
		add_score(pts)
	_on_target_down(node, by_player)


func _on_damaged(victim: Node3D, _amount: float, source: Node) -> void:
	if over or not _is_player(source) or _is_player(victim):
		return
	var frame := Engine.get_physics_frames()
	if frame != _last_hit_frame:
		_last_hit_frame = frame
		hits += 1


## weapon_fired comes once per physics tick while the gun is firing, so shots count firing frames, not rounds.
func _on_weapon_fired(shooter: Node3D, _weapon_id: String) -> void:
	if over or not _is_player(shooter):
		return
	var frame := Engine.get_physics_frames()
	if frame != _last_shot_frame:
		_last_shot_frame = frame
		shots += 1


func _points_for(node: Node, fallback: float) -> float:
	return float(_points.get(node.get_instance_id(), fallback))


func _player() -> Aircraft:
	var p = _level.player if _level != null else null
	return p if is_instance_valid(p) and p.alive else null


## The flag, not the node: a respawn makes a new player Aircraft, and shots the old one fired must still count for the player.
func _is_player(node: Variant) -> bool:
	return is_instance_valid(node) and node is Aircraft and (node as Aircraft).is_player


func _nearest_base(from: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_d := INF
	for b in _bases:
		var d := _flat_dist(from, b)
		if d < best_d:
			best_d = d
			best = b
	return best


func _at_base(pos: Vector3) -> bool:
	for b in _bases:
		if _flat_dist(pos, b) <= RTB_RADIUS_M:
			return true
	return false


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Virtual hooks. Modes override what they need; the defaults do nothing.
## _prepare: build objectives and track nodes. Runs once in setup(), before the clock starts.
func _prepare() -> void:
	pass


## _on_begin: the first frame of play, after begin().
func _on_begin() -> void:
	pass


## _tick: per-frame rules for the mode.
func _tick(_delta: float) -> void:
	pass


## _on_target_down: a target has been destroyed, by anyone. by_player is true for the player's kills.
func _on_target_down(_node: Node, _by_player: bool) -> void:
	pass


## _on_time_up: the clock ran out. Default: a win if the objectives were met, otherwise a loss.
func _on_time_up() -> void:
	if victory_pending:
		finish(true, _victory_reason)
	else:
		finish(false, "Time is up")
