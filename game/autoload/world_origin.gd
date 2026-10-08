extends Node
## Floating origin. The map is up to ~300 km wide, which is too far from (0,0) for 32-bit
## render transforms, so the world is shifted back toward the origin whenever the anchor
## (the player aircraft / camera) drifts more than SHIFT_DISTANCE away.
##
## Coordinates:
## - "local" = Godot scene coordinates (what node.global_position returns).
## - "world" = true map coordinates in meters, map centre = (0, 0); X = east, -Z = north, Y = altitude ASL.
##   world = local + offset. offset_x / offset_z are 64-bit GDScript floats.
##
## Contract for every script:
## - Every Node3D placed in the world (aircraft, missiles, targets, effects, cameras) must be in the
##   group "floating" and be a direct child of the level's World node (children move with parents).
## - If you cache a position in a variable (waypoints, impact points), connect to `shifted` and
##   subtract `delta` from it, or store it in world coordinates via to_world()/to_local().

signal shifted(delta: Vector3)

const SHIFT_DISTANCE := 4000.0
const SHIFT_STEP := 1000.0

var offset_x: float = 0.0
var offset_z: float = 0.0
## Node whose position triggers shifts (player aircraft). Set by the level.
var anchor: Node3D


func reset() -> void:
	offset_x = 0.0
	offset_z = 0.0
	anchor = null


func to_world(local: Vector3) -> Vector3:
	return Vector3(local.x + offset_x, local.y, local.z + offset_z)


func to_local(world: Vector3) -> Vector3:
	return Vector3(world.x - offset_x, world.y, world.z - offset_z)


## World X/Z as 64-bit floats (Vector3 is 32-bit). Use for map lookups.
func world_x(local_x: float) -> float:
	return local_x + offset_x


func world_z(local_z: float) -> float:
	return local_z + offset_z


func _physics_process(_delta: float) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var p := anchor.global_position
	if absf(p.x) > SHIFT_DISTANCE or absf(p.z) > SHIFT_DISTANCE:
		shift(Vector3(snappedf(p.x, SHIFT_STEP), 0.0, snappedf(p.z, SHIFT_STEP)))


func shift(delta: Vector3) -> void:
	offset_x += delta.x
	offset_z += delta.z
	for n in get_tree().get_nodes_in_group("floating"):
		if n is Node3D:
			n.global_position -= delta
			n.reset_physics_interpolation()
	shifted.emit(delta)
