extends Control
## Main menu. STUB: replaced by the menus task.


func _ready() -> void:
	var b := Button.new()
	b.text = "FLY"
	b.custom_minimum_size = Vector2(240, 80)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	b.pressed.connect(GameState.start_flight)
	add_child(b)
