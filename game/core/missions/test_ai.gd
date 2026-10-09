class_name TestAI
extends Node3D
## AI pilot test (scenes/test_ai.tscn): 2v2 dogfight (F-16 vs MiG-29), an A-10 strike on a static ground target and a
## wingman formation behind a scripted leader. Runs DURATION simulated seconds, prints a timeline every REPORT_S,
## then a summary (kills, shots, hits, terrain crashes, stalls, formation error, AI cost per physics tick).
## Headless: godot --headless --path game --fixed-fps 60 res://scenes/test_ai.tscn

const TAG := "[ai-test] "
const MAP_ID := "test"
const DURATION := 180.0
const REPORT_S := 10.0
const FIGHT_ALT := 3000.0
const FIGHT_SEPARATION := 9000.0
const STRIKE_ORIGIN := Vector3(20000.0, 0.0, 0.0)
const FORMATION_ORIGIN := Vector3(-20000.0, 0.0, 0.0)

var world: Node3D
var pilots: Array[AIPilot] = []
var stall_ticks: Dictionary = {}
var shots := 0
var hits := 0
var kills := 0
var crashes := 0
var ground_kills := 0
var form_err_sum := 0.0
var form_err_n := 0
var form_leader: Aircraft
var form_wings: Array[AIPilot] = []
var ticks := 0
var strike_target: DummyTarget


func _ready() -> void:
	GameState.difficulty = "ace"
	WorldOrigin.reset()
	if not Ground.load_map(MAP_ID):
		push_error("test_ai: cannot load map " + MAP_ID)
		get_tree().quit(1)
		return
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3500, 4000)
	cam.far = 60000.0
	cam.current = true
	add_child(cam)
	Events.weapon_fired.connect(func(_s: Node3D, _w: String) -> void: shots += 1)
	Events.damaged.connect(func(v: Node3D, _a: float, src: Node) -> void:
		if src is Aircraft and v != src:
			hits += 1)
	Events.aircraft_destroyed.connect(_on_destroyed)
	Events.target_destroyed.connect(func(t: Node3D, _k: Node) -> void:
		if t == strike_target:
			ground_kills += 1)
	_spawn_dogfight()
	_spawn_strike()
	_spawn_formation()
	print(TAG + "started: %d AI aircraft" % pilots.size())


func _make(id: String, team: int, pos: Vector3, heading: float, role: String, skill: float) -> AIPilot:
	var ac := Aircraft.create(id, team, false)
	if ac == null:
		push_error("test_ai: cannot create " + id)
		return null
	world.add_child(ac)
	ac.spawn_in_air(pos, heading, 700.0)
	var p := AIPilot.new()
	p.name = "AIPilot"
	ac.add_child(p)
	p.setup(ac, skill, role)
	pilots.append(p)
	stall_ticks[ac] = 0
	return p


func _spawn_dogfight() -> void:
	var half := FIGHT_SEPARATION * 0.5
	var red := FlightGroup.new()
	var blue := FlightGroup.new()
	add_child(red)
	add_child(blue)
	var b1 := _make("f16c", 0, Vector3(-300, FIGHT_ALT, half), 0.0, "fighter", 1.0)
	var b2 := _make("f16c", 0, Vector3(300, FIGHT_ALT + 100.0, half + 400.0), 0.0, "wingman", 1.0)
	var r1 := _make("mig29", 1, Vector3(300, FIGHT_ALT, -half), 180.0, "fighter", 1.0)
	var r2 := _make("mig29", 1, Vector3(-300, FIGHT_ALT + 100.0, -half - 400.0), 180.0, "wingman", 1.0)
	blue.setup(b1.aircraft)
	blue.add_member(b2)
	b2.order("engage_free")
	red.setup(r1.aircraft)
	red.add_member(r2)
	r2.order("engage_free")


func _spawn_strike() -> void:
	var gx := STRIKE_ORIGIN.x
	var gz := STRIKE_ORIGIN.z - 9000.0
	strike_target = DummyTarget.create("vehicle", 1, 300.0, Vector3(12, 4, 12))
	world.add_child(strike_target)
	strike_target.position = Vector3(gx, Ground.surface_at(gx, gz) + 2.0, gz)
	var p := _make("a10c", 0, Vector3(gx, 2000.0, STRIKE_ORIGIN.z + 4000.0), 0.0, "attacker", 0.8)
	if p != null:
		p.set_strike([strike_target])


func _spawn_formation() -> void:
	var lead := _make("f16c", 0, Vector3(FORMATION_ORIGIN.x, 2500.0, 3000.0), 0.0, "fighter", 0.7)
	var pts: Array[Vector3] = [Vector3(FORMATION_ORIGIN.x, 0, -6000), Vector3(FORMATION_ORIGIN.x - 6000, 0, -2000),
			Vector3(FORMATION_ORIGIN.x, 0, 3000), Vector3(FORMATION_ORIGIN.x + 6000, 0, -2000)]
	lead.set_patrol(pts, 2500.0)
	form_leader = lead.aircraft
	var group := FlightGroup.new()
	add_child(group)
	group.setup(form_leader)
	for i in 2:
		var w := _make("f16c", 0, Vector3(FORMATION_ORIGIN.x + (150.0 if i == 0 else -150.0), 2500.0, 3200.0 + 100.0 * i), 0.0, "wingman", 0.7)
		group.add_member(w)
		w.order("rejoin")
		form_wings.append(w)


func _on_destroyed(a: Node3D, killer: Node) -> void:
	if killer == null:
		crashes += 1
		print(TAG + "t=%.1f CRASH %s" % [ticks / 60.0, a.name])
	else:
		kills += 1
		print(TAG + "t=%.1f KILL %s by %s" % [ticks / 60.0, a.name, killer.name])


func _physics_process(_delta: float) -> void:
	ticks += 1
	for p in pilots:
		if p.aircraft != null and p.aircraft.alive and p.aircraft.is_stalling():
			stall_ticks[p.aircraft] += 1
	if form_leader != null and form_leader.alive and ticks % 30 == 0:
		for w in form_wings:
			if w.aircraft.alive:
				var off := AITactics.slot_offset(w.formation_slot, maxf(45.0, w.aircraft.data.wing_span * 2.5))
				var lf := AITactics.flat(form_leader.velocity)
				var right := Vector3(-lf.z, 0.0, lf.x)
				var slot := form_leader.position + right * off.x + Vector3.UP * off.y - lf * off.z
				if ticks > 1800:
					form_err_sum += w.aircraft.position.distance_to(slot)
					form_err_n += 1
	if ticks % int(REPORT_S * 60.0) == 0:
		var line := TAG + "t=%3.0f " % (ticks / 60.0)
		for p in pilots:
			var a := p.aircraft
			line += "%s:%s%s " % [a.name, p.get_state() if a.alive else "dead", "!" if p.is_avoiding_terrain() else ""]
		print(line)
	if ticks >= int(DURATION * 60.0):
		_finish()


func _finish() -> void:
	var stalls := 0
	for k in stall_ticks:
		stalls += int(stall_ticks[k])
	var cost_us := float(AIPilot.debug_cost_usec) / maxf(AIPilot.debug_ticks, 1.0) * pilots.size()
	print(TAG + "SUMMARY kills=%d shots=%d hits=%d terrain_crashes=%d ground_target_killed=%d stall_ticks=%d" % [
			kills, shots, hits, crashes, ground_kills, stalls])
	print(TAG + "formation mean error %.1f m (%d samples)" % [form_err_sum / maxf(form_err_n, 1), form_err_n])
	print(TAG + "AI cost %.0f us per physics tick for %d pilots (%.1f us per pilot)" % [
			cost_us, pilots.size(), cost_us / maxf(pilots.size(), 1)])
	get_tree().quit(1 if crashes > 0 else 0)
