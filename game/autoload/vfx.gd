extends Node
## Visual effects service. STUB: replaced by the vfx task. Keep these signatures.
## All positions are LOCAL scene coordinates. Spawned effects are added to the current level's World node,
## are in group "floating" and free themselves.

## kind: "air" (mid-air fireball), "ground" (dirt + fire), "water" (splash column), "aircraft" (big fireball + debris)
func explosion(_local_pos: Vector3, _size: float = 1.0, _kind: String = "ground") -> void:
	pass


## Bullet/shell impact. kind: "ground", "water", "metal"
func impact(_local_pos: Vector3, _normal: Vector3, _kind: String = "ground") -> void:
	pass


## Muzzle flash attached to `parent` at `local_offset` for one shot burst frame.
func muzzle_flash(_parent: Node3D, _local_offset: Vector3, _size: float = 1.0) -> void:
	pass


## Persistent smoke/fire trail following `parent` (missile motor, burning aircraft, damaged engine).
## kind: "missile", "rocket", "fire", "smoke_light", "smoke_heavy". Returns the effect node; call stop_trail() to let it fade.
func attach_trail(_parent: Node3D, _kind: String = "missile", _local_offset := Vector3.ZERO) -> Node3D:
	return null


func stop_trail(_trail: Node3D) -> void:
	pass


## Flare burning ball with smoke trail; returns the node (moves itself with given velocity + gravity + drag, lives `life` s).
func flare(_local_pos: Vector3, _velocity: Vector3, _life: float = 4.0) -> Node3D:
	return null


## Lingering column of smoke at a destroyed target.
func wreck_smoke(_local_pos: Vector3, _size: float = 1.0, _duration: float = 90.0) -> void:
	pass
