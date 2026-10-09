class_name StrikeMission
extends Mission
## Strike: destroy the targets at the site. SAM sites guard the area. They are optional kills, but they make the run safer.

var _targets: Array = []
var _sams: Array = []


func _prepare() -> void:
	_targets = by_role("target")
	_sams = by_role("sam")
	track_all(_targets, float(tuning["target_pts"]))
	track_all(_sams, float(tuning["sam_pts"]))
	objectives.add("targets", "", plan["site"], null, true)
	objectives.add("sams", "", Vector3.ZERO, null, false)
	_show()


func _tick(_delta: float) -> void:
	_show()
	if count_alive(_targets) == 0 and not victory_pending:
		objectives.complete("targets")
		victory("Targets destroyed")


func _show() -> void:
	objectives.set_text("targets", "Targets left: %d of %d" % [count_alive(_targets), _targets.size()])
	objectives.set_text("sams", "SAM sites up: %d of %d" % [count_alive(_sams), _sams.size()])
