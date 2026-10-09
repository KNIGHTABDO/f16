class_name PauseMenu
extends Control
## In-flight pause menu with Resume, Settings, Restart, and Quit to Menu options.

var _settings_subview: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = true

	# Dimmed backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.03, 0.06, 0.75)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 480)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	# Header Title
	var title_lbl := Label.new()
	title_lbl.text = "MISSION PAUSED"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	vbox.add_child(title_lbl)

	# Status Subtitle
	var status_lbl := Label.new()
	var ac_name: String = GameState.selected_aircraft.to_upper()
	var mode_name: String = GameState.selected_mode.capitalize().replace("_", " ")
	status_lbl.text = "SORTIE: %s  |  %s  |  CALLSIGN: %s" % [
		mode_name,
		ac_name,
		Settings.pilot_callsign.to_upper()
	]
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 13)
	status_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.8))
	vbox.add_child(status_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.25, 0.82, 1.0, 0.25)
	vbox.add_child(sep)

	# Action Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 12)
	btn_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_vbox)

	var btn_resume := _create_btn("RESUME SORTIE")
	btn_resume.pressed.connect(_on_resume_pressed)
	btn_vbox.add_child(btn_resume)

	var btn_settings := _create_btn("SETTINGS")
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_vbox.add_child(btn_settings)

	var btn_restart := _create_btn("RESTART SORTIE")
	btn_restart.pressed.connect(_on_restart_pressed)
	btn_vbox.add_child(btn_restart)

	var btn_quit := _create_btn("QUIT TO MENU")
	btn_quit.pressed.connect(_on_quit_pressed)
	btn_vbox.add_child(btn_quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _settings_subview:
			_settings_subview.queue_free()
			_settings_subview = null
		else:
			_on_resume_pressed()
		get_viewport().set_input_as_handled()


func _create_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(360, 56)
	btn.add_theme_font_size_override("font_size", 20)
	return btn


func _on_resume_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	get_tree().paused = false
	queue_free()


func _on_settings_pressed() -> void:
	Sfx.play_2d("ui_click")
	if _settings_subview:
		return

	var subview := Control.new()
	subview.process_mode = Node.PROCESS_MODE_ALWAYS
	subview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(subview)
	_settings_subview = subview

	var settings_screen := preload("res://ui/menu/settings_screen.gd").new()
	settings_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	subview.add_child(settings_screen)

	# Overlay back button to return from in-pause settings
	var back_btn := Button.new()
	back_btn.text = "◀  BACK TO PAUSE"
	back_btn.custom_minimum_size = Vector2(170, 52)
	back_btn.position = Vector2(24, 18)
	back_btn.pressed.connect(func():
		Sfx.play_2d("ui_back")
		subview.queue_free()
		_settings_subview = null
	)
	subview.add_child(back_btn)


func _on_restart_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	get_tree().paused = false
	WorldOrigin.reset()
	GameState.start_flight()
	queue_free()


func _on_quit_pressed() -> void:
	Sfx.play_2d("ui_back")
	get_tree().paused = false
	GameState.goto_menu()
	queue_free()
