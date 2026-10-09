class_name MainMenuScreen
extends Control
## Main menu screen with animated panning background, military HUD accents, and primary navigation buttons.

var _bg_texture: TextureRect
var _pan_time: float = 0.0
var _callsign_label: Label
var _flight_btn: Button
var _hangar_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 1. Panning background container
	var bg_container := Control.new()
	bg_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_container.clip_contents = true
	add_child(bg_container)

	_bg_texture = TextureRect.new()
	var bg_path := "res://ui/menu/art/menu_bg.png"
	var bg_img: Texture2D = null
	if ResourceLoader.exists(bg_path):
		bg_img = load(bg_path) as Texture2D
	elif FileAccess.file_exists(bg_path):
		var img := Image.load_from_file(bg_path)
		if img and not img.is_empty():
			bg_img = ImageTexture.create_from_image(img)
	if bg_img:
		_bg_texture.texture = bg_img
		_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_bg_texture.custom_minimum_size = Vector2(1700, 720)
		_bg_texture.size = Vector2(1700, 720)
	bg_container.add_child(_bg_texture)

	# 2. Vignette / Dark gradient overlay for military glass look and readability
	var dark_overlay := ColorRect.new()
	dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark_overlay.color = Color(0.02, 0.05, 0.08, 0.55)
	add_child(dark_overlay)

	# Left gradient panel for menu buttons
	var left_gradient := Panel.new()
	left_gradient.position = Vector2(0, 0)
	left_gradient.custom_minimum_size = Vector2(480, 720)
	left_gradient.size = Vector2(480, 720)
	var sb_grad := StyleBoxFlat.new()
	sb_grad.bg_color = Color(0.03, 0.07, 0.12, 0.88)
	sb_grad.border_width_right = 2
	sb_grad.border_color = Color(0.25, 0.82, 1.0, 0.3)
	left_gradient.add_theme_stylebox_override("panel", sb_grad)
	add_child(left_gradient)

	# Main content layout
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var hbox_main := HBoxContainer.new()
	hbox_main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox_main.add_theme_constant_override("separation", 48)
	margin.add_child(hbox_main)

	# Left Column: Title + Buttons
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(400, 0)
	left_vbox.add_theme_constant_override("separation", 20)
	hbox_main.add_child(left_vbox)

	# Title Block
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	left_vbox.add_child(title_box)

	var title_lbl := Label.new()
	title_lbl.text = "KNIGHT WINGS"
	title_lbl.add_theme_font_size_override("font_size", 46)
	title_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	title_box.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "TACTICAL COMBAT FLIGHT SIMULATOR"
	sub_lbl.add_theme_font_size_override("font_size", 16)
	sub_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9, 0.85))
	title_box.add_child(sub_lbl)

	# Subtle separator
	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.25, 0.82, 1.0, 0.35)
	left_vbox.add_child(sep)

	# Button Menu Column
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 12)
	btn_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	left_vbox.add_child(btn_vbox)

	_flight_btn = _create_menu_button("FREE FLIGHT", "")
	_flight_btn.pressed.connect(_on_free_flight_pressed)
	btn_vbox.add_child(_flight_btn)

	var btn_missions := _create_menu_button("MISSIONS", "Air combat engagements & strikes")
	btn_missions.pressed.connect(_on_missions_pressed)
	btn_vbox.add_child(btn_missions)

	_hangar_btn = _create_menu_button("HANGAR", "")
	_hangar_btn.pressed.connect(_on_hangar_pressed)
	btn_vbox.add_child(_hangar_btn)

	var btn_settings := _create_menu_button("SETTINGS", "Controls, graphics, audio & radio")
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_vbox.add_child(btn_settings)

	var btn_credits := _create_menu_button("CREDITS", "Open assets & attribution")
	btn_credits.pressed.connect(_on_credits_pressed)
	btn_vbox.add_child(btn_credits)

	# Version & Pilot callsign bottom bar
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(bottom_hbox)

	var ver_lbl := Label.new()
	ver_lbl.text = "v1.0.0 MOBILE"
	ver_lbl.add_theme_font_size_override("font_size", 13)
	ver_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7, 0.7))
	bottom_hbox.add_child(ver_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(spacer)

	_callsign_label = Label.new()
	_update_callsign()
	_callsign_label.add_theme_font_size_override("font_size", 14)
	_callsign_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	bottom_hbox.add_child(_callsign_label)

	Settings.changed.connect(_on_settings_changed)
	_refresh_subtexts()


func _process(delta: float) -> void:
	if _bg_texture:
		_pan_time += delta * 0.04
		# Gentle smooth oscillation panning
		var offset_x: float = sin(_pan_time) * 160.0 - 160.0
		_bg_texture.position.x = offset_x


func _create_menu_button(text: String, subtext: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(380, 64)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var main_lbl := Label.new()
	main_lbl.text = text
	main_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	main_lbl.add_theme_font_size_override("font_size", 22)
	main_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	main_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(main_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = subtext
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.60, 0.70, 0.80, 0.75))
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_lbl)
	btn.set_meta("subtext", sub_lbl)

	return btn


func _update_callsign() -> void:
	if _callsign_label:
		_callsign_label.text = "PILOT: " + Settings.pilot_callsign.to_upper()


func _on_settings_changed(key: String) -> void:
	if key == "pilot_callsign" or key == "" or key == "all":
		_update_callsign()
	if key in ["", "all", "flight_mode", "gameplay_time_of_day", "gameplay_weather"]:
		_refresh_subtexts()


## Loads the level with the selected map, aircraft, and Settings flight mode, time of day and weather.
func _on_free_flight_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	GameState.selected_mode = "free_flight"
	GameState.start_flight()


func _on_missions_pressed() -> void:
	Sfx.play_2d("ui_confirm")
	GameState.selected_mode = "dogfight"
	GameState.start_flight()


## Hangar: opens the hangar screen (aircraft, loadout, livery).
func _on_hangar_pressed() -> void:
	Sfx.play_2d("ui_click")
	var root := _get_menu_root()
	if root and root.has_method("push_screen"):
		var hangar_screen := preload("res://ui/hangar/hangar.gd").new()
		root.push_screen(hangar_screen)


func _refresh_subtexts() -> void:
	var flight := "%s flight" % Settings.flight_mode.capitalize()
	var sky := "%s, %s" % [Settings.gameplay_time_of_day.capitalize(), Settings.gameplay_weather.capitalize()]
	_set_subtext(_flight_btn, "%s · %s · %s" % [GameState.selected_map.capitalize(), flight, sky])
	_set_subtext(_hangar_btn, "%s · open hangar" % _aircraft_name(GameState.selected_aircraft))


func _set_subtext(btn: Button, text: String) -> void:
	(btn.get_meta("subtext") as Label).text = text


func _aircraft_name(id: String) -> String:
	var data: Variant = GameState.load_json("res://data/aircraft/%s.json" % id)
	if data is Dictionary and data.has("short_name"):
		return str(data["short_name"])
	return id.to_upper()


func _aircraft_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at("res://data/aircraft"):
		if file.ends_with(".json"):
			ids.append(file.get_basename())
	ids.sort()
	return ids


func _on_settings_pressed() -> void:
	Sfx.play_2d("ui_click")
	var root := _get_menu_root()
	if root and root.has_method("push_screen"):
		var settings_screen := preload("res://ui/menu/settings_screen.gd").new()
		root.push_screen(settings_screen)


func _on_credits_pressed() -> void:
	Sfx.play_2d("ui_click")
	var root := _get_menu_root()
	if root and root.has_method("push_screen"):
		var credits_screen := preload("res://ui/menu/credits_screen.gd").new()
		root.push_screen(credits_screen)


func _get_menu_root() -> Node:
	var cur: Node = get_parent()
	while cur != null:
		if cur.has_method("push_screen"):
			return cur
		cur = cur.get_parent()
	return null
