class_name StatsPanel
extends VBoxContainer
## Stat bars for one aircraft, read from roster.json. Each bar is scaled to the roster's own range
## (the constants below), so a full bar means the best in the roster.

const SPEED_MAX_KMH := 2700.0
const CLIMB_MAX_MS := 360.0
const TURN_BEST_S := 8.0  ## full turn bar
const TURN_WORST_S := 26.0  ## empty turn bar; shorter turn times are better
const PAYLOAD_MAX_KG := 12000.0

var _name_lbl: Label
var _desc_lbl: Label
var _ceiling_lbl: Label
var _guns_lbl: Label
var _bars: Dictionary = {}  ## key -> ProgressBar
var _values: Dictionary = {}  ## key -> Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 24)
	_name_lbl.add_theme_color_override("font_color", Color("#3FD0FF"))
	add_child(_name_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_font_size_override("font_size", 15)
	_desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	add_child(_desc_lbl)

	add_child(_bar_row("speed", "SPEED"))
	add_child(_bar_row("climb", "CLIMB"))
	add_child(_bar_row("turn", "TURN"))
	add_child(_bar_row("payload", "PAYLOAD"))

	_ceiling_lbl = Label.new()
	add_child(_ceiling_lbl)
	_guns_lbl = Label.new()
	_guns_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_guns_lbl)


func set_aircraft(aircraft_id: String) -> void:
	if not is_node_ready():
		return
	var e := Progression.entry(aircraft_id)
	var stats: Dictionary = e.get("stats", {})
	var speed := float(stats.get("speed_kmh", 0.0))
	var climb := float(stats.get("climb_ms", 0.0))
	var turn := float(stats.get("turn_s", TURN_WORST_S))
	var payload := Progression.payload_kg(aircraft_id)

	_name_lbl.text = str(e.get("name", aircraft_id))
	_desc_lbl.text = str(e.get("description", ""))
	_set_bar("speed", speed / SPEED_MAX_KMH, "%d km/h" % roundi(speed))
	_set_bar("climb", climb / CLIMB_MAX_MS, "%d m/s" % roundi(climb))
	_set_bar("turn", (TURN_WORST_S - turn) / (TURN_WORST_S - TURN_BEST_S), "%.1f s" % turn)
	_set_bar("payload", payload / PAYLOAD_MAX_KG, "%s kg" % Progression.format_int(roundi(payload)))
	_ceiling_lbl.text = "CEILING   %s m" % Progression.format_int(int(stats.get("ceiling_m", 0)))
	_guns_lbl.text = "GUNS   %s" % str(stats.get("guns", "none"))


func _bar_row(key: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.custom_minimum_size = Vector2(96, 0)
	row.add_child(title_lbl)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#3FD0FF")
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 18)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(110, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_lbl)

	_bars[key] = bar
	_values[key] = value_lbl
	return row


func _set_bar(key: String, fraction: float, text: String) -> void:
	var bar: ProgressBar = _bars[key]
	var value_lbl: Label = _values[key]
	bar.value = clampf(fraction, 0.0, 1.0)
	value_lbl.text = text
