class_name HUDRadioTicker
extends Control
## In-flight radio now-playing ticker banner with audio equalizer animation.
## Appears when a track changes or radio starts, with auto-fadeout.

signal clicked

var hud_color := Color("#3FD0FF")
var hud_scale := 1.0

var _title := ""
var _artist := ""
var _show_time := 0.0
var _anim_phase := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(280, 36)
	size = custom_minimum_size

	if Radio != null:
		Radio.track_changed.connect(_on_track_changed)
		Radio.status_changed.connect(_on_status_changed)
		if Radio.now_title != "":
			_on_track_changed(Radio.now_title, Radio.now_artist)


func _exit_tree() -> void:
	if Radio != null:
		if Radio.track_changed.is_connected(_on_track_changed):
			Radio.track_changed.disconnect(_on_track_changed)
		if Radio.status_changed.is_connected(_on_status_changed):
			Radio.status_changed.disconnect(_on_status_changed)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		clicked.emit()
		accept_event()


func update_ticker(delta: float) -> void:
	_anim_phase += delta * 8.0
	if _show_time > 0.0:
		_show_time = maxf(0.0, _show_time - delta)
		visible = true
	else:
		visible = false
	queue_redraw()


func _on_track_changed(t: String, a: String) -> void:
	if t != "":
		_title = t
		_artist = a if a != "" else "Navidrome Radio"
		_show_time = 7.0  # Show for 7 seconds on track change


func _on_status_changed(st: String) -> void:
	if st == "playing" and _title != "":
		_show_time = 5.0


func _draw() -> void:
	if _title == "" or _show_time <= 0.0:
		return

	var w := size.x * hud_scale
	var h := size.y * hud_scale
	var alpha := clampf(_show_time / 0.8, 0.0, 1.0)
	var col := Color(hud_color.r, hud_color.g, hud_color.b, alpha)

	# Banner pill background
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.06, 0.10, 0.85 * alpha), true)
	draw_rect(Rect2(0, 0, w, h), Color(col.r, col.g, col.b, 0.5 * alpha), false, 1.2)

	# Equalizer animation bars on left
	var bar_x := 10.0 * hud_scale
	var bar_w := 3.0 * hud_scale
	for b in 4:
		var bar_h := (6.0 + sin(_anim_phase + float(b) * 1.5) * 5.0) * hud_scale
		draw_rect(Rect2(bar_x + b * 6.0 * hud_scale, (h - bar_h) * 0.5, bar_w, bar_h), col, true)

	# Track & Artist text
	var text_x := 38.0 * hud_scale
	var fs_title := int(13.0 * hud_scale)
	var label := "%s - %s" % [_title, _artist]
	draw_string(_font, Vector2(text_x, h * 0.65), label, HORIZONTAL_ALIGNMENT_LEFT, int(w - text_x - 10 * hud_scale), fs_title, Color(1, 1, 1, alpha))
