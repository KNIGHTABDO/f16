extends Node3D
## Visual test bench for the VFX system (scene: res://scenes/test_vfx.tscn). Builds a sky, flat land, a water
## strip, a gun, a wreck, a missile and a jet (afterburner, contrail, vapour), then cycles every effect every
## CYCLE seconds with an orbiting camera. The jet's g and altitude are synthetic (fixed values fed to update()).
## Screenshots (windowed run only): godot --path game res://scenes/test_vfx.tscn -- --shots=<absolute dir>
## Saves one frame per cycle at phase 0.9 s (muzzle cycles at 0.03 s) and quits after SHOTS frames.

const CYCLE := 1.5
const SHOTS := 12
const CENTER := Vector3(20.0, 0.0, -20.0)
const WRECK_POS := Vector3(50.0, 0.0, -40.0)
const GUN_POS := Vector3(-60.0, 1.5, 0.0)
const JET_ALT := 9600.0  # passed to update(): well above the contrail altitude

var _world: Node3D
var _camera: Camera3D
var _gun: Node3D
var _wreck_box: Node3D
var _wreck_trail: Node3D
var _missile: Node3D
var _missile_trail: Node3D
var _missile_vel := Vector3.ZERO
var _missile_age := -1.0
var _jet: Node3D
var _jet_ab: AfterburnerFx
var _jet_vapor: VaporFx
var _contrail: Contrail
var _t := 0.0
var _cycle := -1
var _shot_dir := ""
var _shots_taken := 0
var _last_shot_cycle := -1
var _closeup := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shot_dir = arg.trim_prefix("--shots=")
		elif arg == "--closeup":
			_closeup = true
	_build_environment()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	_add_plane(Vector3(0.0, 0.0, 0.0), Vector2(900.0, 900.0), Color(0.33, 0.36, 0.2))
	_add_plane(Vector3(230.0, 0.3, 0.0), Vector2(340.0, 900.0), Color(0.07, 0.2, 0.34))

	_gun = _add_box(_world, GUN_POS, Vector3(2.0, 1.5, 3.0), Color(0.2, 0.2, 0.2))
	_wreck_box = _add_box(_world, WRECK_POS, Vector3(6.0, 2.0, 3.0), Color(0.08, 0.07, 0.07))
	_missile = _add_box(_world, Vector3.ZERO, Vector3(0.4, 0.4, 2.4), Color(0.7, 0.7, 0.72))
	_missile.visible = false

	_jet = Node3D.new()
	_world.add_child(_jet)
	_jet.add_to_group("floating")
	_add_box(_jet, Vector3.ZERO, Vector3(1.2, 1.2, 12.0), Color(0.45, 0.46, 0.5))
	_add_box(_jet, Vector3.ZERO, Vector3(14.0, 0.2, 2.0), Color(0.4, 0.41, 0.45))
	var nozzle := Node3D.new()
	nozzle.position = Vector3(0.0, 0.0, 6.0)
	_jet.add_child(nozzle)
	_jet_ab = AfterburnerFx.new()
	nozzle.add_child(_jet_ab)
	_jet_ab.setup(0.9, 8.0)
	_jet_vapor = VaporFx.new()
	_jet.add_child(_jet_vapor)
	_jet_vapor.setup(12.0, 0.6)
	_contrail = Contrail.new()
	_world.add_child(_contrail)
	_contrail.setup(_jet, 7.0, Vector3(0.0, 0.0, 6.0))

	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.current = true


func _process(delta: float) -> void:
	_t += delta
	var a := _t * 0.05
	_camera.position = CENTER + Vector3(cos(a) * 170.0, 55.0, sin(a) * 170.0)


	var aj := _t * 0.35
	var jet_pos := Vector3(CENTER.x + cos(aj) * 110.0, 50.0, CENTER.z + sin(aj) * 110.0)
	var tangent := Vector3(-sin(aj), 0.0, cos(aj))
	_jet.global_position = jet_pos
	_jet.look_at(jet_pos + tangent, Vector3.UP)
	if _closeup:
		# Close chase view from the side and aft of the jet, to check the afterburner, vapour and contrail.
		_camera.global_position = _jet.to_global(Vector3(14.0, 3.0, 14.0))
		_camera.look_at(_jet.to_global(Vector3(0.0, 0.0, 6.0)), Vector3.UP)
	else:
		_camera.look_at(CENTER.lerp(jet_pos, 0.4) + Vector3(0.0, 5.0, 0.0), Vector3.UP)
	var g := 2.0 + 4.0 * (0.5 + 0.5 * sin(_t * 0.6))
	var mach := 0.95
	_jet_ab.set_intensity(0.85)
	_jet_ab.update(mach, g, 0.25, JET_ALT)
	_jet_vapor.update(mach, g, 0.25, JET_ALT)
	_contrail.update(mach, g, 0.25, JET_ALT)

	if _missile_age >= 0.0:
		_missile_age += delta
		_missile.position += _missile_vel * delta
		if _missile_age > 2.5:
			Vfx.stop_trail(_missile_trail)
			_missile_trail = null
			_missile.visible = false
			_missile_age = -1.0

	var c := int(floor(_t / CYCLE))
	if c != _cycle:
		_cycle = c
		_run_cycle(c % 12)
	var phase := _t - float(c) * CYCLE
	# Muzzle flashes last 0.07 s, so their cycles are shot early. Everything else is shot at 0.9 s.
	var shot_at := 0.03 if (c % 12 == 5 or c % 12 == 10) else 0.9
	if _shot_dir != "" and c != _last_shot_cycle and phase >= shot_at:
		_last_shot_cycle = c
		_save_shot(c)


func _run_cycle(step: int) -> void:
	match step:
		0:
			Events.explosion.emit(Vector3(-15.0, 0.0, -10.0), 0.6)
			Vfx.explosion(Vector3(-15.0, 0.0, -40.0), 1.0, "ground")
		1:
			Vfx.explosion(Vector3(120.0, 0.3, 10.0), 1.2, "water")
		2:
			Vfx.explosion(Vector3(-40.0, 30.0, 10.0), 0.4, "air")
		3:
			Vfx.explosion(Vector3(-5.0, 0.0, -70.0), 2.5, "aircraft")
		4:
			Vfx.impact(Vector3(10.0, 0.0, -10.0), Vector3.UP, "ground")
			Vfx.impact(Vector3(14.0, 0.0, -6.0), Vector3(0.3, 1.0, 0.2), "ground")
			Vfx.impact(Vector3(20.0, 0.0, -5.0), Vector3(0.3, 1.0, 0.2), "metal")
			Vfx.impact(Vector3(130.0, 0.3, 25.0), Vector3.UP, "water")
		5:
			Vfx.muzzle_flash(_gun, Vector3(0.0, 0.0, -1.6), 1.0)
		6:
			Vfx.wreck_smoke(WRECK_POS, 1.2, 30.0)
		7:
			Vfx.flare(Vector3(0.0, 60.0, -30.0), Vector3(40.0, 0.0, 0.0), 4.0)
			Vfx.flare(Vector3(0.0, 62.0, -28.0), Vector3(36.0, 0.0, 6.0), 4.0)
			Vfx.flare(Vector3(4.0, 58.0, -34.0), Vector3(44.0, 0.0, -4.0), 4.0)
		8:
			_missile.position = Vector3(-140.0, 25.0, -120.0)
			_missile.look_at(_missile.position + Vector3(70.0, -4.0, 45.0), Vector3.UP)
			_missile.visible = true
			_missile_vel = Vector3(70.0, -4.0, 45.0)
			_missile_age = 0.0
			_missile_trail = Vfx.attach_trail(_missile, "missile")
		9:
			Vfx.explosion(Vector3(60.0, 0.0, -50.0), 0.8, "ground")
			Vfx.wreck_smoke(Vector3(-60.0, 0.0, -10.0), 0.8, 20.0)
		10:
			Vfx.explosion(Vector3(100.0, 40.0, -20.0), 0.6, "air")
			Vfx.muzzle_flash(_gun, Vector3(0.0, 0.0, -1.6), 1.0)
		11:
			if is_instance_valid(_wreck_trail):
				Vfx.stop_trail(_wreck_trail)
			_wreck_trail = Vfx.attach_trail(_wreck_box, "smoke_heavy", Vector3(0.0, 1.5, 0.0))
	# The heavy wreck smoke trail runs from step 11 until step 4 of the next loop.
	if step == 4 and _wreck_trail != null:
		Vfx.stop_trail(_wreck_trail)
		_wreck_trail = null


func _save_shot(cycle: int) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_shot_dir.path_join("shot_%02d.png" % _shots_taken))
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("shot %d cycle %d draw_calls %d" % [_shots_taken, cycle, draws])
	_shots_taken += 1
	if _shots_taken >= SHOTS:
		get_tree().quit()


func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = false
	add_child(sun)


func _add_plane(pos: Vector3, size: Vector2, color: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)


func _add_box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi
