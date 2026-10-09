class_name AircraftList
extends VBoxContainer
## Aircraft list in category groups. Locked aircraft show a lock and their price. The aircraft being previewed
## is highlighted, and the one flown from the menus is marked ACTIVE.

signal aircraft_picked(aircraft_id: String)

const GROUPS := ["FIGHTERS", "ATTACK", "BOMBERS", "HELICOPTERS", "WW2"]

var _group := "FIGHTERS"
var _preview := ""
var _tab_group := ButtonGroup.new()
var _row_group := ButtonGroup.new()
var _tabs: HFlowContainer
var _rows: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_tabs = HFlowContainer.new()
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	add_child(_tabs)
	for group in GROUPS:
		var tab := Button.new()
		tab.text = group
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.button_pressed = group == _group
		tab.add_theme_font_size_override("font_size", 15)
		tab.pressed.connect(_on_tab_pressed.bind(group))
		_tabs.add_child(tab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	refresh(_preview)


## Switches to the group that holds aircraft_id and previews it.
func focus(aircraft_id: String) -> void:
	var e := Progression.entry(aircraft_id)
	if e.is_empty():
		return
	_group = group_of(e)
	for tab in _tabs.get_children():
		var btn := tab as Button
		btn.button_pressed = btn.text == _group
	refresh(aircraft_id)


## Rebuilds the rows of the current group. preview_id is the aircraft shown on the turntable.
func refresh(preview_id: String) -> void:
	_preview = preview_id
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var active := Progression.selected_aircraft()
	for e: Dictionary in Progression.aircraft_roster():
		if group_of(e) != _group:
			continue
		var id := str(e.get("id", ""))
		var unlocked := Progression.is_unlocked(id)
		var row := Button.new()
		row.toggle_mode = true
		row.button_group = _row_group
		row.button_pressed = id == _preview
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, 68)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.expand_icon = true
		row.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.icon = Progression.art_texture("aircraft/" + id) if unlocked else Progression.art_texture("icons/lock")
		row.text = "%s\n%s  ·  %s" % [str(e.get("name", id)), str(e.get("nation", "")), _status(id, unlocked, active)]
		row.modulate = Color.WHITE if unlocked else Color(0.8, 0.85, 0.9, 0.6)
		row.pressed.connect(_on_row_pressed.bind(id))
		_rows.add_child(row)


static func group_of(e: Dictionary) -> String:
	match str(e.get("category", "")):
		"attack":
			return "ATTACK"
		"bomber":
			return "BOMBERS"
		"helicopter":
			return "HELICOPTERS"
		"prop":
			return "WW2"
	if str(e.get("era", "")) == "ww2":
		return "WW2"
	return "FIGHTERS"


func _status(aircraft_id: String, unlocked: bool, active: String) -> String:
	if aircraft_id == active:
		return "ACTIVE"
	if unlocked:
		return "UNLOCKED"
	return "LOCKED  ·  %s CR" % Progression.format_int(Progression.price_of(aircraft_id))


func _on_tab_pressed(group: String) -> void:
	_group = group
	refresh(_preview)


func _on_row_pressed(aircraft_id: String) -> void:
	aircraft_picked.emit(aircraft_id)
