extends Node3D
## Test flight scene for world dressing (sky, clouds, weather, vegetation, cities, airbases, carrier).
##
## Command-line options after "--":
##   --map=gibraltar|test
##   --time=dawn|morning|noon|afternoon|sunset|dusk|night (default: noon)
##   --weather=clear|scattered|overcast|storm|haze (default: scattered)
##   --frames=N (quit after N frames)
##   --shot=PATH (save PNG before quitting)

@onready var world_node: Node3D = $World
@onready var camera: Camera3D = $World/Camera
@onready var hud_stats: Label = $Hud/Stats

var map_id := "gibraltar"
var time_of_day := "noon"
var weather_state := "scattered"
var frame_limit := -1
var shot_path := ""

var _world_data: Dictionary = {}
var _frames := 0
var _hud_timer := 0.0

# Scripted flight waypoints: [pos_world: Vector3, look_world: Vector3, duration_sec: float]
var _waypoints: Array = [
	# 1. Low pass over Tangier Airport (GMTT)
	{"pos": Vector3(-35800.0, 95.0, 7250.0), "look": Vector3(-32000.0, 15.0, 7700.0), "t": 6.0},
	# 2. Low pass over Tangier city and coastline
	{"pos": Vector3(-24500.0, 240.0, 4800.0), "look": Vector3(-21500.0, 40.0, 2500.0), "t": 6.0},
	# 3. Climb through cloud deck
	{"pos": Vector3(-12000.0, 1850.0, -6000.0), "look": Vector3(0.0, 1950.0, -18000.0), "t": 6.0},
	# 4. High over Strait of Gibraltar looking at Gibraltar Rock
	{"pos": Vector3(6000.0, 3800.0, -22000.0), "look": Vector3(17684.0, 420.0, -37684.0), "t": 6.0},
	# 5. Over the Carrier group in the sea
	{"pos": Vector3(-44800.0, 180.0, 5200.0), "look": Vector3(-45000.0, 20.0, 5000.0), "t": 6.0}
]

var _wp_index := 0
var _wp_elapsed := 0.0


func _ready() -> void:
	var args := _parse_args()
	map_id = String(args.get("map", map_id))
	time_of_day = String(args.get("time", time_of_day))
	weather_state = String(args.get("weather", weather_state))
	frame_limit = int(args.get("frames", -1))
	shot_path = String(args.get("shot", ""))

	WorldOrigin.reset()

	# Fallback to test map if requested or map data missing
	if not Ground.load_map(map_id):
		print("test_world: could not load map '%s', falling back to 'test'" % map_id)
		map_id = "test"
		Ground.load_map("test")

	camera.add_to_group("floating")
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = 0.5
	camera.far = 400000.0
	camera.fov = 68.0
	WorldOrigin.anchor = camera

	_world_data = WorldBuilder.build(world_node, map_id, time_of_day, weather_state, camera)
	if _world_data.is_empty():
		push_error("test_world: WorldBuilder.build failed")
		get_tree().quit(1)
		return

	# If map is 'test', adjust waypoints for test map coordinates
	if map_id == "test":
		_waypoints = [
			{"pos": Vector3(-10000.0, 180.0, -10000.0), "look": Vector3(10000.0, 180.0, 10000.0), "t": 10.0},
			{"pos": Vector3(0.0, 2200.0, 0.0), "look": Vector3(20000.0, 1500.0, 20000.0), "t": 10.0}
		]

	_place_camera(_waypoints[0]["pos"], _waypoints[0]["look"])
	print("test_world: built map '%s', time '%s', weather '%s'" % [map_id, time_of_day, weather_state])


func _process(delta: float) -> void:
	WorldBuilder.update(delta)
	_step_flight(delta)
	_frames += 1

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.25
		_update_hud()

	if frame_limit >= 0 and _frames >= frame_limit:
		_finish()


func _step_flight(delta: float) -> void:
	if _waypoints.is_empty():
		return
	var cur = _waypoints[_wp_index]
	var next_idx = (_wp_index + 1) % _waypoints.size()
	var nxt = _waypoints[next_idx]

	_wp_elapsed += delta
	var dur: float = float(cur["t"])
	var f := clampf(_wp_elapsed / dur, 0.0, 1.0)
	var smooth_f := smoothstep(0.0, 1.0, f)

	var pos: Vector3 = cur["pos"].lerp(nxt["pos"], smooth_f)
	var look: Vector3 = cur["look"].lerp(nxt["look"], smooth_f)
	_place_camera(pos, look)

	if _wp_elapsed >= dur:
		_wp_elapsed = 0.0
		_wp_index = next_idx


func _place_camera(world_pos: Vector3, world_look: Vector3) -> void:
	camera.global_position = WorldOrigin.to_local(world_pos)
	camera.look_at(WorldOrigin.to_local(world_look), Vector3.UP)


func _update_hud() -> void:
	var w := WorldOrigin.to_world(camera.global_position)
	var agl := w.y - (Ground.world_height_at(w.x, w.z) if Ground.is_loaded() else 0.0)
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var fps := Engine.get_frames_per_second()

	hud_stats.text = "%d fps | %d draw calls | %d k tris\ntime: %s | weather: %s | map: %s\nalt: %.0f m ASL (%.0f m AGL)\nworld: (%.0f, %.0f)" % [
		fps, dc, prims / 1000, time_of_day, weather_state, map_id, w.y, agl, w.x, w.z
	]


func _finish() -> void:
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var fps := Engine.get_frames_per_second()
	print("test_world: frame %d, fps %d, draw calls %d" % [_frames, fps, dc])
	if shot_path != "":
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(shot_path)
		print("test_world: saved screenshot %s (%s)" % [shot_path, error_string(err)])
	get_tree().quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var eq := a.find("=")
		if a.begins_with("--") and eq > 2:
			out[a.substr(2, eq - 2)] = a.substr(eq + 1)
	return out
