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
var best_times: Dictionary = {}  # "map:length" -> seconds, time trial
var mission_history: Array = []  # last 20 results

## The sortie being flown: seed and options from the mission screen, and the last result for the results screen.
var mission_seed := -1  # -1 rolls a new seed on the next flight
var mission_options: Dictionary = {}
var last_result: Dictionary = {}

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
	LoadingScreen.start("res://scenes/level.tscn", selected_map, selected_mode)


func goto_menu() -> void:
	player = null
	level = null
	mission_seed = -1
	mission_options = {}
	LoadingScreen.dismiss()
	WorldOrigin.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menu/menu_root.tscn")


## Starts a sortie picked on the mission screen. A new seed is rolled, so RETRY flies this same sortie again.
func begin_mission(mode_id: String, map_id: String, options: Dictionary, diff: String) -> void:
	selected_mode = mode_id
	selected_map = map_id
	difficulty = diff
	mission_options = options.duplicate()
	mission_seed = randi()
	for def in MissionGenerator.data()["modes"][mode_id]["options"]:
		if def.has("setting") and options.has(def["id"]):
			Settings.set(String(def["setting"]), options[def["id"]])
	start_flight()


## RETRY: the same seed and options again.
func restart_mission() -> void:
	get_tree().paused = false
	player = null
	level = null
	WorldOrigin.reset()
	start_flight()


## NEXT: a fresh sortie of the same mode, map and difficulty.
func next_mission() -> void:
	mission_seed = randi()
	restart_mission()


## Books a finished sortie: rewards for flown missions, history, best times, and the data the results screen shows.
func record_result(result: Dictionary) -> void:
	var reward := {"credits": 0, "xp": 0, "rank_before": 0, "rank_after": 0}
	if not bool(result.get("practice", false)):
		reward = Progression.record_mission(result)
	mission_history.push_front(result)
	if mission_history.size() > 20:
		mission_history.resize(20)
	if bool(result.get("won", false)):
		missions_completed += 1
		if String(result.get("mode", "")) == "time_trial":
			var length := String(result.get("options", {}).get("length", "short"))
			var key := "%s:%s" % [String(result.get("map", "")), length]
			var secs := float(result.get("time_s", 0.0))
			if not best_times.has(key) or secs < float(best_times[key]):
				best_times[key] = secs
	last_result = result.duplicate()
	last_result.merge(reward)
	save_progress()


## Loads a JSON file from res://data and returns its parsed value (Dictionary or Array).
func load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("GameState: cannot read %s" % path)
		return {}
	return JSON.parse_string(text)
