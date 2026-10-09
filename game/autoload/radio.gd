extends Node
## Music radio streamed from the user's Navidrome (OpenSubsonic) server, played on the "Music" bus.
## Status: "off", "connecting", "connected" (test_connection ok), "playing", "error: <msg>".
## Godot cannot stream HTTP audio, so each track is downloaded whole, the next one is prefetched, and tracks crossfade.
## At most two tracks are held in memory (the playing one and the prefetched one).

signal track_changed(title: String, artist: String)
signal status_changed(status: String)  # "off", "connecting", "connected", "playing", "error: <msg>"
signal playlists_loaded(list: Array)  # [{id, name, count}]
signal genres_loaded(list: Array)  # [{name, count}]

const API_VERSION := "1.16.1"
const CLIENT_NAME := "KnightWings"
const CROSSFADE_SECONDS := 2.0
const DUCK_DB := -6.0
const SILENT_DB := -60.0
const SONG_LIST_SIZE := 50
const GENRE_SONG_COUNT := 100
const API_TIMEOUT := 15.0
const DOWNLOAD_TIMEOUT := 120.0
const DOWNLOAD_CHUNK := 65536
const RETRY_SECONDS := 20.0
const MAX_FAILS_IN_A_ROW := 3
const SALT_CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

var now_title := ""
var now_artist := ""
var status := "off"
## Subtle band-pass on the Music bus for a cockpit-radio flavour. Off by default.
var cockpit_fx: bool = false:
	set(value):
		cockpit_fx = value
		_apply_cockpit_fx()

var _players: Array[AudioStreamPlayer] = []
var _slot_db: Array[float] = [0.0, SILENT_DB]  # fade level per player; combined with _duck_db
var _active := 0
var _fading_old := -1
var _tween: Tween
var _music_bus := -1
var _running := false
var _queue: Array = []  # song dictionaries waiting to be downloaded
var _next_stream: AudioStreamMP3
var _next_song: Dictionary = {}
var _download_song: Dictionary = {}
var _http_download: HTTPRequest
var _retry_timer: Timer  # a node timer, unlike create_timer(), can be stopped when the radio goes away
var _listing := false
var _skip_pending := false
var _retry_pending := false
var _fails_in_a_row := 0
var _duck_left := 0.0
var _duck_db := 0.0


func _ready() -> void:
	_music_bus = AudioServer.get_bus_index("Music")
	var bus: StringName = &"Music" if _music_bus >= 0 else &"Master"
	for _i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_players.append(p)
	_http_download = HTTPRequest.new()
	_http_download.download_chunk_size = DOWNLOAD_CHUNK
	_http_download.body_size_limit = -1
	_http_download.timeout = DOWNLOAD_TIMEOUT
	add_child(_http_download)
	_http_download.request_completed.connect(_on_download_done)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	add_child(_retry_timer)
	_retry_timer.timeout.connect(_on_retry)
	_apply_cockpit_fx()


## Stops the crossfade and the retry timer, so no pending callback is left when the autoload is freed.
func _exit_tree() -> void:
	if _tween != null:
		_tween.kill()
	_retry_timer.stop()


func _process(delta: float) -> void:
	_duck_left = maxf(_duck_left - delta, 0.0)
	_duck_db = move_toward(_duck_db, DUCK_DB if _duck_left > 0.0 else 0.0, 12.0 * delta)
	for i in 2:
		_players[i].volume_db = _slot_db[i] + _duck_db
	if not _running:
		return
	var cur := _players[_active]
	if cur.playing:
		if _next_stream != null and _fading_old < 0 and cur.stream != null:
			if cur.stream.get_length() - cur.get_playback_position() <= CROSSFADE_SECONDS:
				_switch_to_next(true)
	elif _next_stream != null:
		_switch_to_next(false)


## Starts the radio (no-op if already running). Status goes "connecting", then "playing".
func start() -> void:
	if _running:
		return
	if not Settings.radio_enabled:
		_set_status("off")
		return
	if not _configured():
		_set_status("error: no server set")
		return
	_running = true
	_fails_in_a_row = 0
	_set_status("connecting")
	_prefetch()


## Stops playback, drops the queue and any prefetched track. The next start() re-reads Settings.radio_source.
func stop() -> void:
	_running = false
	_skip_pending = false
	_retry_pending = false
	_retry_timer.stop()
	_http_download.cancel_request()
	_download_song = {}
	_next_stream = null
	_next_song = {}
	_queue.clear()
	if _tween != null:
		_tween.kill()
	_fading_old = -1
	_active = 0
	for p in _players:
		p.stop()
		p.stream = null
	_slot_db[0] = 0.0
	_slot_db[1] = SILENT_DB
	now_title = ""
	now_artist = ""
	track_changed.emit("", "")
	_set_status("off")


func toggle() -> void:
	if _running:
		stop()
	else:
		start()


## Skips to the next track. Crossfades when the next track is already downloaded.
func next_track() -> void:
	if not _running:
		return
	if _next_stream != null:
		_switch_to_next(_players[_active].playing)
	else:
		_skip_pending = true
		_prefetch()


## Lowers the music by 6 dB for `seconds` (called by voice warnings).
func duck(seconds: float) -> void:
	_duck_left = maxf(_duck_left, seconds)


## Pings the server. Emits status_changed "connecting", then "connected" or "error: <msg>".
func test_connection() -> void:
	if not _configured():
		_set_status("error: no server set")
		return
	if not _running:
		_set_status("connecting")
	_api("ping.view", "", _on_ping_done)


## Emits playlists_loaded([{id, name, count}]). Empty list on error.
func fetch_playlists() -> void:
	_api("getPlaylists.view", "", _on_playlists_done)


## Emits genres_loaded([{name, count}]). Empty list on error.
func fetch_genres() -> void:
	_api("getGenres.view", "", _on_genres_done)


## URL of a cover image (for the menu or HUD). Empty string when no server is set.
func cover_art_url(song_id: String) -> String:
	if not _configured():
		return ""
	return "%s/rest/getCoverArt.view?id=%s&size=256&%s" % [_base(), song_id.uri_encode(), _auth()]


func _configured() -> bool:
	return _base() != "" and Settings.navidrome_user != ""


func _base() -> String:
	return Settings.navidrome_url.strip_edges().rstrip("/")


## Subsonic token auth: t = md5(password + salt), s = salt. A fresh salt per request.
func _auth() -> String:
	var salt := ""
	for _i in 12:
		salt += SALT_CHARS[randi() % SALT_CHARS.length()]
	var token := (Settings.navidrome_password + salt).md5_text()
	return "u=%s&t=%s&s=%s&v=%s&c=%s&f=json" % [
		Settings.navidrome_user.uri_encode(), token, salt, API_VERSION, CLIENT_NAME]


## Async JSON call. on_done receives (ok: bool, resp: Dictionary, err: String).
func _api(endpoint: String, query: String, on_done: Callable) -> void:
	if not _configured():
		on_done.call(false, {}, "no server set")
		return
	var req := HTTPRequest.new()
	req.timeout = API_TIMEOUT
	add_child(req)
	var url := "%s/rest/%s?%s" % [_base(), endpoint, _auth()]
	if query != "":
		url += "&" + query
	req.request_completed.connect(_on_api_done.bind(req, on_done))
	if req.request(url) != OK:
		req.queue_free()
		on_done.call(false, {}, "request failed")


func _on_api_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		req: HTTPRequest, on_done: Callable) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		on_done.call(false, {}, "HTTP %d (result %d)" % [code, result])
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var root: Dictionary = parsed if parsed is Dictionary else {}
	var resp: Dictionary = root.get("subsonic-response", {})
	if resp.is_empty():
		on_done.call(false, {}, "bad server response")
		return
	if str(resp.get("status", "")) != "ok":
		var msg := "server error"
		if resp.has("error"):
			msg = str(resp["error"].get("message", msg))
		on_done.call(false, resp, msg)
		return
	on_done.call(true, resp, "")


## Returns resp[container][item_key] as an Array (Subsonic JSON returns a bare object when there is one item).
func _items(resp: Dictionary, container: String, item_key: String) -> Array:
	var box: Variant = resp.get(container, {})
	if not (box is Dictionary):
		return []
	var items: Variant = (box as Dictionary).get(item_key, [])
	if items is Dictionary:
		return [items]
	if items is Array:
		return items
	return []


func _on_ping_done(ok: bool, _resp: Dictionary, err: String) -> void:
	if _running:
		return
	_set_status("connected" if ok else "error: " + err)


func _on_playlists_done(ok: bool, resp: Dictionary, err: String) -> void:
	var out: Array = []
	if ok:
		for item in _items(resp, "playlists", "playlist"):
			out.append({"id": str(item.get("id", "")), "name": str(item.get("name", "")),
				"count": int(item.get("songCount", 0))})
	else:
		_report_error(err)
	playlists_loaded.emit(out)


func _on_genres_done(ok: bool, resp: Dictionary, err: String) -> void:
	var out: Array = []
	if ok:
		for item in _items(resp, "genres", "genre"):
			out.append({"name": str(item.get("value", "")), "count": int(item.get("songCount", 0))})
	else:
		_report_error(err)
	genres_loaded.emit(out)


func _report_error(err: String) -> void:
	if not _running:
		_set_status("error: " + err)


## Fills the queue from Settings.radio_source: "random", "starred", "playlist:<id>", "genre:<name>".
func _fetch_songs() -> void:
	_listing = true
	var source := Settings.radio_source
	if source == "starred":
		_api("getStarred2.view", "", _on_songs_done.bind("starred2", "song"))
	elif source.begins_with("playlist:"):
		var pid := source.trim_prefix("playlist:")
		_api("getPlaylist.view", "id=" + pid.uri_encode(), _on_songs_done.bind("playlist", "entry"))
	elif source.begins_with("genre:"):
		var genre := source.trim_prefix("genre:")
		_api("getSongsByGenre.view", "genre=%s&count=%d" % [genre.uri_encode(), GENRE_SONG_COUNT],
			_on_songs_done.bind("songsByGenre", "song"))
	else:
		_api("getRandomSongs.view", "size=%d" % SONG_LIST_SIZE, _on_songs_done.bind("randomSongs", "song"))


func _on_songs_done(ok: bool, resp: Dictionary, err: String, container: String, item_key: String) -> void:
	_listing = false
	if not _running:
		return
	if not ok:
		_on_failure("song list: " + err)
		return
	for song in _items(resp, container, item_key):
		if song is Dictionary and song.has("id"):
			_queue.append(song)
	if _queue.is_empty():
		_on_failure("no songs for this source")
		return
	_prefetch()


## Downloads the next queued track into _next_stream, unless one is already waiting or a fade is running.
func _prefetch() -> void:
	if not _running or _next_stream != null or _fading_old >= 0:
		return
	if not _download_song.is_empty() or _listing or _retry_pending:
		return
	if _queue.is_empty():
		_fetch_songs()
		return
	var song: Dictionary = _queue.pop_front()
	_download_song = song
	var url := "%s/rest/stream.view?id=%s&format=mp3&maxBitRate=192&%s" % [
		_base(), str(song["id"]).uri_encode(), _auth()]
	if _http_download.request(url) != OK:
		_download_song = {}
		_on_failure("stream request failed")


func _on_download_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var song := _download_song
	_download_song = {}
	if not _running or song.is_empty():
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.is_empty():
		_on_failure("download failed (HTTP %d)" % code)
		return
	if body.size() < 4096 and body[0] == 0x7B:  # '{': a JSON error body, not audio
		_on_failure("server refused a track")
		return
	var stream := AudioStreamMP3.new()
	stream.data = body
	_next_stream = stream
	_next_song = song
	_fails_in_a_row = 0
	if _skip_pending:
		_skip_pending = false
		_switch_to_next(_players[_active].playing)
	elif not _players[_active].playing:
		_switch_to_next(false)


## A track or list request failed: show the error, try the next track, and back off after repeated failures.
func _on_failure(msg: String) -> void:
	_set_status("error: " + msg)
	_fails_in_a_row += 1
	if _fails_in_a_row >= MAX_FAILS_IN_A_ROW:
		_fails_in_a_row = 0
		_retry_later()
	else:
		_prefetch()


func _retry_later() -> void:
	if _retry_pending:
		return
	_retry_pending = true
	_retry_timer.start(RETRY_SECONDS)


func _on_retry() -> void:
	_retry_pending = false
	if _running:
		_set_status("connecting")
		_prefetch()


## Starts the prefetched track on the idle player. With `crossfade`, the current track fades out over 2 s.
func _switch_to_next(crossfade: bool) -> void:
	if _next_stream == null:
		return
	if _fading_old >= 0:
		# A fade is still running: finish it immediately.
		_tween.kill()
		_slot_db[_active] = 0.0
		_on_fade_done(_fading_old)
	var old_i := _active
	var new_i := 1 - _active
	var fade := crossfade and _players[old_i].playing
	var incoming := _players[new_i]
	incoming.stream = _next_stream
	incoming.play()
	_slot_db[new_i] = SILENT_DB if fade else 0.0
	_active = new_i
	now_title = str(_next_song.get("title", ""))
	now_artist = str(_next_song.get("artist", ""))
	_next_stream = null
	_next_song = {}
	track_changed.emit(now_title, now_artist)
	_set_status("playing")
	if fade:
		_fading_old = old_i
		_tween = create_tween()
		_tween.tween_method(_fade_step.bind(old_i, new_i), 0.0, 1.0, CROSSFADE_SECONDS)
		_tween.finished.connect(_on_fade_done.bind(old_i))
	else:
		_on_fade_done(old_i)


func _fade_step(t: float, old_i: int, new_i: int) -> void:
	_slot_db[old_i] = lerpf(0.0, SILENT_DB, t)
	_slot_db[new_i] = lerpf(SILENT_DB, 0.0, t)


## Releases the faded-out player's stream (keeps at most two tracks in memory) and starts the next prefetch.
func _on_fade_done(old_i: int) -> void:
	_fading_old = -1
	_players[old_i].stop()
	_players[old_i].stream = null
	_slot_db[old_i] = SILENT_DB
	_prefetch()


func _apply_cockpit_fx() -> void:
	if _music_bus >= 0 and AudioServer.get_bus_effect_count(_music_bus) > 0:
		AudioServer.set_bus_effect_enabled(_music_bus, 0, cockpit_fx)


func _set_status(text: String) -> void:
	if status == text:
		return
	status = text
	status_changed.emit(text)
