class_name TimeTrialMission
extends Mission
## Time trial: fly the ring course in order. Each ring must be passed within ring_radius_m. Time is score: the par bonus
## shrinks by pts_per_s every second, and the course ends when the last ring is passed.

var _rings: Array = []
var _next := 0


func _prepare() -> void:
	_rings = plan["rings"]
	objectives.add("ring", "", _rings[0], null, true)
	_show()


func _tick(_delta: float) -> void:
	var p = _player()
	if p == null or _next >= _rings.size():
		return
	var here := WorldOrigin.to_world(p.position)
	if here.distance_to(_rings[_next]) > float(tuning["ring_radius_m"]):
		return
	_next += 1
	if _next >= _rings.size():
		_finish_course()
		return
	_show()


func _finish_course() -> void:
	objectives.complete("ring")
	add_score(maxf(0.0, float(tuning["par_pts"]) - elapsed * float(tuning["pts_per_s"])))
	victory("Course done in %.1f s" % elapsed)


func _show() -> void:
	var n := _rings.size()
	objectives.set_text("ring", "Ring %d of %d" % [_next + 1, n])
	objectives.set_marker("ring", _rings[_next], null)
