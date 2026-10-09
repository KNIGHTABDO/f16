class_name Convoy
extends Node3D
## Manages a column of 4-10 ground vehicles travelling along a road route with spacing.

@export var team: int = 1
@export var unit_count: int = 6
@export var spacing_m: float = 28.0

var vehicles: Array[GroundVehicle] = []
var road_path: Array[Vector3] = []


func _ready() -> void:
	add_to_group("floating")
	WorldOrigin.shifted.connect(_on_origin_shifted)


func setup_convoy(p_team: int, p_path: Array, kinds: Array[String] = []) -> void:
	team = p_team
	road_path.clear()
	for p in p_path:
		if p is Vector3:
			road_path.append(p)
		elif p is Vector2:
			var y := Ground.surface_at(p.x, p.y) if Ground.is_loaded() else 0.0
			road_path.append(Vector3(p.x, y, p.y))
		elif p is Array and p.size() >= 2:
			var px: float = float(p[0])
			var pz: float = float(p[1])
			var py := Ground.surface_at(px, pz) if Ground.is_loaded() else 0.0
			road_path.append(Vector3(px, py, pz))

	if road_path.size() < 2:
		return

	var default_kinds: Array[String] = ["apc", "tank", "truck", "fuel_truck", "truck", "aaa_zsu"]
	if kinds.is_empty():
		kinds = default_kinds

	var n := clampi(unit_count, 3, 10)
	var prev_veh: GroundVehicle = null

	var start_p := road_path[0]
	var dir := (road_path[1] - road_path[0]).normalized()

	for i in n:
		var kind: String = kinds[i % kinds.size()]
		var veh := GroundVehicle.new()
		veh.setup_unit(kind, team)
		veh.convoy_spacing = spacing_m
		veh.convoy_lead = prev_veh

		# Position trailing behind start along road direction
		var spawn_pos := start_p - dir * (float(i) * spacing_m)
		if Ground.is_loaded():
			spawn_pos.y = Ground.surface_at(spawn_pos.x, spawn_pos.z)
		veh.position = spawn_pos

		add_child(veh)
		veh.set_road_path(road_path, true)
		vehicles.append(veh)
		prev_veh = veh


func _on_origin_shifted(delta: Vector3) -> void:
	for i in road_path.size():
		road_path[i] -= delta
