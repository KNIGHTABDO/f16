class_name SettingsScreen
extends Control
## Complete settings screen with 9 tab categories, live application, and touch-first controls.

const SettingSlider = preload("res://ui/menu/widgets/setting_slider.gd")
const SettingToggle = preload("res://ui/menu/widgets/setting_toggle.gd")
const SettingChoice = preload("res://ui/menu/widgets/setting_choice.gd")
const SettingText = preload("res://ui/menu/widgets/setting_text.gd")
const SectionHeader = preload("res://ui/menu/widgets/section_header.gd")

const TAB_INFO := [
	{"id": "graphics", "name": "GRAPHICS", "icon": "res://ui/menu/art/graphics.png"},
	{"id": "flight", "name": "FLIGHT", "icon": "res://ui/menu/art/flight.png"},
	{"id": "controls", "name": "CONTROLS", "icon": "res://ui/menu/art/controls.png"},
	{"id": "camera", "name": "CAMERA", "icon": "res://ui/menu/art/camera.png"},
	{"id": "hud", "name": "HUD", "icon": "res://ui/menu/art/hud.png"},
	{"id": "audio", "name": "AUDIO", "icon": "res://ui/menu/art/audio.png"},
	{"id": "radio", "name": "RADIO", "icon": "res://ui/menu/art/radio.png"},
	{"id": "gameplay", "name": "GAMEPLAY", "icon": "res://ui/menu/art/gameplay.png"},
	{"id": "data", "name": "DATA", "icon": "res://ui/menu/art/data.png"}
]

var _current_tab_id: String = "graphics"
var _tab_buttons: Dictionary = {}
var _header_title: Label
var _scroll_container: ScrollContainer
var _content_box: VBoxContainer
var _radio_status_label: Label
var _playlist_choice: SettingChoice
var _genre_choice: SettingChoice


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dark military backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.05, 0.08, 0.92)
	add_child(bg)

	# Main Margin
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(main_vbox)

	# Top Bar: Title & Subtitle (offset for back button on top-left)
	var top_hbox := HBoxContainer.new()
	top_hbox.custom_minimum_size = Vector2(0, 56)
	main_vbox.add_child(top_hbox)

	var spacer_back := Control.new()
	spacer_back.custom_minimum_size = Vector2(150, 0)
	top_hbox.add_child(spacer_back)

	_header_title = Label.new()
	_header_title.text = "SETTINGS // GRAPHICS & DISPLAY"
	_header_title.add_theme_font_size_override("font_size", 26)
	_header_title.add_theme_color_override("font_color", Color("#3FD0FF"))
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_hbox.add_child(_header_title)

	# Body: Left Tab List + Right Scrollable Content Panel
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(body_hbox)

	# Left Tab Bar (Scrollable for smaller screens)
	var tab_scroll := ScrollContainer.new()
	tab_scroll.custom_minimum_size = Vector2(230, 0)
	tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_hbox.add_child(tab_scroll)

	var tab_vbox := VBoxContainer.new()
	tab_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_vbox.add_theme_constant_override("separation", 6)
	tab_scroll.add_child(tab_vbox)

	for tab in TAB_INFO:
		var btn := _create_tab_button(tab["id"], tab["name"], tab["icon"])
		tab_vbox.add_child(btn)
		_tab_buttons[tab["id"]] = btn

	# Right Content Area (Military Glass Panel Container)
	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_child(content_panel)

	_scroll_container = ScrollContainer.new()
	_scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_panel.add_child(_scroll_container)

	_content_box = VBoxContainer.new()
	_content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_box.add_theme_constant_override("separation", 8)
	_scroll_container.add_child(_content_box)

	# Radio Autoload signal connections for the Radio tab
	if has_node("/root/Radio"):
		var radio_node = get_node("/root/Radio")
		radio_node.status_changed.connect(_on_radio_status_changed)
		radio_node.playlists_loaded.connect(_on_radio_playlists_loaded)
		radio_node.genres_loaded.connect(_on_radio_genres_loaded)

	_select_tab("graphics")


func _create_tab_button(id: String, title: String, icon_path: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(210, 60)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(pad)

	var icon_rect := TextureRect.new()
	var tex: Texture2D = null
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path) as Texture2D
	elif FileAccess.file_exists(icon_path):
		var img := Image.load_from_file(icon_path)
		if img and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex:
		icon_rect.texture = tex
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.custom_minimum_size = Vector2(32, 32)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_rect)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	btn.pressed.connect(func():
		Sfx.play_2d("ui_click", -4.0)
		_select_tab(id)
	)
	return btn


func _select_tab(id: String) -> void:
	_current_tab_id = id

	for tab_id in _tab_buttons:
		var btn: Button = _tab_buttons[tab_id]
		var sb := StyleBoxFlat.new()
		sb.corner_radius_top_left = 10
		sb.corner_radius_top_right = 10
		sb.corner_radius_bottom_right = 10
		sb.corner_radius_bottom_left = 10
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		if tab_id == id:
			sb.bg_color = Color(0.12, 0.28, 0.42, 0.90)
			sb.border_width_left = 4
			sb.border_color = Color("#3FD0FF")
		else:
			sb.bg_color = Color(0.05, 0.09, 0.14, 0.60)
			sb.border_width_left = 0
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)

	# Update header text
	for tab in TAB_INFO:
		if tab["id"] == id:
			_header_title.text = "SETTINGS // " + str(tab["name"])
			break

	# Clear content and build requested tab
	for child in _content_box.get_children():
		child.queue_free()

	_scroll_container.scroll_vertical = 0

	match id:
		"graphics":
			_build_graphics_tab()
		"flight":
			_build_flight_tab()
		"controls":
			_build_controls_tab()
		"camera":
			_build_camera_tab()
		"hud":
			_build_hud_tab()
		"audio":
			_build_audio_tab()
		"radio":
			_build_radio_tab()
		"gameplay":
			_build_gameplay_tab()
		"data":
			_build_data_tab()


# ============================================================
# 1. GRAPHICS TAB
# ============================================================
func _build_graphics_tab() -> void:
	_content_box.add_child(SectionHeader.new("Display & Quality Preset", "Overall fidelity preset; tuning individual values switches to Custom."))

	var preset_choice := SettingChoice.new(
		"Graphics Preset", "Select overall graphics level or customize below.",
		[
			{"val": "low", "label": "LOW"},
			{"val": "balanced", "label": "BALANCED"},
			{"val": "high", "label": "HIGH"},
			{"val": "ultra", "label": "ULTRA"},
			{"val": "custom", "label": "CUSTOM"}
		],
		0, "graphics_preset"
	)
	preset_choice.set_by_value(Settings.graphics_preset)
	preset_choice.choice_changed.connect(func(val, _idx):
		if val != "custom":
			Settings.apply_graphics_preset(str(val))
			_select_tab("graphics")
	)
	_content_box.add_child(preset_choice)

	var fps_choice := SettingChoice.new(
		"Target Frame Rate", "Cap rendering frame rate (ProMotion 120Hz supported on iPad).",
		[
			{"val": 30, "label": "30 FPS"},
			{"val": 60, "label": "60 FPS"},
			{"val": 120, "label": "120 FPS"}
		],
		0, "fps_target"
	)
	fps_choice.set_by_value(Settings.fps_target)
	_content_box.add_child(fps_choice)

	_content_box.add_child(SettingSlider.new(
		"3D Render Scale", "Resolution scaling for 3D world geometry and terrain.",
		0.5, 1.0, 0.05, Settings.render_scale, "render_scale", "%.0f%%", 100.0
	))

	var msaa_choice := SettingChoice.new(
		"MSAA Anti-Aliasing", "Hardware multisample anti-aliasing for crisp edges.",
		[
			{"val": 0, "label": "OFF"},
			{"val": 1, "label": "2X"},
			{"val": 2, "label": "4X"}
		],
		0, "msaa_3d"
	)
	msaa_choice.set_by_value(Settings.msaa_3d)
	_content_box.add_child(msaa_choice)

	_content_box.add_child(SettingToggle.new(
		"FXAA Post-Processing", "Fast approximate anti-aliasing shader.",
		Settings.fxaa, "fxaa"
	))

	_content_box.add_child(SectionHeader.new("World & Environment", "Terrain, clouds, shadows, and environment draw distance."))

	var terrain_choice := SettingChoice.new(
		"Terrain Detail", "Resolution of procedural elevation & texturing.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}, {"val": "ultra", "label": "ULTRA"}],
		0, "terrain_detail"
	)
	terrain_choice.set_by_value(Settings.terrain_detail)
	_content_box.add_child(terrain_choice)

	_content_box.add_child(SettingSlider.new(
		"View Distance", "Atmospheric horizon distance in kilometers.",
		20.0, 100.0, 5.0, Settings.view_distance_km, "view_distance_km", "%.0f KM", 1.0
	))

	var cloud_choice := SettingChoice.new(
		"Cloud Quality", "Volumetric cloud layer density and steps.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}, {"val": "ultra", "label": "ULTRA"}],
		0, "cloud_quality"
	)
	cloud_choice.set_by_value(Settings.cloud_quality)
	_content_box.add_child(cloud_choice)

	var shadow_choice := SettingChoice.new(
		"Shadows Quality", "Directional sunlight shadow map resolution.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}, {"val": "ultra", "label": "ULTRA"}],
		0, "shadow_quality"
	)
	shadow_choice.set_by_value(Settings.shadow_quality)
	_content_box.add_child(shadow_choice)

	_content_box.add_child(SettingSlider.new(
		"Shadow Distance", "Maximum distance shadows are cast from camera.",
		500.0, 6000.0, 250.0, Settings.shadow_distance, "shadow_distance", "%.0f M", 1.0
	))

	var veg_choice := SettingChoice.new(
		"Vegetation Density", "Trees, shrubs, and terrain foliage coverage.",
		[{"val": "off", "label": "OFF"}, {"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}],
		0, "vegetation_density"
	)
	veg_choice.set_by_value(Settings.vegetation_density)
	_content_box.add_child(veg_choice)

	var city_choice := SettingChoice.new(
		"City Density", "Urban building density and landmark complexity.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}],
		0, "city_density"
	)
	city_choice.set_by_value(Settings.city_density)
	_content_box.add_child(city_choice)

	var fx_choice := SettingChoice.new(
		"Effects Quality", "Particles for smoke, missile trails, and fire.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}],
		0, "effects_quality"
	)
	fx_choice.set_by_value(Settings.effects_quality)
	_content_box.add_child(fx_choice)

	var water_choice := SettingChoice.new(
		"Water Quality", "Ocean shader wave physics and screen reflections.",
		[{"val": "low", "label": "LOW"}, {"val": "medium", "label": "MED"}, {"val": "high", "label": "HIGH"}],
		0, "water_quality"
	)
	water_choice.set_by_value(Settings.water_quality)
	_content_box.add_child(water_choice)

	_content_box.add_child(SectionHeader.new("Post-Processing & Atmosphere", "Lighting effects and cinematic colour filters."))

	_content_box.add_child(SettingToggle.new("Bloom / Glow", "Atmospheric bloom around sun, afterburners & explosions.", Settings.bloom, "bloom"))
	_content_box.add_child(SettingToggle.new("Lens Flare", "Anamorphic lens flares when looking near the sun.", Settings.lens_flare, "lens_flare"))
	_content_box.add_child(SettingToggle.new("Motion Speed Lines", "High-speed camera streak lines during Mach acceleration.", Settings.motion_blur, "motion_blur"))
	_content_box.add_child(SettingToggle.new("Heat Haze", "Jet engine exhaust distortion refraction effect.", Settings.heat_haze, "heat_haze"))

	_content_box.add_child(SettingSlider.new(
		"Brightness", "Global scene exposure level.",
		0.5, 1.5, 0.05, Settings.color_brightness, "color_brightness", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingSlider.new(
		"Contrast", "Colour dynamic range separation.",
		0.5, 1.5, 0.05, Settings.color_contrast, "color_contrast", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingSlider.new(
		"Saturation", "Colour richness and intensity.",
		0.5, 1.5, 0.05, Settings.color_saturation, "color_saturation", "%.0f%%", 100.0
	))

	var filter_choice := SettingChoice.new(
		"Colour Grading Filter", "Cinematic colour mood LUT.",
		[
			{"val": "none", "label": "NONE"},
			{"val": "warm", "label": "WARM SUN"},
			{"val": "cool", "label": "COOL BLUE"},
			{"val": "cinematic", "label": "CINEMATIC"},
			{"val": "vivid", "label": "VIVID COMBAT"}
		],
		0, "color_filter"
	)
	filter_choice.set_by_value(Settings.color_filter)
	_content_box.add_child(filter_choice)

	_content_box.add_child(SettingToggle.new("Show FPS Counter", "Display live FPS and frame time in flight HUD.", Settings.show_perf_hud, "show_perf_hud"))
	_content_box.add_child(SettingToggle.new("Battery Saver", "Cap frame rate at 30 FPS to reduce heat and power.", Settings.battery_saver, "battery_saver"))


# ============================================================
# 2. FLIGHT TAB
# ============================================================
func _build_flight_tab() -> void:
	_content_box.add_child(SectionHeader.new("Flight Physics & Model", "Select flight realism and active assistance systems."))

	var mode_choice := SettingChoice.new(
		"Flight Dynamics Model",
		"Arcade: Point-to-fly assist, stall prevented, accessible.\nRealistic: Authentic aerodynamics, full energy & stall physics.",
		[
			{"val": "arcade", "label": "ARCADE"},
			{"val": "realistic", "label": "REALISTIC"}
		],
		0, "flight_mode"
	)
	mode_choice.set_by_value(Settings.flight_mode)
	_content_box.add_child(mode_choice)

	_content_box.add_child(SectionHeader.new("Flight Computer Assists", "Fly-by-wire sub-routines and safety overrides."))

	_content_box.add_child(SettingToggle.new("Stall Protection", "Prevents entering uncontrollable deep aerodynamic stalls.", Settings.stall_protection, "stall_protection"))
	_content_box.add_child(SettingToggle.new("G-Force Limiter", "Limits structural stick pull to prevent pilot blackout.", Settings.g_limiter, "g_limiter"))
	_content_box.add_child(SettingToggle.new("Auto-Rudder", "Automatically coordinates turns and sideslip with ailerons.", Settings.auto_rudder, "auto_rudder"))
	_content_box.add_child(SettingToggle.new("Auto-Level Stick Release", "Levels wings to horizon when virtual stick is released.", Settings.auto_level, "auto_level"))
	_content_box.add_child(SettingToggle.new("Auto-Throttle Assist", "Maintains optimal cruise speed automatically.", Settings.auto_throttle, "auto_throttle"))
	_content_box.add_child(SettingToggle.new("Landing Assist", "Guides glideslope and aligns aircraft with runway threshold.", Settings.landing_assist, "landing_assist"))
	_content_box.add_child(SettingToggle.new("Blackout / Redout FX", "Simulates physiological vision loss under sustained Gs.", Settings.blackout_effects, "blackout_effects"))

	_content_box.add_child(SectionHeader.new("Damage & Cheats", "Combat damage rules and free flight modifiers."))

	var dmg_choice := SettingChoice.new(
		"Damage Model", "Severity of subsystem failure from weapon hits.",
		[
			{"val": "off", "label": "OFF"},
			{"val": "arcade", "label": "ARCADE"},
			{"val": "realistic", "label": "REALISTIC"}
		],
		0, "damage_model"
	)
	dmg_choice.set_by_value(Settings.damage_model)
	_content_box.add_child(dmg_choice)

	_content_box.add_child(SettingToggle.new("Infinite Fuel", "Fuel tanks never deplete.", Settings.infinite_fuel, "infinite_fuel"))
	_content_box.add_child(SettingToggle.new("Infinite Ammo", "Guns and missile hardpoints never run out of munitions.", Settings.infinite_ammo, "infinite_ammo"))
	_content_box.add_child(SettingToggle.new("Invincible (Free Flight)", "Immune to terrain impact and collision damage.", Settings.invincible, "invincible"))

	var unit_choice := SettingChoice.new(
		"Measurement Units", "Speed, altitude, and range units on HUD instruments.",
		[
			{"val": "aviation", "label": "AVIATION (KT / FT)"},
			{"val": "metric", "label": "METRIC (KM/H / M)"},
			{"val": "imperial", "label": "IMPERIAL (MPH / FT)"}
		],
		0, "units"
	)
	unit_choice.set_by_value(Settings.units)
	_content_box.add_child(unit_choice)


# ============================================================
# 3. CONTROLS TAB
# ============================================================
func _build_controls_tab() -> void:
	_content_box.add_child(SectionHeader.new("Control Scheme & Sensitivity", "Primary control input hardware and handling."))

	var scheme_choice := SettingChoice.new(
		"Control Scheme", "Primary pilot flight steering mechanism.",
		[
			{"val": "touch", "label": "TOUCH STICK"},
			{"val": "gyro", "label": "GYRO TILT"},
			{"val": "hybrid", "label": "HYBRID (AIM+STICK)"},
			{"val": "mouse_aim", "label": "MOUSE-AIM DRAG"}
		],
		0, "control_scheme"
	)
	scheme_choice.set_by_value(Settings.control_scheme)
	_content_box.add_child(scheme_choice)

	_content_box.add_child(SettingSlider.new(
		"Pitch Sensitivity", "Elevator stick response multiplier.",
		0.2, 2.0, 0.05, Settings.pitch_sensitivity, "pitch_sensitivity", "%.2fx", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Roll Sensitivity", "Aileron stick response multiplier.",
		0.2, 2.0, 0.05, Settings.roll_sensitivity, "roll_sensitivity", "%.2fx", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Yaw Sensitivity", "Rudder pedal response multiplier.",
		0.2, 2.0, 0.05, Settings.yaw_sensitivity, "yaw_sensitivity", "%.2fx", 1.0
	))

	_content_box.add_child(SectionHeader.new("Gyroscope Tilt Tuning", "Motion sensor calibration and filter parameters."))

	_content_box.add_child(SettingSlider.new(
		"Gyro Sensitivity", "Device tilt steering authority.",
		0.2, 3.0, 0.1, Settings.gyro_sensitivity, "gyro_sensitivity", "%.1fx", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Gyro Smoothing", "Filter out small hand jitter and tremor.",
		0.0, 1.0, 0.05, Settings.gyro_smoothing, "gyro_smoothing", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingSlider.new(
		"Gyro Dead Zone", "Central neutral zone before tilt applies input.",
		0.0, 0.20, 0.01, Settings.gyro_deadzone, "gyro_deadzone", "%.2f", 1.0
	))

	# Recalibrate Gyro Button Row
	var calib_panel := PanelContainer.new()
	calib_panel.custom_minimum_size.y = 88.0
	var sb_cal := StyleBoxFlat.new()
	sb_cal.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_cal.border_width_bottom = 1
	sb_cal.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_cal.corner_radius_top_left = 8
	sb_cal.corner_radius_top_right = 8
	sb_cal.corner_radius_bottom_right = 8
	sb_cal.corner_radius_bottom_left = 8
	sb_cal.content_margin_left = 16
	sb_cal.content_margin_right = 16
	calib_panel.add_theme_stylebox_override("panel", sb_cal)
	_content_box.add_child(calib_panel)

	var hbox_cal := HBoxContainer.new()
	hbox_cal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	calib_panel.add_child(hbox_cal)

	var vbox_cal_text := VBoxContainer.new()
	vbox_cal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_cal_text.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_cal.add_child(vbox_cal_text)

	var cal_lbl := Label.new()
	cal_lbl.text = "Recalibrate Gyroscope Neutral"
	cal_lbl.add_theme_font_size_override("font_size", 18)
	vbox_cal_text.add_child(cal_lbl)

	var cal_sub := Label.new()
	cal_sub.text = "Hold device in comfortable playing angle and tap to zero sensors."
	cal_sub.add_theme_font_size_override("font_size", 13)
	cal_sub.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
	vbox_cal_text.add_child(cal_sub)

	var cal_btn := Button.new()
	cal_btn.text = "RECALIBRATE"
	cal_btn.custom_minimum_size = Vector2(160, 48)
	cal_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cal_btn.pressed.connect(func():
		Settings.calibrate_gyro_requested.emit()
		Sfx.play_2d("ui_confirm")
		cal_btn.text = "CALIBRATED!"
		get_tree().create_timer(1.5).timeout.connect(func(): cal_btn.text = "RECALIBRATE")
	)
	hbox_cal.add_child(cal_btn)

	_content_box.add_child(SectionHeader.new("Touch & Virtual Stick", "Touch stick styling, aiming, and layout configuration."))

	_content_box.add_child(SettingToggle.new("Invert Pitch", "Push forward to dive, pull back to climb.", Settings.invert_pitch, "invert_pitch"))
	_content_box.add_child(SettingToggle.new("Left-Handed Layout", "Swap primary stick and weapon firing sides.", Settings.left_handed, "left_handed"))
	_content_box.add_child(SettingSlider.new(
		"Virtual Stick Size", "Radius of on-screen flight touch control.",
		0.7, 1.5, 0.05, Settings.stick_size, "stick_size", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingSlider.new(
		"Stick Dead Zone", "Center threshold before stick input begins.",
		0.0, 0.30, 0.02, Settings.stick_deadzone, "stick_deadzone", "%.0f%%", 100.0
	))

	var stick_float_choice := SettingChoice.new(
		"Stick Placement", "Fixed: pinned in place; Floating: appears under finger touch.",
		[{"val": false, "label": "FIXED"}, {"val": true, "label": "FLOATING"}],
		0, "stick_floating"
	)
	stick_float_choice.set_by_value(Settings.stick_floating)
	_content_box.add_child(stick_float_choice)

	_content_box.add_child(SettingToggle.new("Auto-Fire on Target Lead", "Fires vulcan cannon automatically when pip crosses target.", Settings.auto_fire, "auto_fire"))
	_content_box.add_child(SettingSlider.new(
		"Aim Assist Magnetism", "Crosshair magnetic pull towards locked target lead.",
		0.0, 1.0, 0.05, Settings.aim_assist, "aim_assist", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingToggle.new("Haptic Vibration", "Handheld tactile feedback on gunshots, stall & hits.", Settings.haptics, "haptics"))
	_content_box.add_child(SettingSlider.new(
		"Haptic Strength", "Vibration actuator motor intensity.",
		0.1, 1.0, 0.05, Settings.haptic_intensity, "haptic_intensity", "%.0f%%", 100.0
	))

	# Edit Touch Layout Button Row
	var editor_panel := PanelContainer.new()
	editor_panel.custom_minimum_size.y = 88.0
	var sb_ed := StyleBoxFlat.new()
	sb_ed.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_ed.border_width_bottom = 1
	sb_ed.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_ed.corner_radius_top_left = 8
	sb_ed.corner_radius_top_right = 8
	sb_ed.corner_radius_bottom_right = 8
	sb_ed.corner_radius_bottom_left = 8
	sb_ed.content_margin_left = 16
	sb_ed.content_margin_right = 16
	editor_panel.add_theme_stylebox_override("panel", sb_ed)
	_content_box.add_child(editor_panel)

	var hbox_ed := HBoxContainer.new()
	hbox_ed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor_panel.add_child(hbox_ed)

	var vbox_ed_text := VBoxContainer.new()
	vbox_ed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_ed_text.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_ed.add_child(vbox_ed_text)

	var ed_lbl := Label.new()
	ed_lbl.text = "HUD Touch Controls Editor"
	ed_lbl.add_theme_font_size_override("font_size", 18)
	vbox_ed_text.add_child(ed_lbl)

	var ed_sub := Label.new()
	ed_sub.text = "Drag, reposition, resize, and tune opacity for each flight button."
	ed_sub.add_theme_font_size_override("font_size", 13)
	ed_sub.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
	vbox_ed_text.add_child(ed_sub)

	var ed_btn := Button.new()
	ed_btn.text = "EDIT TOUCH LAYOUT"
	ed_btn.custom_minimum_size = Vector2(210, 48)
	ed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ed_btn.pressed.connect(_on_edit_touch_layout_pressed)
	hbox_ed.add_child(ed_btn)

	_content_box.add_child(SectionHeader.new("Gamepad Controller", "MFi / Xbox / PlayStation Bluetooth controller bindings."))

	_content_box.add_child(SettingToggle.new("Gamepad Controller Enabled", "Detect and accept Bluetooth hardware gamepad input.", Settings.gamepad_enabled, "gamepad_enabled"))

	for action in Settings.gamepad_bindings:
		var btn_name: String = str(Settings.gamepad_bindings[action])
		var row := SettingChoice.new(
			action.capitalize().replace("_", " "),
			"Assigned controller button mapping.",
			[{"val": btn_name, "label": btn_name}],
			0, ""
		)
		_content_box.add_child(row)


# ============================================================
# 4. CAMERA TAB
# ============================================================
func _build_camera_tab() -> void:
	_content_box.add_child(SectionHeader.new("Camera Perspectives & View", "Default flight perspective and Chase camera tuning."))

	var cam_view_choice := SettingChoice.new(
		"Default Camera View", "Perspective selected upon taking off.",
		[
			{"val": "chase", "label": "CHASE"},
			{"val": "cockpit", "label": "COCKPIT"},
			{"val": "far_chase", "label": "FAR CHASE"},
			{"val": "cinematic", "label": "CINEMATIC"}
		],
		0, "camera_default_view"
	)
	cam_view_choice.set_by_value(Settings.camera_default_view)
	_content_box.add_child(cam_view_choice)

	_content_box.add_child(SettingSlider.new(
		"Field of View (FOV)", "Horizontal camera lens angle in degrees.",
		60.0, 100.0, 1.0, Settings.camera_fov, "camera_fov", "%.0f°", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Chase Camera Distance", "Trailing distance behind the aircraft in meters.",
		10.0, 35.0, 1.0, Settings.camera_chase_distance, "camera_chase_distance", "%.1f M", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Chase Camera Height", "Elevation height above aircraft tail in meters.",
		1.0, 10.0, 0.5, Settings.camera_chase_height, "camera_chase_height", "%.1f M", 1.0
	))
	_content_box.add_child(SettingSlider.new(
		"Camera Shake Intensity", "Vibration shake during transonic speed & explosions.",
		0.0, 2.0, 0.1, Settings.camera_shake_intensity, "camera_shake_intensity", "%.0f%%", 100.0
	))

	_content_box.add_child(SectionHeader.new("Cockpit & Target Tracking", "Cockpit immersion and enemy padlock views."))

	_content_box.add_child(SettingToggle.new("Cockpit Gyro Look-Around", "Tilt device to look freely around the canopy.", Settings.camera_gyro_look, "camera_gyro_look"))
	_content_box.add_child(SettingToggle.new("Target Padlock View", "Camera automatically pivots to track selected target.", Settings.camera_padlock, "camera_padlock"))
	_content_box.add_child(SettingSlider.new(
		"Camera Smoothing", "Inertial lag and damping when aircraft maneuvers.",
		0.0, 1.0, 0.05, Settings.camera_smoothing, "camera_smoothing", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingToggle.new("Show Cockpit Frame", "Renders canopy struts, mirrors, and HUD glass frame.", Settings.camera_cockpit_canopy, "camera_cockpit_canopy"))


# ============================================================
# 5. HUD TAB
# ============================================================
func _build_hud_tab() -> void:
	_content_box.add_child(SectionHeader.new("Heads-Up Display Styling", "Tactical symbology coloration, scale, and opacity."))

	var hud_col_choice := SettingChoice.new(
		"HUD Phosphor Colour", "Military collimated HUD projection colour.",
		[
			{"val": "green", "label": "MIL-SPEC GREEN"},
			{"val": "cyan", "label": "TACTICAL CYAN"},
			{"val": "amber", "label": "AMBER WARNING"},
			{"val": "white", "label": "STARK WHITE"},
			{"val": "red", "label": "COMBAT RED"}
		],
		0, "hud_color"
	)
	hud_col_choice.set_by_value(Settings.hud_color)
	_content_box.add_child(hud_col_choice)

	_content_box.add_child(SettingSlider.new(
		"HUD Symbology Scale", "Size multiplier for HUD ladder, reticle, and tapes.",
		0.75, 1.25, 0.05, Settings.hud_scale, "hud_scale", "%.0f%%", 100.0
	))
	_content_box.add_child(SettingSlider.new(
		"HUD Glass Opacity", "Transparency of collimated HUD reticle lines.",
		0.3, 1.0, 0.05, Settings.hud_opacity, "hud_opacity", "%.0f%%", 100.0
	))

	_content_box.add_child(SectionHeader.new("Tactical Instruments & Gauges", "Toggle visibility of individual tactical HUD modules."))

	_content_box.add_child(SettingToggle.new("Tactical Minimap", "Round 2D radar minimap showing aircraft and terrain.", Settings.hud_show_minimap, "hud_show_minimap"))
	_content_box.add_child(SettingSlider.new(
		"Minimap Range Zoom", "Radar display radius range scale.",
		0.5, 2.0, 0.1, Settings.hud_minimap_zoom, "hud_minimap_zoom", "%.1fx", 1.0
	))
	_content_box.add_child(SettingToggle.new("Target Box & Lead Pip", "Displays target range, heading, and lead calculation.", Settings.hud_show_target_info, "hud_show_target_info"))
	_content_box.add_child(SettingToggle.new("Radar Warning Receiver (RWR)", "Azimuth threat indicator for active radar locks & SAMs.", Settings.hud_show_rwr, "hud_show_rwr"))
	_content_box.add_child(SettingToggle.new("Speed & Altitude Tapes", "Airspeed (IAS) and barometric altitude tape ladders.", Settings.hud_show_tapes, "hud_show_tapes"))
	_content_box.add_child(SettingToggle.new("G-Force Acceleration Meter", "Instantaneous and peak G indicator on left tape.", Settings.hud_show_g_meter, "hud_show_g_meter"))
	_content_box.add_child(SettingToggle.new("Waypoint & Objective Markers", "3D diamond markers for navigation waypoints.", Settings.hud_show_waypoints, "hud_show_waypoints"))
	_content_box.add_child(SettingToggle.new("Damage Direction Indicators", "Radial flashes indicating incoming fire azimuth.", Settings.hud_show_damage, "hud_show_damage"))
	_content_box.add_child(SettingToggle.new("Combat Kill Feed", "Notifications of splashed bandits and ground strikes.", Settings.hud_show_kill_feed, "hud_show_kill_feed"))
	_content_box.add_child(SettingToggle.new("Subtitles for Radio Voices", "Display on-screen captions for AWACS and tower chatter.", Settings.hud_subtitles, "hud_subtitles"))


# ============================================================
# 6. AUDIO TAB
# ============================================================
func _build_audio_tab() -> void:
	_content_box.add_child(SectionHeader.new("Volume Channels", "Independent audio bus mixing sliders."))

	_content_box.add_child(SettingSlider.new("Master Volume", "Overall game audio master output.", 0.0, 1.0, 0.05, Settings.volume_master, "volume_master", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("Sound Effects", "World explosions, impacts, and sonic booms.", 0.0, 1.0, 0.05, Settings.volume_sfx, "volume_sfx", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("Jet Engine Volume", "Turbine whine and afterburner rumble.", 0.0, 1.0, 0.05, Settings.volume_engine, "volume_engine", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("Weapons & Cannon", "Vulcan gun bursts, missile launches, and bombs.", 0.0, 1.0, 0.05, Settings.volume_weapons, "volume_weapons", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("Menu & Music Volume", "Background orchestral score in menus and flight.", 0.0, 1.0, 0.05, Settings.volume_music, "volume_music", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("Radio Chatter & Warnings", "AWACS, wingmen calls, and cockpit voice warnings.", 0.0, 1.0, 0.05, Settings.volume_radio_chatter, "volume_radio_chatter", "%.0f%%", 100.0))
	_content_box.add_child(SettingSlider.new("User Interface Sounds", "Button clicks, confirmation beeps, and tactical alerts.", 0.0, 1.0, 0.05, Settings.volume_ui, "volume_ui", "%.0f%%", 100.0))

	_content_box.add_child(SectionHeader.new("Cockpit Acoustics & Voice", "Cockpit canopy muffling, radio filter and voice warning system."))

	_content_box.add_child(SettingToggle.new("Cockpit Acoustic Muffle", "Low-pass filters exterior engine sounds in cockpit view.", Settings.cockpit_muffle, "cockpit_muffle"))
	_content_box.add_child(SettingToggle.new("Cockpit Radio Effect", "Military band-pass filter on the music radio in cockpit view.", Settings.radio_cockpit_fx, "radio_cockpit_fx"))

	var voice_choice := SettingChoice.new(
		"Voice Warning System (VWS)", "Cockpit audible alarm voice style.",
		[
			{"val": "female", "label": "FEMALE ('BETTY')"},
			{"val": "male", "label": "MALE ('BOB')"},
			{"val": "tones", "label": "TONES ONLY"}
		],
		0, "warning_voice"
	)
	voice_choice.set_by_value(Settings.warning_voice)
	_content_box.add_child(voice_choice)

	_content_box.add_child(SettingToggle.new("Mute When In Background", "Silence game when switching to iOS home screen.", Settings.mute_in_background, "mute_in_background"))


# ============================================================
# 7. RADIO TAB
# ============================================================
func _build_radio_tab() -> void:
	_content_box.add_child(SectionHeader.new("Navidrome / OpenSubsonic Server", "Stream personal music directly to your aircraft radio."))

	_content_box.add_child(SettingToggle.new("Radio Streaming Enabled", "Activate background streaming over HTTPS.", Settings.radio_enabled, "radio_enabled"))
	_content_box.add_child(SettingText.new("Server URL", "Full URL of Navidrome or OpenSubsonic server.", Settings.navidrome_url, false, "navidrome_url", "https://music.example.com"))
	_content_box.add_child(SettingText.new("Username", "Subsonic user login username.", Settings.navidrome_user, false, "navidrome_user", "pilot"))
	_content_box.add_child(SettingText.new("Password", "Subsonic token auth password (masked).", Settings.navidrome_password, true, "navidrome_password", "••••••••"))

	# Test Connection Action Row
	var test_panel := PanelContainer.new()
	test_panel.custom_minimum_size.y = 88.0
	var sb_test := StyleBoxFlat.new()
	sb_test.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_test.border_width_bottom = 1
	sb_test.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_test.corner_radius_top_left = 8
	sb_test.corner_radius_top_right = 8
	sb_test.corner_radius_bottom_right = 8
	sb_test.corner_radius_bottom_left = 8
	sb_test.content_margin_left = 16
	sb_test.content_margin_right = 16
	test_panel.add_theme_stylebox_override("panel", sb_test)
	_content_box.add_child(test_panel)

	var hbox_test := HBoxContainer.new()
	hbox_test.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	test_panel.add_child(hbox_test)

	var vbox_t_text := VBoxContainer.new()
	vbox_t_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_t_text.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_test.add_child(vbox_t_text)

	var t_lbl := Label.new()
	t_lbl.text = "Connection Status"
	t_lbl.add_theme_font_size_override("font_size", 18)
	vbox_t_text.add_child(t_lbl)

	_radio_status_label = Label.new()
	_radio_status_label.text = "Status: " + (Radio.status if has_node("/root/Radio") else "off")
	_radio_status_label.add_theme_font_size_override("font_size", 14)
	_radio_status_label.add_theme_color_override("font_color", Color("#3FD0FF"))
	vbox_t_text.add_child(_radio_status_label)

	var test_btn := Button.new()
	test_btn.text = "TEST CONNECTION"
	test_btn.custom_minimum_size = Vector2(180, 48)
	test_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	test_btn.pressed.connect(func():
		if has_node("/root/Radio"):
			_radio_status_label.text = "Testing connection..."
			Radio.test_connection()
			Radio.fetch_playlists()
			Radio.fetch_genres()
	)
	hbox_test.add_child(test_btn)

	_content_box.add_child(SectionHeader.new("Music Source & Playlists", "Select playback mode and playlist."))

	var source_choice := SettingChoice.new(
		"Radio Source", "Source selection for continuous playback queue.",
		[
			{"val": "random", "label": "RANDOM SONGS"},
			{"val": "starred", "label": "STARRED FAVORITES"},
			{"val": "playlist", "label": "PLAYLIST"},
			{"val": "genre", "label": "GENRE"}
		],
		0, "radio_source"
	)
	source_choice.set_by_value(Settings.radio_source)
	_content_box.add_child(source_choice)

	_playlist_choice = SettingChoice.new(
		"Playlist", "Select server playlist (loaded automatically via Test Connection).",
		[{"val": "", "label": "DEFAULT / NONE"}], 0, "radio_playlist_id"
	)
	_content_box.add_child(_playlist_choice)

	_genre_choice = SettingChoice.new(
		"Music Genre", "Select server music genre tag.",
		[{"val": "", "label": "ALL GENRES"}], 0, "radio_genre"
	)
	_content_box.add_child(_genre_choice)

	_content_box.add_child(SettingToggle.new("Shuffle Playback", "Randomize song queue order.", Settings.radio_shuffle, "radio_shuffle"))
	_content_box.add_child(SettingToggle.new("Auto-Start When Flying", "Start music radio automatically once wheels leave runway.", Settings.radio_autostart, "radio_autostart"))
	_content_box.add_child(SettingSlider.new("Radio Volume", "Music radio playback level.", 0.0, 1.0, 0.05, Settings.volume_radio, "volume_radio", "%.0f%%", 100.0))
	_content_box.add_child(SettingToggle.new("Duck During Voice Warnings", "Lower music volume by 6 dB during missile/stall alerts.", Settings.radio_duck_during_warnings, "radio_duck_during_warnings"))
	_content_box.add_child(SettingToggle.new("Show Now-Playing Toast", "Display banner at top of screen when song starts.", Settings.radio_show_toast, "radio_show_toast"))


# ============================================================
# 8. GAMEPLAY TAB
# ============================================================
func _build_gameplay_tab() -> void:
	_content_box.add_child(SectionHeader.new("Simulation Difficulty", "Enemy AI skill and mission difficulty tuning."))

	var diff_choice := SettingChoice.new(
		"Difficulty Level", "Opponent piloting accuracy, reaction times, and missile evasion.",
		[
			{"val": "easy", "label": "EASY - CADET"},
			{"val": "normal", "label": "NORMAL - VETERAN"},
			{"val": "hard", "label": "HARD - ELITE"},
			{"val": "ace", "label": "ACE - DEADLY"}
		],
		0, "gameplay_difficulty"
	)
	diff_choice.set_by_value(Settings.gameplay_difficulty)
	_content_box.add_child(diff_choice)

	var tod_choice := SettingChoice.new(
		"Default Time of Day", "Sun azimuth and atmospheric lighting for free flight.",
		[
			{"val": "dawn", "label": "DAWN (06:30)"},
			{"val": "noon", "label": "HIGH NOON (12:00)"},
			{"val": "sunset", "label": "DRAMATIC SUNSET (19:30)"},
			{"val": "night", "label": "MIDNIGHT (00:00)"},
			{"val": "realtime", "label": "REAL TIME (LOCAL CLOCK)"}
		],
		0, "gameplay_time_of_day"
	)
	tod_choice.set_by_value(Settings.gameplay_time_of_day)
	_content_box.add_child(tod_choice)

	var weather_choice := SettingChoice.new(
		"Default Weather", "Atmospheric cloud ceiling and precipitation.",
		[
			{"val": "clear", "label": "CLEAR SKIES"},
			{"val": "scattered", "label": "SCATTERED CLOUDS"},
			{"val": "overcast", "label": "OVERCAST & GLOOM"},
			{"val": "storm", "label": "TURBULENT STORM"}
		],
		0, "gameplay_weather"
	)
	weather_choice.set_by_value(Settings.gameplay_weather)
	_content_box.add_child(weather_choice)

	_content_box.add_child(SectionHeader.new("Scenario Spawning & AI Density", "Air and ground combat population density."))

	_content_box.add_child(SettingSlider.new(
		"AI Aircraft Count", "Maximum simultaneous enemy aircraft in air combat scenarios.",
		1.0, 12.0, 1.0, float(Settings.gameplay_ai_count), "gameplay_ai_count", "%.0f JETS", 1.0
	))

	var ground_choice := SettingChoice.new(
		"Ground Target Density", "Prevalence of SAM sites, radar towers, and convoys.",
		[
			{"val": "low", "label": "LOW"},
			{"val": "medium", "label": "MEDIUM"},
			{"val": "high", "label": "HIGH"}
		],
		0, "gameplay_ground_density"
	)
	ground_choice.set_by_value(Settings.gameplay_ground_density)
	_content_box.add_child(ground_choice)

	_content_box.add_child(SettingToggle.new("Friendly AI Wingmen", "Spawn allied fighters providing air cover and escort.", Settings.gameplay_wingmen, "gameplay_wingmen"))
	_content_box.add_child(SettingToggle.new("Mission Time Limit", "Enforce tactical sortie timer during combat missions.", Settings.gameplay_time_limit, "gameplay_time_limit"))
	_content_box.add_child(SettingToggle.new("Show Tutorial Hints", "Display in-flight tactical tips for maneuvers & radar.", Settings.gameplay_tutorial_hints, "gameplay_tutorial_hints"))


# ============================================================
# 9. DATA TAB
# ============================================================
func _build_data_tab() -> void:
	_content_box.add_child(SectionHeader.new("Pilot Profile & Callsign", "Player tactical callsign and account modifiers."))

	_content_box.add_child(SettingText.new("Pilot Callsign", "Tactical callsign shown in HUD, menus, and kill feed.", Settings.pilot_callsign, false, "pilot_callsign", "VIPER"))
	_content_box.add_child(SettingToggle.new("Unlock All Aircraft", "Developer / personal use toggle unlocking all jets immediately.", Settings.unlock_all_aircraft, "unlock_all_aircraft"))

	_content_box.add_child(SectionHeader.new("Settings Backup & Transfer", "Export or import settings configuration as JSON text."))

	# Export / Import Row
	var exp_panel := PanelContainer.new()
	exp_panel.custom_minimum_size.y = 88.0
	var sb_exp := StyleBoxFlat.new()
	sb_exp.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_exp.border_width_bottom = 1
	sb_exp.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_exp.corner_radius_top_left = 8
	sb_exp.corner_radius_top_right = 8
	sb_exp.corner_radius_bottom_right = 8
	sb_exp.corner_radius_bottom_left = 8
	sb_exp.content_margin_left = 16
	sb_exp.content_margin_right = 16
	exp_panel.add_theme_stylebox_override("panel", sb_exp)
	_content_box.add_child(exp_panel)

	var hbox_exp := HBoxContainer.new()
	hbox_exp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox_exp.add_theme_constant_override("separation", 12)
	exp_panel.add_child(hbox_exp)

	var vbox_exp_t := VBoxContainer.new()
	vbox_exp_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_exp_t.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_exp.add_child(vbox_exp_t)

	var exp_lbl := Label.new()
	exp_lbl.text = "Clipboard Backup"
	exp_lbl.add_theme_font_size_override("font_size", 18)
	vbox_exp_t.add_child(exp_lbl)

	var exp_sub := Label.new()
	exp_sub.text = "Copy entire configuration to clipboard or paste from JSON string."
	exp_sub.add_theme_font_size_override("font_size", 13)
	exp_sub.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
	vbox_exp_t.add_child(exp_sub)

	var exp_btn := Button.new()
	exp_btn.text = "EXPORT TO CLIPBOARD"
	exp_btn.custom_minimum_size = Vector2(180, 48)
	exp_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exp_btn.pressed.connect(_on_export_pressed.bind(exp_btn))
	hbox_exp.add_child(exp_btn)

	var imp_btn := Button.new()
	imp_btn.text = "IMPORT FROM CLIPBOARD"
	imp_btn.custom_minimum_size = Vector2(190, 48)
	imp_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	imp_btn.pressed.connect(_on_import_pressed.bind(imp_btn))
	hbox_exp.add_child(imp_btn)

	_content_box.add_child(SectionHeader.new("Factory Reset Options", "Reset configurations or clear pilot mission progress."))

	# Reset Settings Button Row
	var reset_s_panel := PanelContainer.new()
	reset_s_panel.custom_minimum_size.y = 88.0
	var sb_rs := StyleBoxFlat.new()
	sb_rs.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_rs.border_width_bottom = 1
	sb_rs.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_rs.corner_radius_top_left = 8
	sb_rs.corner_radius_top_right = 8
	sb_rs.corner_radius_bottom_right = 8
	sb_rs.corner_radius_bottom_left = 8
	sb_rs.content_margin_left = 16
	sb_rs.content_margin_right = 16
	reset_s_panel.add_theme_stylebox_override("panel", sb_rs)
	_content_box.add_child(reset_s_panel)

	var hbox_rs := HBoxContainer.new()
	hbox_rs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_s_panel.add_child(hbox_rs)

	var vbox_rs_t := VBoxContainer.new()
	vbox_rs_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_rs_t.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_rs.add_child(vbox_rs_t)

	var rs_lbl := Label.new()
	rs_lbl.text = "Reset All Settings to Defaults"
	rs_lbl.add_theme_font_size_override("font_size", 18)
	vbox_rs_t.add_child(rs_lbl)

	var rs_sub := Label.new()
	rs_sub.text = "Restores all graphics, controls, audio, and camera sliders to factory defaults."
	rs_sub.add_theme_font_size_override("font_size", 13)
	rs_sub.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
	vbox_rs_t.add_child(rs_sub)

	var rst_btn := Button.new()
	rst_btn.text = "RESET SETTINGS"
	rst_btn.custom_minimum_size = Vector2(170, 48)
	rst_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rst_btn.pressed.connect(_on_reset_settings_pressed)
	hbox_rs.add_child(rst_btn)

	# Reset Progress Button Row
	var reset_p_panel := PanelContainer.new()
	reset_p_panel.custom_minimum_size.y = 88.0
	var sb_rp := StyleBoxFlat.new()
	sb_rp.bg_color = Color(0.04, 0.08, 0.13, 0.45)
	sb_rp.border_width_bottom = 1
	sb_rp.border_color = Color(0.25, 0.82, 1.0, 0.12)
	sb_rp.corner_radius_top_left = 8
	sb_rp.corner_radius_top_right = 8
	sb_rp.corner_radius_bottom_right = 8
	sb_rp.corner_radius_bottom_left = 8
	sb_rp.content_margin_left = 16
	sb_rp.content_margin_right = 16
	reset_p_panel.add_theme_stylebox_override("panel", sb_rp)
	_content_box.add_child(reset_p_panel)

	var hbox_rp := HBoxContainer.new()
	hbox_rp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_p_panel.add_child(hbox_rp)

	var vbox_rp_t := VBoxContainer.new()
	vbox_rp_t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox_rp_t.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_rp.add_child(vbox_rp_t)

	var rp_lbl := Label.new()
	rp_lbl.text = "Reset Pilot Career Progress"
	rp_lbl.add_theme_font_size_override("font_size", 18)
	vbox_rp_t.add_child(rp_lbl)

	var rp_sub := Label.new()
	rp_sub.text = "Clears completed sorties, best flight times, credits, and total kills."
	rp_sub.add_theme_font_size_override("font_size", 13)
	rp_sub.add_theme_color_override("font_color", Color(0.60, 0.68, 0.76, 0.8))
	vbox_rp_t.add_child(rp_sub)

	var rst_prog_btn := Button.new()
	rst_prog_btn.text = "RESET PROGRESS"
	rst_prog_btn.custom_minimum_size = Vector2(170, 48)
	rst_prog_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rst_prog_btn.pressed.connect(_on_reset_progress_pressed)
	hbox_rp.add_child(rst_prog_btn)


# ============================================================
# RADIO HANDLERS
# ============================================================
func _on_radio_status_changed(status: String) -> void:
	if _radio_status_label:
		_radio_status_label.text = "Status: " + status
		if status == "connected" or status == "playing":
			_radio_status_label.add_theme_color_override("font_color", Color("#4CAF50"))
		elif status.begins_with("error"):
			_radio_status_label.add_theme_color_override("font_color", Color("#FF5252"))
		else:
			_radio_status_label.add_theme_color_override("font_color", Color("#3FD0FF"))


func _on_radio_playlists_loaded(list: Array) -> void:
	if not _playlist_choice or list.is_empty():
		return
	var items: Array = [{"val": "", "label": "ALL TRACKS / SHUFFLE"}]
	for p in list:
		items.append({
			"val": "playlist:" + str(p.get("id", "")),
			"label": str(p.get("name", "Playlist")).to_upper() + " (" + str(p.get("count", 0)) + ")"
		})
	_playlist_choice.set_options(items, 0)


func _on_radio_genres_loaded(list: Array) -> void:
	if not _genre_choice or list.is_empty():
		return
	var items: Array = [{"val": "", "label": "ALL GENRES"}]
	for g in list:
		items.append({
			"val": "genre:" + str(g.get("name", "")),
			"label": str(g.get("name", "Genre")).to_upper() + " (" + str(g.get("count", 0)) + ")"
		})
	_genre_choice.set_options(items, 0)


# ============================================================
# ACTION HANDLERS
# ============================================================
func _on_edit_touch_layout_pressed() -> void:
	Sfx.play_2d("ui_click")
	var root := _get_menu_root()
	if root and root.has_method("push_screen"):
		var ed: Control = preload("res://ui/controls_editor/controls_editor.gd").new()
		root.push_screen(ed)


func _on_export_pressed(btn: Button) -> void:
	Sfx.play_2d("ui_confirm")
	var json_str := Settings.export_to_json()
	DisplayServer.clipboard_set(json_str)
	var prev_txt: String = btn.text
	btn.text = "COPIED TO CLIPBOARD!"
	get_tree().create_timer(1.8).timeout.connect(func(): btn.text = prev_txt)


func _on_import_pressed(btn: Button) -> void:
	var clip := DisplayServer.clipboard_get()
	if Settings.import_from_json(clip):
		Sfx.play_2d("ui_confirm")
		var prev_txt: String = btn.text
		btn.text = "IMPORTED SUCCESSFULLY!"
		get_tree().create_timer(1.8).timeout.connect(func():
			btn.text = prev_txt
			_select_tab(_current_tab_id)
		)
	else:
		Sfx.play_2d("ui_back")
		var prev_txt: String = btn.text
		btn.text = "INVALID JSON IN CLIPBOARD"
		get_tree().create_timer(1.8).timeout.connect(func(): btn.text = prev_txt)


func _on_reset_settings_pressed() -> void:
	Sfx.play_2d("ui_click")
	var dlg := ConfirmationDialog.new()
	dlg.title = "RESET ALL SETTINGS?"
	dlg.dialog_text = "Are you sure you want to restore all settings to default values?"
	dlg.confirmed.connect(func():
		Settings.reset_to_defaults()
		_select_tab(_current_tab_id)
	)
	add_child(dlg)
	dlg.popup_centered()


func _on_reset_progress_pressed() -> void:
	Sfx.play_2d("ui_click")
	var dlg := ConfirmationDialog.new()
	dlg.title = "RESET CAREER PROGRESS?"
	dlg.dialog_text = "Are you sure you want to erase all pilot sortie stats, kill counts, and best times?"
	dlg.confirmed.connect(func():
		GameState.credits = 0
		GameState.total_kills = 0
		GameState.missions_completed = 0
		GameState.flight_seconds = 0.0
		GameState.best_times.clear()
		GameState.mission_history.clear()
		GameState.save_progress()
	)
	add_child(dlg)
	dlg.popup_centered()


func _get_menu_root() -> Node:
	var cur: Node = get_parent()
	while cur != null:
		if cur.has_method("push_screen"):
			return cur
		cur = cur.get_parent()
	return null
