class_name SettingToggle
extends PanelContainer

signal toggled(is_on: bool)

var title: String = ""
var description: String = ""
var is_checked: bool = false
var setting_key: String = ""

var _btn: Button
var _title_label: Label
var _desc_label: Label


func _init(
	p_title: String = "",
	p_desc: String = "",
	p_checked: bool = false,
	p_key: String = ""
) -> void:
	title = p_title
	description = p_desc
	is_checked = p_checked
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

	# Right side: Custom styled military toggle button (min 120x48 px hit target)
	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(130, 48)
	_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_btn.toggle_mode = true
	_btn.button_pressed = is_checked
	_btn.toggled.connect(_on_btn_toggled)
	hbox.add_child(_btn)

	_update_btn_style()


func _on_btn_toggled(pressed_state: bool) -> void:
	is_checked = pressed_state
	_update_btn_style()
	if setting_key != "":
		Settings.set_value(setting_key, is_checked)
	Sfx.play_2d("ui_click", -4.0)
	toggled.emit(is_checked)


func _update_btn_style() -> void:
	if not _btn:
		return
	_btn.text = "ENABLED" if is_checked else "DISABLED"
	var sb := StyleBoxFlat.new()
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_detail = 5
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	if is_checked:
		sb.bg_color = Color(0.10, 0.28, 0.40, 0.90)
		sb.border_color = Color("#3FD0FF")
		_btn.add_theme_color_override("font_color", Color("#3FD0FF"))
	else:
		sb.bg_color = Color(0.06, 0.10, 0.15, 0.70)
		sb.border_color = Color(0.3, 0.4, 0.5, 0.4)
		_btn.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75, 0.7))
	_btn.add_theme_stylebox_override("normal", sb)
	_btn.add_theme_stylebox_override("hover", sb)
	_btn.add_theme_stylebox_override("pressed", sb)


func set_checked(c: bool) -> void:
	is_checked = c
	if _btn:
		_btn.button_pressed = c
	_update_btn_style()
