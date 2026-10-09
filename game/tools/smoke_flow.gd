extends Node
## Headless check of the menu flow, through the same handlers the buttons and the Escape key call:
## main menu → MISSIONS → mission picker → map picker → START → loading → level → pause → resume → mission end →
## results → MENU → main menu. Run it with:
##   godot --headless --path game --fixed-fps 30 res://tools/smoke_flow.tscn
## One line per step. Engine and script errors raised during a step are listed under it. The first failed step stops the check.

const ModesRunner := preload("res://tools/smoke_modes.gd")
const MENU_SCENE := "res://ui/menu/menu_root.tscn"
const MENU_MODE := "dogfight"  ## the mission card pressed in the picker
const PAUSE_ACTION := "ui_cancel"  ## the Escape key's action
const SETTLE_S := 0.5  ## real s to let transitions and frees finish after each step
const STEP_TIMEOUT_MS := 120000
const MAX_LINES_SHOWN := 3
const LINE_CHARS := 180

var _is_driver := false
var _steps: Array = []  ## {name, act, done}; act runs once on entry, done is polled until it is true
var _step := 0
var _acted := false
var _hold := 0.0
var _step_started_ms := 0
var _log
var _failures := 0
var _save_backup := ""
var _had_save := false


func _ready() -> void:
	if not _is_driver:
		# Scene changes replace the scene root, so the driver is added under the root and survives them.
		var driver: Node = get_script().new()
		driver.set("_is_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS  ## keeps running while the pause menu and results pause the tree
	_log = ModesRunner.ErrorLog.new()
	OS.add_logger(_log)
	_backup_save()
	_build_steps()


func _exit_tree() -> void:
	if _is_driver:
		OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _is_driver:
		return
	if _hold > 0.0:
		_hold -= delta
		return
	if _step >= _steps.size():
		_finish()
		return
	var step: Dictionary = _steps[_step]
	if not _acted:
		_acted = true
		_step_started_ms = Time.get_ticks_msec()
		var act: Callable = step["act"]
		if act.is_valid():
			act.call()
		_hold = SETTLE_S
		return
	var done: Callable = step["done"]
	if done.call():
		_end_step(true, "")
	elif Time.get_ticks_msec() - _step_started_ms > STEP_TIMEOUT_MS:
		_end_step(false, "timed out")


func _build_steps() -> void:
	_steps = [
		_make_step("menu boots", func(): get_tree().change_scene_to_file(MENU_SCENE), _menu_up),
		_make_step("MISSIONS opens the mission picker",
				func(): _press(_find_button(get_tree().current_scene, "_on_missions_pressed")),
				func(): return _find_script(get_tree().current_scene, ModeSelectScreen) != null),
		_make_step("mission card opens the map picker",
				func(): _press(_find_button(_find_script(get_tree().current_scene, ModeSelectScreen), "_open_maps", MENU_MODE)),
				func(): return _find_script(get_tree().current_scene, MapSelectScreen) != null),
		_make_step("START loads the sortie into the level",
				func(): _press(_find_button(_find_script(get_tree().current_scene, MapSelectScreen), "_start")),
				_level_ready),
		_make_step("Escape opens the pause menu",
				func(): _send_action(PAUSE_ACTION, true),
				func(): return _pause_open() and get_tree().paused),
		_make_step("Escape released", func(): _send_action(PAUSE_ACTION, false), func(): return true),
		_make_step("RESUME closes the pause menu",
				func(): _press(_find_button(_find_script(GameState.level, PauseMenu), "_on_resume_pressed")),
				func(): return not _pause_open() and not get_tree().paused),
		_make_step("mission end opens the results",
				func(): GameState.level.get("_mission").victory("Flow check"),
				func(): return _find_script(GameState.level, ResultsScreen) != null),
		_make_step("MENU returns to the main menu",
				func(): _press(_find_text_button(_find_script(GameState.level, ResultsScreen), "MENU")),
				_menu_up),
	]


func _make_step(step_name: String, act: Callable, done: Callable) -> Dictionary:
	return {"name": step_name, "act": act, "done": done}


## Ends the current step and prints its line. A failed step ends the check.
func _end_step(ok: bool, note: String) -> void:
	var step_name := String(_steps[_step]["name"])
	var errors: Array[String] = _log.take()
	var status := "OK"
	if not ok:
		status = "FAIL (%s)" % note
	elif not errors.is_empty():
		status = "ERRORS %d" % errors.size()
	print("%-40s %s" % [step_name, status])
	if not ok or not errors.is_empty():
		_failures += 1
		var shown := {}
		for line in errors:
			if shown.size() >= MAX_LINES_SHOWN:
				break
			var text := String(line).left(LINE_CHARS)
			if not shown.has(text):
				shown[text] = true
				print("    %s" % text)
	_acted = false
	_hold = SETTLE_S
	_step += 1
	if not ok:
		_finish()


func _finish() -> void:
	_restore_save()
	print("smoke_flow: %s" % ("all steps OK" if _failures == 0 else "failed at %d step(s)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _menu_up() -> bool:
	var scene := get_tree().current_scene
	return GameState.level == null and scene != null and scene.scene_file_path == MENU_SCENE \
			and _find_button(scene, "_on_missions_pressed") != null


func _level_ready() -> bool:
	var level = GameState.level
	return level != null and is_instance_valid(level) and level.get("_mission") != null \
			and GameState.player != null and get_tree().get_nodes_in_group(LoadingScreen.GROUP).is_empty()


func _pause_open() -> bool:
	return _find_script(GameState.level, PauseMenu) != null


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
