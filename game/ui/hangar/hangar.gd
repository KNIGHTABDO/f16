class_name HangarScreen
extends Control
## Hangar screen, pushed onto MenuRoot from the main menu. Pick an aircraft, turn it on the turntable, check its
## stats, set its loadout and livery, then unlock it or select it for flight.

var _preview := ""
var _shown := ""
var _turntable: HangarTurntable
var _list: AircraftList
var _stats: StatsPanel
var _loadout: LoadoutEditor
var _livery: LiveryPicker
var _info_lbl: Label
var _credits_lbl: Label
var _rank_lbl: Label
var _rank_bar: ProgressBar
var _action_btn: Button
var _note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	Progression.changed.connect(_refresh)
	Settings.changed.connect(_on_settings_changed)
	_show(GameState.selected_aircraft)


func _exit_tree() -> void:
	if Progression.changed.is_connected(_refresh):
		Progression.changed.disconnect(_refresh)
	if Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.disconnect(_on_settings_changed)


## Turns the turntable and every panel to aircraft_id.
func _show(aircraft_id: String) -> void:
	_preview = aircraft_id
	if aircraft_id != _shown:
		_shown = aircraft_id
		_turntable.show_aircraft(aircraft_id)
	_list.focus(aircraft_id)
	_refresh()


func _refresh() -> void:
	_credits_lbl.text = "%s CR" % Progression.format_int(Progression.credits)
	_rank_lbl.text = "%s  ·  %s XP" % [Progression.rank_name(), Progression.format_int(Progression.xp)]
	_rank_bar.value = Progression.rank_progress() * 100.0

	var e := Progression.entry(_preview)
	_info_lbl.text = "%s  ·  %s  ·  %s" % [
		str(e.get("name", _preview)),
		str(e.get("nation", "")),
		str(e.get("era", "")).replace("_", " ").to_upper(),
	]
	_list.refresh(_preview)
	_stats.set_aircraft(_preview)
	_loadout.set_aircraft(_preview)
	_livery.set_aircraft(_preview)

	var lid := Progression.livery_for(_preview)
	var tex: Texture2D = Progression.art_texture("liveries/" + lid) if lid != "" else null
	_turntable.set_livery(tex)
	_update_action()


func _update_action() -> void:
	if not Progression.is_unlocked(_preview):
		var price := Progression.price_of(_preview)
		_action_btn.text = "UNLOCK  ·  %s CR" % Progression.format_int(price)
		_action_btn.disabled = Progression.credits < price
	elif Progression.selected_aircraft() == _preview:
		_action_btn.text = "FLYING THIS AIRCRAFT"
		_action_btn.disabled = true
	else:
		_action_btn.text = "SELECT FOR FLIGHT"
		_action_btn.disabled = false


func _on_action_pressed() -> void:
	if not Progression.is_unlocked(_preview) and not Progression.buy_aircraft(_preview):
		_note.text = "Not enough credits."
		return
	_note.text = ""
	Progression.select_aircraft(_preview)
	Sfx.play_2d("ui_confirm")


func _on_settings_changed(key: String) -> void:
	if key in ["unlock_all_aircraft", "", "all"]:
		_refresh()


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.texture = Progression.art_texture("menu/bg_hangar")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.08, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	add_child(page)
	page.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	page.add_child(body)

	_list = AircraftList.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.aircraft_picked.connect(_show)
	body.add_child(_list)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 6)
	body.add_child(center)
	_turntable = HangarTurntable.new()
	_turntable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turntable.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_turntable)
	_info_lbl = Label.new()
	_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_lbl.add_theme_font_size_override("font_size", 16)
	_info_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	center.add_child(_info_lbl)

	_stats = StatsPanel.new()
	_loadout = LoadoutEditor.new()
	_livery = LiveryPicker.new()
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420, 0)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(_tab("STATS", _stats))
	tabs.add_child(_tab("LOADOUT", _loadout))
	tabs.add_child(_tab("LIVERY", _livery))
	body.add_child(tabs)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	page.add_child(footer)
	_note = Label.new()
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.add_theme_color_override("font_color", Color("#FFB36B"))
	footer.add_child(_note)
	_action_btn = Button.new()
	_action_btn.custom_minimum_size = Vector2(320, 56)
	_action_btn.pressed.connect(_on_action_pressed)
	footer.add_child(_action_btn)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 56)
	header.add_theme_constant_override("separation", 16)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(150, 0)  # clears the BACK button
	header.add_child(spacer)

	var title := Label.new()
	title.text = "HANGAR"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#3FD0FF"))
	header.add_child(title)

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(grow)

	_rank_lbl = Label.new()
	_rank_lbl.add_theme_font_size_override("font_size", 16)
	header.add_child(_rank_lbl)
	_rank_bar = ProgressBar.new()
	_rank_bar.custom_minimum_size = Vector2(140, 14)
	_rank_bar.show_percentage = false
	_rank_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_rank_bar)
	_credits_lbl = Label.new()
	_credits_lbl.add_theme_font_size_override("font_size", 22)
	_credits_lbl.add_theme_color_override("font_color", Color("#FFD26B"))
	header.add_child(_credits_lbl)
	return header


func _tab(title: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll
