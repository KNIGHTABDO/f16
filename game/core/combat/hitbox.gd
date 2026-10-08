class_name Hitbox
extends Area3D
## Hit volume for anything that can be shot. Add as a child (with CollisionShape3D children) of a
## damageable node and set `target` to that node. Guns ray-cast against these areas.
## Layers: aircraft -> 2, ground units/ships/SAMs -> 3, structures -> 4.

@export var target: Node


func _ready() -> void:
	monitoring = false
	monitorable = true
	if target == null:
		target = get_parent()


func apply_damage(amount: float, source: Node, hit_pos: Vector3) -> void:
	if target and is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(amount, source, hit_pos)
