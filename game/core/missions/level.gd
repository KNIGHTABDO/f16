extends Node3D
## Flight level: builds the world for the selected map through WorldBuilder (terrain, ocean, sky, weather, vegetation,
## cities, airbases, carrier) with the Settings time of day and weather, spawns the player's aircraft at the map's spawn
## point in the air, and runs the follow camera, the controller and the overlay. A destroyed player respawns at the spawn
## point after RESPAWN_DELAY. Esc or the pause control opens the pause menu. World is the floating-origin root.

const RESPAWN_DELAY := 3.0  ## s from the crash to the next spawn
const SPAWN_KMH := 560.0  ## airspeed at the start and at respawn, km/h

@onready var world: Node3D = $World

var map_id := ""
var player: Aircraft
var camera: FlightCamera
var controller: PlayerController
var hud: HUD
var terrain: Terrain
var ocean: Ocean
var _hud: CanvasLayer
var _pause_menu: PauseMenu
var _spawn: Dictionary = {}  ## map spawn {x, z, alt_m, heading_deg} in world coordinates
var _respawn_left := -1.0  ## s until respawn while the player is down, -1 while flying
var _plan: Dictionary = {}  ## sortie plan from MissionGenerator: start, units, objectives inputs
var _mission: Mission
var _overlay: MissionOverlay


func _ready() -> void:
	if world == null:
		world = get_node_or_null("World")
	if world == null:
		world = Node3D.new()
		world.name = "World"
		add_child(world)
	WorldOrigin.reset()
	GameState.level = self
	map_id = GameState.selected_map
	if not Ground.load_map(map_id):
		push_error("level: could not load map '%s'" % map_id)
		GameState.goto_menu()
		return
	_spawn = Ground.meta.get("spawn", {}) as Dictionary

	controller = PlayerController.new()
	controller.name = "PlayerController"
	add_child(controller)

	camera = FlightCamera.new()
	camera.name = "FlightCamera"
	camera.controller = controller
	world.add_child(camera)

	var built := WorldBuilder.build(world, map_id, _time_of_day(), Settings.gameplay_weather, camera.get_camera())
	if built.is_empty():
		push_error("level: world build failed for map '%s'" % map_id)
		GameState.goto_menu()
		return
	terrain = built["terrain"]
	ocean = built["ocean"]

	_plan = _make_plan()
	_spawn_player()

	_hud = CanvasLayer.new()
	_hud.name = "Hud"
	add_child(_hud)
	hud = HUD.new()
	hud.name = "HUD"
	hud.setup(controller, camera)
	_hud.add_child(hud)
	_start_mission()

	if Settings.radio_enabled:
		Radio.start()


func _exit_tree() -> void:
	if Settings.radio_enabled:
		Radio.stop()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		_open_pause()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	WorldBuilder.update(delta)
	if _mission != null:
		_mission.update(delta)
	if controller.pause_requested:
		controller.pause_requested = false
		_open_pause()
	if controller.camera_requested:
		controller.camera_requested = false
		camera.cycle_mode()
	controller.aim_drag_enabled = camera.get_mode() != FlightCamera.Mode.ORBIT
	camera.set_look_back(controller.look_back)
	if _respawn_left >= 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn_left = -1.0
			_spawn_player()
	hud.respawn_in = _respawn_left


## The settings name a fixed time of day. "realtime" passes the device clock as a float hour, which WorldSky parses.
func _time_of_day() -> String:
	if Settings.gameplay_time_of_day == "realtime":
		var now := Time.get_time_dict_from_system()
		return str(float(now["hour"]) + float(now["minute"]) / 60.0)
	return Settings.gameplay_time_of_day


func _open_pause() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		return
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	_hud.add_child(_pause_menu)


## Creates a fresh player aircraft at the map spawn, in the air, and hands it the controls and the camera.
func _spawn_player() -> void:
	var a := Aircraft.create(GameState.selected_aircraft, 0, true)
	if a == null:
		push_error("level: could not create aircraft '%s'" % GameState.selected_aircraft)
		return
	world.add_child(a)
	var start := _start_spec()
	var local: Vector3 = WorldOrigin.to_local(start["pos"])
	if bool(start.get("ground", false)):
		a.spawn_on_ground(local, float(start["heading"]))
	else:
		a.spawn_in_air(local, float(start["heading"]), float(start["speed_kmh"]))
	a.destroyed.connect(_on_player_destroyed)
	player = a
	GameState.player = a
	controller.attach(a)
	camera.set_target(a)
	WorldOrigin.anchor = a


func _on_player_destroyed(_killer: Node) -> void:
	if _mission == null or _mission.on_player_destroyed():
		_respawn_left = RESPAWN_DELAY


## The sortie plan for the selected mode, map and difficulty. The seed is kept in GameState so RETRY flies it again.
func _make_plan() -> Dictionary:
	var seed_value := GameState.mission_seed
	if seed_value < 0:
		seed_value = randi()
	GameState.mission_seed = seed_value
	var carrier: Node = null
	for child in world.get_children():
		if child is Carrier:
			carrier = child
			break
	return MissionGenerator.generate(GameState.selected_mode, map_id, GameState.difficulty, GameState.mission_options,
			seed_value, {"carrier": carrier})


## Where the player starts: the plan's start when there is one, otherwise the map spawn point in the air.
func _start_spec() -> Dictionary:
	var start: Dictionary = _plan.get("start", {})
	if start.has("pos"):
		return start
	return {
		"pos": Vector3(float(_spawn.get("x", 0.0)), float(_spawn.get("alt_m", 2000.0)), float(_spawn.get("z", 0.0))),
		"heading": float(_spawn.get("heading_deg", 0.0)),
		"speed_kmh": SPAWN_KMH,
		"ground": false,
	}


## Creates the mission, spawns its units and starts the clock. The loading screen goes away first, so an
## immediate result is not hidden behind it.
func _start_mission() -> void:
	_mission = Mission.create(String(_plan["mode"]))
	add_child(_mission)
	var spawned := MissionSpawner.spawn_all(world, _plan)
	_mission.finished.connect(_on_mission_finished)
	_mission.setup(self, _plan, spawned)
	_overlay = MissionOverlay.new()
	_overlay.name = "MissionOverlay"
	_hud.add_child(_overlay)
	_overlay.setup(self, _mission)
	LoadingScreen.dismiss()
	_mission.begin()


func _on_mission_finished(result: Dictionary) -> void:
	GameState.record_result(result)
	_open_results(result)


func _open_results(result: Dictionary) -> void:
	var screen := ResultsScreen.new()
	screen.name = "ResultsScreen"
	screen.setup(result)
	screen.retry.connect(GameState.restart_mission)
	screen.next_mission.connect(GameState.next_mission)
	screen.menu.connect(GameState.goto_menu)
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.add_child(screen)
	get_tree().paused = true
