class_name BaseDefenseMission
extends Mission
## Base defense: bombers with escorts come for the base. Shoot down every bomber before it drops. The base assets are
## what they are after. Losing more than max_asset_losses of them fails the sortie.

var _assets: Array = []
var _bombers: Array = []
var _escorts: Array = []


func _prepare() -> void:
	_assets = by_role("asset")
	_bombers = by_role("bomber")
	_escorts = by_role("escort")
	track_all(_bombers, float(tuning["bomber_pts"]))
	track_all(_escorts, float(tuning["escort_pts"]))
	objectives.add("bombers", "", plan["site"], null, true)
	objectives.add("assets", "", plan["site"], null, false)
	_show()


func _tick(_delta: float) -> void:
	_show()
	if _assets.size() - count_alive(_assets) > int(tuning["max_asset_losses"]):
		finish(false, "Too many base assets lost")
		return
	if count_alive(_bombers) == 0 and not victory_pending:
		victory("Bombers destroyed")


func _show() -> void:
	objectives.set_text("bombers", "Bombers left: %d of %d" % [count_alive(_bombers), _bombers.size()])
	objectives.set_text("assets", "Base assets standing: %d of %d" % [count_alive(_assets), _assets.size()])
