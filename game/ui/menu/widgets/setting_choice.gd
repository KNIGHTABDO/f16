class_name SettingChoice
extends PanelContainer

signal choice_changed(value: Variant, index: int)

var title: String = ""
var description: String = ""
var options: Array = []  # Array of values, or Array of dictionaries {"val": x, "label": "Y"}
var current_index: int = 0
var setting_key: String = ""

var _title_label: Label
var _desc_label: Label
var _choice_label: Label
var _prev_btn: Button
var _next_btn: Button


func _init(
	p_title: String = "",
	p_desc: String = "",
	p_options: Array = [],
	p_initial_index: int = 0,
	p_key: String = ""
) -> void:
	title = p_title
	description = p_desc
	options = p_options
	current_index = clampi(p_initial_index, 0, maxi(options.size() - 1, 0))
	setting_key = p_key


func _ready() -> void:
	custom_minimum_size.y = 88.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb.border_width_bottom = 1
	sb.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

	var vbox_left := VBoxContainer.new()
	vbox_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_left.size_flags_stretch_ratio = 1.1
	vbox_left.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(vbox_left)

	_title_label = Label.new()
	_title_label.text = title
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	vbox_left.add_child(_title_label)

	if description != "":
		_desc_label = Label.new()
		_desc_label.text = description
		_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_desc_label.add_theme_font_size_override("font_size", 13)
		_desc_label.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
		vbox_left.add_child(_desc_label)

	# Right side: segmented choice picker [<] [ LABEL ] [>]
	var hbox_picker := HBoxContainer.new()
	hbox_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_picker.size_flags_stretch_ratio = 1.0
	hbox_picker.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_picker.add_theme_constant_override("separation", 8)
	hbox.add_child(hbox_picker)

	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.custom_minimum_size = Vector2(56, 48)
	_prev_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prev_btn.pressed.connect(_on_prev_pressed)
	hbox_picker.add_child(_prev_btn)

	var panel_label := PanelContainer.new()
	panel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_label.custom_minimum_size = Vector2(140, 48)
	var sb_lbl := StyleBoxFlat.new()
	sb_lbl.bg_color = Color(0.06, 0.11, 0.17, 0.8)
	sb_lbl.border_width_left = 1
	sb_lbl.border_width_top = 1
	sb_lbl.border_width_right = 1
	sb_lbl.border_width_bottom = 1
	sb_lbl.border_color = Color(0.25, 0.82, 1.0, 0.25)
	sb_lbl.corner_radius_top_left = 8
	sb_lbl.corner_radius_top_right = 8
	sb_lbl.corner_radius_bottom_right = 8
	sb_lbl.corner_radius_bottom_left = 8
	panel_label.add_theme_stylebox_override("panel", sb_lbl)
	hbox_picker.add_child(panel_label)

	_choice_label = Label.new()
	_choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_choice_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choice_label.add_theme_font_size_override("font_size", 18)
	_choice_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	panel_label.add_child(_choice_label)

	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.custom_minimum_size = Vector2(56, 48)
	_next_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_next_btn.pressed.connect(_on_next_pressed)
	hbox_picker.add_child(_next_btn)

	_update_display()


func _on_prev_pressed() -> void:
	if options.is_empty():
		return
	current_index = (current_index - 1 + options.size()) % options.size()
	_apply_choice()


func _on_next_pressed() -> void:
	if options.is_empty():
		return
	current_index = (current_index + 1) % options.size()
	_apply_choice()


func _apply_choice() -> void:
	_update_display()
	var val = get_selected_value()
	if setting_key != "":
		Settings.set_value(setting_key, val)
	Sfx.play_2d("ui_click", -4.0)
	choice_changed.emit(val, current_index)


func get_selected_value() -> Variant:
	if options.is_empty():
		return null
	var item = options[current_index]
	if typeof(item) == TYPE_DICTIONARY and item.has("val"):
		return item["val"]
	return item


func get_selected_label() -> String:
	if options.is_empty():
		return ""
	var item = options[current_index]
	if typeof(item) == TYPE_DICTIONARY and item.has("label"):
		return str(item["label"])
	return str(item).to_upper()


func _update_display() -> void:
	if _choice_label:
		_choice_label.text = get_selected_label()


func set_options(p_opts: Array, p_selected_idx: int = 0) -> void:
	options = p_opts
	current_index = clampi(p_selected_idx, 0, maxi(options.size() - 1, 0))
	_update_display()


func set_by_value(val: Variant) -> void:
	for i in options.size():
		var item = options[i]
		var item_val = item["val"] if (typeof(item) == TYPE_DICTIONARY and item.has("val")) else item
		if item_val == val:
			current_index = i
			_update_display()
			return
