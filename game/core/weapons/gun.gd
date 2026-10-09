class_name Gun
extends Node
## Aircraft cannon. Spawns rounds into the shared BulletPool; handles rate, ammo, spread, sound and aim assist.

const ASSIST_CONE_DEG := 1.5
const ASSIST_STRENGTH := 0.65  ## fraction of the angle toward the lead point that is removed
const FLASH_EVERY := 3  ## muzzle flash every Nth round
const TAIL_MIN_FIRE_S := 0.4

signal fired

var weapon_id := ""
var wdata: Dictionary = {}
var ammo := 0
var ammo_max := 0
var aircraft: Aircraft
var muzzles: Array[Vector3] = []

var _acc := 0.0
var _round := 0
var _muzzle_i := 0
var _pool: BulletPool
var _loop: AudioStreamPlayer3D
var _firing := false
var _fire_time := 0.0
var _exclude: Array = []
var _rng := RandomNumberGenerator.new()


func setup(ac: Aircraft, id: String, weapons: Dictionary, ammo_count: int, muzzle_list: Array[Vector3]) -> void:
	aircraft = ac
	weapon_id = id
	wdata = weapons.get(id, {})
	ammo = ammo_count
	ammo_max = ammo_count
	muzzles = muzzle_list
	if muzzles.is_empty():
		muzzles.append(Vector3(0, 0, -ac.data.length * 0.3))
	_rng.randomize()
	var hb := ac.get_node_or_null("Hitbox") as Hitbox
	if hb != null:
		_exclude = [hb.get_rid()]


func get_range() -> float:
	return float(wdata.get("range", 2000.0))


func get_muzzle_velocity() -> float:
	return float(wdata.get("muzzle_velocity", 900.0))


## `assist_dir` is a unit vector toward the lead point (or ZERO) used for arcade aim magnetism.
func tick(firing: bool, delta: float, assist_dir: Vector3) -> void:
	if wdata.is_empty():
		return
	firing = firing and ammo > 0 and aircraft.alive
	if firing:
		if _pool == null:
			_pool = BulletPool.get_pool(aircraft)
		_fire_time += delta
		var rate := float(wdata.rpm) / 60.0
		_acc += delta * rate
		var count := mini(int(_acc), 40)
		_acc -= floorf(_acc)
		if count > 0:
			_fire_rounds(count, rate, delta, assist_dir)
		if not _firing:
			_start_loop()
	else:
		_acc = minf(_acc, 1.0)
		if _firing:
			_stop_loop()
	_firing = firing


func _fire_rounds(count: int, rate: float, delta: float, assist_dir: Vector3) -> void:
	var basis := aircraft.global_transform.basis
	var fwd := -basis.z
	var mv := get_muzzle_velocity()
	var spread := float(wdata.get("spread_mrad", 4.0)) * 0.001
	var tracer_every := int(wdata.get("tracer_every", 3))
	var dmg := float(wdata.damage)
	var life := get_range() / mv * 1.1
	var assist := Vector3.ZERO
	if assist_dir != Vector3.ZERO and Settings.flight_mode == "arcade" and aircraft.is_player:
		assist = assist_dir
	var base_dir := fwd
	if assist != Vector3.ZERO and fwd.angle_to(assist) < deg_to_rad(ASSIST_CONE_DEG):
		base_dir = fwd.slerp(assist, ASSIST_STRENGTH)
	for k in count:
		if ammo <= 0:
			break
		ammo -= 1
		_round += 1
		var m := muzzles[_muzzle_i % muzzles.size()]
		_muzzle_i += 1
		var dir := base_dir
		var side := basis.x
		var up := basis.y
		dir = (dir + side * _rng.randfn(0.0, spread * 0.5) + up * _rng.randfn(0.0, spread * 0.5)).normalized()
		# Rounds fired within this tick are spread along the tick so the stream is continuous.
		# Rounds fired earlier within this tick have already travelled a little (continuous stream).
		var adv := delta * (1.0 - float(k) / float(count))
		var vel := aircraft.velocity + dir * mv
		_pool.spawn(aircraft.to_global(m) + dir * mv * adv, vel, life, dmg,
				_round % maxi(tracer_every, 1) == 0, aircraft, _exclude)
		if _round % FLASH_EVERY == 0:
			Vfx.muzzle_flash(aircraft, m, 1.0)
	Events.weapon_fired.emit(aircraft, weapon_id)
	fired.emit()


func _start_loop() -> void:
	_fire_time = 0.0
	if _loop == null or not is_instance_valid(_loop):
		_loop = Sfx.attach_loop(str(wdata.get("sound", "gun_vulcan")), aircraft, 0.0)
	elif not _loop.playing:
		_loop.play()


func _stop_loop() -> void:
	if _loop != null and is_instance_valid(_loop):
		_loop.stop()
	if _fire_time > TAIL_MIN_FIRE_S:
		Sfx.play_3d("gun_tail", aircraft.global_position)
	_fire_time = 0.0
