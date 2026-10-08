extends Node
## In-game music radio streaming from the user's Navidrome server. STUB: replaced by the audio task.

signal track_changed(title: String, artist: String)
signal status_changed(status: String)  # "off", "connecting", "playing", "error: <msg>"

var now_title := ""
var now_artist := ""
var status := "off"


func start() -> void:
	pass


func stop() -> void:
	pass


func next_track() -> void:
	pass


func toggle() -> void:
	pass
