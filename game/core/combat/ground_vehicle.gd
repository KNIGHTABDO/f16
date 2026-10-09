class_name GroundVehicle
extends CombatUnit
## Ground vehicle (tank, APC, truck, fuel truck) that follows a route,
## conforms to the terrain normal, and scatters off-road when damaged.

const DEFAULT_SPEED_KMH := 45.0
const SCATTER_SPEED_KMH := 65.0
const ARRIVE_RADIUS := 6.0
const TERRAIN_SAMPLE_STEP := 15.0

var speed_mps: float = DEFAULT_SPEED_KMH / 3.6
var target_speed_mps: float = DEFAULT_SPEED_KMH / 3.6
var path: Array[Vector3] = []
var path_index: int = 0
var is_looping: bool = true

var convoy_lead: GroundVehicle = null
var convoy_spacing: float = 25.0

var is_scattering: bool = false
var scatter_timer: float = 0.0
var scatter_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	_snap_to_terrain()


func set_road_path(points: Array, loop := true) -> void:
	path.clear()
	for p in points:
		if p is Vector3:
			path.append(p)
		elif p is Vector2:
			var y := Ground.surface_at(p.x, p.y) if Ground.is_loaded() else 0.0
			path.append(Vector3(p.x, y, p.y))
		elif p is Array and p.size() >= 2:
			var px: float = float(p[0])
			var pz: float = float(p[1])
			var py := Ground.surface_at(px, pz) if Ground.is_loaded() else 0.0
			path.append(Vector3(px, py, pz))
	is_looping = loop
	path_index = 0
	if not path.is_empty():
		_snap_to_terrain()


func _snap_to_terrain() -> void:
	if Ground.is_loaded():
		var px := global_position.x if is_inside_tree() else position.x
		var pz := global_position.z if is_inside_tree() else position.z
		var y := Ground.surface_at(px, pz)
		if is_inside_tree():
			global_position.y = y
			_align_to_terrain(Vector3.FORWARD)
		else:
			position.y = y


func unit_tick(dt: float) -> void:
	if not alive:
		velocity = Vector3.ZERO
		return

	if is_scattering:
		scatter_timer -= dt
		if scatter_timer <= 0.0:
			is_scattering = false
			target_speed_mps = DEFAULT_SPEED_KMH / 3.6

	# Convoy pacing: adjust speed if too close to unit ahead
	if convoy_lead != null and is_instance_valid(convoy_lead) and convoy_lead.alive:
		var dist_to_lead := global_position.distance_to(convoy_lead.global_position)
		if dist_to_lead < convoy_spacing * 0.7:
			target_speed_mps = convoy_lead.speed_mps * 0.4
		elif dist_to_lead < convoy_spacing:
			target_speed_mps = convoy_lead.speed_mps * 0.8
		elif dist_to_lead > convoy_spacing * 1.5:
			target_speed_mps = clampf(convoy_lead.speed_mps * 1.3, 10.0, 20.0)

	speed_mps = move_toward(speed_mps, target_speed_mps, 8.0 * dt)

	if path.is_empty():
		velocity = Vector3.ZERO
		return

	var target_wp := path[path_index] + (scatter_offset if is_scattering else Vector3.ZERO)
	var diff := target_wp - global_position
	diff.y = 0.0
	var dist := diff.length()

	if dist < ARRIVE_RADIUS:
		path_index += 1
		if path_index >= path.size():
			if is_looping:
				path_index = 0
			else:
				path_index = path.size() - 1
				velocity = Vector3.ZERO
				return
		target_wp = path[path_index]
		diff = target_wp - global_position
		diff.y = 0.0

	var dir := diff.normalized() if diff.length_squared() > 0.001 else -global_transform.basis.z
	var move_dist := speed_mps * dt
	var next_pos := global_position + dir * move_dist

	if Ground.is_loaded():
		next_pos.y = Ground.surface_at(next_pos.x, next_pos.z)

	velocity = (next_pos - global_position) / maxf(dt, 0.001)
	global_position = next_pos
	_align_to_terrain(dir)


func _align_to_terrain(forward_dir: Vector3) -> void:
	var norm := Vector3.UP
	if Ground.is_loaded():
		norm = Ground.normal_at(global_position.x, global_position.z, TERRAIN_SAMPLE_STEP)
	var fwd := (forward_dir - norm * norm.dot(forward_dir)).normalized()
	if fwd.length_squared() > 0.001:
		# Godot nose/forward is -Z, so looking_at looks along -Z with target at pos + fwd
		global_transform.basis = Basis.looking_at(-fwd, norm)


func _on_damaged(_amount: float, _source: Node) -> void:
	if not is_scattering:
		is_scattering = true
		scatter_timer = randf_range(10.0, 15.0)
		target_speed_mps = SCATTER_SPEED_KMH / 3.6
		var side := 1.0 if randf() > 0.5 else -1.0
		var right := global_transform.basis.x
		scatter_offset = right * (side * randf_range(15.0, 30.0))


func _on_origin_shifted(delta: Vector3) -> void:
	for i in path.size():
		path[i] -= delta
