class_name ModeSelectScreen
extends Control
## Mission picker: one card per mode in modes.json. A card opens the map and difficulty picker for that mode.

const COLUMNS := 3
const CARD_SIZE := Vector2(380, 132)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MISSIONS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#3FD0FF"))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)

	var data := MissionGenerator.data()
	for mode_id in data["mode_order"]:
		grid.add_child(_card(String(mode_id), data["modes"][String(mode_id)]))


func _card(mode_id: String, mode: Dictionary) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = CARD_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.expand_icon = true
	btn.icon = Progression.art_texture(String(mode.get("art", "")))
	btn.text = "%s\n%s" % [mode["title"], mode["tagline"]]
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(_open_maps.bind(mode_id))
	return btn


func _open_maps(mode_id: String) -> void:
	var picker := MapSelectScreen.new()
	picker.setup(mode_id)
	var root := _menu_root()
	if root != null:
		root.push_screen(picker)
	else:
		picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(picker)


func _menu_root() -> Node:
	var n: Node = get_parent()
	while n != null and not n.has_method("push_screen"):
		n = n.get_parent()
	return n
