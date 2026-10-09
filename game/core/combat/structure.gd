class_name Structure
extends CombatUnit
## Static structure (buildings, hangars, fuel tanks, rotating radar dishes, bunkers, bridges).

const ROTATING_RADAR_SPEED := 2.0

var is_rotating_radar: bool = false
var _dish_node: Node3D = null


func _ready() -> void:
	super._ready()
	_snap_to_terrain()
	_find_radar_dish()


func setup_structure(p_kind: String, p_team: int, p_hp: float = 0.0) -> void:
	setup_unit(p_kind, p_team, p_hp)
	_snap_to_terrain()
	_find_radar_dish()


func _snap_to_terrain() -> void:
	if Ground.is_loaded() and unit_kind != "bridge" and unit_kind != "bridges":
		var px := global_position.x if is_inside_tree() else position.x
		var pz := global_position.z if is_inside_tree() else position.z
		var surf_y := Ground.surface_at(px, pz)
		if is_inside_tree():
			global_position.y = surf_y
		else:
			position.y = surf_y


func _find_radar_dish() -> void:
	if visual == null:
		return
	_dish_node = visual.find_child("RadarDish", true, false) as Node3D
	if _dish_node != null or unit_kind == "radar" or unit_kind == "comms":
		is_rotating_radar = true


func unit_tick(dt: float) -> void:
	if not alive:
		return

	if is_rotating_radar and _dish_node != null and is_instance_valid(_dish_node):
		_dish_node.rotation.y += ROTATING_RADAR_SPEED * dt
