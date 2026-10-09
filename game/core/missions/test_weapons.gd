extends Node3D
## Weapons test (scenes/test_weapons.tscn). Runs an automated sortie that must kill an intended target with every
## weapon: gun, AIM-9X, AIM-120C, Mk 82 (ground and ship), GBU-12, AGM-65, Hydra rockets, and survives a missile with
## flares. Prints one line per phase and a summary; exit code 1 when a phase fails.
## Run: godot --headless --path game --fixed-fps 60 res://scenes/test_weapons.tscn
## Optional user args (after --): --shot=/tmp/weapons.png saves a screenshot while the gun and a missile fire.

const TAG := "[weapons-test] "
const MAP_ID := "test"
const DT := 1.0 / 60.0
const GUN_TIMEOUT := 70.0
const MISSILE_TIMEOUT := 60.0

var world: Node3D
var player: Aircraft
var enemy: Aircraft
var cam: Camera3D
var results: Array[String] = []
var failures := 0
var shot_path := ""
var shot_taken := 0
var _targets: Array[DummyTarget] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
	Settings.flight_mode = "arcade"
	WorldOrigin.reset()
	if not Ground.load_map(MAP_ID):
		push_error("test_weapons: cannot load map")
		get_tree().quit(1)
		return
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.62, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	add_child(env)
	cam = Camera3D.new()
	cam.far = 40000.0
	cam.current = true
	add_child(cam)
	_run.call_deferred()


func _process(_d: float) -> void:
	if player != null and is_instance_valid(player) and player.alive:
		var b := player.global_transform.basis
		cam.global_position = player.global_position + b.z * 28.0 + b.y * 7.0
		cam.look_at(player.global_position - b.z * 120.0, Vector3.UP)


# ----- helpers -----

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## Waits until cond() or timeout seconds of simulated time; returns the elapsed seconds, -1 on timeout.
func _wait(cond: Callable, timeout: float) -> float:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return t
		await get_tree().physics_frame
		t += DT
	return -1.0


func _clear_world() -> void:
	for n in world.get_children():
		if n.name != "BulletPool":
			n.queue_free()
	_targets.clear()
	player = null
	enemy = null


func _terrain_y(x: float, z: float) -> float:
	return Ground.surface_at(x, z)


func _spawn_player(loadout: String, pos: Vector3, heading: float, kmh := 700.0) -> void:
	GameState.selected_loadout = loadout
	player = Aircraft.create("f16c", 0, true)
	world.add_child(player)
	player.spawn_in_air(pos, heading, kmh)
	player.controls.throttle = 0.8
	WorldOrigin.anchor = null


func _drone(center: Vector3, radius: float, speed: float, hp := 100.0) -> DummyTarget:
	var d := DummyTarget.create("air", 1, hp, Vector3(9, 3, 14))
	d.circle_center = center
	d.circle_radius = radius
	d.speed = speed
	world.add_child(d)
	_targets.append(d)
	return d


func _ground_target(kind: String, x: float, z: float, hp: float, size: Vector3) -> DummyTarget:
	var d := DummyTarget.create(kind, 1, hp, size)
	world.add_child(d)
	d.position = Vector3(x, _terrain_y(x, z) + size.y * 0.5, z)
	_targets.append(d)
	return d


func _steer(point: Vector3) -> void:
	player.controls.use_aim = true
	player.controls.aim_direction = (point - player.global_position).normalized()


func _press_fire() -> void:
	player.controls.fire_weapon = true
	await get_tree().physics_frame
	player.controls.clear_triggers()


func _select(id: String) -> bool:
	for _i in 8:
		if player.weapons.get_selected().id == id:
			return true
		player.weapons.select_next()
	return false


func _report(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	var line := "%s%s: %s  %s" % [TAG, "PASS" if ok else "FAIL", name, detail]
	results.append(line)
	print(line)


func _shot(label: String) -> void:
	if shot_path == "" or DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(shot_path.replace(".png", "_%s.png" % label))
		shot_taken += 1


# ----- phases -----

func _run() -> void:
	await _frames(5)
	var land := Vector2(0.0, 0.0)
	var alt := maxf(2000.0, _terrain_y(land.x, land.y) + 1200.0)
	await _phase_gun(alt)
	await _phase_missile("aim9x", "air_superiority", alt, 3000.0)
	await _phase_missile("aim120c", "air_superiority", alt, 14000.0)
	await _phase_bomb(alt)
	await _phase_gbu()
	await _phase_agm()
	await _phase_rockets()
	await _phase_ship()
	await _phase_flares(alt, false)
	await _phase_flares(alt, true)
	print(TAG + "SUMMARY: %d phases, %d failed" % [results.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _phase_gun(alt: float) -> void:
	_clear_world()
	_spawn_player("air_superiority", Vector3(0, alt, 0), 0.0, 700.0)
	var drone := _drone(Vector3(0, alt, -4200), 1500.0, 130.0)
	var start_ammo: int = player.weapons.get_gun_ammo()
	var t := 0.0
	var fired_ticks := 0
	while t < GUN_TIMEOUT and drone.alive:
		var w: WeaponSystem = player.weapons
		w.set_target(drone)
		var lead := w.get_gun_lead_point()
		_steer(lead)
		var dist := player.global_position.distance_to(drone.global_position)
		var ang := rad_to_deg(player.get_nose().angle_to(lead - player.global_position))
		player.controls.fire_gun = dist < 1400.0 and ang < 1.5
		if player.controls.fire_gun:
			fired_ticks += 1
			if fired_ticks == 40:
				_shot("gun")
		player.controls.throttle = 1.0 if dist > 1000.0 else 0.4
		await get_tree().physics_frame
		t += DT
	player.controls.fire_gun = false
	var used := start_ammo - player.weapons.get_gun_ammo()
	_report("gun vs drone", not drone.alive, "t=%.1fs rounds=%d hp_left=%.0f" % [t, used, drone.health])


func _phase_missile(id: String, loadout: String, alt: float, dist: float) -> void:
	_clear_world()
	_spawn_player(loadout, Vector3(0, alt, 0), 0.0, 800.0)
	var drone := _drone(Vector3(0, alt + 100.0, -dist - 1500.0), 1500.0, 120.0)
	# Drone starts at angle 0 (south of centre, i.e. closest to the player): the circle's nearest point.
	player.weapons.set_target(drone)
	_select(id)
	var locked_t := -1.0
	var t := 0.0
	while t < 20.0:
		_steer(drone.global_position)
		if player.weapons.get_lock_state() == WeaponSystem.Lock.LOCKED:
			locked_t = t
			break
		await get_tree().physics_frame
		t += DT
	if locked_t < 0.0:
		_report(id + " lock", false, "never locked, state=%d progress=%.2f" % [
			player.weapons.get_lock_state(), player.weapons.get_lock_progress()])
		return
	await _press_fire()
	var fire_t := 0.0
	var count_before: int = player.weapons.get_selected().count
	var kill := -1.0
	while fire_t < MISSILE_TIMEOUT:
		_steer(drone.global_position)
		if not drone.alive:
			kill = fire_t
			break
		if fire_t > 1.5 and fire_t < 1.6:
			_shot("missile_" + id)
		await get_tree().physics_frame
		fire_t += DT
	_report(id + " vs drone", kill >= 0.0, "lock=%.1fs time_to_impact=%.1fs launch_dist=%.0fm ammo %d->%d" % [
		locked_t, kill, dist, count_before + 1, count_before])


## Flies level toward `point` at the player's altitude until `cond` is true. Returns elapsed seconds or -1.
func _fly_until(point_xz: Vector2, cond: Callable, timeout: float) -> float:
	var t := 0.0
	while t < timeout:
		_steer(Vector3(point_xz.x, player.global_position.y, point_xz.y))
		if cond.call():
			return t
		await get_tree().physics_frame
		t += DT
	return -1.0


func _phase_bomb(alt: float) -> void:
	_clear_world()
	var agl := 1000.0
	var tank := _ground_target("armor", 0.0, -7000.0, 300.0, Vector3(8, 3, 4))
	_spawn_player("strike", Vector3(0, _terrain_y(0, -1500) + agl, 0), 0.0, 720.0)
	var dropped := 0
	var best_err := 1.0e9
	var t := 0.0
	while t < 60.0 and tank.alive and dropped < 4:
		_steer(Vector3(tank.position.x, player.global_position.y, tank.position.z))
		var ccip: Vector3 = player.weapons.get_ccip_point()
		if ccip != Vector3.INF and player.weapons.get_selected().id == "mk82":
			var err := Vector2(ccip.x - tank.position.x, ccip.z - tank.position.z).length()
			best_err = minf(best_err, err)
			if err < 14.0 and player.weapons.get_selected().count > 0:
				await _press_fire()
				dropped += 1
				await _frames(40)
		elif player.weapons.get_selected().id != "mk82":
			_select("mk82")
		await get_tree().physics_frame
		t += DT
	await _wait(func() -> bool: return not tank.alive, 25.0)
	_report("Mk82 vs tank (CCIP)", not tank.alive, "bombs=%d best_ccip_err=%.0fm t=%.0fs" % [dropped, best_err, t])


func _phase_gbu() -> void:
	_clear_world()
	var tank := _ground_target("sam", 300.0, -9000.0, 300.0, Vector3(8, 4, 8))
	_spawn_player("precision", Vector3(0, _terrain_y(0, -3000) + 2000.0, 0), 0.0, 720.0)
	_select("gbu12")
	player.weapons.set_target(tank)
	var released := false
	var t := 0.0
	while t < 60.0 and tank.alive:
		_steer(tank.position)
		var w: WeaponSystem = player.weapons
		var d := Vector2(tank.position.x - player.global_position.x, tank.position.z - player.global_position.z).length()
		if not released and w.get_lock_state() == WeaponSystem.Lock.LOCKED and d < 5000.0:
			await _press_fire()
			released = true
		if released and not tank.alive:
			break
		await get_tree().physics_frame
		t += DT
	await _wait(func() -> bool: return not tank.alive, 25.0)
	_report("GBU-12 vs SAM", not tank.alive, "released=%s t=%.0fs" % [released, t])


func _phase_agm() -> void:
	_clear_world()
	var tank := _ground_target("armor", -200.0, -8000.0, 300.0, Vector3(8, 3, 4))
	_spawn_player("precision", Vector3(0, _terrain_y(0, -2000) + 800.0, 0), 0.0, 650.0)
	_select("agm65")
	player.weapons.set_target(tank)
	var fired := false
	var t := 0.0
	while t < 70.0 and tank.alive:
		_steer(tank.position)
		if not fired and player.weapons.get_lock_state() == WeaponSystem.Lock.LOCKED:
			var d := player.global_position.distance_to(tank.position)
			if d < 6000.0:
				await _press_fire()
				fired = true
		await get_tree().physics_frame
		t += DT
	await _wait(func() -> bool: return not tank.alive, 20.0)
	_report("AGM-65 vs tank", not tank.alive, "fired=%s t=%.0fs" % [fired, t])


func _phase_rockets() -> void:
	_clear_world()
	var tank := _ground_target("vehicle", 0.0, -4500.0, 250.0, Vector3(8, 3, 4))
	_spawn_player("rockets", Vector3(0, _terrain_y(0, -1500) + 900.0, 0), 0.0, 700.0)
	_select("hydra70")
	var salvos := 0
	var t := 0.0
	while t < 40.0 and tank.alive and salvos < 4:
		_steer(tank.position)
		var d := player.global_position.distance_to(tank.position)
		var ang := rad_to_deg(player.get_nose().angle_to(tank.position - player.global_position))
		if d < 1900.0 and d > 700.0 and ang < 1.0 and player.weapons.get_selected().count > 0:
			await _press_fire()
			salvos += 1
			await _frames(60)
		elif d <= 700.0:
			break
		await get_tree().physics_frame
		t += DT
	await _wait(func() -> bool: return not tank.alive, 10.0)
	_report("Hydra rockets vs tank", not tank.alive, "salvos=%d rockets_left=%d" % [
		salvos, player.weapons.get_selected().count])


func _phase_ship() -> void:
	_clear_world()
	# Find open sea on the map (world coordinates), move the origin there.
	var found := false
	var wx := 0.0
	var wz := 0.0
	var step := 4000.0
	var r := 0.0
	while r < 120000.0 and not found:
		for k in 16:
			var a := TAU * k / 16.0
			var x := r * cos(a)
			var z := r * sin(a)
			if Ground.world_height_at(x, z) < -30.0 and Ground.world_height_at(x - 6000, z) < -30.0 \
					and Ground.world_height_at(x + 6000, z) < -30.0 and Ground.world_height_at(x, z - 12000) < -30.0:
				wx = x
				wz = z
				found = true
				break
		r += step
	if not found:
		_report("Mk82 vs ship", false, "no sea found on the test map")
		return
	WorldOrigin.offset_x = wx
	WorldOrigin.offset_z = wz
	var ship := _ground_target("ship", 0.0, -6000.0, 500.0, Vector3(14, 8, 70))
	_spawn_player("strike", Vector3(0, 900.0, 0), 0.0, 720.0)
	var dropped := 0
	var t := 0.0
	var best := 1.0e9
	while t < 60.0 and ship.alive and dropped < 4:
		_steer(Vector3(ship.position.x, player.global_position.y, ship.position.z))
		var ccip: Vector3 = player.weapons.get_ccip_point()
		if ccip != Vector3.INF and player.weapons.get_selected().id != "mk82":
			_select("mk82")
		elif ccip != Vector3.INF:
			var err := Vector2(ccip.x - ship.position.x, ccip.z - ship.position.z).length()
			best = minf(best, err)
			if err < 20.0 and player.weapons.get_selected().count > 0:
				await _press_fire()
				dropped += 1
				await _frames(40)
		await get_tree().physics_frame
		t += DT
	await _wait(func() -> bool: return not ship.alive, 25.0)
	_report("Mk82 vs ship (sea)", not ship.alive, "bombs=%d best_ccip_err=%.0fm" % [dropped, best])
	WorldOrigin.reset()


func _phase_flares(alt: float, use_flares: bool) -> void:
	_clear_world()
	_spawn_player("air_superiority", Vector3(0, alt, 0), 0.0, 700.0)
	enemy = Aircraft.create("f16c", 1, false)
	world.add_child(enemy)
	enemy.spawn_in_air(Vector3(0, alt, 3500.0), 0.0, 850.0)
	enemy.controls.throttle = 1.0
	enemy.controls.use_aim = true
	enemy.controls.aim_direction = Vector3(0, 0, -1)
	var ew: WeaponSystem = enemy.weapons
	ew.set_target(player)
	_select_for(ew, "aim9x")
	var missile_seen: Missile = null
	var t := 0.0
	var warned := false
	var flares_used := 0
	var switched := false
	while t < 45.0:
		_steer(Vector3(0, alt, -30000.0))
		var lock: int = ew.get_lock_state()
		if lock == WeaponSystem.Lock.LOCKED and missile_seen == null:
			enemy.controls.fire_weapon = true
			await get_tree().physics_frame
			enemy.controls.clear_triggers()
			for m in get_tree().get_nodes_in_group("missiles"):
				missile_seen = m
		if missile_seen != null and is_instance_valid(missile_seen):
			var d := missile_seen.global_position.distance_to(player.global_position)
			if player.weapons.get_incoming_missiles().size() > 0:
				warned = true
			if use_flares and d < 3000.0 and int(t * 60.0) % 20 == 0:
				player.controls.drop_flares = true
			else:
				player.controls.drop_flares = false
			if missile_seen.target != null and missile_seen.target.is_in_group("flares"):
				switched = true
		elif missile_seen != null:
			break
		flares_used = 60 - player.weapons.get_flares()
		await get_tree().physics_frame
		player.controls.clear_triggers()
		t += DT
	await _frames(120)
	var survived := player.alive and player.health > 30.0
	var name := "missile + flares" if use_flares else "missile, no flares (control)"
	var ok := (survived and switched and warned) if use_flares else (missile_seen != null and warned and player.health < 100.0)
	_report(name, ok, "hp=%.0f decoyed=%s warned=%s flares_used=%d" % [player.health, switched, warned, flares_used])


func _select_for(ws: WeaponSystem, id: String) -> void:
	for _i in 8:
		if ws.get_selected().id == id:
			return
		ws.select_next()
