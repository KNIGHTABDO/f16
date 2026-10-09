class_name HUDWarnings
extends Control
## Critical flight warnings system: visual annunciators and voice/tone alerts.
## Warns for PULL UP, LOW ALT, STALL, MISSILE, BINGO FUEL, and OVER G.

var aircraft: Aircraft
var hud_scale := 1.0
var incoming_missile_active := false

var _cooldowns: Dictionary = {
	"pull_up": 0.0,
	"altitude": 0.0,
	"stall": 0.0,
	"missile": 0.0,
	"bingo": 0.0,
	"overg": 0.0
}

var _active_warnings: Array[String] = []
var _blink_timer := 0.0
var _blink_on := false
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func update_warnings(delta: float) -> void:
	_blink_timer += delta * 6.0
	_blink_on = int(_blink_timer) % 2 == 0

	for k in _cooldowns:
		_cooldowns[k] = maxf(0.0, _cooldowns[k] - delta)

	_check_conditions()
	queue_redraw()


func _check_conditions() -> void:
	if aircraft == null or not is_instance_valid(aircraft) or not aircraft.alive:
		_active_warnings.clear()
		return

	var warnings: Array[String] = []
	var voice_mode: String = Settings.warning_voice  # "female", "male", "tones"

	var agl_m := aircraft.get_agl_m()
	var vel_y := aircraft.get_velocity().y
	var on_ground := aircraft.is_on_ground()
	var gear_down := aircraft.is_gear_down()
	var fuel_frac := aircraft.get_fuel_frac()
	var g_load := absf(aircraft.get_g())
	var max_g := aircraft.data.max_g if aircraft.data != null else 9.0

	# 1. PULL UP (Critical ground collision threat)
	var sink_rate := -vel_y
	var time_to_impact := agl_m / maxf(sink_rate, 0.1) if sink_rate > 10.0 else 999.0
	if not on_ground and (time_to_impact < 4.0 or (agl_m < 250.0 and sink_rate > 20.0)):
		warnings.append("PULL UP")
		if _cooldowns["pull_up"] <= 0.0:
			_cooldowns["pull_up"] = 4.0
			_play_alert("pull_up", voice_mode)

	# 2. MISSILE (Incoming missile tracking)
	if incoming_missile_active:
		warnings.append("MISSILE")
		if _cooldowns["missile"] <= 0.0:
			_cooldowns["missile"] = 3.5
			_play_alert("missile", voice_mode)

	# 3. STALL
	if aircraft.is_stalling() and not on_ground:
		warnings.append("STALL")
		if _cooldowns["stall"] <= 0.0:
			_cooldowns["stall"] = 3.0
			_play_alert("stall", voice_mode)

	# 4. LOW ALT / ALTITUDE
	if not on_ground and not gear_down and agl_m < 120.0 and not warnings.has("PULL UP"):
		warnings.append("ALTITUDE")
		if _cooldowns["altitude"] <= 0.0:
			_cooldowns["altitude"] = 5.0
			_play_alert("altitude", voice_mode)

	# 5. OVER G
	if Settings.flight_mode == "realistic" and g_load > max_g * 1.05:
		warnings.append("OVER G")
		if _cooldowns["overg"] <= 0.0:
			_cooldowns["overg"] = 4.0
			_play_alert("overg", voice_mode)

	# 6. BINGO FUEL
	if fuel_frac <= 0.15 and not Settings.infinite_fuel and not on_ground:
		warnings.append("BINGO FUEL")
		if _cooldowns["bingo"] <= 0.0:
			_cooldowns["bingo"] = 30.0  # Infrequent alert
			_play_alert("bingo_fuel", voice_mode)

	_active_warnings = warnings


func _play_alert(alert_type: String, voice_mode: String) -> void:
	if voice_mode == "tones":
		match alert_type:
			"missile":
				Sfx.play_2d("missile_warning", 0.0)
			"stall", "pull_up":
				Sfx.play_2d("stall_warning", 0.0)
			_:
				Sfx.play_2d("rwr_ping", 0.0)
	else:
		# Voice alert (Bitching Betty voice)
		match alert_type:
			"pull_up":
				Sfx.play_2d("voice_pull_up")
			"altitude":
				Sfx.play_2d("voice_altitude")
			"missile":
				Sfx.play_2d("voice_missile")
			"overg":
				Sfx.play_2d("voice_overg")
			"bingo_fuel":
				Sfx.play_2d("voice_bingo_fuel")
			"stall":
				Sfx.play_2d("stall_warning")


func _draw() -> void:
	if _active_warnings.is_empty() or not _blink_on:
		return

	var vp_size := size
	var center_x := vp_size.x * 0.5
	var start_y := vp_size.y * 0.28
	var line_h := 36.0 * hud_scale
	var fs := int(22.0 * hud_scale)

	for i in _active_warnings.size():
		var txt := _active_warnings[i]
		var y := start_y + i * line_h
		var pill_w := 220.0 * hud_scale
		var pill_h := 32.0 * hud_scale

		# Red caution banner
		var pill_rect := Rect2(center_x - pill_w * 0.5, y - pill_h * 0.5, pill_w, pill_h)
		draw_rect(pill_rect, Color(0.85, 0.08, 0.08, 0.85), true)
		draw_rect(pill_rect, Color(1.0, 0.9, 0.2, 0.9), false, 2.0)

		# Text
		draw_string(_font, Vector2(center_x, y + fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, int(pill_w), fs, Color(1.0, 1.0, 1.0, 1.0))
