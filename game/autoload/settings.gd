extends Node
## Persistent user settings (user://settings.cfg). Read fields directly; call save() after changing.

signal changed

const PATH := "user://settings.cfg"

## Graphics: "low", "balanced", "high", "ultra". Default picked from the device on first launch.
var graphics_preset := "balanced"
var fps_target := 60  # 30, 60 or 120
var render_scale := 1.0  # 0.5..1.0 (3D only)
var show_perf_hud := false

## Flight: "arcade" (point-to-fly assist, no stall/spin) or "realistic" (direct stick, full physics).
var flight_mode := "arcade"
## Controls: "touch" (virtual stick), "gyro" (tilt to aim), "controller" is auto when one is connected.
var control_scheme := "touch"
var gyro_sensitivity := 1.0
var stick_sensitivity := 1.0
var invert_pitch := false
var left_handed := false
var haptics := true
var auto_fire := false
var camera_shake := true

var volume_master := 1.0
var volume_sfx := 1.0
var volume_music := 0.6
var volume_radio_chatter := 0.8

## Navidrome / OpenSubsonic server for the in-game radio.
var navidrome_url := ""
var navidrome_user := ""
var navidrome_password := ""
var radio_enabled := true
var radio_source := "random"  # "random", "starred", "playlist:<id>", "genre:<name>"


func _ready() -> void:
	if not load_settings():
		graphics_preset = _default_preset()
	apply()


func _default_preset() -> String:
	var name := OS.get_model_name()
	# iPad with A16+/M-series gets "high"; iPhone 13 Pro (A15) gets "balanced".
	if name.begins_with("iPad"):
		return "high"
	if OS.has_feature("pc"):
		return "high"
	return "balanced"


func load_settings() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return false
	for key in _keys():
		set(key, cfg.get_value("s", key, get(key)))
	return true


func save() -> void:
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value("s", key, get(key))
	cfg.save(PATH)
	apply()
	changed.emit()


func apply() -> void:
	Engine.max_fps = fps_target
	Engine.physics_ticks_per_second = 60
	for bus in [["Master", volume_master], ["SFX", volume_sfx], ["Music", volume_music]]:
		var idx := AudioServer.get_bus_index(bus[0])
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(bus[1], 0.0001)))


func _keys() -> Array:
	var out := []
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p.name)
	return out
