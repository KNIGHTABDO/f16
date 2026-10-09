class_name MissionOverlay
extends Control
## In-flight mission HUD: title, lives, clock and score across the top, the objective list on the left, a briefing card
## when the sortie starts, world markers for open objectives and short mission messages at the bottom.

const BRIEF_S := 13.0  ## s the briefing card stays up

var _level  ## the flight level (untyped: no class_name)
var _mission: Mission
var _top: Label
var _list: VBoxContainer
var _brief: PanelContainer
var _brief_label: Label
var _brief_left := BRIEF_S
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
	Events.objective_updated.connect(_on_objectives)
	Events.mission_message.connect(_on_message)
	_on_objectives(mission.objectives.to_array())


func _exit_tree() -> void:
	if Events.objective_updated.is_connected(_on_objectives):
		Events.objective_updated.disconnect(_on_objectives)
	if Events.mission_message.is_connected(_on_message):
		Events.mission_message.disconnect(_on_message)


func _build() -> void:
	_top = _label(20, Color("#E8F6FF"))
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top.offset_top = 14.0
	add_child(_top)

	_list = VBoxContainer.new()
	_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_list.offset_left = 24.0
	_list.offset_top = 92.0
	add_child(_list)

	_message = _label(22, Color("#FFB020"))
	_message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message.offset_bottom = -150.0
	_message.visible = false
	add_child(_message)

	_brief = PanelContainer.new()
	_brief.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_brief.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_brief.grow_vertical = Control.GROW_DIRECTION_BOTH
	_brief_label = _label(18, Color("#E8F6FF"))
	_brief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief_label.custom_minimum_size = Vector2(540, 0)
	_brief.add_child(_brief_label)
	add_child(_brief)


func _process(delta: float) -> void:
	if _mission == null:
		return
	_top.text = _top_text()
	if _brief.visible:
		_brief_left -= delta
		_brief.visible = _brief_left > 0.0
	if _message.visible:
		_message_left -= delta
		_message.visible = _message_left > 0.0
	_update_markers()


func _top_text() -> String:
	var m := _mission
	var lives := "∞" if m.lives < 0 else str(m.lives)
	var clock := _clock(m.elapsed)
	if m.time_limit > 0.0:
		clock = "%s left" % _clock(maxf(0.0, m.time_limit - m.elapsed))
	return "%s   ·   Lives %s   ·   %s   ·   Score %s" % [
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
		var lbl := _label(16, Color(0.6, 0.7, 0.8, 0.55) if done else Color("#E8F6FF"))
		lbl.text = ("✓ " if done else "• ") + text
		_list.add_child(lbl)


func _on_message(text: String, duration: float) -> void:
	_message.text = text
	_message.visible = true
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
		var lbl := _label(16, Color("#FFB020"))
		add_child(lbl)
		_markers.append(lbl)
	return _markers[i]


func _label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
