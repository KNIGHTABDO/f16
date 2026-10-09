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
var overlay: FlightOverlay
var terrain: Terrain
var ocean: Ocean
var _hud: CanvasLayer
var _pause_menu: PauseMenu
var _spawn: Dictionary = {}  ## map spawn {x, z, alt_m, heading_deg} in world coordinates
var _respawn_left := -1.0  ## s until respawn while the player is down, -1 while flying


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

	_spawn_player()

	_hud = CanvasLayer.new()
	_hud.name = "Hud"
	add_child(_hud)
	overlay = FlightOverlay.new()
	overlay.name = "FlightOverlay"
	overlay.setup(controller, camera)
	_hud.add_child(overlay)

	if Settings.radio_enabled:
		Radio.cockpit_fx = (camera.get_mode() == FlightCamera.Mode.COCKPIT) and Settings.radio_cockpit_fx
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
	overlay.respawn_in = _respawn_left


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
	var x := float(_spawn.get("x", 0.0))
	var z := float(_spawn.get("z", 0.0))
	var alt := float(_spawn.get("alt_m", 2000.0))
	var heading := float(_spawn.get("heading_deg", 0.0))
	a.spawn_in_air(WorldOrigin.to_local(Vector3(x, alt, z)), heading, SPAWN_KMH)
	a.destroyed.connect(_on_player_destroyed)
	player = a
	GameState.player = a
	controller.attach(a)
	camera.set_target(a)
	WorldOrigin.anchor = a


func _on_player_destroyed(_killer: Node) -> void:
	_respawn_left = RESPAWN_DELAY
