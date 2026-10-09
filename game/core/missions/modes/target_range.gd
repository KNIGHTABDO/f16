class_name TargetRangeMission
extends Mission
## Target range: practice with no clock and no win. When every target is down, they all come back respawn_s later.

var _units: Array = []  ## the spawned range targets, the same array as nodes["units"]
var _entries: Array = []  ## the plan entries those targets came from, index-aligned with _units
var _respawn_left := -1.0  ## s until the targets come back, or -1 while any are up


func _prepare() -> void:
	_units = nodes["units"]
	_entries = plan["units"]
	objectives.add("range", "", plan["site"], null, false)
	_show()


func _tick(delta: float) -> void:
	if count_alive(_units) > 0:
		_respawn_left = -1.0
	else:
		if _respawn_left < 0.0:
			_respawn_left = float(tuning["respawn_s"])
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn()
	_show()


func _show() -> void:
	var up := count_alive(_units)
	var text := "Targets up: %d of %d" % [up, _units.size()]
	if up == 0 and _respawn_left > 0.0:
		text += ", back in %.0f s" % _respawn_left
	objectives.set_text("range", text)


## Rebuilds every target from its plan entry. Only called once all of them are down.
func _respawn() -> void:
	_respawn_left = -1.0
	for i in _units.size():
		if is_instance_valid(_units[i]):
			_units[i].queue_free()
		var e: Dictionary = _entries[i]
		var node := UnitFactory.spawn(String(e["kind"]), int(e["team"]), WorldOrigin.to_local(e["pos"]), float(e["heading"]))
		_level.world.add_child(node)
		node.set_meta("role", "range")
		_units[i] = node
