class_name SettingSlider
extends PanelContainer

signal value_changed(val: float)

var title: String = ""
var description: String = ""
var min_val: float = 0.0
var max_val: float = 1.0
var step: float = 0.05
var current_value: float = 1.0
var display_multiplier: float = 1.0
var format_string: String = "%.0f"
var setting_key: String = ""

var _slider: HSlider
var _val_label: Label
var _title_label: Label
var _desc_label: Label


func _init(
	p_title: String = "",
	p_desc: String = "",
	p_min: float = 0.0,
	p_max: float = 1.0,
	p_step: float = 0.05,
	p_val: float = 1.0,
	p_key: String = "",
	p_fmt: String = "%.0f",
	p_mult: float = 1.0
) -> void:
	title = p_title
	description = p_desc
	min_val = p_min
	max_val = p_max
	step = p_step
	current_value = p_val
	setting_key = p_key
	format_string = p_fmt
	display_multiplier = p_mult


func _ready() -> void:
	custom_minimum_size.y = 88.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Subtle military glass row background
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

	# Left side: title + description
	var vbox_left := VBoxContainer.new()
	vbox_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_left.size_flags_stretch_ratio = 1.2
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

	# Right side: Slider + Value Label
	var hbox_right := HBoxContainer.new()
	hbox_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_right.size_flags_stretch_ratio = 1.0
	hbox_right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_right.add_theme_constant_override("separation", 14)
	hbox.add_child(hbox_right)

	_slider = HSlider.new()
	_slider.min_value = min_val
	_slider.max_value = max_val
	_slider.step = step
	_slider.value = current_value
	_slider.custom_minimum_size = Vector2(180, 48)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_changed)
	hbox_right.add_child(_slider)

	_val_label = Label.new()
	_val_label.custom_minimum_size = Vector2(72, 32)
	_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_val_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_val_label.add_theme_font_size_override("font_size", 18)
	_val_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	hbox_right.add_child(_val_label)

	_update_label(current_value)


func _on_slider_changed(val: float) -> void:
	current_value = val
	_update_label(val)
	if setting_key != "":
		Settings.set_value(setting_key, val)
	value_changed.emit(val)


func _update_label(val: float) -> void:
	if _val_label:
		_val_label.text = format_string % (val * display_multiplier)


func set_val(val: float) -> void:
	current_value = val
	if _slider:
		_slider.set_value_no_signal(val)
	_update_label(val)
