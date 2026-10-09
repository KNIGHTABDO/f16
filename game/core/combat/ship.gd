class_name Ship
extends CombatUnit
## Sea vessel (patrol boat, frigate with SAM+gun, cargo ship).
## Floats at sea level with pitch/roll/heave bobbing, creates wake effects,
## and navigates maritime waypoints.

const BOB_ROLL_AMP := 0.025
const BOB_PITCH_AMP := 0.015
const BOB_HEAVE_AMP := 0.4
const WAKE_INTERVAL := 0.35

var speed_mps: float = 12.0  # ~23 knots
var waypoints: Array[Vector3] = []
var current_wp_idx: int = 0
var is_looping: bool = true

var _bob_timer: float = 0.0
var _wake_timer: float = 0.0
var _sam_subsystem: SamSite = null
var _aaa_subsystem: AAA = null


func _ready() -> void:
	super._ready()
	_snap_to_sea_level()
	_setup_ship_weapons()


func setup_ship(p_kind: String, p_team: int, p_speed_knots: float = 20.0) -> void:
	setup_unit(p_kind, p_team)
	speed_mps = p_speed_knots * 0.51444
	_snap_to_sea_level()
	_setup_ship_weapons()


func set_waypoints(pts: Array, loop := true) -> void:
	waypoints.clear()
	for p in pts:
		var sea_y := Ground.sea_level if Ground.is_loaded() else 0.0
		if p is Vector3:
			waypoints.append(Vector3(p.x, sea_y, p.z))
		elif p is Vector2:
			waypoints.append(Vector3(p.x, sea_y, p.y))
		elif p is Array and p.size() >= 2:
			waypoints.append(Vector3(float(p[0]), sea_y, float(p[1])))
	is_looping = loop
	current_wp_idx = 0


func _snap_to_sea_level() -> void:
	var sea_y := Ground.sea_level if Ground.is_loaded() else 0.0
	if is_inside_tree():
		global_position.y = sea_y
	else:
		position.y = sea_y


func _setup_ship_weapons() -> void:
	if unit_kind == "frigate":
		# Add internal SAM system
		if _sam_subsystem == null:
			_sam_subsystem = SamSite.new()
			_sam_subsystem.setup_sam("sam_sa15", team, "sa15")
			_sam_subsystem.max_range_m = 12000.0
			_sam_subsystem.position = Vector3(0, 5.0, -15.0)
			add_child(_sam_subsystem)
		# Add naval gun / AAA system
		if _aaa_subsystem == null:
			_aaa_subsystem = AAA.new()
			_aaa_subsystem.setup_aaa("aaa_bofors", team, "bofors40")
			_aaa_subsystem.max_range_m = 4000.0
			_aaa_subsystem.position = Vector3(0, 5.0, -28.0)
			add_child(_aaa_subsystem)
	elif unit_kind == "patrol_boat":
		if _aaa_subsystem == null:
			_aaa_subsystem = AAA.new()
			_aaa_subsystem.setup_aaa("aaa_zsu", team, "zu23")
			_aaa_subsystem.max_range_m = 2500.0
			_aaa_subsystem.position = Vector3(0, 2.0, -7.0)
			add_child(_aaa_subsystem)


func unit_tick(dt: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		return

	# Water bobbing physics
	_bob_timer += dt
	var sea_y := Ground.sea_level if Ground.is_loaded() else 0.0
	var heave := sin(_bob_timer * 1.2) * BOB_HEAVE_AMP
	global_position.y = sea_y + heave

	var roll := sin(_bob_timer * 0.9) * BOB_ROLL_AMP
	var pitch := cos(_bob_timer * 0.7) * BOB_PITCH_AMP

	if waypoints.is_empty():
		velocity = Vector3.ZERO
		_apply_attitude(-global_transform.basis.z, roll, pitch)
		return

	# Waypoint navigation
	var target_wp := waypoints[current_wp_idx]
	var diff := target_wp - global_position
	diff.y = 0.0
	var dist := diff.length()

	if dist < size.z * 0.6:
		current_wp_idx += 1
		if current_wp_idx >= waypoints.size():
			if is_looping:
				current_wp_idx = 0
			else:
				current_wp_idx = waypoints.size() - 1
				velocity = Vector3.ZERO
				return
		target_wp = waypoints[current_wp_idx]
		diff = target_wp - global_position
		diff.y = 0.0

	var dir := diff.normalized() if diff.length_squared() > 0.001 else -global_transform.basis.z
	var move_dist := speed_mps * dt
	global_position += dir * move_dist
	velocity = dir * speed_mps

	_apply_attitude(dir, roll, pitch)

	# Wake effects
	_wake_timer += dt
	if _wake_timer >= WAKE_INTERVAL:
		_wake_timer = 0.0
		_spawn_wake()


func _apply_attitude(fwd_dir: Vector3, roll: float, pitch: float) -> void:
	var up := Vector3.UP
	var right := fwd_dir.cross(up).normalized()
	var new_basis := Basis.looking_at(-fwd_dir, up)
	new_basis = new_basis.rotated(fwd_dir, roll)
	new_basis = new_basis.rotated(right, pitch)
	global_transform.basis = new_basis


func _spawn_wake() -> void:
	if not is_inside_tree():
		return
	var stern_pos := global_position + global_transform.basis.z * (size.z * 0.45)
	stern_pos.y = Ground.sea_level if Ground.is_loaded() else 0.0
	Vfx.impact(stern_pos, Vector3.UP, "water")


func _on_origin_shifted(delta: Vector3) -> void:
	for i in waypoints.size():
		waypoints[i] -= delta
