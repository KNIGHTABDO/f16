extends Node
## Hangar progression (autoload "Progression"). Owns credits, XP and rank, aircraft and livery unlocks,
## and per-aircraft loadouts. Static config: res://data/progression.json. Player progress: user://progression.json.
## Loadouts use the same shape as the aircraft json: [{"weapon": id, "count": stores}, ...].
## A loadout is edited per pylon: one weapon id (or "") per pylon. A pylon holds one rack, and a rack
## holds rack_capacity(weapon) stores (rocket pods, Hellfire quads), so count = pylons x capacity.
##
## Used by:
##   hangar UI            is_unlocked, price_of, buy_aircraft, select_aircraft, aircraft_roster,
##                        livery_list, set_livery, buy_livery, livery_for, art_texture,
##                        legal_weapons, weapon_info, pylon_count, pylons_from_loadout, loadout_from_pylons,
##                        build_preset, preset_available, presets, set_loadout, clear_loadout, payload_kg
##   mission results      record_mission({won, air_kills, ground_kills}) -> {credits, xp, rank_before, rank_after}
##   aircraft spawn       loadout_for(id) (replaces AircraftData.loadout(GameState.selected_loadout))
##   aircraft visuals     livery_for(id) + art_texture("liveries/<id>")

const SAVE_PATH := "user://progression.json"
const DATA_PATH := "res://data/progression.json"
const ROSTER_PATH := "res://data/roster.json"
const WEAPONS_PATH := "res://data/weapons.json"
const UI_ART_PATH := "res://data/ui_art.json"
const SAVE_VERSION := 1
const GUN_TYPE := "gun"

signal changed

var credits := 0
var xp := 0
var missions := 0
var wins := 0
var air_kills := 0
var ground_kills := 0

var _config: Dictionary = {}
var _art: Dictionary = {}
var _roster: Array[Dictionary] = []
var _roster_by_id: Dictionary = {}
var _weapons: Dictionary = {}
var _owned_aircraft: Array[String] = []
var _owned_liveries: Array[String] = []
var _loadouts: Dictionary = {}  # aircraft id -> Array of {weapon, count}
var _liveries_selected: Dictionary = {}  # aircraft id -> livery id
var _textures: Dictionary = {}  # art key -> Texture2D cache


func _ready() -> void:
	_config = _read_json(DATA_PATH)
	_art = _read_json(UI_ART_PATH)
	_weapons = _read_json(WEAPONS_PATH)
	for row_v in _read_json_array(ROSTER_PATH):
		var row: Dictionary = row_v
		_roster.append(row)
		_roster_by_id[str(row.get("id", ""))] = row
	_load_save()
	_ensure_selection()


# ---------- Aircraft and unlocks ----------

func aircraft_roster() -> Array[Dictionary]:
	return _roster


func entry(aircraft_id: String) -> Dictionary:
	return _roster_by_id.get(aircraft_id, {})


func is_unlocked(aircraft_id: String) -> bool:
	if Settings.unlock_all_aircraft:
		return true
	if aircraft_id in _config.get("starter_aircraft", []):
		return true
	return aircraft_id in _owned_aircraft


func price_of(aircraft_id: String) -> int:
	var overrides: Dictionary = _config.get("price_overrides", {})
	if overrides.has(aircraft_id):
		return int(overrides[aircraft_id])
	return int(entry(aircraft_id).get("unlock_cost", 0))


## Spends credits to unlock an aircraft. Returns false if it is already unlocked, unknown, or unaffordable.
func buy_aircraft(aircraft_id: String) -> bool:
	if entry(aircraft_id).is_empty() or is_unlocked(aircraft_id):
		return false
	var price := price_of(aircraft_id)
	if credits < price:
		return false
	credits -= price
	_owned_aircraft.append(aircraft_id)
	_save_and_notify()
	return true


## Makes an unlocked aircraft the one flown from the menus (GameState.selected_aircraft).
func select_aircraft(aircraft_id: String) -> bool:
	if not is_unlocked(aircraft_id):
		return false
	GameState.selected_aircraft = aircraft_id
	GameState.save_progress()
	changed.emit()
	return true


func selected_aircraft() -> String:
	return GameState.selected_aircraft


# ---------- Liveries ----------

## All liveries of one aircraft, in config order: [{id, name, price, owned}].
func livery_list(aircraft_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _config.get("liveries", []):
		var def: Dictionary = raw
		if str(def.get("aircraft", "")) != aircraft_id:
			continue
		var lid := str(def.get("id", ""))
		out.append({"id": lid, "name": str(def.get("name", lid)), "price": int(def.get("price", 0)), "owned": livery_owned(lid)})
	return out


func livery_owned(livery_id: String) -> bool:
	var def := _livery_def(livery_id)
	if def.is_empty():
		return false
	if Settings.unlock_all_aircraft or int(def.get("price", 0)) <= 0:
		return true
	return livery_id in _owned_liveries


## Livery id applied to an aircraft, or "" for the factory paint.
func livery_for(aircraft_id: String) -> String:
	var lid := str(_liveries_selected.get(aircraft_id, ""))
	return lid if lid != "" and livery_owned(lid) else ""


## Applies an owned livery to an aircraft. Pass "" to return to the factory paint.
func set_livery(aircraft_id: String, livery_id: String) -> bool:
	if livery_id == "":
		_liveries_selected.erase(aircraft_id)
	else:
		var def := _livery_def(livery_id)
		if def.is_empty() or str(def.get("aircraft", "")) != aircraft_id or not livery_owned(livery_id):
			return false
		_liveries_selected[aircraft_id] = livery_id
	_save_and_notify()
	return true


func buy_livery(livery_id: String) -> bool:
	var def := _livery_def(livery_id)
	if def.is_empty() or livery_owned(livery_id):
		return false
	var price := int(def.get("price", 0))
	if credits < price:
		return false
	credits -= price
	_owned_liveries.append(livery_id)
	_save_and_notify()
	return true


## Cached texture from ui_art.json, e.g. "aircraft/f16c" (profile) or "liveries/f16c_desert_camo".
## Returns null when the key is unknown or the texture is missing.
func art_texture(key: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	var path := str(_art.get(key, ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_textures[key] = tex
	return tex


# ---------- Loadouts ----------

## Pylon-carrying weapons this aircraft can legally take: every weapon named in its json loadouts, guns excluded.
func legal_weapons(aircraft_id: String) -> Array[String]:
	var out: Array[String] = []
	var ac := AircraftData.load_id(aircraft_id)
	if ac == null:
		return out
	for key in ac.loadouts:
		for item in ac.loadouts[key]:
			var weapon := str((item as Dictionary).get("weapon", ""))
			if weapon == "" or weapon in out or weapon_info(weapon).get("type", "") == GUN_TYPE:
				continue
			out.append(weapon)
	return out


func weapon_info(weapon_id: String) -> Dictionary:
	return _weapons.get(weapon_id, {})


func rack_capacity(weapon_id: String) -> int:
	var caps: Dictionary = _config.get("rack_capacity", {})
	return maxi(int(caps.get(weapon_id, 1)), 1)


## Number of pylons: the json hardpoints, or more if the factory loadout needs more racks.
func pylon_count(aircraft_id: String) -> int:
	var ac := AircraftData.load_id(aircraft_id)
	if ac == null:
		return 0
	return maxi(ac.hardpoints, _pylons_needed(ac.loadout("")))


## The loadout the aircraft will fly: the player's custom one, else the json default.
func loadout_for(aircraft_id: String) -> Array:
	if _loadouts.has(aircraft_id):
		return (_loadouts[aircraft_id] as Array).duplicate(true)
	var ac := AircraftData.load_id(aircraft_id)
	if ac == null:
		return []
	return _normalize_items(ac.loadout(""))


func loadout_is_custom(aircraft_id: String) -> bool:
	return _loadouts.has(aircraft_id)


## Stores a custom loadout after checking every weapon is legal and the racks fit the pylons.
func set_loadout(aircraft_id: String, items: Array) -> bool:
	var legal := legal_weapons(aircraft_id)
	var clean := _normalize_items(items)
	for item in clean:
		if not (item["weapon"] in legal):
			return false
	if _pylons_needed(clean) > pylon_count(aircraft_id):
		return false
	_loadouts[aircraft_id] = clean
	_save_and_notify()
	return true


func clear_loadout(aircraft_id: String) -> void:
	if _loadouts.erase(aircraft_id):
		_save_and_notify()


## Splits a loadout into pylon slots (one weapon id per pylon, "" = empty), padded to pylon_count.
func pylons_from_loadout(aircraft_id: String, items: Array) -> Array[String]:
	var slots: Array[String] = []
	for item in _normalize_items(items):
		var racks := _racks_for(item["weapon"], item["count"])
		for _i in racks:
			slots.append(item["weapon"])
	var total := pylon_count(aircraft_id)
	while slots.size() < total:
		slots.append("")
	slots.resize(total)
	return slots


## Turns pylon slots back into a loadout: each rack adds rack_capacity stores of its weapon.
func loadout_from_pylons(pylons: Array) -> Array:
	var order: Array[String] = []
	var stores := {}
	for slot in pylons:
		var weapon := str(slot)
		if weapon == "":
			continue
		if not stores.has(weapon):
			order.append(weapon)
			stores[weapon] = 0
		stores[weapon] = int(stores[weapon]) + rack_capacity(weapon)
	var out: Array = []
	for weapon in order:
		out.append({"weapon": weapon, "count": stores[weapon]})
	return out


func presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _config.get("presets", []):
		out.append(raw)
	return out


func preset_available(aircraft_id: String, preset_id: String) -> bool:
	return not build_preset(aircraft_id, preset_id).is_empty()


## Pylon slots for a role preset, dealing the aircraft's matching weapons round-robin over every pylon.
## Returns [] when the aircraft has no weapon for that role.
func build_preset(aircraft_id: String, preset_id: String) -> Array[String]:
	var result: Array[String] = []
	var preset := _preset_def(preset_id)
	if preset.is_empty():
		return result
	var candidates: Array[String] = []
	var want_targets: Array = preset.get("targets", [])
	var want_types: Array = preset.get("types", [])
	for weapon in legal_weapons(aircraft_id):
		var info := weapon_info(weapon)
		if _any_match(info.get("targets", []), want_targets) and _any_match([info.get("type", "")], want_types):
			candidates.append(weapon)
	if candidates.is_empty():
		return result
	for i in pylon_count(aircraft_id):
		result.append(candidates[i % candidates.size()])
	return result


## Mass in kg of the heaviest json loadout, for the payload bar.
func payload_kg(aircraft_id: String) -> float:
	var ac := AircraftData.load_id(aircraft_id)
	if ac == null:
		return 0.0
	var best := 0.0
	for key in ac.loadouts:
		best = maxf(best, loadout_mass_kg(ac.loadouts[key]))
	return best


func loadout_mass_kg(items: Array) -> float:
	var total := 0.0
	for item in _normalize_items(items):
		total += float(weapon_info(item["weapon"]).get("mass", 0.0)) * float(item["count"])
	return total


# ---------- Missions, credits, XP and rank ----------

## Pays out a finished mission. result: {won: bool, air_kills: int, ground_kills: int}.
## Returns {credits, xp, rank_before, rank_after} so the results screen can show the rank-up.
func record_mission(result: Dictionary) -> Dictionary:
	var eco: Dictionary = _config.get("economy", {})
	var won := bool(result.get("won", false))
	var air := maxi(int(result.get("air_kills", 0)), 0)
	var ground := maxi(int(result.get("ground_kills", 0)), 0)
	var earned_credits := int(eco.get("mission_base", 0)) + air * int(eco.get("air_kill", 0)) + ground * int(eco.get("ground_kill", 0))
	var earned_xp := air * int(eco.get("xp_air_kill", 0)) + ground * int(eco.get("xp_ground_kill", 0))
	if won:
		earned_credits += int(eco.get("win_bonus", 0))
		earned_xp += int(eco.get("xp_win", 0))
	else:
		earned_xp += int(eco.get("xp_loss", 0))
	var before := rank_index()
	credits += earned_credits
	xp += earned_xp
	missions += 1
	if won:
		wins += 1
	air_kills += air
	ground_kills += ground
	_save_and_notify()
	return {"credits": earned_credits, "xp": earned_xp, "rank_before": before, "rank_after": rank_index()}


func rank_index() -> int:
	var idx := 0
	var ranks: Array = _config.get("ranks", [])
	for i in ranks.size():
		if xp >= int((ranks[i] as Dictionary).get("xp", 0)):
			idx = i
	return idx


func rank_name() -> String:
	var ranks: Array = _config.get("ranks", [])
	return str((ranks[rank_index()] as Dictionary).get("name", "")) if not ranks.is_empty() else ""


## XP needed for the next rank, or -1 at the top rank.
func next_rank_xp() -> int:
	var ranks: Array = _config.get("ranks", [])
	var next := rank_index() + 1
	if next >= ranks.size():
		return -1
	return int((ranks[next] as Dictionary).get("xp", 0))


## Progress from the current rank threshold to the next one, 0..1 (1.0 at the top rank).
func rank_progress() -> float:
	var next := next_rank_xp()
	if next < 0:
		return 1.0
	var ranks: Array = _config.get("ranks", [])
	var start := int((ranks[rank_index()] as Dictionary).get("xp", 0))
	return clampf(float(xp - start) / float(maxi(next - start, 1)), 0.0, 1.0)


## "1234567" -> "1,234,567"
func format_int(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


# ---------- Internals ----------

func _livery_def(livery_id: String) -> Dictionary:
	for raw in _config.get("liveries", []):
		var def: Dictionary = raw
		if str(def.get("id", "")) == livery_id:
			return def
	return {}


func _preset_def(preset_id: String) -> Dictionary:
	for raw in _config.get("presets", []):
		var def: Dictionary = raw
		if str(def.get("id", "")) == preset_id:
			return def
	return {}


func _any_match(have: Array, want: Array) -> bool:
	for v in have:
		if v in want:
			return true
	return false


func _racks_for(weapon: String, count: int) -> int:
	return ceili(float(count) / float(rack_capacity(weapon)))


func _pylons_needed(items: Array) -> int:
	var racks := 0
	for item in items:
		var d: Dictionary = item
		racks += _racks_for(str(d.get("weapon", "")), int(d.get("count", 0)))
	return racks


func _normalize_items(items: Variant) -> Array:
	var out: Array = []
	if typeof(items) != TYPE_ARRAY:
		return out
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var weapon := str((raw as Dictionary).get("weapon", ""))
		var count := int((raw as Dictionary).get("count", 0))
		if weapon != "" and count > 0:
			out.append({"weapon": weapon, "count": count})
	return out


func _ensure_selection() -> void:
	if not is_unlocked(GameState.selected_aircraft):
		var starters: Array = _config.get("starter_aircraft", [])
		GameState.selected_aircraft = str(starters[0]) if not starters.is_empty() else "f16c"


func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	credits = int(d.get("credits", 0))
	xp = int(d.get("xp", 0))
	missions = int(d.get("missions", 0))
	wins = int(d.get("wins", 0))
	air_kills = int(d.get("air_kills", 0))
	ground_kills = int(d.get("ground_kills", 0))
	for id in d.get("owned_aircraft", []):
		_owned_aircraft.append(str(id))
	for id in d.get("owned_liveries", []):
		_owned_liveries.append(str(id))
	var saved_loadouts: Dictionary = d.get("loadouts", {})
	for id in saved_loadouts:
		_loadouts[str(id)] = _normalize_items(saved_loadouts[id])
	var saved_liveries: Dictionary = d.get("liveries", {})
	for id in saved_liveries:
		_liveries_selected[str(id)] = str(saved_liveries[id])


func save() -> void:
	var data := {
		"version": SAVE_VERSION,
		"credits": credits,
		"xp": xp,
		"missions": missions,
		"wins": wins,
		"air_kills": air_kills,
		"ground_kills": ground_kills,
		"owned_aircraft": _owned_aircraft,
		"owned_liveries": _owned_liveries,
		"loadouts": _loadouts,
		"liveries": _liveries_selected,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Progression: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))


func _save_and_notify() -> void:
	save()
	changed.emit()


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Progression: %s is not a JSON object" % path)
		return {}
	return parsed


func _read_json_array(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		push_error("Progression: %s is not a JSON array" % path)
		return []
	return parsed
