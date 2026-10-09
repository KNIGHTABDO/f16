class_name FreeFlightMission
extends Mission
## Free flight: no objectives and no time limit. Fly anywhere on the map. Landing and stopping on the ground ends the sortie.

const STOP_S := 5.0  ## s stopped on the ground after a flight before the sortie ends

var _airborne := false
var _stopped_s := 0.0


func _prepare() -> void:
	objectives.add("fly", "Fly anywhere. Land and stop to end the sortie.", Vector3.ZERO, null, false)


func _tick(delta: float) -> void:
	var p = _player()
	if p == null:
		return
	if not p.is_on_ground():
		_airborne = true
		_stopped_s = 0.0
	elif _airborne and p.get_speed_kmh() < 20.0:
		_stopped_s += delta
		if _stopped_s >= STOP_S:
			finish(true, "Sortie ended on the ground")
