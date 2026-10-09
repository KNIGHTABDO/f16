class_name ConvoyHuntMission
extends Mission
## Convoy hunt: stop every vehicle in the enemy convoys on the roads near the site. The sortie is won when none are left.

var _vehicles: Array = []
var _total := 0


func _prepare() -> void:
	for convoy in by_role("convoy"):
		_vehicles.append_array(convoy.vehicles)
	_total = _vehicles.size()
	track_all(_vehicles, float(tuning["vehicle_pts"]))
	objectives.add("vehicles", "", plan["site"], null, true)
	_show()


func _on_begin() -> void:
	if _vehicles.is_empty():
		finish(false, "No convoy on this map")


func _tick(_delta: float) -> void:
	_show()
	if count_alive(_vehicles) == 0 and not victory_pending:
		victory("Convoys stopped")


func _show() -> void:
	objectives.set_text("vehicles", "Vehicles left: %d of %d" % [count_alive(_vehicles), _total])
