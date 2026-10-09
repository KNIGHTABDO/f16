class_name MapSelectScreen
extends Control
## Map, difficulty and option picker for one mode. START generates the sortie and loads the flight.

var _mode_id := ""
var _map_id := ""
var _difficulty := ""
var _options: Dictionary = {}  ## option id -> chosen value
var _data: Dictionary = {}


## Call before adding the screen to the tree.
func setup(mode_id: String) -> void:
	_mode_id = mode_id
	_data = MissionGenerator.data()
	_map_id = GameState.selected_map
	_difficulty = GameState.difficulty
	var mode: Dictionary = _data["modes"][mode_id]
	for def in mode["options"]:
		_options[String(def["id"])] = String(def["default"])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mode: Dictionary = _data["modes"][_mode_id]

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.05, 0.08, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	vbox.add_child(_label(String(mode["title"]), 30, Color("#3FD0FF")))
	vbox.add_child(_label(String(mode["tagline"]), 18, Color("#E8F6FF")))
	var description := _label(String(mode["description"]), 15, Color(0.65, 0.75, 0.85, 0.85))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(description)

	vbox.add_child(_label("MAP", 16, Color("#FFB020")))
	vbox.add_child(_map_row())
	vbox.add_child(_label("DIFFICULTY", 16, Color("#FFB020")))
	vbox.add_child(_difficulty_row())
	for def in mode["options"]:
		vbox.add_child(_option_row(def))

	var start := Button.new()
	start.text = "START"
	start.custom_minimum_size = Vector2(360, 56)
	start.add_theme_font_size_override("font_size", 20)
	start.add_theme_color_override("font_color", Color("#FFB020"))
	start.pressed.connect(_start)
	vbox.add_child(start)


func _map_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var group := ButtonGroup.new()
	var maps: Dictionary = _data["maps"]
	for map_id in maps:
		var map: Dictionary = maps[map_id]
		var btn := _choice_btn("%s\n%s" % [map["name"], map["subtitle"]], String(map.get("art", "")))
		btn.custom_minimum_size = Vector2(300, 90)
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = String(map_id) == _map_id
		btn.pressed.connect(_on_map.bind(String(map_id)))
		row.add_child(btn)
	return row


func _difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var group := ButtonGroup.new()
	for diff_id in _data["difficulty_order"]:
		var diff: Dictionary = _data["difficulty"][String(diff_id)]
		var btn := _choice_btn(String(diff["label"]), "")
		btn.custom_minimum_size = Vector2(160, 56)
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = String(diff_id) == _difficulty
		btn.pressed.connect(_on_difficulty.bind(String(diff_id)))
		row.add_child(btn)
	return row


func _option_row(def: Dictionary) -> HBoxContainer:
	var id := String(def["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := _label(String(def["label"]), 16, Color("#E8F6FF"))
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(320, 48)
	var choices: Array = def["choices"]
	var names: Array = def.get("names", choices)
	for i in choices.size():
		picker.add_item(String(names[i]), i)
	picker.select(maxi(choices.find(_options[id]), 0))
	picker.item_selected.connect(_on_option.bind(id, choices))
	row.add_child(picker)
	return row


func _choice_btn(text: String, art_key: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.expand_icon = true
	btn.icon = Progression.art_texture(art_key) if art_key != "" else null
	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _on_map(map_id: String) -> void:
	_map_id = map_id


func _on_difficulty(diff_id: String) -> void:
	_difficulty = diff_id


func _on_option(index: int, id: String, choices: Array) -> void:
	_options[id] = String(choices[index])


func _start() -> void:
	GameState.begin_mission(_mode_id, _map_id, _options, _difficulty)
