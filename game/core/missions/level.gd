extends Node3D
## Flight level: loads the selected map (Terrain, Ocean, environment), spawns the player's aircraft at the map's
## spawn point in the air, and runs the follow camera, the controller and the overlay. A destroyed player respawns
## at the spawn point after RESPAWN_DELAY; the pause control returns to the menu. The sky and sun are built in
## _build_environment() only, so the world builder can replace them later. World is the floating-origin root.

const RESPAWN_DELAY := 3.0  ## s from the crash to the next spawn
const SPAWN_KMH := 560.0  ## airspeed at the start and at respawn, km/h
const HAZE := Color(0.62, 0.74, 0.86)  ## sky horizon and aerial haze, same tone the terrain uses
const SKY_TOP := Color(0.26, 0.42, 0.7)
const GROUND_BOTTOM := Color(0.08, 0.1, 0.12)
const LIGHT_DIR := Vector3(-0.45, 0.6, -0.65)  ## towards the sun, same light as the terrain shading

@onready var world: Node3D = $World

var map_id := ""
var player: Aircraft
var camera: FlightCamera
var controller: PlayerController
var overlay: FlightOverlay
var terrain: Terrain
var ocean: Ocean
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
	_build_environment()

	controller = PlayerController.new()
	controller.name = "PlayerController"
	add_child(controller)

	camera = FlightCamera.new()
	camera.name = "FlightCamera"
	camera.controller = controller
	world.add_child(camera)

	if not _build_terrain():
		push_error("level: terrain or ocean failed for map '%s'" % map_id)
		GameState.goto_menu()
		return

	_spawn_player()

	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)
	overlay = FlightOverlay.new()
	overlay.name = "FlightOverlay"
	overlay.setup(controller, camera)
	layer.add_child(overlay)

	if Settings.radio_enabled:
		Radio.cockpit_fx = (camera.get_mode() == FlightCamera.Mode.COCKPIT) and Settings.radio_cockpit_fx
		Radio.start()


func _exit_tree() -> void:
	if Settings.radio_enabled:
		Radio.stop()


func _process(delta: float) -> void:
	if controller.pause_requested:
		controller.pause_requested = false
		GameState.goto_menu()
		return
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


## Sky, sun and environment. Isolated here so the world builder can replace it.
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = HAZE
	sky_mat.ground_bottom_color = GROUND_BOTTOM
	sky_mat.ground_horizon_color = HAZE
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.fog_enabled = true
	env.fog_light_color = HAZE
	env.fog_density = 0.000018
	env.fog_sky_affect = 0.5
	env.fog_aerial_perspective = 0.6
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at(sun.global_position - LIGHT_DIR.normalized(), Vector3.UP)


## Terrain and Ocean sit at identity under World (not floating): they are the map itself.
func _build_terrain() -> bool:
	terrain = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	ocean = Ocean.new()
	ocean.name = "Ocean"
	world.add_child(ocean)
	var cam := camera.get_camera()
	terrain.haze_color = HAZE
	ocean.haze_color = HAZE
	terrain.set_camera(cam)
	ocean.set_camera(cam)
	terrain.apply_quality(Settings.graphics_preset)
	ocean.apply_quality(Settings.graphics_preset)
	return terrain.setup(map_id) and ocean.setup(map_id, terrain)


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
