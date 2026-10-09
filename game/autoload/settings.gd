extends Node
## Persistent user settings (user://settings.cfg). Read fields directly; call save() or set_value() after changing.

signal changed(key: String)
signal calibrate_gyro_requested

const PATH := "user://settings.cfg"

const DEFAULT_TOUCH_LAYOUT := {
	"stick": {"pos": [0.14, 0.72], "scale": 1.0, "opacity": 0.75},
	"throttle": {"pos": [0.06, 0.42], "scale": 1.0, "opacity": 0.75},
	"gun": {"pos": [0.90, 0.72], "scale": 1.1, "opacity": 0.85},
	"weapon": {"pos": [0.80, 0.60], "scale": 1.1, "opacity": 0.85},
	"cycle_weapon": {"pos": [0.88, 0.48], "scale": 0.9, "opacity": 0.75},
	"cycle_target": {"pos": [0.78, 0.45], "scale": 0.9, "opacity": 0.75},
	"flares": {"pos": [0.92, 0.32], "scale": 0.9, "opacity": 0.80},
	"airbrake": {"pos": [0.06, 0.18], "scale": 0.85, "opacity": 0.70},
	"gear": {"pos": [0.14, 0.18], "scale": 0.85, "opacity": 0.70},
	"camera": {"pos": [0.86, 0.12], "scale": 0.85, "opacity": 0.70},
	"look": {"pos": [0.76, 0.12], "scale": 0.85, "opacity": 0.70},
	"pause": {"pos": [0.96, 0.08], "scale": 0.85, "opacity": 0.75},
	"radio": {"pos": [0.66, 0.12], "scale": 0.85, "opacity": 0.70}
}

const DEFAULT_GAMEPAD_BINDINGS := {
	"fire": "A / Cross",
	"weapon": "B / Circle",
	"flares": "X / Square",
	"cycle_target": "Y / Triangle",
	"throttle_up": "RT / R2",
	"throttle_down": "LT / L2",
	"airbrake": "LB / L1",
	"cycle_weapon": "RB / R1",
	"camera": "Back / Select",
	"pause": "Start / Options"
}

## 1. Graphics: "low", "balanced", "high", "ultra", "custom"
var graphics_preset := "balanced"
var fps_target := 60  # 30, 60 or 120
var render_scale := 1.0  # 0.5..1.0 (3D only); ceiling for dynamic resolution
var dynamic_resolution := true  # PerfGovernor lowers the 3D scale toward dynamic_resolution_min when frames run long
var dynamic_resolution_min := 0.6  # 0.5..render_scale
var unit_draw_m := 6000.0  # aircraft and units beyond this distance are not drawn; 2000..12000
var show_perf_hud := false
var msaa_3d := 2  # 0 = Off, 1 = 2x, 2 = 4x
var fxaa := false
var terrain_detail := "high"  # "low", "medium", "high", "ultra"
var view_distance_km := 60.0  # 20..100
var cloud_quality := "high"  # "low", "medium", "high", "ultra"
var shadow_quality := "high"  # "low", "medium", "high", "ultra"
var shadow_distance := 3000.0  # 500..6000
var vegetation_density := "high"  # "off", "low", "medium", "high"
var city_density := "high"  # "low", "medium", "high"
var effects_quality := "high"  # "low", "medium", "high"
var water_quality := "high"  # "low", "medium", "high"
var bloom := true
var lens_flare := true
var motion_blur := true
var heat_haze := true
var color_brightness := 1.0  # 0.5..1.5
var color_contrast := 1.0  # 0.5..1.5
var color_saturation := 1.0  # 0.5..1.5
var color_filter := "none"  # "none", "warm", "cool", "cinematic", "vivid"
var battery_saver := false

## 2. Flight
var flight_mode := "arcade"  # "arcade", "realistic"
var stall_protection := true
var g_limiter := true
var auto_rudder := true
var auto_level := true
var auto_throttle := false
var landing_assist := true
var blackout_effects := true
var damage_model := "arcade"  # "off", "arcade", "realistic"
var infinite_fuel := false
var infinite_ammo := false
var invincible := false  # free flight only
var units := "aviation"  # "metric", "imperial", "aviation"

## 3. Controls
var control_scheme := "touch"  # "touch", "gyro", "hybrid", "mouse_aim"
var pitch_sensitivity := 1.0  # 0.2..2.0
var roll_sensitivity := 1.0  # 0.2..2.0
var yaw_sensitivity := 1.0  # 0.2..2.0
var gyro_sensitivity := 1.0
var stick_sensitivity := 1.0
var gyro_smoothing := 0.5  # 0.0..1.0
var gyro_deadzone := 0.05  # 0.0..0.2
var invert_pitch := false
var left_handed := false
var stick_size := 1.0  # 0.7..1.5
var stick_deadzone := 0.1  # 0.0..0.3
var stick_floating := false
var auto_fire := false
var aim_assist := 0.5  # 0.0..1.0
var haptics := true
var haptic_intensity := 0.7  # 0.1..1.0
var touch_layout: Dictionary = {}
var gamepad_enabled := true
var gamepad_bindings: Dictionary = {}

## 4. Camera
var camera_default_view := "chase"  # "chase", "cockpit", "far_chase", "cinematic"
var camera_fov := 75.0  # 60..100
var camera_chase_distance := 18.0  # 10..35
var camera_chase_height := 4.0  # 1..10
var camera_shake := true
var camera_shake_intensity := 1.0  # 0.0..2.0
var camera_gyro_look := true
var camera_padlock := false
var camera_smoothing := 0.5  # 0.0..1.0
var camera_cockpit_canopy := true

## 5. HUD
var hud_color := "green"  # "green", "cyan", "amber", "white", "red"
var hud_scale := 1.0  # 0.75..1.25
var hud_opacity := 0.9  # 0.3..1.0
var hud_show_minimap := true
var hud_minimap_zoom := 1.0  # 0.5..2.0
var hud_show_target_info := true
var hud_show_rwr := true
var hud_show_tapes := true
var hud_show_g_meter := true
var hud_show_waypoints := true
var hud_show_damage := true
var hud_show_kill_feed := true
var hud_subtitles := true

## 6. Audio
var volume_master := 1.0
var volume_sfx := 1.0
var volume_engine := 1.0
var volume_weapons := 1.0
var volume_music := 0.6
var volume_radio_chatter := 0.8
var volume_ui := 0.8
var cockpit_muffle := true
var warning_voice := "female"  # "female", "male", "tones"
var mute_in_background := true
var _cockpit_view := false  # runtime, not saved: set by set_cockpit_view()

## 7. Radio (Navidrome)
var navidrome_url := ""
var navidrome_user := ""
var navidrome_password := ""
var radio_enabled := true
var radio_source := "random"  # "random", "starred", "playlist:<id>", "genre:<name>"
var radio_playlist_id := ""
var radio_genre := ""
var radio_shuffle := true
var radio_autostart := true
var volume_radio := 0.8
var radio_duck_during_warnings := true
var radio_cockpit_fx := true  # band-pass on the music radio while in cockpit view
var radio_show_toast := true

## 8. Gameplay
var gameplay_difficulty := "normal"  # "easy", "normal", "hard", "ace"
var gameplay_time_of_day := "noon"  # "dawn", "noon", "sunset", "night", "realtime"
var gameplay_weather := "clear"  # "clear", "scattered", "overcast", "storm"
var gameplay_ai_count := 4  # 1..12
var gameplay_ground_density := "medium"  # "low", "medium", "high"
var gameplay_wingmen := true
var gameplay_time_limit := true
var gameplay_tutorial_hints := true

## 9. Account / Data
var pilot_callsign := "Viper"
var unlock_all_aircraft := false


func _ready() -> void:
	if not load_settings():
		graphics_preset = _default_preset()
		apply_graphics_preset(graphics_preset)
	if touch_layout.is_empty():
		touch_layout = DEFAULT_TOUCH_LAYOUT.duplicate(true)
	if gamepad_bindings.is_empty():
		gamepad_bindings = DEFAULT_GAMEPAD_BINDINGS.duplicate(true)
	apply()


func _default_preset() -> String:
	var name := OS.get_model_name()
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
	changed.emit("")


func set_value(key: String, value: Variant) -> void:
	if key in self:
		set(key, value)
		# Changing graphics sub-options switches preset to custom
		if key in [
			"render_scale", "dynamic_resolution", "dynamic_resolution_min", "unit_draw_m",
			"fps_target", "msaa_3d", "fxaa", "terrain_detail",
			"view_distance_km", "cloud_quality", "shadow_quality", "shadow_distance",
			"vegetation_density", "city_density", "effects_quality", "water_quality",
			"bloom", "lens_flare", "motion_blur", "heat_haze"
		] and graphics_preset != "custom":
			graphics_preset = "custom"
		apply()
		save()
		changed.emit(key)


func apply() -> void:
	Engine.max_fps = 30 if battery_saver else fps_target
	Engine.physics_ticks_per_second = 60

	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = clampf(render_scale, 0.5, 1.0)
		match msaa_3d:
			0:
				vp.msaa_3d = Viewport.MSAA_DISABLED
			1:
				vp.msaa_3d = Viewport.MSAA_2X
			2:
				vp.msaa_3d = Viewport.MSAA_4X
			_:
				vp.msaa_3d = Viewport.MSAA_2X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED

	var buses: Array = [
		["Master", volume_master],
		["SFX", volume_sfx],
		["Music", volume_music],
		["Cockpit", volume_sfx]
	]
	for bus in buses:
		var idx := AudioServer.get_bus_index(bus[0])
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(bus[1], 0.0001)))

	_apply_cockpit_audio()


## Called by FlightCamera on each view change. Cockpit audio follows it, and so does a setting changed in cockpit view.
func set_cockpit_view(on: bool) -> void:
	_cockpit_view = on
	_apply_cockpit_audio()


## Exterior-sound muffle (Sfx) and the radio band-pass (Radio): each needs cockpit view and its own setting.
func _apply_cockpit_audio() -> void:
	var sfx_node = get_node_or_null("/root/Sfx")
	if sfx_node != null:
		sfx_node.set_cockpit(_cockpit_view and cockpit_muffle)
	var radio_node = get_node_or_null("/root/Radio")
	if radio_node != null:
		radio_node.cockpit_fx = _cockpit_view and radio_cockpit_fx


func apply_graphics_preset(preset: String) -> void:
	graphics_preset = preset
	match preset:
		"low":
			render_scale = 0.65
			dynamic_resolution = true
			dynamic_resolution_min = 0.5
			unit_draw_m = 2500.0
			fps_target = 30
			msaa_3d = 0
			fxaa = false
			terrain_detail = "low"
			view_distance_km = 30.0
			cloud_quality = "low"
			shadow_quality = "low"
			shadow_distance = 1000.0
			vegetation_density = "off"
			city_density = "low"
			effects_quality = "low"
			water_quality = "low"
			bloom = false
			lens_flare = false
			motion_blur = false
			heat_haze = false
		"balanced":
			render_scale = 0.9
			dynamic_resolution = true
			dynamic_resolution_min = 0.6
			unit_draw_m = 4000.0
			fps_target = 60
			msaa_3d = 1
			fxaa = false
			terrain_detail = "medium"
			view_distance_km = 50.0
			cloud_quality = "medium"
			shadow_quality = "medium"
			shadow_distance = 1500.0
			vegetation_density = "medium"
			city_density = "medium"
			effects_quality = "medium"
			water_quality = "medium"
			bloom = true
			lens_flare = true
			motion_blur = true
			heat_haze = true
		"high":
			render_scale = 1.0
			dynamic_resolution = true
			dynamic_resolution_min = 0.75
			unit_draw_m = 6000.0
			fps_target = 60
			msaa_3d = 2
			fxaa = true
			terrain_detail = "high"
			view_distance_km = 70.0
			cloud_quality = "high"
			shadow_quality = "high"
			shadow_distance = 2500.0
			vegetation_density = "high"
			city_density = "high"
			effects_quality = "high"
			water_quality = "high"
			bloom = true
			lens_flare = true
			motion_blur = true
			heat_haze = true
		"ultra":
			render_scale = 1.0
			dynamic_resolution = false
			dynamic_resolution_min = 1.0
			unit_draw_m = 9000.0
			fps_target = 120
			msaa_3d = 2
			fxaa = true
			terrain_detail = "ultra"
			view_distance_km = 100.0
			cloud_quality = "ultra"
			shadow_quality = "ultra"
			shadow_distance = 4000.0
			vegetation_density = "high"
			city_density = "high"
			effects_quality = "high"
			water_quality = "high"
			bloom = true
			lens_flare = true
			motion_blur = true
			heat_haze = true
	save()
	apply()
	changed.emit("graphics_preset")


func reset_to_defaults() -> void:
	graphics_preset = _default_preset()
	apply_graphics_preset(graphics_preset)

	fps_target = 60
	render_scale = 1.0
	show_perf_hud = false
	color_brightness = 1.0
	color_contrast = 1.0
	color_saturation = 1.0
	color_filter = "none"
	battery_saver = false

	flight_mode = "arcade"
	stall_protection = true
	g_limiter = true
	auto_rudder = true
	auto_level = true
	auto_throttle = false
	landing_assist = true
	blackout_effects = true
	damage_model = "arcade"
	infinite_fuel = false
	infinite_ammo = false
	invincible = false
	units = "aviation"

	control_scheme = "touch"
	pitch_sensitivity = 1.0
	roll_sensitivity = 1.0
	yaw_sensitivity = 1.0
	gyro_sensitivity = 1.0
	stick_sensitivity = 1.0
	gyro_smoothing = 0.5
	gyro_deadzone = 0.05
	invert_pitch = false
	left_handed = false
	stick_size = 1.0
	stick_deadzone = 0.1
	stick_floating = false
	auto_fire = false
	aim_assist = 0.5
	haptics = true
	haptic_intensity = 0.7
	touch_layout = DEFAULT_TOUCH_LAYOUT.duplicate(true)
	gamepad_enabled = true
	gamepad_bindings = DEFAULT_GAMEPAD_BINDINGS.duplicate(true)

	camera_default_view = "chase"
	camera_fov = 75.0
	camera_chase_distance = 18.0
	camera_chase_height = 4.0
	camera_shake = true
	camera_shake_intensity = 1.0
	camera_gyro_look = true
	camera_padlock = false
	camera_smoothing = 0.5
	camera_cockpit_canopy = true

	hud_color = "green"
	hud_scale = 1.0
	hud_opacity = 0.9
	hud_show_minimap = true
	hud_minimap_zoom = 1.0
	hud_show_target_info = true
	hud_show_rwr = true
	hud_show_tapes = true
	hud_show_g_meter = true
	hud_show_waypoints = true
	hud_show_damage = true
	hud_show_kill_feed = true
	hud_subtitles = true

	volume_master = 1.0
	volume_sfx = 1.0
	volume_engine = 1.0
	volume_weapons = 1.0
	volume_music = 0.6
	volume_radio_chatter = 0.8
	volume_ui = 0.8
	cockpit_muffle = true
	warning_voice = "female"
	mute_in_background = true

	radio_enabled = true
	radio_source = "random"
	radio_playlist_id = ""
	radio_genre = ""
	radio_shuffle = true
	radio_autostart = true
	volume_radio = 0.8
	radio_duck_during_warnings = true
	radio_cockpit_fx = true
	radio_show_toast = true

	gameplay_difficulty = "normal"
	gameplay_time_of_day = "noon"
	gameplay_weather = "clear"
	gameplay_ai_count = 4
	gameplay_ground_density = "medium"
	gameplay_wingmen = true
	gameplay_time_limit = true
	gameplay_tutorial_hints = true

	pilot_callsign = "Viper"
	unlock_all_aircraft = false

	save()
	apply()
	changed.emit("all")


func export_to_json() -> String:
	var data := {}
	for key in _keys():
		data[key] = get(key)
	return JSON.stringify(data, "\t")


func import_from_json(json_str: String) -> bool:
	var parsed: Variant = JSON.parse_string(json_str)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = parsed
	for key in dict:
		if key in self:
			set(key, dict[key])
	save()
	apply()
	changed.emit("all")
	return true


func _keys() -> Array:
	var out := []
	for p in get_property_list():
		# Runtime state (names starting with _) is not saved.
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name.begins_with("_"):
			out.append(p.name)
	return out
