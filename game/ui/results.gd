class_name ResultsScreen
extends Control
## Results after a sortie: the outcome, the score breakdown and the rewards. Call setup() before adding the screen to the
## tree. RETRY replays the same seed, NEXT starts a new sortie of the same mode (wins on flown missions only), MENU leaves.

signal retry
signal next_mission
signal menu

var _result: Dictionary = {}


func setup(result: Dictionary) -> void:
	_result = result


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.06, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
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

	var won := bool(_result.get("won", false))
	vbox.add_child(_label("MISSION COMPLETE" if won else "MISSION FAILED", 30,
			Color("#3FD0FF") if won else Color("#FF6B6B")))
	vbox.add_child(_label(String(_result.get("title", "")), 18, Color("#E8F6FF")))
	var reason := _label(String(_result.get("reason", "")), 15, Color(0.65, 0.75, 0.85, 0.85))
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(reason)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)
	var secs := int(_result.get("time_s", 0.0))
	_stat(grid, "Time", "%d:%02d" % [floori(secs / 60.0), secs % 60])
	_stat(grid, "Score", Progression.format_int(int(_result.get("score", 0))))
	_stat(grid, "Air kills", str(int(_result.get("air_kills", 0))))
	_stat(grid, "Ground kills", str(int(_result.get("ground_kills", 0))))
	var shots := int(_result.get("shots", 0))
	var hits := int(_result.get("hits", 0))
	_stat(grid, "Accuracy", "%d%%  (%d / %d)" % [roundi(float(_result.get("accuracy", 0.0)) * 100.0), hits, shots])
	var rtb := int(_result.get("rtb_bonus", 0))
	if rtb > 0:
		_stat(grid, "Base bonus", Progression.format_int(rtb))

	var reward: Dictionary = GameState.last_result
	if reward.has("credits"):
		_stat(grid, "Credits", "+%s" % Progression.format_int(int(reward["credits"])))
		_stat(grid, "XP", "+%d" % int(reward.get("xp", 0)))
		if int(reward.get("rank_after", 0)) > int(reward.get("rank_before", 0)):
			_stat(grid, "Rank up", Progression.rank_name())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons)
	buttons.add_child(_button("RETRY", retry.emit))
	if won and not bool(_result.get("practice", false)):
		buttons.add_child(_button("NEXT", next_mission.emit))
	buttons.add_child(_button("MENU", menu.emit))


func _stat(grid: GridContainer, name_text: String, value_text: String) -> void:
	grid.add_child(_label(name_text, 15, Color(0.65, 0.75, 0.85, 0.85)))
	grid.add_child(_label(value_text, 15, Color("#E8F6FF")))


func _button(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 52)
	btn.add_theme_font_size_override("font_size", 18)
	btn.pressed.connect(on_press)
	return btn


func _label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
