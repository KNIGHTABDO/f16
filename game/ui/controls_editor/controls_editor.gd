class_name ControlsEditor
extends Control
## On-screen touch layout editor allowing repositioning, resizing, and opacity adjustment of flight buttons.

const BUTTON_LABELS := {
	"stick": "FLIGHT STICK",
	"throttle": "THROTTLE",
	"gun": "GUN FIRE",
	"weapon": "FIRE MISSILE",
	"cycle_weapon": "CYCLE WPN",
	"cycle_target": "CYCLE TGT",
	"flares": "FLARES",
	"airbrake": "AIRBRAKE",
	"gear": "LND GEAR",
	"camera": "CAMERA",
	"look": "LOOK VIEW",
	"pause": "PAUSE",
	"radio": "RADIO"
}

var _layout_data: Dictionary = {}
var _button_nodes: Dictionary = {}
var _selected_btn_key: String = ""
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

var _selected_label: Label
var _scale_slider: HSlider
var _opacity_slider: HSlider
var _editor_canvas: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://ui/theme/knight_theme.tres")

	# Load current layout or defaults
	_layout_data = Settings.touch_layout.duplicate(true)
	if _layout_data.is_empty():
		_layout_data = Settings.DEFAULT_TOUCH_LAYOUT.duplicate(true)

	# Ensure every key exists in _layout_data
	for k in Settings.DEFAULT_TOUCH_LAYOUT:
		if not _layout_data.has(k):
			_layout_data[k] = Settings.DEFAULT_TOUCH_LAYOUT[k].duplicate(true)

	# Dark tactical HUD grid background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.07, 0.95)
	add_child(bg)

	_editor_canvas = Control.new()
	_editor_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor_canvas)

	# Grid & horizon lines decoration
	_create_mock_hud_overlay()

	# Create draggable buttons
	for btn_key in BUTTON_LABELS:
		_create_touch_button_widget(btn_key)

	# Top Editor Toolbar
	_create_toolbar()

	# Select first button by default
	_select_button("gun")


func _create_mock_hud_overlay() -> void:
	var hud_overlay := Control.new()
	hud_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor_canvas.add_child(hud_overlay)

	# Center crosshair watermark
	var center_pip := Label.new()
	center_pip.text = "+\n[ HUD TOUCH CONTROLS CONFIGURATION ]"
	center_pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_pip.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center_pip.add_theme_color_override("font_color", Color(0.25, 0.82, 1.0, 0.25))
	center_pip.add_theme_font_size_override("font_size", 16)
	center_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_overlay.add_child(center_pip)


func _create_touch_button_widget(key: String) -> void:
	var data: Dictionary = _layout_data.get(key, {"pos": [0.5, 0.5], "scale": 1.0, "opacity": 0.8})
	var pos_frac: Array = data.get("pos", [0.5, 0.5])
	var b_scale: float = float(data.get("scale", 1.0))
	var b_opacity: float = float(data.get("opacity", 0.8))

	var container := PanelContainer.new()
	container.name = "Btn_" + key
	container.mouse_filter = Control.MOUSE_FILTER_PASS

	var base_size := Vector2(100, 100) if key == "stick" else (Vector2(60, 140) if key == "throttle" else Vector2(80, 80))
	container.custom_minimum_size = base_size * b_scale
	container.size = container.custom_minimum_size

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.16, 0.24, b_opacity)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.25, 0.82, 1.0, 0.5)
	sb.corner_radius_top_left = int(container.custom_minimum_size.x * 0.5)
	sb.corner_radius_top_right = int(container.custom_minimum_size.x * 0.5)
	sb.corner_radius_bottom_right = int(container.custom_minimum_size.x * 0.5)
	sb.corner_radius_bottom_left = int(container.custom_minimum_size.x * 0.5)
	container.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = BUTTON_LABELS[key]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", int(14 * b_scale))
	lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, b_opacity))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(lbl)

	# Position based on fraction
	var vp_size := get_viewport_rect().size
	container.position = Vector2(pos_frac[0] * vp_size.x, pos_frac[1] * vp_size.y) - (container.size * 0.5)

	container.gui_input.connect(_on_button_gui_input.bind(key))
	_editor_canvas.add_child(container)
	_button_nodes[key] = container


func _on_button_gui_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_select_button(key)
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - _button_nodes[key].position
			else:
				_is_dragging = false
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_select_button(key)
			_is_dragging = true
			_drag_offset = st.position - _button_nodes[key].position
		else:
			_is_dragging = false


func _input(event: InputEvent) -> void:
	if not _is_dragging or _selected_btn_key == "":
		return

	var mouse_pos := Vector2.ZERO
	if event is InputEventMouseMotion:
		mouse_pos = (event as InputEventMouseMotion).position
	elif event is InputEventScreenDrag:
		mouse_pos = (event as InputEventScreenDrag).position
	else:
		return

	var node: Control = _button_nodes[_selected_btn_key]
	var new_pos := mouse_pos - _drag_offset
	var vp_size := get_viewport_rect().size

	# Clamp inside screen bounds
	new_pos.x = clampf(new_pos.x, 0, vp_size.x - node.size.x)
	new_pos.y = clampf(new_pos.y, 60, vp_size.y - node.size.y - 80)
	node.position = new_pos

	# Update fraction in _layout_data
	var center_pos := new_pos + (node.size * 0.5)
	var frac_x: float = clampf(center_pos.x / vp_size.x, 0.0, 1.0)
	var frac_y: float = clampf(center_pos.y / vp_size.y, 0.0, 1.0)
	_layout_data[_selected_btn_key]["pos"] = [frac_x, frac_y]


func _select_button(key: String) -> void:
	_selected_btn_key = key
	if _selected_label:
		_selected_label.text = "EDITING: " + BUTTON_LABELS[key]

	# Update visual highlights
	for k in _button_nodes:
		var node: Control = _button_nodes[k]
		var data: Dictionary = _layout_data[k]
		var b_opacity: float = float(data.get("opacity", 0.8))
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = int(node.size.x * 0.5)
		sb.corner_radius_top_right = int(node.size.x * 0.5)
		sb.corner_radius_bottom_right = int(node.size.x * 0.5)
		sb.corner_radius_bottom_left = int(node.size.x * 0.5)
		if k == key:
			sb.bg_color = Color(0.12, 0.32, 0.50, b_opacity)
			sb.border_width_left = 3
			sb.border_width_top = 3
			sb.border_width_right = 3
			sb.border_width_bottom = 3
			sb.border_color = Color("#3FD0FF")
		else:
			sb.bg_color = Color(0.06, 0.12, 0.18, b_opacity)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
			sb.border_color = Color(0.25, 0.82, 1.0, 0.35)
		node.add_theme_stylebox_override("panel", sb)

	# Update sliders to match selected button
	var cur_data: Dictionary = _layout_data[key]
	if _scale_slider:
		_scale_slider.set_value_no_signal(float(cur_data.get("scale", 1.0)))
	if _opacity_slider:
		_opacity_slider.set_value_no_signal(float(cur_data.get("opacity", 0.8)))


func _create_toolbar() -> void:
	# Bottom Controls Toolbar Panel
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.custom_minimum_size.y = 80.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.14, 0.95)
	sb.border_width_top = 2
	sb.border_color = Color(0.25, 0.82, 1.0, 0.4)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 24)
	bar.add_child(hbox)

	_selected_label = Label.new()
	_selected_label.custom_minimum_size = Vector2(180, 0)
	_selected_label.add_theme_font_size_override("font_size", 16)
	_selected_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	hbox.add_child(_selected_label)

	# Scale adjustment
	var hbox_scale := HBoxContainer.new()
	hbox_scale.add_theme_constant_override("separation", 8)
	hbox.add_child(hbox_scale)

	var scale_lbl := Label.new()
	scale_lbl.text = "SIZE:"
	scale_lbl.add_theme_font_size_override("font_size", 14)
	hbox_scale.add_child(scale_lbl)

	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.6
	_scale_slider.max_value = 1.8
	_scale_slider.step = 0.05
	_scale_slider.value = 1.0
	_scale_slider.custom_minimum_size = Vector2(130, 40)
	_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale_slider.value_changed.connect(_on_scale_slider_changed)
	hbox_scale.add_child(_scale_slider)

	# Opacity adjustment
	var hbox_op := HBoxContainer.new()
	hbox_op.add_theme_constant_override("separation", 8)
	hbox.add_child(hbox_op)

	var op_lbl := Label.new()
	op_lbl.text = "OPACITY:"
	op_lbl.add_theme_font_size_override("font_size", 14)
	hbox_op.add_child(op_lbl)

	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.2
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.value = 0.8
	_opacity_slider.custom_minimum_size = Vector2(130, 40)
	_opacity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_opacity_slider.value_changed.connect(_on_opacity_slider_changed)
	hbox_op.add_child(_opacity_slider)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Action Buttons
	var reset_btn := Button.new()
	reset_btn.text = "RESET DEFAULT"
	reset_btn.custom_minimum_size = Vector2(140, 48)
	reset_btn.pressed.connect(_on_reset_pressed)
	hbox.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "SAVE & EXIT"
	save_btn.custom_minimum_size = Vector2(140, 48)
	save_btn.pressed.connect(_on_save_pressed)
	hbox.add_child(save_btn)


func _on_scale_slider_changed(val: float) -> void:
	if _selected_btn_key == "":
		return
	_layout_data[_selected_btn_key]["scale"] = val
	var node: Control = _button_nodes[_selected_btn_key]
	var base_size := Vector2(100, 100) if _selected_btn_key == "stick" else (Vector2(60, 140) if _selected_btn_key == "throttle" else Vector2(80, 80))
	node.custom_minimum_size = base_size * val
	node.size = node.custom_minimum_size
	_select_button(_selected_btn_key)


func _on_opacity_slider_changed(val: float) -> void:
	if _selected_btn_key == "":
		return
	_layout_data[_selected_btn_key]["opacity"] = val
	_select_button(_selected_btn_key)


func _on_reset_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	_layout_data = Settings.DEFAULT_TOUCH_LAYOUT.duplicate(true)
	var vp_size := get_viewport_rect().size
	for k in _button_nodes:
		var node: Control = _button_nodes[k]
		var data: Dictionary = _layout_data[k]
		var pos_frac: Array = data["pos"]
		var b_scale: float = float(data["scale"])
		var base_size := Vector2(100, 100) if k == "stick" else (Vector2(60, 140) if k == "throttle" else Vector2(80, 80))
		node.custom_minimum_size = base_size * b_scale
		node.size = node.custom_minimum_size
		node.position = Vector2(pos_frac[0] * vp_size.x, pos_frac[1] * vp_size.y) - (node.size * 0.5)
	_select_button(_selected_btn_key)


func _on_save_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	Settings.set_value("touch_layout", _layout_data)
	Settings.save()
	var root := _get_menu_root()
	if root and root.has_method("pop_screen"):
		root.pop_screen()
	else:
		queue_free()


func _get_menu_root() -> Node:
	var cur: Node = get_parent()
	while cur != null:
		if cur.has_method("pop_screen"):
			return cur
		cur = cur.get_parent()
	return null
