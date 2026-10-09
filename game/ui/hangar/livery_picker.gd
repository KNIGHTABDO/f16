class_name LiveryPicker
extends VBoxContainer
## Livery picker for one aircraft: the factory paint plus the aircraft's liveries. Tapping an unowned livery
## buys it and equips it at once. The turntable follows through Progression.changed.

var _aircraft_id := ""
var _grid: GridContainer
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)
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
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	if _aircraft_id == "":
		return
	var unlocked := Progression.is_unlocked(_aircraft_id)
	_note.text = "" if unlocked else "Unlock this aircraft to paint it."
	var equipped := Progression.livery_for(_aircraft_id)

	var factory_status := "EQUIPPED" if equipped == "" else "EQUIP"
	_grid.add_child(_card("FACTORY PAINT", factory_status, Progression.art_texture("aircraft/" + _aircraft_id), unlocked, _on_equip.bind("")))
	for livery: Dictionary in Progression.livery_list(_aircraft_id):
		var lid := str(livery.get("id", ""))
		var status := ""
		if lid == equipped:
			status = "EQUIPPED"
		elif bool(livery.get("owned", false)):
			status = "OWNED"
		else:
			var price := int(livery.get("price", 0))
			status = ("BUY  %s CR" if Progression.credits >= price else "NEED  %s CR") % Progression.format_int(price)
		_grid.add_child(_card(str(livery.get("name", lid)), status, Progression.art_texture("liveries/" + lid), unlocked, _on_equip.bind(lid)))


func _card(title: String, status: String, icon: Texture2D, enabled: bool, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = "%s\n%s" % [title, status]
	btn.icon = icon
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(200, 76)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not enabled
	btn.pressed.connect(handler)
	return btn


func _on_equip(livery_id: String) -> void:
	if livery_id != "" and not Progression.livery_owned(livery_id):
		if not Progression.buy_livery(livery_id):
			_note.text = "Not enough credits."
			return
	if Progression.set_livery(_aircraft_id, livery_id):
		_rebuild()
