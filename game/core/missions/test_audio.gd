extends Node3D
## Audio test scene. On start it checks that every library sound loads, then plays them in sequence, flies a
## Doppler flyby past the camera, and runs an EngineAudio aircraft that flies away from the camera (distance crossfade).
## If NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASS are set in the environment, it also plays 10 s of radio.

## Stand-in aircraft for EngineAudio: throttle sweeps, afterburner near full throttle, flies away from the camera.
class FakeAircraft extends Node3D:
	var data := {"engine": "jet"}
	var _t := 0.0

	func _physics_process(delta: float) -> void:
		_t += delta
		position = Vector3(0.0, 40.0, -30.0 - fposmod(_t * 120.0, 3000.0))

	func get_throttle() -> float:
		return 0.6 + 0.4 * sin(_t * 0.5)

	func is_afterburner() -> bool:
		return get_throttle() > 0.95

	func get_speed_kmh() -> float:
		return 300.0 + 400.0 * get_throttle()


const SOUNDS := [
	"engine_jet", "engine_jet_ab", "engine_jet_far", "engine_prop", "engine_heli", "wind",
	"gun_vulcan", "gun_30mm", "gun_gau8", "gun_50cal", "gun_tail",
	"missile_launch", "missile_flyby", "rocket_launch", "bomb_release", "flare_launch",
	"explosion_small", "explosion_large", "explosion_far", "bullet_hit_metal", "bullet_hit_ground", "water_splash",
	"lock_tone", "lock_solid", "rwr_ping", "missile_warning", "stall_warning", "gear", "canopy",
	"ui_click", "ui_confirm", "ui_back", "hit_marker", "kill_confirm",
	"voice_pull_up", "voice_altitude", "voice_missile", "voice_bingo_fuel", "voice_overg",
]
## Cockpit and warning sounds play 2D (on the Cockpit bus). Voice lines are 2D too.
const COCKPIT_SOUNDS := [
	"lock_tone", "lock_solid", "rwr_ping", "missile_warning", "stall_warning", "gear", "canopy",
	"ui_click", "ui_confirm", "ui_back", "hit_marker", "kill_confirm",
]
const EMITTER_POS := Vector3(0.0, 0.0, -60.0)
const SOUND_GAP := 1.5
const LOOP_HOLD := 2.5
const FLYBY_PERIOD := 4.0
const FLYBY_HALF_SPAN := 300.0

@onready var _flyby: AudioStreamPlayer3D = $Flyby
var _flyby_t := 0.0
var _flyby_last_phase := 0.0
var _aircraft: FakeAircraft
var _engine: EngineAudio


func _ready() -> void:
	_check_library()
	_flyby.stream = Sfx.get_stream("missile_flyby")
	_flyby.unit_size = 30.0
	_flyby.max_distance = 4000.0
	_flyby.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	_flyby.play()
	_setup_engine()
	_run_sequence()
	_radio_test()


func _physics_process(delta: float) -> void:
	# Doppler tracking works on physics steps, so the flyby moves here.
	_flyby_t += delta
	var phase := fposmod(_flyby_t, FLYBY_PERIOD) / FLYBY_PERIOD
	if phase < _flyby_last_phase:
		_flyby.play()  # a new pass
	_flyby_last_phase = phase
	_flyby.position = Vector3(lerpf(-FLYBY_HALF_SPAN, FLYBY_HALF_SPAN, phase), 1.0, -40.0)


func _check_library() -> void:
	var missing: Array = []
	for sound: String in SOUNDS:
		if Sfx.get_stream(sound) == null:
			missing.append(sound)
	print("Sfx library: %d of %d sounds load" % [SOUNDS.size() - missing.size(), SOUNDS.size()])
	if not missing.is_empty():
		push_error("Sfx library missing: %s" % str(missing))


func _setup_engine() -> void:
	_aircraft = FakeAircraft.new()
	add_child(_aircraft)
	_engine = EngineAudio.new()
	_aircraft.add_child(_engine)
	_engine.setup(_aircraft)


## Plays every library sound once: loops for LOOP_HOLD seconds, one-shots followed by a short gap.
func _run_sequence() -> void:
	for sound: String in SOUNDS:
		print("Sfx test: ", sound)
		var is_2d := sound.begins_with("voice_") or COCKPIT_SOUNDS.has(sound)
		var looping: bool = Sfx.LOOP_SOUNDS.has(sound)
		var holder := Node3D.new()
		holder.position = EMITTER_POS
		add_child(holder)
		var looped: Node = null
		if looping:
			if is_2d:
				looped = Sfx.loop_2d(sound, -6.0)
			else:
				looped = Sfx.attach_loop(sound, holder, -6.0)
			await get_tree().create_timer(LOOP_HOLD).timeout
		else:
			if is_2d:
				Sfx.play_2d(sound)
			else:
				Sfx.play_3d(sound, EMITTER_POS)
			await get_tree().create_timer(SOUND_GAP).timeout
		if looped != null:
			looped.queue_free()  # 2D loops live under Sfx, so they are not freed with the holder
		holder.queue_free()


## Connects to Navidrome only when the three environment variables are set. Settings stay in memory (not saved).
func _radio_test() -> void:
	var url := OS.get_environment("NAVIDROME_URL")
	var user := OS.get_environment("NAVIDROME_USER")
	var password := OS.get_environment("NAVIDROME_PASS")
	if url == "" or user == "" or password == "":
		print("Radio test skipped: set NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASS to try streaming")
		return
	Settings.navidrome_url = url
	Settings.navidrome_user = user
	Settings.navidrome_password = password
	Settings.radio_enabled = true
	Radio.status_changed.connect(_on_radio_status)
	Radio.track_changed.connect(_on_radio_track)
	Radio.start()
	await get_tree().create_timer(10.0).timeout
	Radio.stop()
	print("Radio test done")


func _on_radio_status(text: String) -> void:
	print("Radio status: ", text)


func _on_radio_track(title: String, artist: String) -> void:
	print("Radio track: %s - %s" % [artist, title])
