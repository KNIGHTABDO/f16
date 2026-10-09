class_name SeadMission
extends Mission
## SEAD: suppress the air defence. Every SAM site on the plan must be destroyed.

var _sams: Array = []


func _prepare() -> void:
	_sams = by_role("sam")
	track_all(_sams, float(tuning["sam_pts"]))
	objectives.add("sams", "", plan["site"], null, true)
	_show()


func _tick(_delta: float) -> void:
	_show()
	if count_alive(_sams) == 0 and not victory_pending:
		objectives.complete("sams")
		victory("Air defences suppressed")


func _show() -> void:
	objectives.set_text("sams", "SAM sites left: %d of %d" % [count_alive(_sams), _sams.size()])
