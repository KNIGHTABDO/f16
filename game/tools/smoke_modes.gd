extends Node
## Headless smoke pass over every mode. Run it with:
##   godot --headless --path game --fixed-fps 30 res://tools/smoke_modes.tscn
## Add `-- --only=<mode_id>` at the end to fly just one mode.
## Each run starts a sortie the way the mode and map screens do (GameState.begin_mission with the mode's default options
## and the normal difficulty), flies it for RUN_S of game time with the player in straight flight, fires one shot of every
## weapon type the player carries in modes with enemies, then goes back to the menu the way the results screen does.
## Engine errors (SCRIPT ERROR, ERROR, push_error) are counted per run by a Logger. One line is printed per run.
## Every AI aircraft that dies is printed with its cause (a killer's name, or a crash) and its pilot state at the end.
## `-- --run-s=<seconds>` changes the run length, and `-- --no-fire` keeps the player from firing: e.g. `--run-s=60 --no-fire`
## checks that enemies survive a minute with nobody shooting them.

const MENU_SCENE := "res://ui/menu/menu_root.tscn"
const SMOKE_MAP := "gibraltar"
const SECOND_MAP := "atlas"
const SECOND_MAP_MODE := "free_flight"
const RUN_S := 15.0  ## game seconds per run, unless --run-s is given
const TIME_SCALE := 2.0  ## game seconds per real second, with --fixed-fps 30
const FIRE_START_S := 2.0  ## game second of the first forced shot
const FIRE_GAP_S := 1.2  ## game seconds between forced shots
const GUN_BURST_S := 0.4  ## s the gun trigger is held for one burst
const GUN_ACTION := "fc_gun"
const LOAD_TIMEOUT_MS := 120000  ## real time allowed for a level to come up
const DIFFICULTY := "normal"
const NO_ENEMY_MODES := ["free_flight", "time_trial", "carrier_landing"]
const MAX_LINES_SHOWN := 3  ## distinct errors printed per run
const LINE_CHARS := 180

enum Phase { LOADING, RUNNING, LEAVING }

var _is_driver := false
var _pending: Array[Dictionary] = []  ## {mode, map} still to fly
var _run: Dictionary = {}  ## the run in progress
var _phase := Phase.LOADING
var _elapsed := 0.0  ## game s into the run
var _started_ms := 0
var _fire_queue: Array[String] = []
var _fire_index := 0
var _gun_until := -1.0
var _log: ErrorLog
var _failures := 0
var _save_backup := ""
var _had_save := false
var _run_s := RUN_S
var _no_fire := false


## Logs every engine error and script error while the smoke pass runs.
class ErrorLog extends Logger:
	var lines: Array[String] = []
	var _mutex := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := rationale if rationale != "" else code
		_add("%s:%d %s" % [file.get_file(), line, text])

	func _log_message(message: String, error: bool) -> void:
		if error and message.strip_edges() != "":
			_add(message.strip_edges())

	func _add(text: String) -> void:
		_mutex.lock()
		lines.append(text)
		_mutex.unlock()

	func take() -> Array[String]:
		_mutex.lock()
		var out := lines.duplicate()
		lines.clear()
		_mutex.unlock()
		return out


func _ready() -> void:
	if not _is_driver:
		# Every level change replaces the scene root, so the driver is added under the root and survives them.
		var driver: Node = get_script().new()
		driver.set("_is_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS  ## keeps running while a results screen pauses the tree
	Engine.time_scale = TIME_SCALE
	_log = ErrorLog.new()
	OS.add_logger(_log)
	_backup_save()
	_pending = _plan_runs()
	print("smoke_modes: %d runs" % _pending.size())
	_next_run()


func _exit_tree() -> void:
	if _is_driver:
		OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _is_driver:
		return
	match _phase:
		Phase.LOADING:
			_check_loading()
		Phase.RUNNING:
			_elapsed += delta
			_drive()
			if _elapsed >= _run_s or _mission_over() or GameState.level == null:
				_leave()
		Phase.LEAVING:
			if _menu_is_up():
				_end_run()


## One run per mode on the smoke map, plus free flight on the second map. `-- --only=<mode>` keeps just that mode.
func _plan_runs() -> Array[Dictionary]:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=")
		elif arg.begins_with("--run-s="):
			_run_s = float(arg.trim_prefix("--run-s="))
		elif arg == "--no-fire":
			_no_fire = true
	var out: Array[Dictionary] = []
	var data := MissionGenerator.data()
	for mode_id in data["mode_order"]:
		if only == "" or String(mode_id) == only:
			out.append({"mode": String(mode_id), "map": SMOKE_MAP})
	if only == "" or only == SECOND_MAP_MODE:
		out.append({"mode": SECOND_MAP_MODE, "map": SECOND_MAP})
	return out


func _next_run() -> void:
	if _pending.is_empty():
		_finish()
		return
	_run = _pending.pop_front()
	_run["errors"] = []
	_elapsed = 0.0
	_fire_index = 0
	_gun_until = -1.0
	_fire_queue.clear()
	_phase = Phase.LOADING
	_started_ms = Time.get_ticks_msec()
	_log.take()
	var mode_id := String(_run["mode"])
	var mode: Dictionary = MissionGenerator.data()["modes"][mode_id]
	var options := {}
	for def in mode["options"]:
		options[String(def["id"])] = String(def["default"])
	GameState.begin_mission(mode_id, String(_run["map"]), options, DIFFICULTY)


func _check_loading() -> void:
	var level = GameState.level
	if level != null and is_instance_valid(level) and level.get("_mission") != null and GameState.player != null:
		_start_run()
		return
	var timed_out := Time.get_ticks_msec() - _started_ms > LOAD_TIMEOUT_MS
	var failed := level == null and get_tree().get_nodes_in_group(LoadingScreen.GROUP).is_empty() \
			and Time.get_ticks_msec() - _started_ms > 2000
	if timed_out or failed:
		_run["errors"].append("level did not start%s" % (" (timeout)" if timed_out else ""))
		_leave()


func _start_run() -> void:
	_phase = Phase.RUNNING
	_elapsed = 0.0
	_run["enemies"] = get_tree().get_nodes_in_group("team_1").size()
	_run["fired"] = {}
	var p := GameState.player as Aircraft
	var w := p.weapons as WeaponSystem if p != null else null
	if w != null:
		w.fired.connect(_on_fired)
		if w.gun != null:
			w.gun.fired.connect(_on_fired.bind("gun"))
	Events.aircraft_destroyed.connect(_on_aircraft_destroyed)
	var mode_id := String(_run["mode"])
	if not NO_ENEMY_MODES.has(mode_id) and not _no_fire:
		_fire_queue = _weapon_types()


## One entry per weapon type the player carries, in loadout order. The gun is always first.
func _weapon_types() -> Array[String]:
	var out: Array[String] = ["gun"]
	var p := GameState.player as Aircraft
	if p == null or p.weapons == null:
		return out
	var w := p.weapons as WeaponSystem
	for item in w.get_weapon_list():
		var type := String(item["type"])
		if type != "" and not out.has(type):
			out.append(type)
	return out


func _drive() -> void:
	if _gun_until >= 0.0 and _elapsed >= _gun_until:
		_gun_until = -1.0
		Input.action_release(GUN_ACTION)
	if _fire_index < _fire_queue.size() and _elapsed >= FIRE_START_S + _fire_index * FIRE_GAP_S:
		_fire(_fire_queue[_fire_index])
		_fire_index += 1


## Fires one shot of the weapon type: the gun for a short burst, otherwise the trigger on the selected weapon.
func _fire(weapon_type: String) -> void:
	var p := GameState.player as Aircraft
	if p == null or not is_instance_valid(p) or not p.alive:
		return
	if weapon_type == "gun":
		Input.action_press(GUN_ACTION)  # the same action the keyboard and pad gun buttons press
		_gun_until = _elapsed + GUN_BURST_S
		return
	var w := p.weapons as WeaponSystem
	if w == null:
		return
	for _i in w.get_weapon_list().size():
		if String(w.get_selected()["type"]) == weapon_type:
			break
		w.select_next()
	if String(w.get_selected()["type"]) == weapon_type:
		_player_controller().press_weapon()


func _on_fired(weapon_id: String) -> void:
	var fired: Dictionary = _run["fired"]
	fired[weapon_id] = int(fired.get(weapon_id, 0)) + 1


## Prints each aircraft death: who or what killed it, and how it was flying (its pilot's state, speed, pitch, altitude).
## A crash has no killer. The speed and attitude are the last synced values, so they are the ones just before a crash.
## The killer is described by team and whether it is a player aircraft that is still alive, so a shot from a player
## aircraft that has since been replaced by a respawn shows up as such.
func _on_aircraft_destroyed(aircraft: Node3D, killer: Node) -> void:
	var a := aircraft as Aircraft
	if a == null:
		return
	if a.is_player:
		print("    player aircraft %s down at %5.1f s (%s)" % [a.name, _elapsed, _cause_text(killer)])
		return
	var pilot_state := "none"
	for child in a.get_children():
		if child is AIPilot:
			pilot_state = (child as AIPilot).get_state()
	print("    AI death at %5.1f s: %s (team %d), %s; pilot %s, %.0f km/h, pitch %.0f deg, altitude %.0f m" % [
		_elapsed, a.name, a.team, _cause_text(killer), pilot_state, a.get_speed_kmh(), a.get_pitch_deg(), a.position.y])


func _cause_text(killer: Node) -> String:
	if killer == null:
		return "crashed into terrain or sea"
	var flags := "player" if killer.get("is_player") == true else "AI"
	flags += ", alive" if killer.get("alive") != false else ", dead"
	return "shot down by %s (team %s, %s)" % [killer.name, str(killer.get("team")), flags]


func _player_controller() -> PlayerController:
	return GameState.level.controller as PlayerController


func _mission_over() -> bool:
	var level = GameState.level
	if level == null or not is_instance_valid(level):
		return false
	var mission = level.get("_mission")
	return mission != null and bool(mission.over)


## Goes back to the menu, the same call the results and pause screens make.
func _leave() -> void:
	if _phase == Phase.LEAVING:
		return
	_phase = Phase.LEAVING
	_run["time_s"] = _elapsed
	if Events.aircraft_destroyed.is_connected(_on_aircraft_destroyed):
		Events.aircraft_destroyed.disconnect(_on_aircraft_destroyed)
	var mission = GameState.level.get("_mission") if GameState.level != null else null
	if mission != null:
		_run["stats"] = "enemies %d, shots %d, hits %d, air kills %d, ground kills %d, score %d, fired %s" % [
			int(_run.get("enemies", 0)), mission.shots, mission.hits, mission.air_kills, mission.ground_kills,
			int(mission.score), str(_run["fired"])]
		if mission.over:
			_run["stats"] += ", ended early: %s" % mission.reason
	GameState.goto_menu()


func _menu_is_up() -> bool:
	var scene := get_tree().current_scene
	return GameState.level == null and scene != null and scene.scene_file_path == MENU_SCENE


func _end_run() -> void:
	var errors: Array[String] = _log.take()
	for line in errors:
		_run["errors"].append(line)
	var mode_id := String(_run["mode"])
	var label := "%s / %s" % [mode_id, String(_run["map"])]
	var errs: Array = _run["errors"]
	var stats := String(_run.get("stats", ""))
	if errs.is_empty():
		print("%-34s OK  (%.1f s game time) %s" % [label, float(_run.get("time_s", 0.0)), stats])
	else:
		_failures += 1
		print("%-34s ERRORS %d" % [label, errs.size()])
		var shown := {}
		for line in errs:
			if shown.size() >= MAX_LINES_SHOWN:
				break
			var text := String(line).left(LINE_CHARS)
			if not shown.has(text):
				shown[text] = true
				print("    %s" % text)
	_next_run()


func _finish() -> void:
	_restore_save()
	print("smoke_modes: %s" % ("all runs OK" if _failures == 0 else "%d run(s) with errors" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## The smoke runs change the sortie record and progress. The player's save is put back afterwards.
func _backup_save() -> void:
	_had_save = FileAccess.file_exists(GameState.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(GameState.SAVE_PATH)


func _restore_save() -> void:
	if not _had_save:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
		return
	var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(_save_backup)

