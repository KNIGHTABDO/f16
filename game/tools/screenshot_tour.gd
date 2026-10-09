extends Node
## Rendered screenshot tour for marketing and review. Run it in a real window, not headless:
##   godot --path game res://tools/screenshot_tour.tscn -- --out=/absolute/dir
## --out sets the folder for the PNGs: absolute, res://, user://, or relative to the shell's folder. The default is
## <repo>/screenshots/v1/. Each shot is saved as NN_description.png and its path is printed. The tour walks the menus
## (main, mode, map, hangar), then starts one sortie per flight shot, places the aircraft and camera by hand, keeps the
## player at full health so AI fire cannot end a shot, puts the player's save back and quits.
## Headless runs (DisplayServer "headless") walk the same path and count the shots, but save no PNG.
## --only=08,24 saves just those shots (by number or full name). Sorties with none of their shots wanted are skipped.

const MENU_SCENE := "res://ui/menu/menu_root.tscn"
const OUT_DEFAULT := "res://../screenshots/v1/"
const SHOT_TOTAL := 25
const SIZE := Vector2i(1920, 1080)
const QUALITY := "high"
const DIFFICULTY := "normal"
const SETTLE_S := 3.0  ## s of settled frames and shader warmup before each shot
const HEADLESS_WAIT_S := 0.05  ## headless draws nothing, so waits only let scene changes and spawns happen
const SAM_WAIT_S := 40.0  ## s to wait for a SAM to fire before the sead shot is taken anyway
const LOAD_TIMEOUT_MS := 120000  ## real time allowed for a menu or a level to come up
const MAP_GIBRALTAR := "gibraltar"
const MAP_ATLAS := "atlas"
const GOLDEN_HOUR := "17.8"  ## float hour that WorldSky reads as late afternoon light
const STRAIT := Vector3(-388.0, 0.0, -3200.0)  ## middle of the strait between Tangier and Ceuta, world m
const TOWN := Vector3(17684.0, 0.0, -37684.0)  ## Gibraltar town at the foot of the rock, world m
const ATLAS_PEAK := Vector3(-34200.0, 0.0, 21100.0)  ## approximate Toubkal, world m
const HANGAR_SHOTS := [["f16c", "04_hangar_f16c"], ["b2", "05_hangar_b2"], ["fa18c", "06_hangar_fa18c"]]

var _is_driver := false
var _headless := false
var _out_dir := ""
var _data: Dictionary = {}
var _shots_done := 0
var _save_backup := ""
var _had_save := false
var _only: Array[String] = []  ## shot ids from --only=, empty saves every shot


func _ready() -> void:
	if not _is_driver:
		# The tour changes scenes, so the driver is added under the root and survives them.
		var driver: Node = get_script().new()
		driver.set("_is_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS  ## keeps running while a results screen pauses the tree
	_headless = DisplayServer.get_name() == "headless"
	_out_dir = _resolve_out_dir()
	_only = _parse_only()
	_data = MissionGenerator.data()
	if _headless:
		print("screenshot_tour: headless, the flow runs but no PNG is saved")
	else:
		get_window().size = SIZE
		DirAccess.make_dir_recursive_absolute(_out_dir)
		print("screenshot_tour: saving to %s" % _out_dir)
	Settings.apply_graphics_preset(QUALITY)  ## in memory only, Settings.save() is never called here
	Settings.unlock_all_aircraft = true
	_backup_save()
	_tour()


func _process(_delta: float) -> void:
	if not _is_driver or not is_instance_valid(GameState.player):
		return
	var p := GameState.player as Aircraft
	if p != null and p.alive:
		p.health = p.max_health  ## AI fire cannot end a shot


func _tour() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
	await _wait_scene(MENU_SCENE)
	await _take("01_main_menu")
	var root = get_tree().current_scene
	root.push_screen(ModeSelectScreen.new(), false)
	await _take("02_mode_select")
	root.pop_screen(false)
	await get_tree().process_frame
	var picker := MapSelectScreen.new()
	picker.setup("free_flight")
	root.push_screen(picker, false)
	await _take("03_map_select")
	root.pop_screen(false)
	await get_tree().process_frame
	for pair in HANGAR_SHOTS:
		GameState.selected_aircraft = String(pair[0])
		root.push_screen(HangarScreen.new(), false)
		await _take(String(pair[1]))
		root.pop_screen(false)
		await get_tree().process_frame
	GameState.selected_aircraft = "f16c"
	await _flight_shots()
	_finish()


## One sortie per group of flight shots. Each group sets its own time of day and weather before its level is built.
func _flight_shots() -> void:
	if await _begin("free_flight", MAP_GIBRALTAR, GOLDEN_HOUR, "clear", "07_loading_screen", ["07", "08", "09", "10", "11"]):
		_place(Vector3(STRAIT.x - 2200.0, 900.0, STRAIT.z), 90.0, 500.0)
		await _take("08_gibraltar_chase_golden_hour")
		_camera().set_mode(FlightCamera.Mode.COCKPIT)
		_place(Vector3(STRAIT.x - 1400.0, 1000.0, STRAIT.z), 90.0, 500.0)
		await _take("09_gibraltar_cockpit")
		_camera().set_mode(FlightCamera.Mode.CHASE)
		var pass_start := Vector3(TOWN.x - 2600.0, 0.0, TOWN.z)
		pass_start.y = _ground_asl(pass_start) + 160.0
		_place(pass_start, 90.0, 520.0)
		await _take("10_gibraltar_low_pass_rock")
		var carrier := _carrier()
		if carrier != null:
			var astern := _flat(carrier.global_transform.basis.z)
			var deck := WorldOrigin.to_world(carrier.get_deck_transform().origin)
			_place(deck + astern * 1400.0 + Vector3(0.0, 260.0, 0.0), _heading_of(-astern), 420.0)
		else:
			push_warning("screenshot_tour: no carrier on the map, the carrier shot is taken where the aircraft is")
		await _take("11_gibraltar_carrier_nearby")

	if await _begin("free_flight", MAP_ATLAS, "noon", "scattered", "", ["12", "13"]):
		var west := Vector3(ATLAS_PEAK.x - 6000.0, 0.0, ATLAS_PEAK.z)
		west.y = _max_ground(west, Vector3(ATLAS_PEAK.x + 6000.0, 0.0, ATLAS_PEAK.z)) + 350.0
		_place(west, 90.0, 430.0)
		await _take("12_atlas_valley_chase")
		_place(Vector3(ATLAS_PEAK.x - 2000.0, _ground_asl(ATLAS_PEAK) + 3300.0, ATLAS_PEAK.z), 90.0, 480.0)
		await _take("13_atlas_high_altitude_clouds")

	if await _begin("dogfight", MAP_GIBRALTAR, "noon", "clear", "", ["14", "15", "16", "17"]):
		var enemy := _enemy_fighter()
		var weapons := _weapons()
		if enemy != null:
			var fwd := _forward(enemy)
			_place(_world_of(enemy) - fwd * 650.0 + Vector3(0.0, 90.0, 0.0), _heading_of(fwd), 480.0)
			if weapons != null:
				weapons.set_target(enemy)
		await _take("14_dogfight_chase_target_box")
		if not _select_weapon(["ir_missile", "radar_missile"]):
			push_warning("screenshot_tour: no air-to-air missile on the aircraft")
		_controller().press_weapon()
		await _wait_real(0.5)
		await _shot("15_dogfight_missile_launch")
		_controller().press_flares()
		await _wait_real(0.8)
		await _shot("16_dogfight_flares")
		enemy = _enemy_fighter()
		if enemy != null:
			enemy.take_damage(enemy.max_health * 10.0, GameState.player, enemy.global_position)
		await _wait_real(0.8)
		await _shot("17_dogfight_explosion")

	if await _begin("sead", MAP_GIBRALTAR, "noon", "clear", "", ["18"]):
		var sams := _by_role("sam")
		if not sams.is_empty():
			var sam_world := _world_of(sams[0])
			var pos := Vector3(sam_world.x - 8000.0, 0.0, sam_world.z)
			pos.y = _ground_asl(pos) + 2200.0
			_place(pos, _heading_of(sam_world - pos), 520.0)
		else:
			push_warning("screenshot_tour: no SAM site in the sead mission")
		await _settle()
		var launched := await _wait_for_missile(SAM_WAIT_S)
		if not launched:
			push_warning("screenshot_tour: no missile seen within %d s, the sead shot is taken anyway" % int(SAM_WAIT_S))
		await _wait_real(0.5)
		await _shot("18_sead_sam_launch")

	GameState.selected_loadout = "strike"  ## the default air-superiority loadout carries no bombs
	if await _begin("strike", MAP_GIBRALTAR, "noon", "clear", "", ["19", "20"]):
		var targets := _by_role("target")
		if not targets.is_empty():
			var target_world := _world_of(targets[0])
			var pos := Vector3(target_world.x - 2200.0, 0.0, target_world.z)
			pos.y = _ground_asl(pos) + 900.0
			_place(pos, _heading_of(target_world - pos), 480.0)
			await _settle()
			if not _select_weapon(["guided_bomb", "bomb"]):
				push_warning("screenshot_tour: no bomb on the aircraft")
			_controller().press_weapon()
			await _wait_real(1.6)
			await _shot("19_strike_bombs_falling")
			Events.explosion.emit(WorldOrigin.to_local(target_world), 2.5)
			await _wait_real(1.0)
			await _shot("20_strike_ground_explosion")

	GameState.selected_loadout = ""
	if await _begin("anti_ship", MAP_GIBRALTAR, "noon", "clear", "", ["21"]):
		var ships := _by_role("ship")
		if not ships.is_empty():
			var fwd := _forward(ships[0])
			_place(_world_of(ships[0]) - fwd * 1500.0 + Vector3(0.0, 180.0, 0.0), _heading_of(fwd), 380.0)
		await _take("21_anti_ship_frigate")

	GameState.selected_aircraft = "fa18c"  ## the Hornet has a tailhook
	if await _begin("carrier_landing", MAP_GIBRALTAR, "noon", "clear", "", ["22"]):
		var carrier := _carrier()
		if carrier != null:
			var astern := _flat(carrier.global_transform.basis.z)
			var deck := WorldOrigin.to_world(carrier.get_deck_transform().origin)
			_place(deck + astern * 2600.0 + Vector3(0.0, 230.0, 0.0), _heading_of(-astern), 265.0)
		await _take("22_carrier_landing_approach")
	GameState.selected_aircraft = "f16c"

	if await _begin("time_trial", MAP_ATLAS, "noon", "clear", "", ["23"]):
		var mission := _mission()
		var rings: Array = mission.plan["rings"]
		var start: Vector3 = mission.plan["start"]["pos"]
		var first: Vector3 = rings[0]
		var dir := (first - start).normalized()
		_place(first - dir * 1400.0, _heading_of(dir), 430.0)
		await _take("23_time_trial_rings")

	if await _begin("free_flight", MAP_GIBRALTAR, "night", "clear", "", ["24"]):
		_place(Vector3(STRAIT.x - 2200.0, 900.0, STRAIT.z), 90.0, 500.0)
		await _take("24_night_strait")

	if await _begin("free_flight", MAP_GIBRALTAR, "noon", "storm", "", ["25"]):
		_place(Vector3(STRAIT.x - 2200.0, 700.0, STRAIT.z), 90.0, 460.0)
		await _take("25_storm_strait")


## Starts a sortie with the time of day and weather the shots need, then waits for the level to come up. A loading_shot
## is saved while the loading screen is still up, with its process held so it does not change scene yet. shots lists the
## shot ids the sortie takes: when none of them is wanted (--only), no sortie is started and false is returned.
func _begin(mode_id: String, map_id: String, time_of_day: String, weather: String, loading_shot: String = "", shots: Array = []) -> bool:
	if not shots.is_empty() and not _any_wanted(shots):
		return false
	if GameState.level != null:
		GameState.goto_menu()
		var menu_up := await _wait_scene(MENU_SCENE)
		if not menu_up:
			return false
	var options := {}
	for def in _data["modes"][mode_id]["options"]:
		options[String(def["id"])] = String(def["default"])
	if options.has("time"):
		options["time"] = time_of_day  ## begin_mission copies these option values into Settings
	if options.has("weather"):
		options["weather"] = weather
	Settings.gameplay_time_of_day = time_of_day
	Settings.gameplay_weather = weather
	GameState.begin_mission(mode_id, map_id, options, DIFFICULTY)
	if loading_shot != "" and _wanted(loading_shot):
		var loading := get_tree().get_first_node_in_group(LoadingScreen.GROUP)
		if loading != null:
			loading.set_process(false)
		await _take(loading_shot)
		if loading != null and is_instance_valid(loading):
			loading.set_process(true)
	var level_up := await _wait_level()
	if level_up:
		return true
	LoadingScreen.dismiss()
	return false


## Waits for the scene to settle, then saves the shot.
func _take(shot_name: String) -> void:
	if not _wanted(shot_name):
		return
	await _settle()
	await _shot(shot_name)


func _settle() -> void:
	await _wait_real(HEADLESS_WAIT_S if _headless else SETTLE_S)


func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


## Saves the frame just drawn as <out>/<shot_name>.png. Headless runs count the shot and save nothing.
func _shot(shot_name: String) -> void:
	if not _wanted(shot_name):
		return
	_shots_done += 1
	if _headless:
		print("screenshot_tour: %s (headless, not saved)" % shot_name)
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % shot_name)
	if image.save_png(path) == OK:
		print("screenshot_tour: saved %s" % path)
	else:
		push_error("screenshot_tour: could not save %s" % path)


func _finish() -> void:
	_restore_save()
	var where := "not saved (headless)" if _headless else "saved to %s" % _out_dir
	var expected := SHOT_TOTAL if _only.is_empty() else _only.size()
	print("screenshot_tour: %d of %d shots reached, %s" % [_shots_done, expected, where])
	get_tree().quit(0 if _shots_done == expected else 1)


func _wait_scene(path: String) -> bool:
	var started := Time.get_ticks_msec()
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != path:
		if Time.get_ticks_msec() - started > LOAD_TIMEOUT_MS:
			push_error("screenshot_tour: %s did not open" % path)
			return false
		await get_tree().process_frame
	return true


func _wait_level() -> bool:
	var started := Time.get_ticks_msec()
	while not _level_ready():
		if Time.get_ticks_msec() - started > LOAD_TIMEOUT_MS:
			push_error("screenshot_tour: the level did not start")
			return false
		await get_tree().process_frame
	return true


func _level_ready() -> bool:
	return GameState.level != null and GameState.player != null and GameState.level.get("_mission") != null \
			and get_tree().get_nodes_in_group(LoadingScreen.GROUP).is_empty()


## Waits until a missile is in flight anywhere. Returns false when none flies within timeout_s.
func _wait_for_missile(timeout_s: float) -> bool:
	var started := Time.get_ticks_msec()
	while get_tree().get_nodes_in_group("missiles").is_empty():
		if Time.get_ticks_msec() - started > timeout_s * 1000.0:
			return false
		await get_tree().process_frame
	return true


## Puts the player's aircraft in the air at a world position, with a heading in degrees and a speed in km/h.
func _place(world: Vector3, heading_deg: float, speed_kmh: float) -> void:
	var p := GameState.player as Aircraft
	if p == null:
		push_error("screenshot_tour: no player aircraft to place")
		return
	p.spawn_in_air(WorldOrigin.to_local(world), heading_deg, speed_kmh)


## Cycles the selected weapon to the first of the types the aircraft carries. Returns false when it carries none.
func _select_weapon(types: Array) -> bool:
	var w := _weapons()
	if w == null or w.get_weapon_list().is_empty():
		return false
	for type in types:
		for _i in w.get_weapon_list().size():
			if String(w.get_selected().get("type", "")) == String(type):
				return true
			w.select_next()
	return false


func _level_prop(prop: String) -> Variant:
	return null if GameState.level == null else GameState.level.get(prop)


func _mission() -> Mission:
	return _level_prop("_mission") as Mission


func _controller() -> PlayerController:
	return _level_prop("controller") as PlayerController


func _camera() -> FlightCamera:
	return _level_prop("camera") as FlightCamera


func _carrier() -> Carrier:
	var world := _level_prop("world") as Node3D
	if world == null:
		return null
	for child in world.get_children():
		if child is Carrier:
			return child as Carrier
	return null


func _weapons() -> WeaponSystem:
	var p := GameState.player as Aircraft
	if p == null:
		return null
	return p.weapons as WeaponSystem


## The live nodes the mission gave a role: fighter, sam, target, ship.
func _by_role(role: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var mission := _mission()
	if mission == null:
		return out
	for node in mission.by_role(role):
		if is_instance_valid(node) and node is Node3D:
			out.append(node)
	return out


func _enemy_fighter() -> Aircraft:
	for node in _by_role("fighter"):
		var a := node as Aircraft
		if a != null and a.alive:
			return a
	return null


func _world_of(node: Node3D) -> Vector3:
	return WorldOrigin.to_world(node.global_position)


## Horizontal unit vector.
func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## Flat direction the node's nose or bow points (local -Z).
func _forward(node: Node3D) -> Vector3:
	return _flat(-node.global_transform.basis.z)


## Compass heading in degrees (0 = north, clockwise) of a flat direction. North is -Z and east is +X.
func _heading_of(dir: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)


## Terrain height (ASL) under a world position.
func _ground_asl(world: Vector3) -> float:
	var local := WorldOrigin.to_local(world)
	return Ground.height_at(local.x, local.z)


## Highest terrain along the straight line from a to b, in world m.
func _max_ground(a: Vector3, b: Vector3) -> float:
	var top := -INF
	for i in 41:
		top = maxf(top, _ground_asl(a.lerp(b, i / 40.0)))
	return top


## Shot ids from --only=08,24. Each id is a shot number or the start of a shot name.
func _parse_only() -> Array[String]:
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			for id in arg.trim_prefix("--only=").split(",", false):
				ids.append(id.strip_edges())
	return ids


## True when no --only filter is set, or the shot name matches one of its ids (in either direction, so "07" and "07_loading_screen" match).
func _wanted(shot_name: String) -> bool:
	if _only.is_empty():
		return true
	for id in _only:
		if shot_name.begins_with(id) or id.begins_with(shot_name):
			return true
	return false


func _any_wanted(shot_names: Array) -> bool:
	for shot_name in shot_names:
		if _wanted(String(shot_name)):
			return true
	return false


## Absolute folder for the PNGs. A relative --out is taken from the folder the shell ran Godot in.
func _resolve_out_dir() -> String:
	var out := OUT_DEFAULT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	if out.begins_with("res://") or out.begins_with("user://"):
		out = ProjectSettings.globalize_path(out)
	elif not out.is_absolute_path():
		var cwd := OS.get_environment("PWD")
		if cwd == "":
			cwd = ProjectSettings.globalize_path("res://")
		out = cwd.path_join(out)
	return out.simplify_path()


## The tour starts sorties, which write the save. The player's save is put back at the end.
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
