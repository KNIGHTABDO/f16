class_name MissionSpawner
extends RefCounted
## Creates the nodes a mission plan describes and parents them under the level's World node. Plan positions are world
## metres and are converted to local space here, at spawn time, so a spawn after a floating-origin shift still lands in
## the right place. Every node gets a "role" meta tag for the mission to read.
## AI pilots are optional. ai_pilot.gd is loaded by path and attached as a child of its aircraft (so it is freed with it).
## Without it, enemy aircraft fly straight and hold their heading.

const AI_PATH := "res://core/controls/ai_pilot.gd"
const AI_ROLE := {"escort": "fighter"}


static func spawn_all(world: Node3D, plan: Dictionary) -> Dictionary:
	return {
		"units": spawn_units(world, plan),
		"convoys": spawn_convoys(world, plan),
		"ships": spawn_ships(world, plan),
		"aircraft": spawn_aircraft(world, plan),
	}


static func spawn_units(world: Node3D, plan: Dictionary) -> Array:
	var out: Array = []
	for u in plan["units"]:
		var node := UnitFactory.spawn(String(u["kind"]), int(u["team"]), WorldOrigin.to_local(u["pos"]), float(u["heading"]))
		world.add_child(node)
		node.set_meta("role", String(u["role"]))
		out.append(node)
	return out


static func spawn_convoys(world: Node3D, plan: Dictionary) -> Array:
	var out: Array = []
	for c in plan["convoys"]:
		var convoy := Convoy.new()
		var kinds: Array[String] = []
		for k in c["kinds"]:
			kinds.append(String(k))
		world.add_child(convoy)
		convoy.setup_convoy(int(c["team"]), _local_xz_path(c["path"]), kinds)
		convoy.set_meta("role", "convoy")
		out.append(convoy)
	return out


static func spawn_ships(world: Node3D, plan: Dictionary) -> Array:
	var out: Array = []
	for s in plan["ships"]:
		var ship := UnitFactory.spawn(String(s["kind"]), int(s["team"]), WorldOrigin.to_local(s["pos"]), float(s["heading"])) as Ship
		if ship == null:
			continue
		world.add_child(ship)
		ship.set_waypoints(_local_xz_path(s["path"]), true)
		ship.set_meta("role", "ship")
		out.append(ship)
	return out


## Spawns every aircraft in the plan. The result is index-aligned with plan["aircraft"]; a failed id gives null.
static func spawn_aircraft(world: Node3D, plan: Dictionary) -> Array:
	var nodes: Array = []
	for entry in plan["aircraft"]:
		nodes.append(spawn_aircraft_entry(world, entry, float(plan["skill"]), nodes))
	return nodes


## One aircraft from a plan entry. Also used for mid-mission waves. `nodes` is the list of aircraft already spawned
## for the same plan, which escort links index into.
static func spawn_aircraft_entry(world: Node3D, entry: Dictionary, skill: float, nodes: Array = []) -> Aircraft:
	var ac := Aircraft.create(String(entry["id"]), int(entry["team"]), false)
	if ac == null:
		push_warning("MissionSpawner: unknown aircraft '%s'" % String(entry["id"]))
		return null
	world.add_child(ac)
	ac.spawn_in_air(WorldOrigin.to_local(entry["pos"]), float(entry["heading"]), float(entry["speed_kmh"]))
	ac.set_meta("role", String(entry["role"]))
	_attach_ai(ac, entry, skill, nodes)
	return ac


static func _local_xz_path(points: Array) -> Array:
	var out: Array = []
	for p in points:
		var local := WorldOrigin.to_local(Vector3(p.x, 0.0, p.y))
		out.append(Vector2(local.x, local.z))
	return out


static func _attach_ai(ac: Aircraft, entry: Dictionary, skill: float, nodes: Array) -> void:
	if not ResourceLoader.exists(AI_PATH):
		return
	var script := load(AI_PATH) as Script
	if script == null:
		return
	var pilot: Node = script.new()
	ac.add_child(pilot)
	var role := String(entry["role"])
	if pilot.has_method("setup"):
		pilot.call("setup", ac, skill, AI_ROLE.get(role, role))
	if entry.has("waypoints") and pilot.has_method("set_patrol"):
		var alt: float = entry["pos"].y
		var pts: Array = []
		for p in entry["waypoints"]:
			pts.append(WorldOrigin.to_local(Vector3(p.x, alt, p.y)))
		pilot.call("set_patrol", pts, alt)
	if entry.has("escort_of") and pilot.has_method("set_escort"):
		var lead := int(entry["escort_of"])
		if lead >= 0 and lead < nodes.size() and nodes[lead] != null:
			pilot.call("set_escort", nodes[lead])
