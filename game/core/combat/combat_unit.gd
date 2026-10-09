class_name CombatUnit
extends Node3D
## Shared base class for all ground/sea combat units and structures.
## Conforms to the Damageable contract (docs/ARCHITECTURE.md).

signal destroyed(killer: Node)
signal damaged(amount: float, source: Node)

const LAYER_GROUND := 4  # bitmask for layer 3 (1 << 2)
const LAYER_STRUCTURE := 8  # bitmask for layer 4 (1 << 3)
const LOD_FREEZE_DIST := 15000.0
const LOW_TICK_RATE := 10.0  # 10 Hz when idle/not engaging

var team: int = 1
var alive: bool = true
var max_health: float = 100.0
var health: float = 100.0
var unit_kind: String = "vehicle"
var velocity: Vector3 = Vector3.ZERO
var size: Vector3 = Vector3(3, 2, 6)

var hitbox: Hitbox
var visual: Node3D
var wreck_visual: Node3D
var is_engaging: bool = false

var _tick_accum: float = 0.0
var _low_tick_interval: float = 1.0 / LOW_TICK_RATE
var _cam_frozen: bool = false


func _ready() -> void:
	add_to_group("damageable")
	add_to_group("floating")
	add_to_group("team_%d" % team)
	_build_hitbox()
	if visual == null:
		_build_visuals()
	WorldOrigin.shifted.connect(_on_origin_shifted)


func setup_unit(p_kind: String, p_team: int, p_hp: float = 0.0) -> void:
	unit_kind = p_kind
	team = p_team
	size = UnitModels.get_size(unit_kind)
	if p_hp > 0.0:
		max_health = p_hp
	else:
		max_health = _default_health(unit_kind)
	health = max_health


func _default_health(kind: String) -> float:
	match kind:
		"tank": return 180.0
		"apc": return 120.0
		"truck", "fuel_truck": return 60.0
		"sam_sa6", "sam_sa15": return 140.0
		"sam_sa2": return 100.0
		"manpads": return 30.0
		"aaa_zsu": return 130.0
		"aaa_bofors": return 90.0
		"radar": return 100.0
		"patrol_boat": return 250.0
		"frigate": return 1200.0
		"cargo_ship": return 800.0
		"hangar": return 500.0
		"shelter": return 600.0
		"fuel_tank": return 150.0
		"bunker": return 700.0
		"tower": return 200.0
		"ammo_dump": return 200.0
		"comms": return 250.0
		"bridge", "bridges": return 1500.0
		_: return 100.0


func _build_hitbox() -> void:
	hitbox = Hitbox.new()
	hitbox.name = "Hitbox"
	hitbox.target = self
	var is_struct := get_target_kind() == "structure"
	hitbox.collision_layer = LAYER_STRUCTURE if is_struct else LAYER_GROUND
	hitbox.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	hitbox.add_child(shape)
	add_child(hitbox)


func _build_visuals() -> void:
	visual = UnitModels.build(unit_kind, false)
	add_child(visual)


func take_damage(amount: float, source: Node, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if not alive:
		return
	health = maxf(health - amount, 0.0)
	Events.damaged.emit(self, amount, source)
	damaged.emit(amount, source)
	_on_damaged(amount, source)
	if health <= 0.0:
		_die(source, hit_pos)


func _on_damaged(_amount: float, _source: Node) -> void:
	# Subclasses can implement evasion / alert reactions
	pass


func _die(killer: Node, hit_pos: Vector3) -> void:
	alive = false
	remove_from_group("damageable")
	if is_in_group("radars"):
		remove_from_group("radars")
	if hitbox != null and is_instance_valid(hitbox):
		hitbox.monitorable = false

	var death_pos := hit_pos if hit_pos != Vector3.ZERO else (global_position + Vector3.UP * (size.y * 0.5))
	Events.target_destroyed.emit(self, killer)
	destroyed.emit(killer)

	var expl_size := _explosion_size()
	Events.explosion.emit(death_pos, expl_size)
	_spawn_wreck(death_pos)
	_handle_secondary_explosions(death_pos)


func _explosion_size() -> float:
	match unit_kind:
		"fuel_tank": return 3.5
		"ammo_dump": return 3.0
		"frigate", "cargo_ship": return 2.8
		"hangar", "shelter", "bridge", "bridges": return 2.5
		"tank", "sam_sa6", "sam_sa15", "patrol_boat": return 1.6
		"manpads": return 0.6
		_: return 1.2


func _handle_secondary_explosions(pos: Vector3) -> void:
	if unit_kind == "fuel_tank" or unit_kind == "fuel_truck":
		# Big secondary fireball sequence
		for i in 3:
			var delay := 0.2 + float(i) * 0.35
			var jitter := Vector3(randf_range(-6, 6), randf_range(1, 4), randf_range(-6, 6))
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				Events.explosion.emit(pos + jitter, 2.2)
			)
	elif unit_kind == "ammo_dump":
		# Munition cook-offs
		for i in 4:
			var delay := 0.25 + float(i) * 0.4
			var jitter := Vector3(randf_range(-8, 8), randf_range(1, 3), randf_range(-8, 8))
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				Events.explosion.emit(pos + jitter, 1.4)
			)


func _spawn_wreck(death_pos: Vector3) -> void:
	if visual != null and is_instance_valid(visual):
		visual.visible = false
	wreck_visual = UnitModels.build(unit_kind, true)
	add_child(wreck_visual)
	wreck_visual.rotation.z = randf_range(-0.08, 0.08)
	wreck_visual.rotation.x = randf_range(-0.06, 0.06)

	var smoke_size := maxf(1.0, size.x * 0.35)
	Vfx.wreck_smoke(death_pos, smoke_size, 90.0)


func get_target_kind() -> String:
	match unit_kind:
		"tank", "apc": return "armor"
		"truck", "fuel_truck": return "vehicle"
		"sam_sa6", "sam_sa2", "sam_sa15", "manpads": return "sam"
		"aaa_zsu", "aaa_bofors": return "aaa"
		"patrol_boat", "frigate", "cargo_ship": return "ship"
		_: return "structure"


func get_velocity() -> Vector3:
	return velocity if alive else Vector3.ZERO


func get_hit_radius() -> float:
	return maxf(size.x, size.z) * 0.5


func _physics_process(delta: float) -> void:
	if not alive:
		return

	# Performance LOD: check distance to active camera
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d := global_position.distance_to(cam.global_position)
		if d > LOD_FREEZE_DIST:
			if not _cam_frozen:
				_cam_frozen = true
				if visual != null:
					visual.visible = false
			return
		elif _cam_frozen:
			_cam_frozen = false
			if visual != null:
				visual.visible = true

	# Cheap 10 Hz tick unless actively engaging
	if not is_engaging:
		_tick_accum += delta
		if _tick_accum < _low_tick_interval:
			return
		unit_tick(_tick_accum)
		_tick_accum = 0.0
	else:
		unit_tick(delta)


func unit_tick(_dt: float) -> void:
	# Subclasses implement unit logic here
	pass


func _on_origin_shifted(_delta: Vector3) -> void:
	# Subclasses can rebase cached waypoints if needed
	pass


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if WorldOrigin != null and WorldOrigin.shifted.is_connected(_on_origin_shifted):
			WorldOrigin.shifted.disconnect(_on_origin_shifted)
