class_name SettingText
extends PanelContainer

signal text_changed(new_text: String)
signal text_submitted(new_text: String)

var title: String = ""
var description: String = ""
var current_text: String = ""
var is_password: bool = false
var placeholder: String = ""
var setting_key: String = ""

var _title_label: Label
var _desc_label: Label
var _line_edit: LineEdit
var _toggle_eye_btn: Button


func _init(
	p_title: String = "",
	p_desc: String = "",
	p_text: String = "",
	p_is_pw: bool = false,
	p_key: String = "",
	p_placeholder: String = ""
) -> void:
	title = p_title
	description = p_desc
	current_text = p_text
	is_password = p_is_pw
	setting_key = p_key
	placeholder = p_placeholder


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
	vbox_left.size_flags_stretch_ratio = 1.0
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

	# Right side: LineEdit + Optional Password Toggle
	var hbox_right := HBoxContainer.new()
	hbox_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_right.size_flags_stretch_ratio = 1.2
	hbox_right.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_right.add_theme_constant_override("separation", 8)
	hbox.add_child(hbox_right)

	_line_edit = LineEdit.new()
	_line_edit.text = current_text
	_line_edit.placeholder_text = placeholder
	_line_edit.secret = is_password
	_line_edit.custom_minimum_size = Vector2(200, 48)
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line_edit.text_changed.connect(_on_text_changed)
	_line_edit.text_submitted.connect(_on_text_submitted)
	hbox_right.add_child(_line_edit)

	if is_password:
		_toggle_eye_btn = Button.new()
		_toggle_eye_btn.text = "SHOW"
		_toggle_eye_btn.custom_minimum_size = Vector2(64, 48)
		_toggle_eye_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_toggle_eye_btn.pressed.connect(_on_toggle_pw_pressed)
		hbox_right.add_child(_toggle_eye_btn)


func _on_text_changed(new_text: String) -> void:
	current_text = new_text
	if setting_key != "":
		Settings.set_value(setting_key, new_text)
	text_changed.emit(new_text)


func _on_text_submitted(new_text: String) -> void:
	current_text = new_text
	if setting_key != "":
		Settings.set_value(setting_key, new_text)
	text_submitted.emit(new_text)


func _on_toggle_pw_pressed() -> void:
	if not _line_edit or not _toggle_eye_btn:
		return
	_line_edit.secret = not _line_edit.secret
	_toggle_eye_btn.text = "HIDE" if not _line_edit.secret else "SHOW"
	Sfx.play_2d("ui_click", -4.0)


func get_text() -> String:
	return _line_edit.text if _line_edit else current_text


func set_text(t: String) -> void:
	current_text = t
	if _line_edit:
		_line_edit.text = t
