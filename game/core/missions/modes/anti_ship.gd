class_name AntiShipMission
extends Mission
## Anti-ship: find and sink the ship group at sea. Frigates, cargo ships and patrol boats each score their own points.
## The sortie is won when every ship on the plan is down.

const POINTS_KEY := {"frigate": "frigate_pts", "cargo_ship": "cargo_pts", "patrol_boat": "patrol_pts"}

var _ships: Array = []


func _prepare() -> void:
	_ships = by_role("ship")
	for ship in _ships:
		track(ship, float(tuning[POINTS_KEY.get(String(ship.get("unit_kind")), "patrol_pts")]))
	objectives.add("ships", "", plan["site"], null, true)
	_show()


func _on_begin() -> void:
	if _ships.is_empty():
		finish(false, "No ships could be spawned")


func _tick(_delta: float) -> void:
	_show()
	if count_alive(_ships) == 0 and not victory_pending:
		victory("Ship group sunk")


func _show() -> void:
	objectives.set_text("ships", "Ships afloat: %d of %d" % [count_alive(_ships), _ships.size()])
