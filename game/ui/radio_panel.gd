class_name RadioPanel
extends Control
## In-flight radio and music streaming panel for Navidrome / OpenSubsonic.
## Allows track skipping, play/pause, volume adjustment, source switching, and status inspection.

signal closed

var _theme: Theme
var _status_lbl: Label
var _track_lbl: Label
var _artist_lbl: Label
var _play_btn: Button
var _source_btn: OptionButton
var _volume_slider: HSlider
var _cockpit_fx_btn: CheckButton
var _ducking_btn: CheckButton
var _playlists: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if ResourceLoader.exists("res://ui/theme/knight_theme.tres"):
		_theme = load("res://ui/theme/knight_theme.tres")
		theme = _theme

	# Dimmed backdrop
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.01, 0.03, 0.06, 0.75)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 520)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Title Header
	var title_lbl := Label.new()
	title_lbl.text = "TACTICAL RADIO / MUSIC"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	vbox.add_child(title_lbl)

	# Status row
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85, 0.8))
	vbox.add_child(_status_lbl)

	var sep := ColorRect.new()
	sep.custom_minimum_size = Vector2(0, 2)
	sep.color = Color(0.25, 0.82, 1.0, 0.25)
	vbox.add_child(sep)

	# Now Playing Box
	var now_box := PanelContainer.new()
	var now_style := StyleBoxFlat.new()
	now_style.bg_color = Color(0.04, 0.08, 0.14, 0.8)
	now_style.border_width_left = 1
	now_style.border_width_top = 1
	now_style.border_width_right = 1
	now_style.border_width_bottom = 1
	now_style.border_color = Color(0.25, 0.82, 1.0, 0.4)
	now_style.content_margin_left = 16
	now_style.content_margin_top = 14
	now_style.content_margin_right = 16
	now_style.content_margin_bottom = 14
	now_box.add_theme_stylebox_override("panel", now_style)
	vbox.add_child(now_box)

	var now_vbox := VBoxContainer.new()
	now_vbox.add_theme_constant_override("separation", 6)
	now_box.add_child(now_vbox)

	_track_lbl = Label.new()
	_track_lbl.text = "NO TRACK PLAYING"
	_track_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track_lbl.add_theme_font_size_override("font_size", 18)
	_track_lbl.add_theme_color_override("font_color", Color("#E8F0F8"))
	_track_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	now_vbox.add_child(_track_lbl)

	_artist_lbl = Label.new()
	_artist_lbl.text = "RADIO OFF"
	_artist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artist_lbl.add_theme_font_size_override("font_size", 14)
	_artist_lbl.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9, 0.8))
	now_vbox.add_child(_artist_lbl)

	# Transport Controls (Prev / Play / Next)
	var controls_hbox := HBoxContainer.new()
	controls_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	controls_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(controls_hbox)

	_play_btn = Button.new()
	_play_btn.text = "PLAY"
	_play_btn.custom_minimum_size = Vector2(140, 48)
	_play_btn.pressed.connect(_on_play_toggle)
	controls_hbox.add_child(_play_btn)

	var next_btn := Button.new()
	next_btn.text = "NEXT TRACK ⏭"
	next_btn.custom_minimum_size = Vector2(140, 48)
	next_btn.pressed.connect(_on_next_pressed)
	controls_hbox.add_child(next_btn)

	# Volume Slider
	var vol_hbox := HBoxContainer.new()
	vol_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(vol_hbox)

	var vol_lbl := Label.new()
	vol_lbl.text = "VOLUME:"
	vol_lbl.custom_minimum_size = Vector2(80, 0)
	vol_hbox.add_child(vol_lbl)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = Settings.volume_radio
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume_slider.value_changed.connect(_on_volume_changed)
	vol_hbox.add_child(_volume_slider)

	# Source Selector
	var src_hbox := HBoxContainer.new()
	src_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(src_hbox)

	var src_lbl := Label.new()
	src_lbl.text = "SOURCE:"
	src_lbl.custom_minimum_size = Vector2(80, 0)
	src_hbox.add_child(src_lbl)

	_source_btn = OptionButton.new()
	_source_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_btn.add_item("RANDOM", 0)
	_source_btn.add_item("STARRED", 1)
	_source_btn.item_selected.connect(_on_source_selected)
	src_hbox.add_child(_source_btn)

	# Cockpit FX & Ducking toggles
	var fx_hbox := HBoxContainer.new()
	fx_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	fx_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(fx_hbox)

	_cockpit_fx_btn = CheckButton.new()
	_cockpit_fx_btn.text = "COCKPIT RADIO FX"
	_cockpit_fx_btn.button_pressed = Settings.radio_cockpit_fx
	_cockpit_fx_btn.toggled.connect(_on_cockpit_fx_toggled)
	fx_hbox.add_child(_cockpit_fx_btn)

	_ducking_btn = CheckButton.new()
	_ducking_btn.text = "VOICE DUCKING"
	_ducking_btn.button_pressed = Settings.radio_duck_during_warnings
	_ducking_btn.toggled.connect(_on_ducking_toggled)
	fx_hbox.add_child(_ducking_btn)

	# Close / Back button
	var back_btn := Button.new()
	back_btn.text = "◀  BACK"
	back_btn.custom_minimum_size = Vector2(0, 48)
	back_btn.pressed.connect(_on_close_pressed)
	vbox.add_child(back_btn)

	# Connect signals
	if Radio != null:
		Radio.track_changed.connect(_on_track_changed)
		Radio.status_changed.connect(_on_status_changed)
		Radio.playlists_loaded.connect(_on_playlists_loaded)
		if Settings.radio_enabled and Radio.status != "playing":
			Radio.fetch_playlists()

	_sync_ui()


func _exit_tree() -> void:
	if Radio != null:
		if Radio.track_changed.is_connected(_on_track_changed):
			Radio.track_changed.disconnect(_on_track_changed)
		if Radio.status_changed.is_connected(_on_status_changed):
			Radio.status_changed.disconnect(_on_status_changed)
		if Radio.playlists_loaded.is_connected(_on_playlists_loaded):
			Radio.playlists_loaded.disconnect(_on_playlists_loaded)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _sync_ui() -> void:
	if Radio == null:
		_status_lbl.text = "RADIO SUB-SYSTEM OFFLINE"
		return

	_status_lbl.text = "SERVER: %s  |  STATUS: %s" % [
		Settings.navidrome_url if Settings.navidrome_url != "" else "LOCAL",
		Radio.status.to_upper()
	]

	if Radio.now_title != "":
		_track_lbl.text = Radio.now_title
		_artist_lbl.text = Radio.now_artist if Radio.now_artist != "" else "UNKNOWN ARTIST"
	else:
		_track_lbl.text = "NO TRACK PLAYING"
		_artist_lbl.text = "RADIO " + Radio.status.to_upper()

	_play_btn.text = "PAUSE / STOP" if Radio.status == "playing" else "START RADIO"


func _on_play_toggle() -> void:
	Sfx.play_2d("ui_click")
	if Radio == null:
		return
	if Radio.status == "playing":
		Radio.stop()
	else:
		Radio.start()
	_sync_ui()


func _on_next_pressed() -> void:
	Sfx.play_2d("ui_click")
	if Radio != null:
		Radio.next_track()


func _on_volume_changed(val: float) -> void:
	Settings.set_value("volume_radio", val)
	# Update music bus volume proportionally
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(val * Settings.volume_music, 0.0001)))


func _on_source_selected(idx: int) -> void:
	Sfx.play_2d("ui_click")
	if idx == 0:
		Settings.set_value("radio_source", "random")
	elif idx == 1:
		Settings.set_value("radio_source", "starred")
	elif idx >= 2 and idx - 2 < _playlists.size():
		var p: Dictionary = _playlists[idx - 2]
		Settings.set_value("radio_source", "playlist:" + str(p.get("id", "")))

	if Radio != null and Radio.status == "playing":
		Radio.stop()
		Radio.start()


func _on_cockpit_fx_toggled(pressed: bool) -> void:
	Sfx.play_2d("ui_click")
	Settings.set_value("radio_cockpit_fx", pressed)
	if Radio != null:
		Radio.cockpit_fx = pressed


func _on_ducking_toggled(pressed: bool) -> void:
	Sfx.play_2d("ui_click")
	Settings.set_value("radio_duck_during_warnings", pressed)


func _on_close_pressed() -> void:
	Sfx.play_2d("ui_back")
	closed.emit()
	queue_free()


func _on_track_changed(_title: String, _artist: String) -> void:
	_sync_ui()


func _on_status_changed(_status: String) -> void:
	_sync_ui()


func _on_playlists_loaded(list: Array) -> void:
	_playlists = list
	while _source_btn.item_count > 2:
		_source_btn.remove_item(2)
	for i in list.size():
		var p: Dictionary = list[i]
		_source_btn.add_item("PLAYLIST: " + str(p.get("name", "Untitled")), i + 2)
