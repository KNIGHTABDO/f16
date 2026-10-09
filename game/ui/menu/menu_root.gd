class_name MenuRoot
extends Control
## Root menu manager with safe-area handling, navigation screen stack, and slide+fade transitions.

const TRANSITION_DURATION := 0.28
const DEFAULT_MARGIN_X := 24
const DEFAULT_MARGIN_Y := 16

var _screen_stack: Array[Control] = []
var _screen_container: Control
var _safe_margin_container: MarginContainer
var _top_bar: HBoxContainer
var _back_button: Button
var _is_transitioning := false


func _ready() -> void:
	# Stretch to full viewport
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = load("res://ui/theme/knight_theme.tres")

	_safe_margin_container = MarginContainer.new()
	_safe_margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_safe_margin_container)

	_update_safe_area_margins()
	get_viewport().size_changed.connect(_update_safe_area_margins)

	# Container for active screens
	_screen_container = Control.new()
	_screen_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_safe_margin_container.add_child(_screen_container)

	# Top navigation bar overlay
	var top_layer := Control.new()
	top_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe_margin_container.add_child(top_layer)

	_top_bar = HBoxContainer.new()
	_top_bar.position = Vector2(0, 0)
	_top_bar.custom_minimum_size = Vector2(0, 64)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_layer.add_child(_top_bar)

	_back_button = Button.new()
	_back_button.text = "◀  BACK"
	_back_button.custom_minimum_size = Vector2(130, 56)
	_back_button.visible = false
	_back_button.pressed.connect(_on_back_pressed)
	_top_bar.add_child(_back_button)

	# Initial screen: Main Menu Screen
	var main_screen := preload("res://ui/menu/main_menu_screen.gd").new()
	push_screen(main_screen, false)


func _update_safe_area_margins() -> void:
	if not _safe_margin_container:
		return
	var vp_size := get_viewport_rect().size
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()

	var margin_left := DEFAULT_MARGIN_X
	var margin_right := DEFAULT_MARGIN_X
	var margin_top := DEFAULT_MARGIN_Y
	var margin_bottom := DEFAULT_MARGIN_Y

	if screen_size.x > 0 and screen_size.y > 0 and safe_area.size.x > 0 and safe_area.size.y > 0:
		var scale_x: float = vp_size.x / float(screen_size.x)
		var scale_y: float = vp_size.y / float(screen_size.y)
		var safe_left: int = int(round(float(safe_area.position.x) * scale_x))
		var safe_top: int = int(round(float(safe_area.position.y) * scale_y))
		var safe_right: int = int(round(float(screen_size.x - safe_area.end.x) * scale_x))
		var safe_bottom: int = int(round(float(screen_size.y - safe_area.end.y) * scale_y))

		margin_left = maxi(margin_left, safe_left)
		margin_right = maxi(margin_right, safe_right)
		margin_top = maxi(margin_top, safe_top)
		margin_bottom = maxi(margin_bottom, safe_bottom)

	_safe_margin_container.add_theme_constant_override("margin_left", margin_left)
	_safe_margin_container.add_theme_constant_override("margin_right", margin_right)
	_safe_margin_container.add_theme_constant_override("margin_top", margin_top)
	_safe_margin_container.add_theme_constant_override("margin_bottom", margin_bottom)


func push_screen(new_screen: Control, animated := true) -> void:
	if _is_transitioning:
		return
	var old_screen: Control = _screen_stack.back() if not _screen_stack.is_empty() else null

	new_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_container.add_child(new_screen)
	_screen_stack.append(new_screen)

	_update_back_button()

	if not animated or old_screen == null:
		if old_screen != null:
			old_screen.visible = false
		new_screen.visible = true
		new_screen.modulate.a = 1.0
		new_screen.position = Vector2.ZERO
		return

	_is_transitioning = true
	var vp_width := get_viewport_rect().size.x

	new_screen.visible = true
	new_screen.position = Vector2(vp_width * 0.35, 0)
	new_screen.modulate.a = 0.0

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(new_screen, "position:x", 0.0, TRANSITION_DURATION)
	tween.tween_property(new_screen, "modulate:a", 1.0, TRANSITION_DURATION)

	if old_screen:
		tween.tween_property(old_screen, "position:x", -vp_width * 0.25, TRANSITION_DURATION)
		tween.tween_property(old_screen, "modulate:a", 0.0, TRANSITION_DURATION)

	tween.chain().tween_callback(func():
		_is_transitioning = false
		if old_screen:
			old_screen.visible = false
	)


func pop_screen(animated := true) -> void:
	if _is_transitioning or _screen_stack.size() <= 1:
		return

	var top_screen: Control = _screen_stack.pop_back()
	var prev_screen: Control = _screen_stack.back()

	_update_back_button()

	if not animated:
		top_screen.queue_free()
		if prev_screen:
			prev_screen.visible = true
			prev_screen.modulate.a = 1.0
			prev_screen.position = Vector2.ZERO
		return

	_is_transitioning = true
	var vp_width := get_viewport_rect().size.x

	if prev_screen:
		prev_screen.visible = true
		prev_screen.position = Vector2(-vp_width * 0.25, 0)
		prev_screen.modulate.a = 0.0

	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(top_screen, "position:x", vp_width * 0.35, TRANSITION_DURATION)
	tween.tween_property(top_screen, "modulate:a", 0.0, TRANSITION_DURATION)

	if prev_screen:
		tween.tween_property(prev_screen, "position:x", 0.0, TRANSITION_DURATION)
		tween.tween_property(prev_screen, "modulate:a", 1.0, TRANSITION_DURATION)

	tween.chain().tween_callback(func():
		_is_transitioning = false
		top_screen.queue_free()
	)


func _update_back_button() -> void:
	if _back_button:
		_back_button.visible = _screen_stack.size() > 1


func _on_back_pressed() -> void:
	Sfx.play_2d("ui_back", -2.0)
	pop_screen(true)
