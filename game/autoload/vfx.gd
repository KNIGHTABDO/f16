extends Node
## Visual effects service (autoload "Vfx"). All positions are LOCAL scene coordinates: the level's World node
## (identity under Level). Spawned effects are children of World, are in group "floating" and give themselves
## back to their pools when finished. Caps scale with Settings.graphics_preset (VfxAssets.amount_scale), so
## low uses fewer simultaneous effects. Default caps (balanced / high): explosions 2/3, trails 4/6, wrecks 8/12,
## flares 4/6, muzzle flashes 3/4. Lights: 4 pooled OmniLight3D, none on low.

const MAX_EXPLOSIONS := 3
const MAX_TRAILS := 6
const MAX_WRECKS := 12
const MAX_FLARES := 6
const MAX_MUZZLES := 4
const CAP_MIN := 2
const LIGHT_COUNT := 4
const LIGHT_TIME := 0.15
const MUZZLE_TIME := 0.07
const MUZZLE_SIZE := 1.6  # metres of star quad per unit of size
const IMPACT_KINDS := ["ground", "water", "metal"]
## Particles emitted per impact call (before the preset scale), and launch speed range (m/s).
const IMPACT_COUNT := {"ground": 10, "water": 14, "metal": 8}
const IMPACT_SPEED := {"ground": Vector2(3.0, 9.0), "water": Vector2(4.0, 11.0), "metal": Vector2(6.0, 16.0)}

var _world: Node3D
var _lights: Array[OmniLight3D] = []
var _light_age := PackedFloat32Array()
var _light_peak := PackedFloat32Array()
var _impact_emitters := {}

var _explosions: FxPool
var _trails: FxPool
var _flares: FxPool
var _wrecks: FxPool
var _muzzles: FxPool

var _active_explosions: Array[ExplosionFx] = []
var _live_trails: Array[TrailFx] = []
var _active_flares: Array[FlareFx] = []
var _active_wrecks: Array[WreckFx] = []
var _active_muzzles: Array[Dictionary] = []


func _ready() -> void:
	_explosions = FxPool.new(func() -> Node3D: return ExplosionFx.new())
	_trails = FxPool.new(func() -> Node3D: return TrailFx.new())
	_flares = FxPool.new(func() -> Node3D: return FlareFx.new())
	_wrecks = FxPool.new(func() -> Node3D: return WreckFx.new())
	_muzzles = FxPool.new(func() -> Node3D: return _make_muzzle())
	if not Events.explosion.is_connected(_on_events_explosion):
		Events.explosion.connect(_on_events_explosion)


func _process(delta: float) -> void:
	for i in _lights.size():
		if _light_age[i] >= LIGHT_TIME or not is_instance_valid(_lights[i]):
			continue
		_light_age[i] = minf(_light_age[i] + delta, LIGHT_TIME)
		var k := 1.0 - _light_age[i] / LIGHT_TIME
		_lights[i].light_energy = _light_peak[i] * k * k
		if _light_age[i] >= LIGHT_TIME:
			_lights[i].visible = false

	for i in range(_active_muzzles.size() - 1, -1, -1):
		var e: Dictionary = _active_muzzles[i]
		var node := e["node"] as MeshInstance3D
		if not is_instance_valid(node):
			_active_muzzles.remove_at(i)
			continue
		e["age"] = float(e["age"]) + delta
		var t: float = clampf(float(e["age"]) / MUZZLE_TIME, 0.0, 1.0)
		if t >= 1.0:
			_muzzles.give(node)
			_active_muzzles.remove_at(i)
			continue
		node.transparency = t
		node.scale = Vector3.ONE * float(e["size"]) * (1.0 + 0.6 * t)

	_prune()


func _on_events_explosion(world_local_pos: Vector3, size: float) -> void:
	explosion(world_local_pos, size, _classify(world_local_pos))


## Surface type for an explosion reported without a kind.
func _classify(p: Vector3) -> String:
	if not Ground.is_loaded():
		return "ground"
	if Ground.is_water(p.x, p.z):
		return "water"
	if p.y > Ground.surface_at(p.x, p.z) + 25.0:
		return "air"
	return "ground"


## kind: "air" (mid-air fireball), "ground" (dirt + fire), "water" (splash column), "aircraft" (big fireball + debris)
func explosion(_local_pos: Vector3, _size: float = 1.0, _kind: String = "ground") -> void:
	var world := _world_node()
	if world == null:
		return
	_prune()
	while _active_explosions.size() >= _cap(MAX_EXPLOSIONS):
		var old: ExplosionFx = _active_explosions.pop_front()
		if is_instance_valid(old):
			old.cut_short()
	var fx := _explosions.take() as ExplosionFx
	world.add_child(fx)
	fx.position = _local_pos
	fx.add_to_group("floating")
	fx.reset_physics_interpolation()
	fx.configure(_explosions, _size, _kind)
	_active_explosions.append(fx)

	var k := pow(clampf(_size, 0.1, 6.0), 0.6)
	var col := Color(0.8, 0.92, 1.0) if _kind == "water" else Color(1.0, 0.7, 0.4)
	_light_flash(_local_pos + Vector3.UP * 3.0, col, clampf(9.0 * k, 3.0, 16.0), clampf(45.0 * k, 20.0, 110.0))


## Bullet/shell impact. kind: "ground", "water", "metal". A burst of particles from a shared emitter per kind.
func impact(_local_pos: Vector3, _normal: Vector3, _kind: String = "ground") -> void:
	var world := _world_node()
	if world == null:
		return
	var kind := _kind if _impact_emitters.has(_kind) else "ground"
	var em := _impact_emitters[kind] as GPUParticles3D
	if em == null or not is_instance_valid(em):
		return
	var n := _normal.normalized() if _normal.length_squared() > 1e-6 else Vector3.UP
	var speed_range: Vector2 = IMPACT_SPEED[kind]
	var count := VfxAssets.scaled(int(IMPACT_COUNT[kind]))
	var origin := em.to_local(_local_pos)
	for i in count:
		var jitter := Vector3(randf_range(-0.7, 0.7), randf_range(-0.7, 0.7), randf_range(-0.7, 0.7))
		var dir := (n + jitter).normalized()
		var speed := randf_range(speed_range.x, speed_range.y)
		em.emit_particle(Transform3D(Basis.IDENTITY, origin), dir * speed, Color.WHITE, Color(),
				GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY)


## Muzzle flash attached to `parent` at `local_offset` for one shot burst frame.
func muzzle_flash(_parent: Node3D, _local_offset: Vector3, _size: float = 1.0) -> void:
	if _parent == null or not is_instance_valid(_parent) or not _parent.is_inside_tree():
		return
	_prune()
	if _active_muzzles.size() >= _cap(MAX_MUZZLES):
		return
	var m := _muzzles.take() as MeshInstance3D
	_parent.add_child(m)
	m.position = _local_offset
	m.scale = Vector3.ONE * _size * MUZZLE_SIZE
	m.transparency = 0.0
	m.visible = true
	_active_muzzles.append({"node": m, "age": 0.0, "size": _size * MUZZLE_SIZE})
	var wp: Vector3 = _parent.global_transform * _local_offset
	_light_flash(wp, Color(1.0, 0.8, 0.5), 3.0 * clampf(_size, 0.2, 3.0), 12.0)


## Persistent smoke/fire trail following `parent` (missile motor, burning aircraft, damaged engine).
## kind: "missile", "rocket", "fire", "smoke_light", "smoke_heavy". Returns the effect node; call stop_trail() to let it fade.
func attach_trail(_parent: Node3D, _kind: String = "missile", _local_offset := Vector3.ZERO) -> Node3D:
	var t := _spawn_trail(_parent, _kind, _local_offset)
	if t == null:
		return null
	_prune()
	while _live_trails.size() >= _cap(MAX_TRAILS):
		var old: TrailFx = _live_trails.pop_front()
		if is_instance_valid(old):
			old.stop()
	_live_trails.append(t)
	return t


func stop_trail(_trail: Node3D) -> void:
	var t := _trail as TrailFx
	if t == null or not is_instance_valid(t):
		return
	t.stop()
	_live_trails.erase(t)


## Flare burning ball with smoke trail; returns the node (moves itself with given velocity + gravity + drag, lives `life` s).
## The node is pooled: keep the reference only until it burns out.
func flare(_local_pos: Vector3, _velocity: Vector3, _life: float = 4.0) -> Node3D:
	var world := _world_node()
	if world == null:
		return null
	_prune()
	while _active_flares.size() >= _cap(MAX_FLARES):
		var old: FlareFx = _active_flares.pop_front()
		if is_instance_valid(old):
			old.burn_out()
	var f := _flares.take() as FlareFx
	world.add_child(f)
	f.start(_flares, _local_pos, _velocity, _life)
	var trail := _spawn_trail(f, "flare", Vector3.ZERO)
	f.set_trail(trail)
	_active_flares.append(f)
	return f


## Lingering column of smoke at a destroyed target.
func wreck_smoke(_local_pos: Vector3, _size: float = 1.0, _duration: float = 90.0) -> void:
	var world := _world_node()
	if world == null:
		return
	_prune()
	var cap := _cap(MAX_WRECKS)
	var live := 0
	for w in _active_wrecks:
		if not w.is_cut():
			live += 1
	for w in _active_wrecks:
		if live < cap:
			break
		if not w.is_cut():
			w.cut()
			live -= 1
	var fx := _wrecks.take() as WreckFx
	world.add_child(fx)
	fx.position = _local_pos
	fx.configure(_wrecks, _size, _duration)
	_active_wrecks.append(fx)


## Spawns a trail under World. The caller must have put `follow` in the tree already.
func _spawn_trail(follow: Node3D, kind: String, offset: Vector3) -> TrailFx:
	var world := _world_node()
	if world == null or follow == null or not is_instance_valid(follow) or not follow.is_inside_tree():
		return null
	var t := _trails.take() as TrailFx
	world.add_child(t)
	t.setup(_trails, follow, kind, offset)
	return t


func _make_muzzle() -> Node3D:
	var m := MeshInstance3D.new()
	m.mesh = VfxAssets.quad()
	m.material_override = VfxAssets.sprite_material("muzzle_star.png", true, BaseMaterial3D.BILLBOARD_ENABLED)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	return m


## Pool cap for a base count, scaled by Settings.graphics_preset.
func _cap(base: int) -> int:
	return maxi(CAP_MIN, roundi(float(base) * VfxAssets.amount_scale()))


## Takes the least recently flashed light (or a free one) for a short flash. Skipped on the low preset.
func _light_flash(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	# The lights belong to the World of the current level; looking it up rebuilds them after a scene change.
	if _world_node() == null or _lights.is_empty() or VfxAssets.amount_scale() < 0.5:
		return
	var idx := 0
	for i in _lights.size():
		if _light_age[i] > _light_age[idx]:
			idx = i
	var l := _lights[idx]
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.visible = true
	_light_age[idx] = 0.0
	_light_peak[idx] = energy


## Returns the World node that effects are added to (cached; looked up again if the scene changed).
func _world_node() -> Node3D:
	if _world == null or not is_instance_valid(_world) or not _world.is_inside_tree():
		_world = null
		var scene := get_tree().current_scene
		if scene != null:
			_world = scene.find_child("World", true, false) as Node3D
		if _world == null:
			return null
		_build_world_nodes()
	return _world


## Lights and impact emitters live under World (so they move with WorldOrigin shifts).
func _build_world_nodes() -> void:
	_lights.clear()
	_light_age = PackedFloat32Array()
	_light_peak = PackedFloat32Array()
	for i in LIGHT_COUNT:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		_world.add_child(l)
		l.add_to_group("floating")
		_lights.append(l)
		_light_age.append(LIGHT_TIME)
		_light_peak.append(0.0)

	_impact_emitters.clear()
	for kind in IMPACT_KINDS:
		var em := _make_impact_emitter(kind)
		_world.add_child(em)
		em.add_to_group("floating")
		_impact_emitters[kind] = em


## One emitter per impact kind. amount_ratio 0 means no continuous emission; bursts come from emit_particle().
func _make_impact_emitter(kind: String) -> GPUParticles3D:
	var mat: StandardMaterial3D
	var lifetime := 1.0
	var pm_color := Color.WHITE
	var gravity := Vector3(0.0, -9.8, 0.0)
	var scale_range := Vector2(0.5, 1.0)
	match kind:
		"water":
			mat = VfxAssets.sprite_material("puff.png", false, BaseMaterial3D.BILLBOARD_PARTICLES)
			lifetime = 1.2
			pm_color = Color(0.85, 0.93, 1.0, 0.9)
			scale_range = Vector2(0.4, 0.9)
		"metal":
			mat = VfxAssets.sprite_material("spark.png", true, BaseMaterial3D.BILLBOARD_PARTICLES)
			lifetime = 0.4
			pm_color = Color(1.0, 0.85, 0.5, 1.0)
			scale_range = Vector2(0.25, 0.5)
		_:
			mat = VfxAssets.sprite_material("puff.png", false, BaseMaterial3D.BILLBOARD_PARTICLES)
			lifetime = 1.0
			pm_color = Color(0.5, 0.43, 0.32, 0.85)
			gravity = Vector3(0.0, -5.0, 0.0)
			scale_range = Vector2(0.5, 1.1)
	var em := VfxAssets.make_particles(120 if kind != "metal" else 96, lifetime, VfxAssets.quad(), mat)
	em.emitting = true
	em.amount_ratio = 0.0
	em.one_shot = false
	em.visibility_aabb = AABB(Vector3(-4000.0, -4000.0, -4000.0), Vector3(8000.0, 8000.0, 8000.0))
	var pm := em.process_material as ParticleProcessMaterial
	pm.gravity = gravity
	pm.damping_min = 0.6
	pm.damping_max = 1.5
	pm.color = pm_color
	pm.scale_min = scale_range.x
	pm.scale_max = scale_range.y
	pm.scale_curve = VfxAssets.curve("impact_" + kind, PackedVector2Array([Vector2(0, 0.6), Vector2(1, 1.0)]))
	pm.color_ramp = VfxAssets.ramp("impact_" + kind,
			PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)]),
			PackedFloat32Array([0.0, 0.5, 1.0]))
	return em


## Drops finished effects from the active lists (their nodes are already back in their pools).
func _prune() -> void:
	for i in range(_active_explosions.size() - 1, -1, -1):
		var e = _active_explosions[i]
		if not is_instance_valid(e) or e.is_finished():
			if is_instance_valid(e):
				e.remove_from_group("floating")
			_active_explosions.remove_at(i)
	for i in range(_live_trails.size() - 1, -1, -1):
		var t = _live_trails[i]
		if not is_instance_valid(t) or not t.is_emitting():
			_live_trails.remove_at(i)
	for i in range(_active_flares.size() - 1, -1, -1):
		var f = _active_flares[i]
		if not is_instance_valid(f) or not f.is_active():
			_active_flares.remove_at(i)
	for i in range(_active_wrecks.size() - 1, -1, -1):
		var w = _active_wrecks[i]
		if not is_instance_valid(w) or w.is_finished():
			_active_wrecks.remove_at(i)
