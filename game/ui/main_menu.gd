extends Control
## Main menu. TEMPORARY minimal version: title, FLY, a map toggle (gibraltar / atlas) and a flight mode toggle
## (arcade / realistic). The real menus come later.

const MAP_IDS := ["gibraltar", "atlas"]
const MAP_LABELS := {"gibraltar": "GIBRALTAR", "atlas": "ATLAS"}

var _map_button: Button
var _mode_button: Button


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "KNIGHT WINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "F-16C  -  touch, gyro or keyboard"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.75, 0.82, 0.9)
	box.add_child(subtitle)

	var fly := _button("FLY")
	fly.custom_minimum_size = Vector2(280, 88)
	fly.add_theme_font_size_override("font_size", 30)
	fly.pressed.connect(GameState.start_flight)
	box.add_child(fly)

	_map_button = _button("")
	_map_button.pressed.connect(_on_map_pressed)
	box.add_child(_map_button)

	_mode_button = _button("")
	_mode_button.pressed.connect(_on_mode_pressed)
	box.add_child(_mode_button)

	_refresh()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 60)
	b.add_theme_font_size_override("font_size", 22)
	return b


func _refresh() -> void:
	_map_button.text = "MAP: " + String(MAP_LABELS.get(GameState.selected_map, GameState.selected_map.to_upper()))
	_mode_button.text = "MODE: " + Settings.flight_mode.to_upper()


func _on_map_pressed() -> void:
	var i := MAP_IDS.find(GameState.selected_map)
	GameState.selected_map = MAP_IDS[(i + 1) % MAP_IDS.size()]
	GameState.save_progress()
	_refresh()


func _on_mode_pressed() -> void:
	Settings.flight_mode = "realistic" if Settings.flight_mode == "arcade" else "arcade"
	Settings.save()
	_refresh()
