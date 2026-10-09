class_name MissionOverlay
extends Control
## In-flight mission HUD: a small status line at top-center, the objective list under the minimap, a briefing card
## that fades after the sortie starts, world markers for open objectives and short mission messages at top-center.

const BRIEF_S := 6.0  ## s the briefing card is up (it fades over the last BRIEF_FADE_S)
const BRIEF_FADE_S := 0.8
const LIST_TOP := 150.0  ## y below the safe-area top, just under the minimap (HUD margin 12 + 138 tall)
const LIST_W := 250.0  ## text width before wrapping; keeps the list clear of the speed tape on the left
const TOP_CARD_Y := 50.0  ## briefing and messages sit under the status line, never over the gunsight
const PLATE := Color(0.02, 0.05, 0.06, 0.45)

var _level  ## the flight level (untyped: no class_name)
var _mission: Mission
var _status: PanelContainer
var _top: Label
var _list_box: PanelContainer
var _list: VBoxContainer
var _brief: PanelContainer
var _brief_label: Label
var _brief_left := BRIEF_S
var _message_box: PanelContainer
var _message: Label
var _message_left := 0.0
var _markers: Array[Label] = []


func setup(level: Node, mission: Mission) -> void:
	_level = level
	_mission = mission
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	var brief := String(mission.plan.get("briefing", ""))
	var note := String(mission.plan.get("note", ""))
	_brief_label.text = brief if note == "" else "%s\n%s" % [brief, note]
	_brief.visible = _brief_label.text != ""
	_brief_left = BRIEF_S
	Events.objective_updated.connect(_on_objectives)
	Events.mission_message.connect(_on_message)
	get_viewport().size_changed.connect(_place)
	_on_objectives(mission.objectives.to_array())
	_place()


func _exit_tree() -> void:
	if Events.objective_updated.is_connected(_on_objectives):
		Events.objective_updated.disconnect(_on_objectives)
	if Events.mission_message.is_connected(_on_message):
		Events.mission_message.disconnect(_on_message)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_place):
		vp.size_changed.disconnect(_place)


func _build() -> void:
	_status = _plated(PRESET_CENTER_TOP, 8.0)
	_top = _label(13, Color("#CFEFFF"))
	_status.add_child(_top)
	add_child(_status)

	_list_box = _plated(PRESET_TOP_LEFT, 0.0)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = LIST_W
	_list.add_theme_constant_override("separation", 2)
	_list_box.add_child(_list)
	add_child(_list_box)

	_message_box = _plated(PRESET_CENTER_TOP, TOP_CARD_Y)
	_message = _label(18, Color("#FFB020"))
	_message_box.add_child(_message)
	_message_box.visible = false
	add_child(_message_box)

	_brief = _plated(PRESET_CENTER_TOP, TOP_CARD_Y)
	_brief_label = _label(16, Color("#E8F6FF"))
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_label.custom_minimum_size = Vector2(440, 0)
	_brief.add_child(_brief_label)
	add_child(_brief)


## A label-holding translucent card anchored by preset; top_offset moves it down from the top edge.
func _plated(preset: int, top_offset: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(preset)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if preset == PRESET_CENTER_TOP:
		# Top-anchored cards grow downward only, so the text never rises past the screen edge
		panel.offset_top = top_offset
		panel.grow_vertical = Control.GROW_DIRECTION_END
	elif preset == PRESET_TOP_LEFT:
		# Left-anchored list grows right and down only, so long lines never run off the left edge
		panel.grow_horizontal = Control.GROW_DIRECTION_END
		panel.grow_vertical = Control.GROW_DIRECTION_END
	var sb := StyleBoxFlat.new()
	sb.bg_color = PLATE
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.45, 0.9, 1.0, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _place() -> void:
	var r := HUDLayout.safe_rect(get_viewport_rect().size)
	_list_box.position = r.position + Vector2(0.0, LIST_TOP)


func _process(delta: float) -> void:
	if _mission == null:
		return
	_top.text = _top_text()
	if _brief.visible:
		_brief_left -= delta
		_brief.modulate.a = clampf(_brief_left / BRIEF_FADE_S, 0.0, 1.0)
		_brief.visible = _brief_left > 0.0
	if _message_box.visible:
		# A message during the briefing stacks under the card instead of covering it
		_message_box.offset_top = TOP_CARD_Y + (_brief.size.y + 6.0 if _brief.visible else 0.0)
		_message_left -= delta
		_message_box.visible = _message_left > 0.0
	_update_markers()


func _top_text() -> String:
	var m := _mission
	var lives := "∞" if m.lives < 0 else str(m.lives)
	var clock := _clock(m.elapsed)
	if m.time_limit > 0.0:
		clock = "%s left" % _clock(maxf(0.0, m.time_limit - m.elapsed))
	return "%s  ·  Lives %s  ·  %s  ·  Score %s" % [
		String(m.plan["title"]), lives, clock, Progression.format_int(int(m.score))]


static func _clock(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [floori(total / 60.0), total % 60]


func _on_objectives(list: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	for entry in list:
		var text := String(entry["text"])
		if text == "":
			continue
		var done: bool = entry["done"]
		var lbl := _label(13, Color(0.6, 0.7, 0.8, 0.55) if done else Color("#CFEFFF"))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.text = ("✓ " if done else "• ") + text
		_list.add_child(lbl)


func _on_message(text: String, duration: float) -> void:
	_message.text = text
	_message_box.visible = true
	_message_left = duration


## Places a label on every open objective that has a marker. Markers behind the camera are hidden.
func _update_markers() -> void:
	var cam: Camera3D = _level.camera.get_camera()
	var player = _level.player
	var used := 0
	for entry in _mission.objectives.to_array():
		if entry["done"] or not entry["marker"]:
			continue
		var pos := _world_pos(entry)
		var lbl := _marker_label(used)
		used += 1
		if cam == null or cam.is_position_behind(WorldOrigin.to_local(pos)):
			lbl.visible = false
			continue
		var km := ""
		if is_instance_valid(player):
			km = "  %.1f km" % (WorldOrigin.to_world(player.position).distance_to(pos) / 1000.0)
		var label_text := String(entry["text"]) if String(entry["text"]) != "" else String(entry["id"])
		lbl.text = "◆ %s%s" % [label_text, km]
		lbl.position = cam.unproject_position(WorldOrigin.to_local(pos)) + Vector2(12.0, -28.0)
		lbl.visible = true
	for i in range(used, _markers.size()):
		_markers[i].visible = false


## World position of an objective: its node when the node is still alive, otherwise its stored point.
func _world_pos(entry: Dictionary) -> Vector3:
	var node = entry["node"]
	if is_instance_valid(node):
		return WorldOrigin.to_world(node.global_position)
	return entry["pos"]


func _marker_label(i: int) -> Label:
	if i >= _markers.size():
		var lbl := _label(14, Color("#FFB020"))
		add_child(lbl)
		_markers.append(lbl)
	return _markers[i]


func _label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
