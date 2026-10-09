class_name Rocket
extends Node3D
## Unguided Hydra-style rocket: short motor boost, then ballistic flight. Detonates on contact with a hitbox
## (ray test) or the terrain; blast damage in a small radius.

const GRAVITY := 9.81
const COAST_DRAG := 3.0e-5
const HIT_MASK := 2 | 4 | 8
const BLAST_SIZE_SCALE := 1.0 / 8.0

signal detonated(rocket: Rocket)

var weapon_id := ""
var data: Dictionary = {}
var shooter: Node3D
var team := 0
var velocity := Vector3.ZERO

var _age := 0.0
var _trail: Node3D
var _dead := false
var _query := PhysicsRayQueryParameters3D.new()


static func launch(world: Node, shooter_node: Node3D, id: String, wdata: Dictionary, xform: Transform3D,
		start_velocity: Vector3) -> Rocket:
	var r := Rocket.new()
	r.weapon_id = id
	r.data = wdata
	r.shooter = shooter_node
	r.team = int(shooter_node.get("team")) if shooter_node != null else 0
	r.velocity = start_velocity
	var hb := shooter_node.get_node_or_null("Hitbox") as Hitbox
	if hb != null:
		r._query.exclude = [hb.get_rid()]
	r._query.collide_with_areas = true
	r._query.collide_with_bodies = false
	r._query.collision_mask = HIT_MASK
	world.add_child(r)
	r.global_transform = xform
	r.reset_physics_interpolation()
	return r


func _ready() -> void:
	add_to_group("floating")
	add_child(WeaponModels.build(weapon_id, data))
	_trail = Vfx.attach_trail(self, "rocket", Vector3(0, 0, 0.7))
	Sfx.play_3d("rocket_launch", global_position, -4.0)


func get_velocity() -> Vector3:
	return velocity


func _physics_process(dt: float) -> void:
	if _dead:
		return
	_age += dt
	var speed := velocity.length()
	var fwd := velocity / maxf(speed, 0.001)
	if _age < float(data.get("boost_s", 1.1)) and speed < float(data.get("speed_max", 740.0)):
		velocity += fwd * float(data.get("accel", 600.0)) * dt
	else:
		velocity -= fwd * (COAST_DRAG * speed * speed) * dt
	velocity += Vector3(0, -GRAVITY, 0) * dt
	var prev := global_position
	var pos := prev + velocity * dt
	global_position = pos
	global_transform.basis = Basis.looking_at(velocity.normalized(),
			Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	_query.from = prev
	_query.to = pos
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		_detonate(hit.position)
		return
	var g := Ground.raycast(prev, pos, 40.0)
	if not g.is_empty():
		_detonate(g.position)
		return
	if _age >= float(data.get("lifetime", 8.0)):
		_cleanup()


func _detonate(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	var radius := float(data.get("blast_radius", 10.0))
	Targeting.blast(get_tree(), at, radius, float(data.get("damage", 70.0)), shooter, team,
			clampf(radius * BLAST_SIZE_SCALE, 0.4, 1.5))
	detonated.emit(self)
	_cleanup()


func _cleanup() -> void:
	_dead = true
	if _trail != null and is_instance_valid(_trail):
		Vfx.stop_trail(_trail)
	queue_free()
