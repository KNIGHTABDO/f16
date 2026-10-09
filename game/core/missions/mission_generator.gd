class_name MissionGenerator
extends RefCounted
## Builds a mission plan from a mode, map, difficulty, option set and seed. The plan is plain data: nothing is spawned
## here, so one seed always gives the same sortie and a restart can reuse it. Positions are world metres (x, z on the
## map). Aircraft y is altitude above sea level; unit and ship y is ground or sea height. Ground and road lookups read
## world coordinates, so generation runs after WorldOrigin.reset() and before any floating-origin shift.

const DATA_PATH := "res://data/modes.json"
const FALLBACK_MODE := "free_flight"
const CRUISE_KMH := 560.0
const START_ALT_M := 4500.0
const ANTI_SHIP_STANDOFF_M := 28000.0
const MAP_EDGE_M := 4000.0
const NO_POINT := Vector2(-1.0e9, -1.0e9)
const STRIKE_KINDS := ["hangar", "ammo_dump", "fuel_tank", "radar", "comms", "bunker", "shelter"]
const ASSET_KINDS := ["radar", "comms", "fuel_tank", "hangar", "ammo_dump"]
const RANGE_KINDS := ["tank", "apc", "truck", "fuel_truck", "bunker", "tower", "ammo_dump"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = GameState.load_json(DATA_PATH)
	return _data


## Plans one mission. `context` may carry "carrier" (Carrier node, already built) for carrier_landing.
static func generate(mode_id: String, map_id: String, difficulty: String, options: Dictionary, seed_value: int,
		context: Dictionary = {}) -> Dictionary:
	var d := data()
	if not d["modes"].has(mode_id):
		mode_id = FALLBACK_MODE
	var mode: Dictionary = d["modes"][mode_id]
	var diff: Dictionary = d["difficulty"].get(difficulty, d["difficulty"]["normal"])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var plan := _base_plan(mode_id, mode, map_id, difficulty, diff, options, seed_value)
	var ctx := {
		"rng": rng,
		"map_id": map_id,
		"mode": mode,
		"spawn": _choice(mode, options, "spawn"),
		"runways": _runways(),
		"carrier": context.get("carrier") as Node3D,
		"enemy": d["enemy"],
	}
	match mode_id:
		"free_flight":
			_plan_free_flight(plan, ctx)
		"instant_action":
			_plan_instant_action(plan, ctx)
		"dogfight":
			_plan_dogfight(plan, ctx)
		"strike":
			_plan_strike(plan, ctx)
		"sead":
			_plan_sead(plan, ctx)
		"anti_ship":
			_plan_anti_ship(plan, ctx)
		"convoy_hunt":
			_plan_convoy_hunt(plan, ctx)
		"base_defense":
			_plan_base_defense(plan, ctx)
		"carrier_landing":
			_plan_carrier_landing(plan, ctx)
		"time_trial":
			_plan_time_trial(plan, ctx)
		"target_range":
			_plan_target_range(plan, ctx)
	_finish_title(plan)
	return plan


# ---------------------------------------------------------------- base plan

static func _base_plan(mode_id: String, mode: Dictionary, map_id: String, difficulty: String, diff: Dictionary,
		options: Dictionary, seed_value: int) -> Dictionary:
	var lives := int(mode["lives"])
	if lives >= 3:
		lives = maxi(1, lives + int(diff["lives_delta"]))
	return {
		"mode": mode_id,
		"map": map_id,
		"title": String(mode["title"]),
		"briefing": String(mode["description"]),
		"note": "",
		"site_name": "",
		"difficulty": difficulty,
		"difficulty_label": String(diff["label"]),
		"seed": seed_value,
		"options": options.duplicate(),
		"skill": float(diff["skill"]),
		"enemy_mult": float(diff["enemies"]),
		"score_mult": float(diff["score"]),
		"lives": lives,
		"time_limit": float(mode["time_limit_s"]),
		"tuning": (mode["tuning"] as Dictionary).duplicate(),
		"practice": String(mode["category"]) == "practice",
		"rtb_enabled": false,
		"surface": "air",
		"start": {},
		"base": Vector3.ZERO,
		"base_points": [],
		"site": Vector3.ZERO,
		"runway": {},
		"units": [],
		"convoys": [],
		"ships": [],
		"aircraft": [],
		"rings": [],
	}


static func _choice(mode: Dictionary, options: Dictionary, option_id: String) -> String:
	if options.has(option_id):
		return String(options[option_id])
	for opt in mode.get("options", []):
		if opt["id"] == option_id:
			return String(opt["default"])
	return ""


static func _finish_title(plan: Dictionary) -> void:
	var mode_title := String(data()["modes"][plan["mode"]]["title"])
	var where := String(plan["site_name"])
	plan["title"] = "%s - %s" % [mode_title, where] if where != "" else mode_title


## Switches a plan to another mode's tuning and title, used when a mode cannot be flown on this map.
static func _adopt(plan: Dictionary, ctx: Dictionary, mode_id: String) -> void:
	var mode: Dictionary = data()["modes"][mode_id]
	plan["mode"] = mode_id
	plan["tuning"] = (mode["tuning"] as Dictionary).duplicate()
	plan["time_limit"] = float(mode["time_limit_s"])
	plan["practice"] = String(mode["category"]) == "practice"
	ctx["mode"] = mode


# ---------------------------------------------------------------- geometry

static func _bearing(from: Vector2, to: Vector2) -> float:
	# Nose vector is (sin h, -cos h) in x/z, so h = atan2(dx, -dz).
	var d := to - from
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


static func _ground(xz: Vector2) -> float:
	return maxf(Ground.world_height_at(xz.x, xz.y), Ground.sea_level)


## World point at height `above` metres over the surface (absolute y).
static func _at(xz: Vector2, above: float) -> Vector3:
	return Vector3(xz.x, _ground(xz) + above, xz.y)


static func _clamp_map(p: Vector2) -> Vector2:
	var half := Ground.size_m * 0.5 - MAP_EDGE_M
	return Vector2(clampf(p.x, -half, half), clampf(p.y, -half, half))


static func _random_point(rng: RandomNumberGenerator, centre: Vector2, radius: float) -> Vector2:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	return _clamp_map(centre + Vector2(cos(a), sin(a)) * r)


static func _find_land(rng: RandomNumberGenerator, centre: Vector2, radius: float) -> Vector2:
	for i in 40:
		var p := _random_point(rng, centre, radius)
		if not Ground.is_water(p.x, p.y):
			return p
	return _clamp_map(centre)


static func _find_sea(rng: RandomNumberGenerator, centre: Vector2, radius: float) -> Vector2:
	for i in 80:
		var p := _random_point(rng, centre, radius)
		if Ground.is_water(p.x, p.y):
			return p
	return NO_POINT


static func _valid(p: Vector2) -> bool:
	return p.x > -1.0e8


static func _pick(rng: RandomNumberGenerator, list: Array) -> Variant:
	return list[rng.randi() % list.size()]


## Number of enemy things for a base count, scaled by difficulty (never below one).
static func _count(plan: Dictionary, base: int) -> int:
	return maxi(1, roundi(float(base) * float(plan["enemy_mult"])))


static func _place_name(xz: Vector2) -> String:
	var best := ""
	var best_d := INF
	for p in Ground.meta.get("places", []):
		var d := Vector2(float(p["x"]), float(p["z"])).distance_squared_to(xz)
		if d < best_d:
			best_d = d
			best = String(p["name"])
	return best


## Looks up a place name or an airbase ICAO code. Returns NO_POINT when neither matches.
static func _named(name: String) -> Vector2:
	for p in Ground.meta.get("places", []):
		if String(p["name"]) == name:
			return Vector2(float(p["x"]), float(p["z"]))
	for ap in Ground.meta.get("airports", []):
		if String(ap.get("icao", "")) == name and not ap.get("runways", []).is_empty():
			var rw: Dictionary = ap["runways"][0]
			return Vector2((float(rw["x1"]) + float(rw["x2"])) * 0.5, (float(rw["z1"]) + float(rw["z2"])) * 0.5)
	return NO_POINT


static func _anchor_points(map_id: String, group: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for n in data()["maps"][map_id]["anchors"].get(group, []):
		var p := _named(String(n))
		if _valid(p):
			out.append(p)
	return out


## A random land point near one of the map's anchors in `group`, or near the map centre if there are none.
static func _anchor_site(ctx: Dictionary, group: String) -> Vector2:
	var rng: RandomNumberGenerator = ctx["rng"]
	var anchors := _anchor_points(String(ctx["map_id"]), group)
	if anchors.is_empty():
		return _find_land(rng, Vector2.ZERO, 40000.0)
	var anchor: Vector2 = _pick(rng, anchors)
	return _find_land(rng, anchor, 2000.0)


static func _spawn_xz() -> Vector2:
	var sp: Dictionary = Ground.meta.get("spawn", {})
	return Vector2(float(sp.get("x", 0.0)), float(sp.get("z", 0.0)))


# ---------------------------------------------------------------- runways and starts

## Every runway in world metres. Friendly bases follow WorldBuilder's rule: GMTT or the first airport.
static func _runways() -> Array:
	var out: Array = []
	var airports: Array = Ground.meta.get("airports", [])
	for i in airports.size():
		var ap: Dictionary = airports[i]
		var friendly := String(ap.get("icao", "")) == "GMTT" or i == 0
		for rw in ap.get("runways", []):
			var x1 := float(rw["x1"])
			var z1 := float(rw["z1"])
			var x2 := float(rw["x2"])
			var z2 := float(rw["z2"])
			var elev := float(rw.get("elevation_m", 0.0))
			if elev <= 0.0:
				elev = Ground.world_height_at((x1 + x2) * 0.5, (z1 + z2) * 0.5)
			var start := Vector3(x1, elev + 0.5, z1)
			var end := Vector3(x2, elev + 0.5, z2)
			out.append({
				"start": start,
				"end": end,
				"mid": (start + end) * 0.5,
				"name": String(rw.get("ref", "RWY")),
				"airbase": String(ap.get("name", "Airbase")),
				"friendly": friendly,
			})
	return out


static func _nearest_runway(runways: Array, xz: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for rw in runways:
		if not rw["friendly"]:
			continue
		var m: Vector3 = rw["mid"]
		var d := Vector2(m.x, m.z).distance_to(xz)
		if d < best_d:
			best_d = d
			best = rw
	return best


static func _friendly_mids(runways: Array) -> Array:
	var out: Array = []
	for rw in runways:
		if rw["friendly"]:
			out.append(rw["mid"])
	return out


static func _base_xz(ctx: Dictionary, xz: Vector2) -> Vector2:
	var rw := _nearest_runway(ctx["runways"], xz)
	if rw.is_empty():
		return _spawn_xz()
	var m: Vector3 = rw["mid"]
	return Vector2(m.x, m.z)


static func _map_spawn_start() -> Dictionary:
	var sp: Dictionary = Ground.meta.get("spawn", {})
	var xz := _spawn_xz()
	return {
		"pos": Vector3(xz.x, float(sp.get("alt_m", 3000.0)), xz.y),
		"heading": float(sp.get("heading_deg", 0.0)),
		"speed_kmh": CRUISE_KMH,
		"ground": false,
	}


static func _runway_start(rw: Dictionary) -> Dictionary:
	var s: Vector3 = rw["start"]
	var e: Vector3 = rw["end"]
	return {
		"pos": s,
		"heading": _bearing(Vector2(s.x, s.z), Vector2(e.x, e.z)),
		"speed_kmh": 0.0,
		"ground": true,
	}


## Air start `standoff_m` short of `site`, on the line from the site to its nearest friendly base, flying at the site.
static func _standoff_start(ctx: Dictionary, site: Vector2, standoff_m: float, alt_m: float) -> Dictionary:
	var dir := _base_xz(ctx, site) - site
	dir = dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	var at := _clamp_map(site + dir * standoff_m)
	return {
		"pos": _at(at, alt_m),
		"heading": _bearing(at, site),
		"speed_kmh": CRUISE_KMH,
		"ground": false,
	}


## Ground start on the friendly runway nearest the site when the player chose a runway spawn, else a standoff start.
static func _start_for(ctx: Dictionary, site: Vector2, standoff_m: float) -> Dictionary:
	if String(ctx["spawn"]) == "runway":
		var rw := _nearest_runway(ctx["runways"], site)
		if not rw.is_empty():
			return _runway_start(rw)
	return _standoff_start(ctx, site, standoff_m, START_ALT_M)


## Start for modes with no site: the map's own spawn, or the first friendly runway when the player chose runway spawn.
static func _main_start(ctx: Dictionary) -> Dictionary:
	if String(ctx["spawn"]) == "runway":
		var rw := _nearest_runway(ctx["runways"], _spawn_xz())
		if not rw.is_empty():
			return _runway_start(rw)
	return _map_spawn_start()


static func _finish_start(plan: Dictionary) -> void:
	var start: Dictionary = plan["start"]
	plan["surface"] = "runway" if start["ground"] else "air"


static func _set_site(plan: Dictionary, site: Vector2) -> void:
	plan["site"] = _at(site, 0.0)
	plan["site_name"] = _place_name(site)


## Friendly runways as the base set, with the nearest one to `xz` as the RTB base.
static func _set_base(plan: Dictionary, ctx: Dictionary, xz: Vector2) -> void:
	var rw := _nearest_runway(ctx["runways"], xz)
	plan["base"] = rw["mid"] if not rw.is_empty() else _at(_spawn_xz(), 0.0)
	plan["base_points"] = _friendly_mids(ctx["runways"])


static func _add_unit(plan: Dictionary, rng: RandomNumberGenerator, kind: String, role: String, xz: Vector2,
		team: int = 1) -> void:
	plan["units"].append({
		"kind": kind,
		"role": role,
		"team": team,
		"pos": _at(xz, 0.0),
		"heading": rng.randf() * 360.0,
	})


## Appends an aircraft entry and returns its index (used for escort links). `pos` is absolute altitude.
static func _add_aircraft(plan: Dictionary, id: String, team: int, pos: Vector3, heading: float, speed: float,
		role: String) -> int:
	plan["aircraft"].append({
		"id": id,
		"team": team,
		"pos": pos,
		"heading": heading,
		"speed_kmh": speed,
		"role": role,
	})
	return plan["aircraft"].size() - 1


static func _sam_kinds(ctx: Dictionary, plan: Dictionary) -> Array:
	return ctx["enemy"]["sam"][plan["difficulty"]]


# ---------------------------------------------------------------- modes

static func _plan_free_flight(plan: Dictionary, ctx: Dictionary) -> void:
	plan["start"] = _main_start(ctx)
	_finish_start(plan)
	_set_base(plan, ctx, _spawn_xz())
	plan["briefing"] = "Free flight. Fly anywhere on the map. Nothing ends the sortie except landing or quitting."


static func _plan_instant_action(plan: Dictionary, ctx: Dictionary) -> void:
	plan["start"] = _main_start(ctx)
	_finish_start(plan)
	_set_base(plan, ctx, _spawn_xz())
	plan["briefing"] = "Waves of enemy fighters arrive from the front. Each wave is bigger. Survive and clear %d waves." % int(plan["tuning"]["win_wave"])


static func _plan_dogfight(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var enemy: Dictionary = ctx["enemy"]
	var size := clampi(int(_choice(ctx["mode"], plan["options"], "size")), 1, 4)
	var centre := _random_point(rng, _spawn_xz(), 25000.0)
	var ang := rng.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var sep := float(t["spawn_km"]) * 1000.0
	var alt := float(t["alt_m"])
	var p0 := centre - dir * sep * 0.5
	var p1 := centre + dir * sep * 0.5
	var heading0 := _bearing(p0, p0 + dir)
	var heading1 := _bearing(p1, p1 - dir)
	if String(ctx["spawn"]) == "runway":
		var rw := _nearest_runway(ctx["runways"], centre)
		if not rw.is_empty():
			plan["start"] = _runway_start(rw)
			_finish_start(plan)
	if plan["surface"] == "air":
		plan["start"] = {"pos": _at(p0, alt), "heading": heading0, "speed_kmh": CRUISE_KMH, "ground": false}
		_finish_start(plan)
	_set_site(plan, centre)
	_set_base(plan, ctx, centre)
	for i in size - 1:
		var wing_xz := p0 - dir * float(i + 1) * 500.0 + perp * (300.0 if i % 2 == 0 else -300.0)
		_add_aircraft(plan, _pick(rng, enemy["wingmen"]), 0, _at(wing_xz, alt), heading0, CRUISE_KMH, "wingman")
	var fighters: Array = enemy["fighters"][plan["difficulty"]]
	for i in _count(plan, size):
		var offset := (float(i) - float(_count(plan, size) - 1) * 0.5) * 900.0
		var xz := p1 + perp * offset + Vector2(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0))
		_add_aircraft(plan, _pick(rng, fighters), 1, _at(xz, alt + rng.randf_range(-300.0, 300.0)), heading1, 520.0, "fighter")
	plan["briefing"] = "%dv%d over the sea and hills. Shoot down every enemy fighter before they shoot you down." % [size, size]


static func _plan_strike(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var site := _anchor_site(ctx, "strike")
	_set_site(plan, site)
	_set_base(plan, ctx, site)
	plan["start"] = _start_for(ctx, site, float(t["standoff_km"]) * 1000.0)
	_finish_start(plan)
	var radius := float(t["site_radius_m"])
	for i in int(t["targets"]):
		_add_unit(plan, rng, _pick(rng, STRIKE_KINDS), "target", _find_land(rng, site, radius))
	var sams: Array = _sam_kinds(ctx, plan)
	for i in _count(plan, int(t["sams"])):
		_add_unit(plan, rng, _pick(rng, sams), "sam", _find_land(rng, site, radius * 1.4))
	plan["rtb_enabled"] = true
	plan["briefing"] = "Strike %d targets around %s. Expect %d SAM sites. Kill the SAMs first if you want the targets." % [
		int(t["targets"]), plan["site_name"], _count(plan, int(t["sams"]))]


static func _plan_sead(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var site := _anchor_site(ctx, "strike")
	_set_site(plan, site)
	_set_base(plan, ctx, site)
	plan["start"] = _start_for(ctx, site, float(t["standoff_km"]) * 1000.0)
	_finish_start(plan)
	var sams: Array = _sam_kinds(ctx, plan)
	for i in _count(plan, int(t["sams"])):
		_add_unit(plan, rng, _pick(rng, sams), "sam", _find_land(rng, site, float(t["site_radius_m"])))
	plan["rtb_enabled"] = true
	plan["briefing"] = "Suppress the air defences around %s. Destroy every SAM site in the area." % plan["site_name"]


static func _plan_anti_ship(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var enemy: Dictionary = ctx["enemy"]
	var centre := NO_POINT
	var course := _anchor_points(String(ctx["map_id"]), "course")
	for anchor in course:
		centre = _find_sea(rng, anchor, 25000.0)
		if _valid(centre):
			break
	if not _valid(centre):
		_adopt(plan, ctx, "strike")
		plan["note"] = "No open sea on this map: strike mission instead."
		_plan_strike(plan, ctx)
		return
	_set_site(plan, centre)
	_set_base(plan, ctx, centre)
	plan["start"] = _standoff_start(ctx, centre, ANTI_SHIP_STANDOFF_M, START_ALT_M)
	_finish_start(plan)
	var kinds: Array[String] = []
	for i in _count(plan, int(t["frigates"])):
		kinds.append("frigate")
	for i in _count(plan, int(t["cargo"])):
		kinds.append("cargo_ship")
	for i in _count(plan, 2):
		kinds.append("patrol_boat")
	for kind in kinds:
		var at := _find_sea(rng, centre, 9000.0)
		if not _valid(at):
			at = centre
		var heading := rng.randf() * 360.0
		var path: Array = []
		for k in 4:
			var a := TAU * float(k) / 4.0
			var wp := at + Vector2(cos(a), sin(a)) * 2500.0
			path.append(wp if Ground.is_water(wp.x, wp.y) else at)
		plan["ships"].append({"kind": kind, "team": 1, "pos": Vector3(at.x, Ground.sea_level, at.y), "heading": heading, "path": path})
	plan["rtb_enabled"] = true
	plan["briefing"] = "Find and sink the ship group at sea near %s. Frigates shoot back." % plan["site_name"]


static func _plan_convoy_hunt(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var enemy: Dictionary = ctx["enemy"]
	var site := _anchor_site(ctx, "course")
	_set_site(plan, site)
	_set_base(plan, ctx, site)
	plan["start"] = _start_for(ctx, site, float(t["standoff_km"]) * 1000.0)
	_finish_start(plan)
	var roads: Array = Ground.meta.get("roads", [])
	var min_len := float(t["min_road_km"]) * 1000.0
	var want := _count(plan, int(t["convoys"]))
	var attempts := 0
	while plan["convoys"].size() < want and attempts < 600 and not roads.is_empty():
		attempts += 1
		var road: Array = roads[rng.randi() % roads.size()]
		if road.size() < 2:
			continue
		var path := _road_path(road, rng.randi() % road.size(), min_len)
		if path.is_empty():
			continue
		var first: Vector2 = path[0]
		if first.distance_to(site) > 60000.0:
			continue
		var kinds: Array = []
		for i in 3 + rng.randi() % 2:
			kinds.append(_pick(rng, enemy["ground"]))
		plan["convoys"].append({"team": 1, "path": path, "kinds": kinds})
	if plan["convoys"].is_empty():
		plan["note"] = "No road long enough near %s: nothing to hunt here." % plan["site_name"]
	plan["rtb_enabled"] = true
	plan["briefing"] = "Enemy convoys are moving on the roads near %s. Stop every vehicle." % plan["site_name"]


## Points from `start_i` along a road until `min_len` metres are covered. Returns [] when the road runs out first.
static func _road_path(road: Array, start_i: int, min_len: float) -> Array:
	var out: Array = []
	var total := 0.0
	var prev := Vector2.ZERO
	for i in range(start_i, road.size()):
		var p := Vector2(float(road[i][0]), float(road[i][1]))
		if not out.is_empty():
			total += prev.distance_to(p)
		out.append(p)
		prev = p
		if total >= min_len:
			return out
	return []


static func _plan_base_defense(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var enemy: Dictionary = ctx["enemy"]
	var base := _base_xz(ctx, _spawn_xz())
	plan["site_name"] = _place_name(base)
	plan["site"] = _at(base, 0.0)
	_set_base(plan, ctx, base)
	plan["start"] = _standoff_start(ctx, base, 8000.0, 2500.0)
	_finish_start(plan)
	for i in int(t["assets"]):
		var xz := _find_land(rng, base, 7000.0)
		for k in 6:
			if xz.distance_to(base) >= 2500.0:
				break
			xz = _find_land(rng, base, 7000.0)
		_add_unit(plan, rng, ASSET_KINDS[i % ASSET_KINDS.size()], "asset", xz, 0)
	var spawn_m := float(t["bomber_spawn_km"]) * 1000.0
	var alt := float(t["bomber_alt_m"])
	var bombers := _count(plan, int(t["bombers"]))
	var bomber_idx: Array[int] = []
	var ang := rng.randf() * TAU
	for i in bombers:
		var a := ang + (float(i) - float(bombers - 1) * 0.5) * 0.12
		var dir := Vector2(cos(a), sin(a))
		var xz := base + dir * spawn_m
		var idx := _add_aircraft(plan, String(enemy["bombers"][0]), 1, _at(xz, alt), _bearing(xz, base), 380.0, "bomber")
		plan["aircraft"][idx]["waypoints"] = [base]
		bomber_idx.append(idx)
	for i in _count(plan, int(t["escorts"])):
		var lead: int = bomber_idx[i % bomber_idx.size()] if not bomber_idx.is_empty() else -1
		var pos := Vector3(0.0, alt, 0.0)
		if lead >= 0:
			pos = plan["aircraft"][lead]["pos"] + Vector3(rng.randf_range(-900.0, 900.0), 300.0, rng.randf_range(-900.0, 900.0))
		var heading := float(plan["aircraft"][lead]["heading"]) if lead >= 0 else 0.0
		var idx := _add_aircraft(plan, _pick(rng, enemy["escorts"]), 1, pos, heading, 520.0, "escort")
		plan["aircraft"][idx]["escort_of"] = lead
	plan["rtb_enabled"] = true
	plan["briefing"] = "Bombers are heading for %s with fighter escort. Destroy every bomber before they drop. Losing more than %d base assets ends the sortie." % [
		plan["site_name"], int(t["max_asset_losses"])]


static func _plan_carrier_landing(plan: Dictionary, ctx: Dictionary) -> void:
	var t: Dictionary = plan["tuning"]
	var carrier := ctx["carrier"] as Node3D
	var approach := float(t["approach_km"]) * 1000.0
	var alt := float(t["alt_m"])
	var speed := float(t["speed_kmh"])
	var at_sea := carrier != null and Ground.is_water(carrier.global_position.x, carrier.global_position.z)
	if at_sea:
		var fwd := -carrier.global_transform.basis.z
		var f := Vector2(fwd.x, fwd.z).normalized()
		var deck := Vector2(carrier.global_position.x, carrier.global_position.z)
		var from := deck - f * approach
		plan["surface"] = "carrier"
		plan["site"] = carrier.global_position
		plan["site_name"] = "Carrier"
		plan["start"] = {"pos": _at(from, alt), "heading": _bearing(from, deck), "speed_kmh": speed, "ground": false}
		plan["base"] = carrier.global_position
		plan["base_points"] = [carrier.global_position]
		return
	var rw := _nearest_runway(ctx["runways"], _spawn_xz())
	if rw.is_empty():
		plan["note"] = "No carrier or runway to land on."
		plan["start"] = _map_spawn_start()
		_finish_start(plan)
		return
	var s: Vector3 = rw["start"]
	var e: Vector3 = rw["end"]
	var dir := Vector2(e.x - s.x, e.z - s.z).normalized()
	var app := Vector2(s.x, s.z) - dir * approach
	plan["surface"] = "runway"
	plan["runway"] = {"start": s, "end": e}
	plan["site"] = rw["mid"]
	plan["site_name"] = String(rw["airbase"])
	plan["base"] = rw["mid"]
	plan["base_points"] = _friendly_mids(ctx["runways"])
	plan["start"] = {"pos": _at(app, alt), "heading": _bearing(Vector2.ZERO, dir), "speed_kmh": speed, "ground": false}
	plan["note"] = "No carrier at sea on this map: landing at %s instead." % rw["airbase"]
	plan["briefing"] = "Land on %s. Come in on the approach and touch down inside the zone." % rw["airbase"]


static func _plan_time_trial(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var long_course := _choice(ctx["mode"], plan["options"], "length") == "long"
	var count := int(t["rings_long"]) if long_course else int(t["rings_short"])
	var leg := float(t["leg_km"]) * 1000.0
	var alt := float(t["ring_alt_m"])
	var site := _anchor_site(ctx, "course")
	_set_site(plan, site)
	_set_base(plan, ctx, site)
	var heading := rng.randf() * TAU
	var xz := site
	var rings: Array = []
	for i in count:
		heading += rng.randf_range(-0.7, 0.7)
		xz = _clamp_map(xz + Vector2(cos(heading), sin(heading)) * leg * rng.randf_range(0.8, 1.2))
		rings.append(_at(xz, alt))
	var first: Vector3 = rings[0]
	var first_dir := (Vector2(first.x, first.z) - site).normalized()
	var start_xz := Vector2(first.x, first.z) - first_dir * 2000.0
	plan["rings"] = rings
	plan["start"] = {"pos": _at(start_xz, alt), "heading": _bearing(start_xz, Vector2(first.x, first.z)), "speed_kmh": CRUISE_KMH, "ground": false}
	_finish_start(plan)
	plan["briefing"] = "Fly the %d-ring course at %s. Pass through each ring inside %d m. Time is score." % [
		count, plan["site_name"], int(t["ring_radius_m"])]


static func _plan_target_range(plan: Dictionary, ctx: Dictionary) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var t: Dictionary = plan["tuning"]
	var site := _anchor_site(ctx, "range")
	_set_site(plan, site)
	_set_base(plan, ctx, site)
	var ang := rng.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var perp := Vector2(-dir.y, dir.x)
	var n := int(t["targets"])
	var spacing := float(t["spacing_m"])
	for i in n:
		var xz := site + perp * (float(i) - float(n - 1) * 0.5) * spacing
		_add_unit(plan, rng, RANGE_KINDS[i % RANGE_KINDS.size()], "range", xz)
	var from := site - dir * 4000.0
	plan["start"] = {"pos": _at(from, float(t["alt_m"])), "heading": _bearing(from, site), "speed_kmh": CRUISE_KMH, "ground": false}
	_finish_start(plan)
	plan["briefing"] = "Practice range near %s. Targets respawn once they are all down." % plan["site_name"]
