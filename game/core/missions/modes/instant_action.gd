class_name InstantActionMission
extends Mission
## Instant action: waves of enemy fighters come in from ahead of the player. The next wave spawns once wave_gap_s has
## passed since the last one and the live count is under max_alive. The sortie is won when the last wave is down.

var _rng := RandomNumberGenerator.new()
var _fighters: Array = []  ## enemy fighter ids for this difficulty
var _enemies: Array = []  ## every enemy aircraft spawned so far
var _waves := 0  ## waves spawned so far
var _gap_left := 0.0  ## s until the next wave may spawn


func _prepare() -> void:
	_rng.seed = int(plan["seed"]) + 101
	var roster: Dictionary = MissionGenerator.data()["enemy"]
	_fighters = roster["fighters"][String(plan["difficulty"])]
	objectives.add("wave", "", Vector3.ZERO, null, false)
	_show()


func _on_begin() -> void:
	_spawn_wave()


func _tick(delta: float) -> void:
	var win_wave := int(tuning["win_wave"])
	var alive := count_alive(_enemies)
	if _waves >= win_wave and alive == 0:
		victory("All %d waves cleared" % win_wave)
		return
	_gap_left -= delta
	if _waves < win_wave and _gap_left <= 0.0 and alive < int(tuning["max_alive"]):
		_spawn_wave()
	_show()


func _show() -> void:
	objectives.set_text("wave", "Wave %d of %d, %d enemies left" % [_waves, int(tuning["win_wave"]), count_alive(_enemies)])


## One wave, placed spawn_km ahead of the player's nose and flying back at them. Waits while the player is down.
func _spawn_wave() -> void:
	var p = _player()
	if p == null:
		return
	var room := int(tuning["max_alive"]) - count_alive(_enemies)
	var size := mini(int(tuning["first_wave"]) + _waves * int(tuning["wave_add"]), room)
	if size <= 0:
		return
	_waves += 1
	_gap_left = float(tuning["wave_gap_s"])
	var here := WorldOrigin.to_world(p.position)
	var h := deg_to_rad(float(p.get_heading_deg()))
	var ahead := Vector2(sin(h), -cos(h))
	var centre := Vector2(here.x, here.z) + ahead * float(tuning["spawn_km"]) * 1000.0
	var perp := Vector2(-ahead.y, ahead.x)
	var heading := _bearing_to(centre, Vector2(here.x, here.z))
	for i in size:
		var xz := centre + perp * (float(i) - float(size - 1) * 0.5) * 400.0
		var ground := maxf(Ground.world_height_at(xz.x, xz.y), Ground.sea_level)
		var entry := {
			"id": String(_fighters[_rng.randi() % _fighters.size()]),
			"team": 1,
			"pos": Vector3(xz.x, ground + float(tuning["alt_m"]), xz.y),
			"heading": heading,
			"speed_kmh": 520.0,
			"role": "fighter",
		}
		var ac := MissionSpawner.spawn_aircraft_entry(_level.world, entry, float(plan["skill"]))
		if ac != null:
			_enemies.append(ac)


static func _bearing_to(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
