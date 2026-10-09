extends Node3D
## Fly-through test for Terrain and Ocean on the synthetic test map (tools/make_test_map.py).
##
## Run in a window:  godot --path game res://scenes/test_terrain.tscn
## Options after "--" (all optional):
##   --preset=low|balanced|high|ultra   quality preset (default: Settings.graphics_preset)
##   --pose=x,y,z,tx,ty,tz              hold the camera at world (x, y, z) looking at (tx, ty, tz); no flight
##   --agl=H                            with --pose: y values are heights above the ground under each point
##   --frames=N                         quit after N frames (default: flight runs on; pose runs 120 frames)
##   --shot=PATH                        save a PNG of the last frame before quitting
##
## Default flight: a low pass at 150 m above ground from the western sea over the coast and into the
## north-east mountains, then a climb to 8 km above sea level. The camera is in the "floating" group and
## a direct child of World, so the floating origin shifts it (and the terrain follows through WorldOrigin).

var MAP_ID := "test"
const FLIGHT_SPEED := 150.0  # m/s along the low pass
const LOW_AGL := 150.0  # low pass height above ground, metres
const CLIMB_ASL := 8000.0  # climb target, metres above sea level
const CLIMB_TIME := 40.0  # seconds to reach CLIMB_ASL
const LOW_START := Vector2(-110000.0, -10000.0)  # world X, Z: sea, west of the coast
const LOW_END := Vector2(60000.0, -60000.0)  # world X, Z: north-east mountains
const LIGHT_DIR := Vector3(-0.45, 0.6, -0.65)  # towards the sun; same light as the test map shading
const HAZE := Color(0.62, 0.74, 0.86)  # sky horizon and aerial haze tone

@onready var camera: Camera3D = $World/Camera
@onready var terrain: Terrain = $World/Terrain
@onready var ocean: Ocean = $World/Ocean
@onready var sun: DirectionalLight3D = $Sun
@onready var sky_material: ProceduralSkyMaterial = $WorldEnvironment.environment.sky.sky_material
@onready var stats: Label = $Hud/Stats

var _preset := "balanced"
var _pose := {}  # empty = flight
var _frame_limit := -1
var _shot := ""
var _frames := 0
var _done := false
var _s := 0.0  # metres flown along the low pass
var _climb := -1.0  # seconds into the climb, -1 while on the low pass
var _flight_len := 0.0
var _dir := Vector2.ZERO
var _hud_timer := 0.0


func _ready() -> void:
	var args := _parse_args()
	_preset = String(args.get("preset", Settings.graphics_preset))
	WorldOrigin.reset()
	MAP_ID = String(args.get("map", MAP_ID))
	if not Ground.load_map(MAP_ID):
		push_error("test_terrain: could not load map '%s'" % MAP_ID)
		get_tree().quit(1)
		return

	camera.add_to_group("floating")
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = 0.5
	camera.far = 600000.0  # sea beyond the far plane shows the sky's ground colour as a dark line at the horizon
	camera.fov = 65.0
	WorldOrigin.anchor = camera
	sun.look_at(sun.global_position - LIGHT_DIR.normalized(), Vector3.UP)
	sky_material.sky_horizon_color = HAZE
	sky_material.ground_horizon_color = HAZE

	terrain.haze_color = HAZE
	ocean.haze_color = HAZE
	terrain.set_camera(camera)
	ocean.set_camera(camera)
	terrain.apply_quality(_preset)
	ocean.apply_quality(_preset)
	if not terrain.setup(MAP_ID) or not ocean.setup(MAP_ID, terrain):
		get_tree().quit(1)
		return

	_shot = String(args.get("shot", ""))
	if args.has("pose"):
		var v := String(args.pose).split(",")
		if v.size() != 6:
			push_error("test_terrain: --pose needs six numbers x,y,z,tx,ty,tz")
			get_tree().quit(1)
			return
		var pos := Vector3(float(v[0]), float(v[1]), float(v[2]))
		var look := Vector3(float(v[3]), float(v[4]), float(v[5]))
		if args.has("agl"):
			# Heights above the ground under each point: pos.y is the camera's height, look.y the target's.
			pos.y = Ground.world_height_at(pos.x, pos.z) + float(args.agl)
			look.y = Ground.world_height_at(look.x, look.z) + look.y
		_pose = {"pos": pos, "look": look}
		_frame_limit = int(args.get("frames", 120))
	else:
		_dir = (LOW_END - LOW_START).normalized()
		_flight_len = LOW_START.distance_to(LOW_END)
		_frame_limit = int(args.get("frames", -1))
	print("test_terrain: preset %s, %s" % [_preset, "pose" if args.has("pose") else "flight"])


func _process(delta: float) -> void:
	if _done:
		return
	if _pose.is_empty():
		_fly(delta)
	else:
		_place_camera(_pose.pos, _pose.look)
	_frames += 1
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.25
		_update_hud()
	if _frame_limit >= 0 and _frames >= _frame_limit:
		_finish()


## Camera position and target are given in world metres; the local transform follows the floating origin.
func _place_camera(world_pos: Vector3, world_look: Vector3) -> void:
	camera.global_position = WorldOrigin.to_local(world_pos)
	camera.look_at(WorldOrigin.to_local(world_look), Vector3.UP)


func _fly(delta: float) -> void:
	var pos: Vector3
	var fwd: Vector3
	if _climb < 0.0:
		_s = minf(_s + FLIGHT_SPEED * delta, _flight_len)
		var p := LOW_START + _dir * _s
		var ground := Ground.world_height_at(p.x, p.y)
		pos = Vector3(p.x, ground + LOW_AGL, p.y)
		fwd = Vector3(_dir.x, -0.03, _dir.y)
		if _s >= _flight_len:
			_climb = 0.0
	else:
		_climb += delta
		var f := smoothstep(0.0, 1.0, clampf(_climb / CLIMB_TIME, 0.0, 1.0))
		var ground := Ground.world_height_at(LOW_END.x, LOW_END.y)
		var alt := lerpf(ground + LOW_AGL, CLIMB_ASL, f)
		pos = Vector3(LOW_END.x, alt, LOW_END.y)
		fwd = Vector3(_dir.x, -0.25, _dir.y)
	_place_camera(pos, pos + fwd.normalized() * 1000.0)


func _update_hud() -> void:
	var w := WorldOrigin.to_world(camera.global_position)
	var agl := w.y - Ground.world_height_at(w.x, w.z)
	stats.text = "%d fps  preset %s\nalt %.0f m ASL, %.0f m AGL\nworld (%.0f, %.0f)  origin offset (%.0f, %.0f)" % [
		Engine.get_frames_per_second(), _preset, w.y, agl, w.x, w.z, WorldOrigin.offset_x, WorldOrigin.offset_z]


func _finish() -> void:
	_done = true
	if _shot != "":
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(_shot)
		print("test_terrain: screenshot %s (%s)" % [_shot, error_string(err)])
	get_tree().quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var eq := a.find("=")
		if a.begins_with("--") and eq > 2:
			out[a.substr(2, eq - 2)] = a.substr(eq + 1)
	return out
