extends Node
## Current selection + persistent progress (user://save.json) + scene flow.

const SAVE_PATH := "user://save.json"

var selected_aircraft := "f16c"
var selected_map := "gibraltar"
var selected_mode := "free_flight"  # see data/modes.json
var selected_loadout := ""  # "" = aircraft default
var selected_skin := ""
var time_of_day := 14.0  # hours, 0..24
var weather := "clear"  # "clear", "scattered", "overcast", "storm"
var difficulty := "normal"  # "easy", "normal", "hard", "ace"

## Persistent progress.
var credits := 0
var total_kills := 0
var missions_completed := 0
var flight_seconds := 0.0
var unlocked_skins: Array = []
var best_times: Dictionary = {}  # mode_id -> seconds
var mission_history: Array = []  # last 20 results

## Set by the level while flying.
var player: Node3D
var level: Node


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key in data:
		if key in self:
			set(key, data[key])


func save_progress() -> void:
	var data := {}
	for key in ["selected_aircraft", "selected_map", "selected_mode", "selected_loadout", "selected_skin",
			"time_of_day", "weather", "difficulty", "credits", "total_kills", "missions_completed",
			"flight_seconds", "unlocked_skins", "best_times", "mission_history"]:
		data[key] = get(key)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func start_flight() -> void:
	save_progress()
	get_tree().change_scene_to_file("res://scenes/level.tscn")


func goto_menu() -> void:
	player = null
	level = null
	WorldOrigin.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Loads a JSON file from res://data and returns its parsed value (Dictionary or Array).
func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("GameState: cannot read %s" % path)
		return {}
	return JSON.parse_string(text)
