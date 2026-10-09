class_name LoadoutEditor
extends VBoxContainer
## Per-pylon loadout editor. Each pylon offers only the stores this aircraft can legally carry, and presets fill
## every pylon for one role. Each change is saved through Progression.set_loadout and the editor rebuilds from it.

var _aircraft_id := ""
var _pylons: Array[String] = []
var _body: VBoxContainer
var _summary: Label
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	add_child(_body)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 15)
	add_child(_summary)
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.add_theme_color_override("font_color", Color("#FFB36B"))
	add_child(_note)
	if _aircraft_id != "":
		_rebuild()


func set_aircraft(aircraft_id: String) -> void:
	_aircraft_id = aircraft_id
	if is_node_ready():
		_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_note.text = ""
	if _aircraft_id == "":
		_summary.text = ""
		return
	var unlocked := Progression.is_unlocked(_aircraft_id)
	var weapons := Progression.legal_weapons(_aircraft_id)
	_pylons = Progression.pylons_from_loadout(_aircraft_id, Progression.loadout_for(_aircraft_id))

	if not unlocked:
		var lock_note := Label.new()
		lock_note.text = "Unlock this aircraft to change its loadout."
		lock_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(lock_note)

	var preset_row := HFlowContainer.new()
	preset_row.add_theme_constant_override("h_separation", 8)
	preset_row.add_theme_constant_override("v_separation", 8)
	_body.add_child(preset_row)
	for preset: Dictionary in Progression.presets():
		var preset_id := str(preset.get("id", ""))
		var usable := unlocked and Progression.preset_available(_aircraft_id, preset_id)
		preset_row.add_child(_action_button(str(preset.get("label", preset_id)), usable, _on_preset_pressed.bind(preset_id)))
	preset_row.add_child(_action_button("DEFAULT", unlocked, _on_default_pressed))
	preset_row.add_child(_action_button("CLEAR", unlocked, _on_clear_pressed))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_body.add_child(grid)
	for i in _pylons.size():
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cap := Label.new()
		cap.text = "PYLON %d" % (i + 1)
		cap.add_theme_font_size_override("font_size", 13)
		cell.add_child(cap)
		var pick := OptionButton.new()
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.disabled = not unlocked
		pick.add_item("- EMPTY -")
		for w in weapons:
			pick.add_item(_weapon_label(w))
		pick.select(weapons.find(_pylons[i]) + 1)
		pick.item_selected.connect(_on_pylon_selected.bind(i))
		cell.add_child(pick)
		grid.add_child(cell)
	_summary.text = _summary_text()


func _summary_text() -> String:
	var items := Progression.loadout_from_pylons(_pylons)
	var mass := Progression.loadout_mass_kg(items)
	var max_mass := Progression.payload_kg(_aircraft_id)
	var parts: Array[String] = []
	for item: Dictionary in items:
		parts.append("%d x %s" % [int(item.get("count", 0)), _weapon_name(str(item.get("weapon", "")))])
	var stores := ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "none"
	return "STORES  %s\nMASS  %s kg of %s kg" % [stores, Progression.format_int(roundi(mass)), Progression.format_int(roundi(max_mass))]


func _weapon_name(weapon_id: String) -> String:
	return str(Progression.weapon_info(weapon_id).get("name", weapon_id))


func _weapon_label(weapon_id: String) -> String:
	var cap := Progression.rack_capacity(weapon_id)
	var label := _weapon_name(weapon_id)
	return label if cap <= 1 else "%s x%d" % [label, cap]


func _action_button(text: String, enabled: bool, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	btn.pressed.connect(handler)
	return btn


func _on_pylon_selected(index: int, pylon: int) -> void:
	var weapons := Progression.legal_weapons(_aircraft_id)
	var slots: Array[String] = _pylons.duplicate()
	slots[pylon] = "" if index == 0 else weapons[index - 1]
	_commit(slots)


func _on_preset_pressed(preset_id: String) -> void:
	var slots: Array[String] = Progression.build_preset(_aircraft_id, preset_id)
	if slots.is_empty():
		_note.text = "No stores for this role on this aircraft."
		return
	_commit(slots)


func _on_default_pressed() -> void:
	Progression.clear_loadout(_aircraft_id)
	set_aircraft(_aircraft_id)


func _on_clear_pressed() -> void:
	_commit(Progression.pylons_from_loadout(_aircraft_id, []))


func _commit(slots: Array[String]) -> void:
	if not Progression.set_loadout(_aircraft_id, Progression.loadout_from_pylons(slots)):
		_note.text = "That loadout is not legal for this aircraft."
		return
	set_aircraft(_aircraft_id)
