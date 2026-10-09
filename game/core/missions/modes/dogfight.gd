class_name DogfightMission
extends Mission
## Dogfight: the player and wingmen against the enemy fighters on the plan. The sortie is won when every enemy fighter is down.

var _fighters: Array = []


func _prepare() -> void:
	_fighters = by_role("fighter")
	objectives.add("enemies", "", plan["site"], null, true)
	_show()


func _tick(_delta: float) -> void:
	_show()
	if not _fighters.is_empty() and count_alive(_fighters) == 0 and not victory_pending:
		victory("All enemy fighters down")


func _show() -> void:
	objectives.set_text("enemies", "Enemy fighters left: %d of %d" % [count_alive(_fighters), _fighters.size()])
