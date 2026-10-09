extends Node
## Headless smoke pass over every mode. Run it with:
##   godot --headless --path game --fixed-fps 30 res://tools/smoke_modes.tscn
## Add `-- --only=<mode_id>` at the end to fly just one mode, or `-- --only=<probe>` to run one UI probe (see PROBES).
## Each run starts a sortie the way the mode and map screens do (GameState.begin_mission with the mode's default options
## and the normal difficulty), flies it for RUN_S of game time with the player in straight flight, fires one shot of every
## weapon type the player carries in modes with enemies, then goes back to the menu the way the results screen does.
## Engine errors (SCRIPT ERROR, ERROR, push_error) are counted per run by a Logger. One line is printed per run.
## Every AI aircraft that dies is printed with its cause (a killer's name, or a crash) and its pilot state at the end.
## `-- --run-s=<seconds>` changes the run length. `-- --no-fire` stops the player firing and keeps the player at full health,
## so `--run-s=60 --no-fire` checks that enemies survive a minute with nobody shooting them.
## The UI probes run after the modes. Each presses a real button the way the player does, then checks the scene that
## comes up with no errors: RETRY and NEXT on the results screen, RESTART SORTIE and QUIT TO MENU on the pause menu, and
## the hangar (pick another aircraft, SELECT FOR FLIGHT, back, FREE FLIGHT, which must fly that aircraft).

const MENU_SCENE := "res://ui/menu/menu_root.tscn"
const LEVEL_SCENE := "res://scenes/level.tscn"
const SMOKE_MAP := "gibraltar"
const SECOND_MAP := "atlas"
const SECOND_MAP_MODE := "free_flight"
const RUN_S := 15.0  ## game seconds per run, unless --run-s is given
const PLAYER_HEALTH_NO_FIRE := 1.0e9  ## player health under --no-fire, far above any hit
const TIME_SCALE := 2.0  ## game seconds per real second, with --fixed-fps 30
const FIRE_START_S := 2.0  ## game second of the first forced shot
const FIRE_GAP_S := 1.2  ## game seconds between forced shots
const GUN_BURST_S := 0.4  ## s the gun trigger is held for one burst
const GUN_ACTION := "fc_gun"
const PAUSE_ACTION := "ui_cancel"  ## the Escape key's action, which opens the pause menu
const LOAD_TIMEOUT_MS := 120000  ## real time allowed for a level to come up
const DIFFICULTY := "normal"
const NO_ENEMY_MODES := ["free_flight", "time_trial", "carrier_landing"]
const MAX_LINES_SHOWN := 3  ## distinct errors printed per run
const LINE_CHARS := 180
const SETTLE_MS := 600  ## real ms a probe step waits before it looks at the screen, so scene changes and tweens finish
const PROBE_TIMEOUT_MS := 120000  ## real ms a probe step may wait for its screen
const PROBE_AT_S := 3.0  ## game s a probe run flies before its UI action
const PROBE_TAIL_S := 2.0  ## game s a probe run keeps flying after its action has been checked
const PROBE_ARCADE_MODE := "dogfight"  ## won and not practice, so the results screen offers NEXT
const PROBE_PRACTICE_MODE := "free_flight"
## Probes that act during the flight. The hangar probe starts from the menu instead, see _start_hangar_probe.
const RUNNING_PROBES := ["retry", "next", "pause_restart", "pause_quit"]
const HANGAR_PROBE := "hangar"
const PROBES := [
	{"probe": "retry", "mode": PROBE_ARCADE_MODE},
	{"probe": "next", "mode": PROBE_ARCADE_MODE},
	{"probe": "pause_restart", "mode": PROBE_PRACTICE_MODE},
	{"probe": "pause_quit", "mode": PROBE_PRACTICE_MODE},
	{"probe": HANGAR_PROBE, "mode": PROBE_PRACTICE_MODE},
]

enum Phase { LOADING, RUNNING, PROBE, LEAVING }

var _is_driver := false
var _pending: Array[Dictionary] = []  ## {mode, map, probe} still to fly
var _run: Dictionary = {}  ## the run in progress
var _phase := Phase.LOADING
var _elapsed := 0.0  ## game s into the run
var _flight_s := RUN_S  ## game s this run flies before it leaves
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
var _probe_begun := false  ## the probe's UI action has started (it acts once)
var _probe_step := ""  ## the probe's current step, see _drive_probe
var _step_started_ms := 0  ## real ms when the current step or the leaving began
var _settle_until_ms := 0  ## real ms before which a probe step does not look at the screen


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
			if _no_fire:
				_keep_player_up()
			if _probe_is_due():
				_begin_probe()
			elif _elapsed >= _flight_s or _mission_over() or GameState.level == null:
				_leave()
		Phase.PROBE:
			_drive_probe()
		Phase.LEAVING:
			if _menu_is_up():
				_end_run()
			elif Time.get_ticks_msec() - _step_started_ms > LOAD_TIMEOUT_MS:
				_run["errors"].append("menu did not come up")
				_end_run()


## With --no-fire the enemy AI can still shoot, but the player cannot die, so a long run is not cut short by lives. The
## health is topped up every frame, and it is high enough that one missile hit cannot take it down in a single step.
func _keep_player_up() -> void:
	var p := GameState.player as Aircraft
	if p != null and p.alive:
		p.max_health = PLAYER_HEALTH_NO_FIRE
		p.health = PLAYER_HEALTH_NO_FIRE


## One run per mode on the smoke map, plus free flight on the second map, plus the UI probes.
## `-- --only=<mode or probe>` keeps just that one.
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
			out.append({"mode": String(mode_id), "map": SMOKE_MAP, "probe": ""})
	if only == "" or only == SECOND_MAP_MODE:
		out.append({"mode": SECOND_MAP_MODE, "map": SECOND_MAP, "probe": ""})
	for probe in PROBES:
		if only == "" or only == String(probe["probe"]):
			out.append({"mode": String(probe["mode"]), "map": SMOKE_MAP, "probe": String(probe["probe"])})
	return out


func _next_run() -> void:
	if _pending.is_empty():
		_finish()
		return
	_run = _pending.pop_front()
	_run["errors"] = []
	_run["probe_done"] = false
	_run["fired"] = {}
	_elapsed = 0.0
	_flight_s = _run_s
	_fire_index = 0
	_gun_until = -1.0
	_fire_queue.clear()
	_probe_begun = false
	_probe_step = ""
	_started_ms = Time.get_ticks_msec()
	_log.take()
	if String(_run["probe"]) == HANGAR_PROBE:
		_start_hangar_probe()
		return
	_phase = Phase.LOADING
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
	if not NO_ENEMY_MODES.has(mode_id) and not _no_fire and String(_run["probe"]) == "":
		_fire_queue = _weapon_types()
	if String(_run["probe"]) == HANGAR_PROBE:
		# The launch is the probe's last step: the level must fly the aircraft that the hangar selected.
		_run["probe_done"] = true
		_flight_s = PROBE_TAIL_S
		if p == null or p.aircraft_id != String(_run["aircraft"]):
			_run["errors"].append("hangar: flew %s, not the picked %s" % [
				"nothing" if p == null else p.aircraft_id, String(_run["aircraft"])])


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
	_run["time_s"] = _elapsed
	var mission = GameState.level.get("_mission") if GameState.level != null else null
	if mission != null:
		_run["stats"] = "enemies %d, shots %d, hits %d, air kills %d, ground kills %d, score %d, fired %s" % [
			int(_run.get("enemies", 0)), mission.shots, mission.hits, mission.air_kills, mission.ground_kills,
			int(mission.score), str(_run["fired"])]
		if mission.over:
			_run["stats"] += ", ended early: %s" % mission.reason
	if String(_run["probe"]) != "" and not bool(_run["probe_done"]):
		_run["errors"].append("probe stopped at step '%s'" % _probe_step)
	_await_menu()
	GameState.goto_menu()


## The run is over and the menu is on its way. _process ends the run once the menu is up.
func _await_menu() -> void:
	if Events.aircraft_destroyed.is_connected(_on_aircraft_destroyed):
		Events.aircraft_destroyed.disconnect(_on_aircraft_destroyed)
	_phase = Phase.LEAVING
	_step_started_ms = Time.get_ticks_msec()


func _menu_is_up() -> bool:
	var scene := get_tree().current_scene
	return GameState.level == null and scene != null and scene.scene_file_path == MENU_SCENE


## Starts a probe's UI action. RETRY and NEXT need a finished sortie, so the mission ends here; the pause menu comes
## from the Escape key. The action itself runs in _drive_probe.
func _begin_probe() -> void:
	_probe_begun = true
	_phase = Phase.PROBE
	var level = GameState.level
	_run["seed"] = GameState.mission_seed
	_run["level_id"] = level.get_instance_id()
	if String(_run["probe"]) == "retry" or String(_run["probe"]) == "next":
		(level.get("_mission") as Mission).finish(true, "Smoke check")
		_next_step("results")
	else:
		_send_action(PAUSE_ACTION, true)
		_next_step("pause")


## True once a probe's flight time is up and its action has not started yet.
func _probe_is_due() -> bool:
	return not _probe_begun and RUNNING_PROBES.has(String(_run["probe"])) and _elapsed >= PROBE_AT_S


## Runs the probe's current step. A step waits SETTLE_MS of real time after it starts, then looks at the screen it expects.
## A step that does not show up within PROBE_TIMEOUT_MS fails the probe.
func _drive_probe() -> void:
	var now := Time.get_ticks_msec()
	if now < _settle_until_ms:
		return
	if now - _step_started_ms > PROBE_TIMEOUT_MS:
		_probe_fail("gave up at step '%s'" % _probe_step)
		return
	match _probe_step:
		"results":
			_probe_press_results()
		"pause":
			_probe_press_pause()
		"reload":
			_probe_check_reload()
		"menu", "hangar", "select", "back", "launch":
			_probe_hangar_step()


func _next_step(step_name: String) -> void:
	_probe_step = step_name
	_step_started_ms = Time.get_ticks_msec()
	_settle_until_ms = _step_started_ms + SETTLE_MS


## Ends the probe with an error. The run then goes back to the menu like any other run.
func _probe_fail(text: String) -> void:
	_run["errors"].append("%s: %s" % [String(_run["probe"]), text])
	_run["probe_done"] = true
	_leave()


## RETRY or NEXT on the results screen. Both load a new level, which the reload step checks.
func _probe_press_results() -> void:
	var button := "RETRY" if String(_run["probe"]) == "retry" else "NEXT"
	var screen := _find_script(GameState.level, ResultsScreen)
	if screen == null:
		return
	var btn := _find_text_button(screen, button)
	if btn == null:
		_probe_fail("%s is missing from the results screen" % button)
		return
	_press(btn)
	_next_step("reload")


## RESTART SORTIE or QUIT TO MENU on the pause menu that Escape opened.
func _probe_press_pause() -> void:
	var pause := _find_script(GameState.level, PauseMenu)
	if pause == null or not get_tree().paused:
		return
	_send_action(PAUSE_ACTION, false)  # release the Escape key that opened the menu, so no action is left held
	var restart := String(_run["probe"]) == "pause_restart"
	var label := "RESTART SORTIE" if restart else "QUIT TO MENU"
	var btn := _find_text_button(pause, label)
	if btn == null:
		_probe_fail("the pause menu has no %s button" % label)
		return
	_press(btn)
	if restart:
		_next_step("reload")
	else:
		# QUIT TO MENU has already asked for the menu, and the level goes with it.
		_run["probe_done"] = true
		_run["time_s"] = _elapsed
		_await_menu()


## Checks the level that RETRY, NEXT or RESTART loaded. RETRY and RESTART replay the same sortie seed, NEXT rolls a new one.
## Then the level flies a short tail before the run goes back to the menu.
func _probe_check_reload() -> void:
	if not _new_level_ready():
		return
	var probe := String(_run["probe"])
	var replays := probe == "retry" or probe == "pause_restart"
	if (GameState.mission_seed == int(_run["seed"])) != replays:
		_run["errors"].append("%s %s the sortie seed" % [probe, "did not keep" if replays else "did not change"])
	if get_tree().paused:
		_run["errors"].append("%s left the tree paused" % probe)
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != LEVEL_SCENE:
		_run["errors"].append("%s loaded %s, not the level" % [
			probe, "nothing" if scene == null else scene.scene_file_path])
	_run["probe_done"] = true
	_flight_s = PROBE_TAIL_S
	_elapsed = 0.0
	_phase = Phase.RUNNING


## True once a level other than the one the probe started in is up, with its mission and its player.
func _new_level_ready() -> bool:
	var level = GameState.level
	return level != null and is_instance_valid(level) and level.get_instance_id() != int(_run["level_id"]) \
			and level.get("_mission") != null and GameState.player != null


## The hangar probe starts from the menu rather than a sortie: the main menu's HANGAR, pick another aircraft, SELECT FOR
## FLIGHT, BACK, then FREE FLIGHT. The launched level is then checked by _start_run.
func _start_hangar_probe() -> void:
	_run["aircraft"] = _hangar_pick()
	_phase = Phase.PROBE
	_next_step("menu")
	# A scene change is deferred, so the menu still on screen would be the one the probe presses. Only change when needed.
	if not _menu_is_up():
		GameState.goto_menu()


## An unlocked aircraft in the same hangar tab as the current one, so its row is on screen. "" if there is none.
func _hangar_pick() -> String:
	var current := GameState.selected_aircraft
	var group := AircraftList.group_of(Progression.entry(current))
	for e: Dictionary in Progression.aircraft_roster():
		var id := str(e.get("id", ""))
		if id != current and Progression.is_unlocked(id) and AircraftList.group_of(e) == group:
			return id
	return ""


## The hangar probe's steps, all on the menu scene.
func _probe_hangar_step() -> void:
	var menu := get_tree().current_scene
	var id := String(_run["aircraft"])
	var hangar := _find_script(menu, HangarScreen)
	match _probe_step:
		"menu":
			if _menu_is_up():
				_press(_find_button(menu, "_on_hangar_pressed"))
				_next_step("hangar")
		"hangar":
			if id == "":
				_probe_fail("no other unlocked aircraft in the current hangar tab")
			elif hangar != null:
				_press(_find_button(hangar.get("_list") as Node, "_on_row_pressed", id))
				_next_step("select")
		"select":
			if hangar != null:
				_press(hangar.get("_action_btn") as Button)
				_next_step("back")
		"back":
			if Progression.selected_aircraft() != id:
				_probe_fail("the hangar did not select %s (selected %s)" % [id, Progression.selected_aircraft()])
			elif not bool(menu.get("_is_transitioning")):
				_press(_find_button(menu, "_on_back_pressed"))
				_next_step("launch")
		"launch":
			var flight := _find_button(menu, "_on_free_flight_pressed")
			if hangar == null and flight != null:
				GameState.selected_map = SMOKE_MAP
				_phase = Phase.LOADING
				_started_ms = Time.get_ticks_msec()
				_press(flight)


func _end_run() -> void:
	var errors: Array[String] = _log.take()
	for line in errors:
		_run["errors"].append(line)
	var mode_id := String(_run["mode"])
	var label := "%s / %s" % [mode_id, String(_run["map"])]
	if String(_run["probe"]) != "":
		label += " [%s]" % String(_run["probe"])
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


## Presses the button the same way a click does: its pressed signal runs the connected handler.
func _press(btn: Button) -> void:
	if btn != null:
		btn.pressed.emit()


func _send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


## The button whose pressed signal calls `method`, with `bound` as its first bound argument if one is given.
func _find_button(root: Node, method: String, bound := "") -> Button:
	if root == null:
		return null
	for node in root.find_children("*", "", true, false):
		if not node is Button:
			continue
		for c in (node as Button).pressed.get_connections():
			var cb: Callable = c["callable"]
			if cb.get_method() != method:
				continue
			if bound == "" or (cb.get_bound_arguments_count() > 0 and String(cb.get_bound_arguments()[0]) == bound):
				return node as Button
	return null


func _find_text_button(root: Node, text: String) -> Button:
	if root == null:
		return null
	for node in root.find_children("*", "", true, false):
		if node is Button and (node as Button).text == text:
			return node as Button
	return null


func _find_script(root: Node, script: Script) -> Node:
	if root == null:
		return null
	for node in root.find_children("*", "", true, false):
		if node.get_script() == script:
			return node
	return null


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
