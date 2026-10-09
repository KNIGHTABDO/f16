class_name WeaponSystem
extends Node
## Per-aircraft weapons manager (child "Weapons" of an Aircraft): gun, pylon loadout, flares, target selection,
## lock-on, CCIP and incoming-missile tracking. Public API is described in tasks/weapons.md; the HUD and the AI read
## the getters, Aircraft calls setup() once and tick() every physics step.

signal weapon_changed
signal target_changed(target: Node3D)
signal lock_changed(state: int)
signal fired(weapon_id: String)

const WEAPONS_PATH := "res://data/weapons.json"
const GUN_FIRE_RANGE_FACTOR := 1.0
const VISIBLE_RANGE := 20000.0
const VISIBLE_REFRESH := 0.2  ## 5 Hz
const CCIP_REFRESH := 0.1  ## 10 Hz
const CCIP_STEP := 0.2
const LAUNCH_COOLDOWN := 0.45
const ROCKET_PAIR_INTERVAL := 0.07
const ROCKET_PAIRS_PER_TRIGGER := 6
const FLARES_PER_PRESS := 4
const FLARE_BURST_DELAY := 0.25
const FLARE_LIFE := 4.0
const AUTO_TARGET_CONE_DEG := 12.0  ## gun target / auto selection cone
const LOCK_TIME := {"ir_missile": 1.2, "radar_missile": 1.5, "ag_missile": 1.0, "guided_bomb": 1.0}
const LOCK_DECAY := 2.0  ## lock progress lost per lock-time unit when the target leaves the cone
const AUTO_DROP_TIME := 1.0  ## an automatically selected target is released after this long out of the cone
const TONE_VOLUME_DB := -6.0

enum Lock { NONE, SEEKING, LOCKING, LOCKED }

static var _weapon_db: Dictionary = {}

var aircraft: Aircraft
var gun: Gun
var flares := 0
var _list: Array[Dictionary] = []  ## {id, name, type, count, data, visuals: Array[Node3D]}
var _selected := 0
var _target: Node3D
var _manual_target := false
var _lock_state := Lock.NONE
var _lock_progress := 0.0
var _visible: Array[Node3D] = []
var _incoming: Array[Node3D] = []
var _gun_target: Node3D
var _lead := Vector3.ZERO
var _ccip := Vector3.INF
var _vis_t := 0.0
var _ccip_t := 0.0
var _cooldown := 0.0
var _off_cone_t := 0.0
var _side := 1.0
var _rocket_pairs := 0
var _rocket_t := 0.0
var _flare_queue := 0
var _flare_t := 0.0
var _tone: AudioStreamPlayer
var _tone_name := ""
var _hardpoints: Array[Vector3] = []
var _next_slot := 0


static func weapon_db() -> Dictionary:
	if _weapon_db.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPONS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_weapon_db = parsed
	return _weapon_db


## loadout "" = the aircraft's default loadout.
func setup(ac: Aircraft, loadout: String) -> void:
	aircraft = ac
	var db := weapon_db()
	var d := ac.data
	flares = d.flares
	if d.gun_weapon != "" and db.has(d.gun_weapon):
		gun = Gun.new()
		gun.name = "Gun"
		add_child(gun)
		gun.setup(ac, d.gun_weapon, db, d.gun_ammo, d.gun_muzzles)
	_hardpoints = WeaponModels.hardpoint_positions(d.wing_span, d.length, d.hardpoints)
	for entry in d.loadout(loadout):
		var id := str(entry.get("weapon", ""))
		if not db.has(id):
			continue
		var w: Dictionary = db[id]
		var item := {"id": id, "name": str(w.get("name", id)), "type": str(w.get("type", "")),
				"count": int(entry.get("count", 1)), "data": w, "visuals": []}
		_list.append(item)
		_build_visuals(item)
	_selected = 0
	weapon_changed.emit()


func _build_visuals(item: Dictionary) -> void:
	var w: Dictionary = item.data
	var visuals: Array = item.visuals
	var shown := mini(int(item.count), 2 if item.type == "rocket" else 8)
	for i in shown:
		if _next_slot >= _hardpoints.size():
			break
		var node := WeaponModels.build(str(item.id), w)
		if item.type == "rocket":
			node.scale = Vector3(5.0, 5.0, 1.0)
		node.position = _hardpoints[_next_slot]
		_next_slot += 1
		aircraft.add_child(node)
		visuals.append(node)


# ----- public getters -----

func get_selected() -> Dictionary:
	if _list.is_empty():
		return {"id": "", "name": "", "type": "none", "count": 0}
	var it := _list[_selected]
	return {"id": it.id, "name": it.name, "type": it.type, "count": it.count}


func get_weapon_list() -> Array:
	var out := []
	for i in _list.size():
		var it := _list[i]
		out.append({"id": it.id, "name": it.name, "type": it.type, "count": it.count, "selected": i == _selected})
	return out


func select_next() -> void:
	if _list.size() < 2:
		return
	var start := _selected
	for _i in _list.size():
		_selected = (_selected + 1) % _list.size()
		if int(_list[_selected].count) > 0:
			break
	if _selected == start:
		return
	_on_selection_changed()


func get_gun_ammo() -> int:
	return gun.ammo if gun != null else 0


func get_gun_ammo_max() -> int:
	return gun.ammo_max if gun != null else 0


func get_flares() -> int:
	return flares


func get_target() -> Node3D:
	return _target if _target != null and is_instance_valid(_target) else null


func set_target(node: Node3D) -> void:
	_manual_target = node != null
	_assign_target(node)


## Selects the next valid target for the selected weapon, nearest to the boresight first.
func cycle_target() -> void:
	var cands := _candidates()
	if cands.is_empty():
		set_target(null)
		return
	var idx := cands.find(get_target())
	set_target(cands[(idx + 1) % cands.size()])


func get_lock_state() -> int:
	return _lock_state


func get_lock_progress() -> float:
	return _lock_progress


func get_gun_lead_point() -> Vector3:
	return _lead


func get_gun_range() -> float:
	return gun.get_range() if gun != null else 0.0


## Estimated impact point of the selected bomb / rocket (Vector3.INF if none).
func get_ccip_point() -> Vector3:
	return _ccip


func get_visible_targets() -> Array[Node3D]:
	return _visible


func get_incoming_missiles() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for m in _incoming:
		if is_instance_valid(m) and m.is_inside_tree():
			out.append(m)
	return out


## Called by missiles that start guiding on this aircraft.
func add_incoming(m: Node3D) -> void:
	if not _incoming.has(m):
		_incoming.append(m)


func remove_incoming(m: Node3D) -> void:
	_incoming.erase(m)


# ----- per tick -----

func tick(controls: ControlInput, delta: float) -> void:
	if aircraft == null or not aircraft.alive:
		_set_tone("")
		if gun != null:
			gun.tick(false, delta, Vector3.ZERO)
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	_vis_t -= delta
	if _vis_t <= 0.0:
		_vis_t = VISIBLE_REFRESH
		_refresh_visible()
	if controls.cycle_weapon:
		select_next()
	if controls.cycle_target:
		cycle_target()
	_validate_target()
	_update_gun(controls, delta)
	_update_lock(delta)
	_update_ccip(delta)
	if controls.fire_weapon:
		_fire_selected()
	_update_rocket_queue(delta)
	if controls.drop_flares:
		_drop_flares()
	_update_flare_queue(delta)


func _refresh_visible() -> void:
	_visible.clear()
	var pos := aircraft.global_position
	for n in get_tree().get_nodes_in_group("damageable"):
		var node := n as Node3D
		if node == null or node == aircraft or not Targeting.is_valid_target(node, aircraft.team):
			continue
		if node.global_position.distance_squared_to(pos) <= VISIBLE_RANGE * VISIBLE_RANGE:
			_visible.append(node)
	# Automatic target for guided weapons when nothing is selected.
	if _target == null or not is_instance_valid(_target):
		var best := _best_in_cone(_selected_cone())
		if best != null:
			_assign_target(best)


func _selected_data() -> Dictionary:
	return _list[_selected].data if not _list.is_empty() else {}


func _selected_type() -> String:
	return str(_list[_selected].type) if not _list.is_empty() else ""


func _needs_lock() -> bool:
	return LOCK_TIME.has(_selected_type())


func _selected_cone() -> float:
	if _needs_lock():
		return deg_to_rad(float(_selected_data().get("lock_fov_deg", 30.0)))
	return deg_to_rad(AUTO_TARGET_CONE_DEG)


func _valid_for_selected(n: Node3D) -> bool:
	var t := _selected_type()
	if t == "" or t == "none":
		return true
	var kinds: Array = _selected_data().get("targets", [])
	if kinds.is_empty():
		return true
	return kinds.has(Targeting.kind_of(n))


## Valid targets sorted by angle off the nose.
func _candidates() -> Array[Node3D]:
	var nose := aircraft.get_nose()
	var pos := aircraft.global_position
	var scored: Array = []
	for n in _visible:
		if is_instance_valid(n) and _valid_for_selected(n):
			scored.append([Targeting.angle_off(pos, nose, n.global_position), n])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Node3D] = []
	for s in scored:
		out.append(s[1])
	return out


func _best_in_cone(cone: float) -> Node3D:
	var nose := aircraft.get_nose()
	var pos := aircraft.global_position
	var best: Node3D = null
	var best_a := cone
	var max_range := float(_selected_data().get("range", VISIBLE_RANGE))
	for n in _visible:
		if not is_instance_valid(n) or not _valid_for_selected(n):
			continue
		if n.global_position.distance_to(pos) > max_range:
			continue
		var a := Targeting.angle_off(pos, nose, n.global_position)
		if a < best_a:
			best_a = a
			best = n
	return best


func _assign_target(n: Node3D) -> void:
	if n == _target:
		return
	_target = n
	_lock_progress = 0.0
	_off_cone_t = 0.0
	if n == null:
		_manual_target = false
	target_changed.emit(n)
	_update_lock(0.0)


func _validate_target() -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or not Targeting.is_valid_target(_target, aircraft.team):
		_target = null
		_manual_target = false
		_lock_progress = 0.0
		target_changed.emit(null)


func _on_selection_changed() -> void:
	_rocket_pairs = 0
	if _target != null and is_instance_valid(_target) and not _valid_for_selected(_target):
		_manual_target = false
		_assign_target(null)
	_lock_progress = 0.0
	_ccip = Vector3.INF
	_set_lock_state(Lock.NONE)
	weapon_changed.emit()


func _update_gun(controls: ControlInput, delta: float) -> void:
	if gun == null:
		return
	var pos := aircraft.global_position
	_gun_target = get_target()
	if _gun_target == null:
		_gun_target = _best_in_cone(deg_to_rad(AUTO_TARGET_CONE_DEG))
		if _gun_target != null and (not Targeting.is_valid_target(_gun_target, aircraft.team)):
			_gun_target = null
	var assist := Vector3.ZERO
	if _gun_target != null:
		_lead = Targeting.lead_point(pos, aircraft.velocity, _gun_target.global_position,
				Targeting.velocity_of(_gun_target), gun.get_muzzle_velocity())
		assist = (_lead - pos).normalized()
	else:
		_lead = pos + aircraft.get_nose() * gun.get_range() * 0.6
	var firing := controls.fire_gun or (Settings.auto_fire and aircraft.is_player and _gun_target != null
			and _gun_target.global_position.distance_to(pos) < gun.get_range() * 0.8
			and Targeting.angle_off(pos, aircraft.get_nose(), _lead) < deg_to_rad(2.0))
	gun.tick(firing, delta, assist)


func _update_lock(delta: float) -> void:
	if not _needs_lock():
		_set_lock_state(Lock.NONE)
		_lock_progress = 0.0
		_set_tone("")
		return
	var tgt := get_target()
	if tgt == null:
		_lock_progress = 0.0
		_set_lock_state(Lock.SEEKING)
		_set_tone("")
		return
	var w := _selected_data()
	var pos := aircraft.global_position
	var in_cone := Targeting.angle_off(pos, aircraft.get_nose(), tgt.global_position) \
			<= deg_to_rad(float(w.get("lock_fov_deg", 30.0)))
	var rng := float(w.get("range", 1.0e9))
	var dist := pos.distance_to(tgt.global_position)
	var lt: float = LOCK_TIME[_selected_type()]
	if in_cone and dist <= rng:
		_off_cone_t = 0.0
		_lock_progress = minf(_lock_progress + delta / lt, 1.0)
	else:
		_lock_progress = maxf(_lock_progress - delta / lt * LOCK_DECAY, 0.0)
		_off_cone_t += delta
		if not _manual_target and _off_cone_t > AUTO_DROP_TIME:
			_assign_target(null)
			return
	if _lock_progress >= 1.0:
		_set_lock_state(Lock.LOCKED)
		_set_tone("lock_solid")
	elif _lock_progress > 0.0:
		_set_lock_state(Lock.LOCKING)
		_set_tone("lock_tone")
	else:
		_set_lock_state(Lock.SEEKING)
		_set_tone("")


func _set_lock_state(s: int) -> void:
	if s == _lock_state:
		return
	_lock_state = s as Lock
	lock_changed.emit(s)


func _set_tone(sound: String) -> void:
	if sound != "" and not aircraft.is_player:
		sound = ""
	if sound == _tone_name:
		return
	_tone_name = sound
	if _tone != null and is_instance_valid(_tone):
		_tone.queue_free()
		_tone = null
	if sound != "":
		_tone = Sfx.loop_2d(sound, TONE_VOLUME_DB)


func _update_ccip(delta: float) -> void:
	_ccip_t -= delta
	if _ccip_t > 0.0:
		return
	_ccip_t = CCIP_REFRESH
	var t := _selected_type()
	var pos := aircraft.global_position
	if t == "bomb" or t == "guided_bomb":
		_ccip = Targeting.bomb_impact(pos, aircraft.velocity, float(_selected_data().get("drag", 0.1)), CCIP_STEP)
	elif t == "rocket":
		var v := aircraft.velocity + aircraft.get_nose() * float(_selected_data().get("speed_max", 740.0)) * 0.85
		_ccip = Targeting.bomb_impact(pos, v, 0.0, CCIP_STEP)
	else:
		_ccip = Vector3.INF


# ----- firing -----

func _world() -> Node:
	return aircraft.get_parent()


func _pop_visual(item: Dictionary) -> Vector3:
	var visuals: Array = item.visuals
	var pick := -1
	for i in range(visuals.size() - 1, -1, -1):
		var n := visuals[i] as Node3D
		if signf(n.position.x) == _side or n.position.x == 0.0:
			pick = i
			break
	if pick < 0 and not visuals.is_empty():
		pick = visuals.size() - 1
	_side = -_side
	if pick < 0:
		return Vector3(_side * aircraft.data.wing_span * 0.2, -0.6, 0.0)
	var node := visuals[pick] as Node3D
	var local_pos := node.position
	node.queue_free()
	visuals.remove_at(pick)
	return local_pos


func _fire_selected() -> void:
	if _list.is_empty() or _cooldown > 0.0:
		return
	var item := _list[_selected]
	if int(item.count) <= 0:
		select_next()
		return
	var w: Dictionary = item.data
	var t := str(item.type)
	var tgt := get_target()
	match t:
		"ir_missile", "radar_missile", "ag_missile":
			var locked := _lock_state == Lock.LOCKED and tgt != null
			if locked and aircraft.global_position.distance_to(tgt.global_position) < float(w.get("min_range", 0.0)):
				return
			var lp := _pop_visual(item)
			var xf := Transform3D(aircraft.global_transform.basis, aircraft.to_global(lp))
			Missile.launch(_world(), aircraft, str(item.id), w, tgt if locked else null, xf, aircraft.velocity)
			_consumed(item, 1, 1.0)
		"bomb", "guided_bomb":
			var lp := _pop_visual(item)
			var xf := Transform3D(aircraft.global_transform.basis, aircraft.to_global(lp))
			var bt: Node3D = tgt if (t == "guided_bomb" and tgt != null) else null
			Bomb.launch(_world(), aircraft, str(item.id), w, bt, xf, aircraft.velocity + aircraft.global_transform.basis.y * -2.0)
			_consumed(item, 1, 0.8)
		"rocket":
			if _rocket_pairs <= 0:
				_rocket_pairs = ROCKET_PAIRS_PER_TRIGGER
				_rocket_t = 0.0
	if t != "rocket":
		_cooldown = LAUNCH_COOLDOWN


func _consumed(item: Dictionary, n: int, haptic: float) -> void:
	item.count = maxi(int(item.count) - n, 0)
	fired.emit(str(item.id))
	Events.weapon_fired.emit(aircraft, str(item.id))
	if aircraft.is_player:
		Sfx.haptic(haptic, 60)
	if int(item.count) <= 0:
		select_next()
	weapon_changed.emit()


func _update_rocket_queue(delta: float) -> void:
	if _rocket_pairs <= 0:
		return
	_rocket_t -= delta
	if _rocket_t > 0.0:
		return
	_rocket_t = ROCKET_PAIR_INTERVAL
	var item := _list[_selected]
	if str(item.type) != "rocket" or int(item.count) <= 0:
		_rocket_pairs = 0
		return
	var w: Dictionary = item.data
	var spread := float(w.get("spread_mrad", 8.0)) * 0.001
	var basis := aircraft.global_transform.basis
	var salvo := int(w.get("salvo", 2))
	for k in mini(salvo, int(item.count)):
		var side := 1.0 if k % 2 == 0 else -1.0
		var lp := Vector3(side * aircraft.data.wing_span * 0.28, -0.5, -aircraft.data.length * 0.1)
		var dir := (-basis.z + basis.x * randfn(0.0, spread) + basis.y * randfn(0.0, spread)).normalized()
		var xf := Transform3D(Basis.looking_at(dir, basis.y), aircraft.to_global(lp))
		Rocket.launch(_world(), aircraft, str(item.id), w, xf, aircraft.velocity + dir * 40.0)
		item.count = int(item.count) - 1
		_remove_rocket_visual(item)
	_rocket_pairs -= 1
	fired.emit(str(item.id))
	Events.weapon_fired.emit(aircraft, str(item.id))
	if aircraft.is_player:
		Sfx.haptic(0.4, 25)
	if int(item.count) <= 0:
		_rocket_pairs = 0
		select_next()
	weapon_changed.emit()


func _remove_rocket_visual(item: Dictionary) -> void:
	var visuals: Array = item.visuals
	var total := int(item.count)
	# Pods disappear only when the rockets are used up.
	if total <= 0:
		for v in visuals:
			(v as Node3D).queue_free()
		visuals.clear()


func _drop_flares() -> void:
	if flares <= 0:
		return
	_spawn_flare_pair()
	_flare_queue = 1
	_flare_t = FLARE_BURST_DELAY
	Events.flares_dropped.emit(aircraft)


func _update_flare_queue(delta: float) -> void:
	if _flare_queue <= 0:
		return
	_flare_t -= delta
	if _flare_t <= 0.0:
		_flare_queue -= 1
		if flares > 0:
			_spawn_flare_pair()


func _spawn_flare_pair() -> void:
	var n := mini(FLARES_PER_PRESS / 2, flares)
	var basis := aircraft.global_transform.basis
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := aircraft.to_global(Vector3(side * 0.8, -0.8, aircraft.data.length * 0.3))
		var v := aircraft.velocity * 0.5 + basis.x * side * randf_range(10.0, 20.0) \
				- basis.y * randf_range(4.0, 9.0) + basis.z * randf_range(5.0, 15.0)
		Vfx.flare(p, v, FLARE_LIFE)
		flares -= 1


func _exit_tree() -> void:
	_set_tone("")
