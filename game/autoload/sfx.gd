extends Node
## Sound effects autoload. Sounds are res://assets/sounds/<name>.(ogg|wav|mp3); `sound_name` is the file name without extension.
## Buses (default_bus_layout.tres): "SFX" = world sounds (3D one-shots and loops), low-passed in cockpit view;
## "Cockpit" = 2D cockpit, warning and UI sounds, volume follows Settings.volume_sfx; "Music" = radio (radio.gd).
## Positions are LOCAL scene coordinates (node.global_position). Pooled players are rebased on WorldOrigin.shifted.

const SOUND_DIR := "res://assets/sounds/"
const SOUND_EXTENSIONS := [".ogg", ".wav", ".mp3"]
const POOL_3D := 24
const POOL_2D := 12
const SPEED_OF_SOUND := 340.0
## Explosions closer than this play at once; farther big ones play the delayed distant boom.
const NEAR_BLAST_DISTANCE := 1200.0
const BIG_BLAST_SIZE := 1.5
const DEFAULT_MAX_DISTANCE := 4000.0
const FAR_BLAST_MAX_DISTANCE := 8000.0
const UNIT_SIZE := 30.0
## Distance low-pass (AudioStreamPlayer3D attenuation filter): far sounds lose their highs.
const WORLD_LOWPASS_HZ := 5000.0
## Names that loop; everything else is one-shot.
const LOOP_SOUNDS := [
	"engine_jet", "engine_jet_ab", "engine_jet_far", "engine_prop", "engine_heli", "wind",
	"gun_vulcan", "gun_30mm", "gun_gau8", "gun_50cal", "lock_tone", "lock_solid",
	"missile_warning", "stall_warning",
]

var _cache: Dictionary = {}  # sound name -> AudioStream (null when missing)
var _warned: Dictionary = {}  # sound name -> true once a warning was printed
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _sfx_bus := -1
var _cockpit_bus := -1


func _ready() -> void:
	_sfx_bus = AudioServer.get_bus_index("SFX")
	_cockpit_bus = AudioServer.get_bus_index("Cockpit")
	var sfx_bus: StringName = &"SFX" if _sfx_bus >= 0 else &"Master"
	var cockpit_bus: StringName = &"Cockpit" if _cockpit_bus >= 0 else &"Master"
	for _i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		_configure_3d(p)
		p.bus = sfx_bus
		add_child(p)
		_pool_3d.append(p)
	for _i in POOL_2D:
		var q := AudioStreamPlayer.new()
		q.bus = cockpit_bus
		add_child(q)
		_pool_2d.append(q)
	Events.explosion.connect(_on_explosion)
	Events.missile_launched.connect(_on_missile_launched)
	Events.flares_dropped.connect(_on_flares_dropped)
	WorldOrigin.shifted.connect(_on_origin_shifted)
	Settings.changed.connect(_apply_volumes)
	_apply_volumes()


## Returns the stream for a sound name, loading it once. Unknown names warn once and return null.
func get_stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var stream: AudioStream = null
	for ext: String in SOUND_EXTENSIONS:
		var path: String = SOUND_DIR + sound_name + ext
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
			break
	if stream == null:
		if not _warned.has(sound_name):
			_warned[sound_name] = true
			push_warning("Sfx: unknown sound '%s'" % sound_name)
	elif LOOP_SOUNDS.has(sound_name) and stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
	_cache[sound_name] = stream
	return stream


## One-shot non-positional sound (UI, cockpit, warnings). Voice warnings (voice_*) duck the radio.
func play_2d(sound_name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := get_stream(sound_name)
	if stream == null:
		return
	var p := _take_2d()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	if sound_name.begins_with("voice_"):
		Radio.duck(stream.get_length() + 0.3)


## One-shot positional sound at a LOCAL position (explosions, impacts, launches). Pitch gets +/-5% random variation.
func play_3d(sound_name: String, local_pos: Vector3, volume_db := 0.0, pitch := 1.0,
		max_distance := DEFAULT_MAX_DISTANCE) -> void:
	var stream := get_stream(sound_name)
	if stream == null:
		return
	var p := _take_3d()
	p.stream = stream
	p.global_position = local_pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.max_distance = max_distance
	p.play()


## Looping positional sound attached to `parent` (engines, guns, wind). Starts at once. The caller sets
## volume_db / pitch_scale on the returned player and frees it (it is also freed together with `parent`).
## Returns null when the sound is unknown.
func attach_loop(sound_name: String, parent: Node3D, volume_db := 0.0) -> AudioStreamPlayer3D:
	var stream := get_stream(sound_name)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	_configure_3d(p)
	p.bus = &"SFX" if _sfx_bus >= 0 else &"Master"
	p.stream = stream
	p.volume_db = volume_db
	if parent == null:
		add_child(p)
	else:
		parent.add_child(p)
	p.play()
	return p


## Looping non-positional sound on the Cockpit bus (cockpit wind, lock tone). Starts at once; caller frees it.
func loop_2d(sound_name: String, volume_db := 0.0) -> AudioStreamPlayer:
	var stream := get_stream(sound_name)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.bus = &"Cockpit" if _cockpit_bus >= 0 else &"Master"
	p.stream = stream
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p


## Cockpit view: low-pass on the SFX bus, so exterior world sounds sound muffled. Cockpit and UI sounds are unaffected.
func set_cockpit(on: bool) -> void:
	if _sfx_bus >= 0 and AudioServer.get_bus_effect_count(_sfx_bus) > 0:
		AudioServer.set_bus_effect_enabled(_sfx_bus, 0, on)


## Short phone vibration if Settings.haptics. strength 0..1.
func haptic(strength := 0.5, duration_ms := 30) -> void:
	if not Settings.haptics:
		return
	Input.vibrate_handheld(duration_ms, clampf(strength, 0.0, 1.0))


func _configure_3d(p: AudioStreamPlayer3D) -> void:
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = UNIT_SIZE
	p.max_distance = DEFAULT_MAX_DISTANCE
	p.attenuation_filter_cutoff_hz = WORLD_LOWPASS_HZ
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP


## Prefers an idle pooled player; otherwise steals the next one in round-robin order.
func _take_3d() -> AudioStreamPlayer3D:
	for i in POOL_3D:
		var idx := (_next_3d + i) % POOL_3D
		if not _pool_3d[idx].playing:
			_next_3d = (idx + 1) % POOL_3D
			return _pool_3d[idx]
	var stolen := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	return stolen


func _take_2d() -> AudioStreamPlayer:
	for i in POOL_2D:
		var idx := (_next_2d + i) % POOL_2D
		if not _pool_2d[idx].playing:
			_next_2d = (idx + 1) % POOL_2D
			return _pool_2d[idx]
	var stolen := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	return stolen


func _apply_volumes() -> void:
	if _cockpit_bus >= 0:
		AudioServer.set_bus_volume_db(_cockpit_bus, linear_to_db(maxf(Settings.volume_sfx, 0.0001)))


func _listener_pos() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position


func _on_explosion(world_local_pos: Vector3, size: float) -> void:
	var distance := _listener_pos().distance_to(world_local_pos)
	var big := size >= BIG_BLAST_SIZE
	var gain := linear_to_db(clampf(size, 0.25, 2.0))
	if distance <= NEAR_BLAST_DISTANCE:
		play_3d("explosion_large" if big else "explosion_small", world_local_pos, gain)
	elif big:
		# The boom reaches the listener after distance / speed of sound. Store world coords, the origin may shift.
		var wpos := WorldOrigin.to_world(world_local_pos)
		get_tree().create_timer(distance / SPEED_OF_SOUND).timeout.connect(_play_far_blast.bind(wpos, gain))


func _play_far_blast(wpos: Vector3, gain: float) -> void:
	play_3d("explosion_far", WorldOrigin.to_local(wpos), gain, 1.0, FAR_BLAST_MAX_DISTANCE)


func _on_missile_launched(missile: Node3D, _shooter: Node3D, _target: Node3D) -> void:
	if is_instance_valid(missile):
		play_3d("missile_launch", missile.global_position)


func _on_flares_dropped(aircraft: Node3D) -> void:
	if is_instance_valid(aircraft):
		play_3d("flare_launch", aircraft.global_position, -3.0)


func _on_origin_shifted(delta: Vector3) -> void:
	for p: AudioStreamPlayer3D in _pool_3d:
		p.global_position -= delta
