class_name ExplosionFx
extends Node3D
## One pooled explosion. Vfx.explosion() takes it from an FxPool, calls configure() and adds it to World.
## Parts (built once, reused by every pool cycle; every part is one draw call):
##   fireball  billboard shader quad (hot core -> body -> rolling smoke)
##   ring      flat shockwave shader on the ground/water
##   smoke     rising column of flipbook smoke, lingers ~9 s
##   sparks    additive embers with gravity
##   dust      ground dust, or white spray column over water
##   debris    lit chunks with ribbon smoke trails (aircraft and large ground explosions)
## Emitters use local coordinates: this node is in group "floating", so WorldOrigin shifts move it and its
## particles together. Positions are world-local (Godot scene) coordinates set by the caller.

const FIREBALL_DIAMETER := 26.0  # metres at size 1 (500 lb bomb)
const FIREBALL_LIFE_MAX := 2.2
const RING_DIAMETER := 28.0
const SMOKE_LIFE := 9.0
const SPARK_LIFE := 0.9
const DUST_LIFE := 2.4
const SPRAY_LIFE := 2.8
const DEBRIS_LIFE := 3.2
const DEBRIS_TRAIL := 0.55
## Particle counts at size 1 before the preset multiplier (see VfxAssets.scaled).
const SMOKE_BASE := 12.0
const SMOKE_PER_K := 10.0
const SPARK_BASE := 22.0
const SPARK_PER_K := 16.0
const DUST_BASE := 26.0
const DUST_PER_K := 18.0
const DEBRIS_BASE := 3.0
const DEBRIS_PER_K := 4.0
const LIFE_PAD := 0.5

const COL_FIRE_HOT := Color(1.0, 0.93, 0.66)
const COL_FIRE_MID := Color(1.0, 0.46, 0.13)
const COL_SMOKE := Color(0.13, 0.12, 0.11)
const COL_RING_LAND := Color(1.0, 0.84, 0.6)
const COL_RING_WATER := Color(0.85, 0.95, 1.0)

var _pool: FxPool
var _kind := "ground"
var _size := 1.0
var _age := 0.0
var _total := 1.0
var _fire_life := 1.4
var _fire_diam := 26.0
var _ring_life := 1.0

var _built := false
var _fire: MeshInstance3D
var _fire_mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _smoke: GPUParticles3D
var _sparks: GPUParticles3D
var _dust: GPUParticles3D
var _debris: GPUParticles3D


func _ready() -> void:
	if not _built:
		_build()


func _build() -> void:
	_built = true
	_fire = MeshInstance3D.new()
	_fire.mesh = VfxAssets.quad()
	_fire_mat = VfxAssets.shader_material("fireball.gdshader")
	_fire.material_override = _fire_mat
	_fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fire)

	_ring = MeshInstance3D.new()
	_ring.mesh = VfxAssets.quad()
	_ring.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_ring.position = Vector3(0.0, 0.35, 0.0)
	_ring_mat = VfxAssets.shader_material("shockwave.gdshader")
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_smoke = VfxAssets.make_particles(1, SMOKE_LIFE, VfxAssets.quad(),
			VfxAssets.sprite_material("smoke_flipbook.png", false, BaseMaterial3D.BILLBOARD_PARTICLES, 4, 4))
	add_child(_smoke)

	_sparks = VfxAssets.make_particles(1, SPARK_LIFE, VfxAssets.quad(),
			VfxAssets.sprite_material("spark.png", true, BaseMaterial3D.BILLBOARD_PARTICLES))
	add_child(_sparks)

	_dust = VfxAssets.make_particles(1, DUST_LIFE, VfxAssets.quad(),
			VfxAssets.sprite_material("puff.png", false, BaseMaterial3D.BILLBOARD_PARTICLES))
	add_child(_dust)

	_debris = VfxAssets.make_particles(1, DEBRIS_LIFE, null, null)
	_debris.trail_enabled = true
	_debris.trail_lifetime = DEBRIS_TRAIL
	var ribbon := RibbonTrailMesh.new()
	ribbon.size = 0.35
	ribbon.sections = 4
	ribbon.section_length = 0.6
	ribbon.material = VfxAssets.plain_material(false)
	# draw_passes must be raised before pass 2 can be set. Pass 1 = trail ribbon, pass 2 = ember chunk.
	_debris.draw_passes = 2
	_debris.draw_pass_1 = ribbon
	var chunk := VfxAssets.chunk_box().duplicate() as BoxMesh
	chunk.material = VfxAssets.chunk_material(true)
	_debris.draw_pass_2 = chunk
	add_child(_debris)


## Sets size and kind and starts every part. size: 1 = 500 lb bomb, 0.3 = missile airburst, 3 = ammo dump.
## kind: "air", "ground", "water", "aircraft".
func configure(pool: FxPool, size: float, kind: String) -> void:
	if not _built:
		_build()
	_pool = pool
	_kind = kind
	_size = clampf(size, 0.1, 6.0)
	_age = 0.0
	var k := pow(_size, 0.75)
	var aircraft := kind == "aircraft"
	var water := kind == "water"
	var ground := kind == "ground" or aircraft
	var air := kind == "air"

	# Fireball: visible everywhere except over water.
	_fire.visible = not water
	_fire_diam = FIREBALL_DIAMETER * k * (1.25 if aircraft else 1.0)
	_fire_life = clampf(1.0 + 0.35 * _size, 1.0, FIREBALL_LIFE_MAX)
	_fire.scale = Vector3.ONE * _fire_diam
	_fire_mat.set_shader_parameter("seed", randf() * 10.0)
	_fire_mat.set_shader_parameter("hot_color", COL_FIRE_HOT)
	_fire_mat.set_shader_parameter("mid_color", COL_FIRE_MID)
	_fire_mat.set_shader_parameter("smoke_color", COL_SMOKE)
	_fire_mat.set_shader_parameter("intensity", 1.0)
	_fire_mat.set_shader_parameter("progress", 0.0)

	# Shockwave ring (ground and water only).
	_ring.visible = ground or water
	var ring_col := COL_RING_WATER if water else COL_RING_LAND
	_ring_life = clampf(0.7 + 0.2 * k, 0.7, 1.4)
	_ring.scale = Vector3(RING_DIAMETER * k * (1.2 if aircraft else 1.0), 1.0, RING_DIAMETER * k * (1.2 if aircraft else 1.0))
	_ring_mat.set_shader_parameter("ring_color", Color(ring_col.r, ring_col.g, ring_col.b, 0.9))
	_ring_mat.set_shader_parameter("disc", 0.0 if water else (0.5 if ground else 0.0))
	_ring_mat.set_shader_parameter("progress", 0.0)

	_setup_smoke(k, water, air)
	_setup_sparks(k, water, air)
	_setup_dust(k, water, ground)
	_setup_debris(k, aircraft, ground)

	_total = maxf(_smoke.lifetime + 0.2, DEBRIS_LIFE) + LIFE_PAD
	if water:
		_total = maxf(_total, SPRAY_LIFE + 1.0)
	_total = maxf(_total, _fire_life + 0.1)
	_total = minf(_total, 12.0)

	var reach := maxf(_fire_diam, _ring.scale.x) * 0.6 + 14.0 * k
	var height := 36.0 * k
	_smoke.visibility_aabb = VfxAssets.big_aabb(reach, height)
	_sparks.visibility_aabb = VfxAssets.big_aabb(reach, height)
	_dust.visibility_aabb = VfxAssets.big_aabb(reach, height)
	_debris.visibility_aabb = VfxAssets.big_aabb(reach, height)

	for emitter in [_smoke, _sparks, _dust, _debris]:
		(emitter as GPUParticles3D).restart()
	visible = true


func _setup_smoke(k: float, water: bool, air: bool) -> void:
	_smoke.visible = true
	var amount := VfxAssets.scaled(int(roundf(SMOKE_BASE + SMOKE_PER_K * k)))
	if water:
		amount = VfxAssets.scaled(int(roundf(6.0 + 4.0 * k)))
	if air:
		amount = VfxAssets.scaled(int(roundf(8.0 + 6.0 * k)))
	_smoke.amount = amount
	_smoke.lifetime = SMOKE_LIFE * (0.9 + 0.1 * minf(k, 2.0))
	var pm := _smoke.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.0 * k
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = 3.0 * sqrt(k)
	pm.initial_velocity_max = 6.5 * sqrt(k)
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.scale_min = 1.8 * sqrt(k)
	pm.scale_max = 3.0 * sqrt(k)
	pm.scale_curve = VfxAssets.curve("smoke_scale", PackedVector2Array([Vector2(0, 0.35), Vector2(0.35, 0.8), Vector2(1, 1.0)]))
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	var ramp_col := Color(0.92, 0.94, 0.96) if water else Color(0.2, 0.18, 0.16)
	pm.color_ramp = VfxAssets.ramp("smoke_" + ("water" if water else "land"),
			PackedColorArray([Color(ramp_col.r, ramp_col.g, ramp_col.b, 0.0), Color(ramp_col.r, ramp_col.g, ramp_col.b, 0.85), Color(ramp_col.r, ramp_col.g, ramp_col.b, 0.5), Color(ramp_col.r, ramp_col.g, ramp_col.b, 0.0)]),
			PackedFloat32Array([0.0, 0.15, 0.6, 1.0]))
	_smoke.emitting = true


func _setup_sparks(k: float, water: bool, air: bool) -> void:
	_sparks.visible = not water
	_sparks.amount = VfxAssets.scaled(int(roundf(SPARK_BASE + SPARK_PER_K * k)))
	_sparks.lifetime = SPARK_LIFE * (0.85 + 0.15 * minf(k, 2.0))
	var pm := _sparks.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8 * k
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0 * sqrt(k) * (1.4 if air else 1.0)
	pm.initial_velocity_max = 18.0 * sqrt(k) * (1.4 if air else 1.0)
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.5
	pm.scale_max = 1.1
	pm.scale_curve = VfxAssets.curve("spark_scale", PackedVector2Array([Vector2(0, 1.0), Vector2(1, 0.2)]))
	pm.color_ramp = VfxAssets.ramp("spark",
			PackedColorArray([Color(1.0, 0.92, 0.6, 1.0), Color(1.0, 0.5, 0.15, 0.9), Color(0.5, 0.12, 0.02, 0.0)]),
			PackedFloat32Array([0.0, 0.4, 1.0]))
	_sparks.emitting = true


func _setup_dust(k: float, water: bool, ground: bool) -> void:
	_dust.visible = ground or water
	var dust_count := (30.0 + 22.0 * k) if water else (DUST_BASE + DUST_PER_K * k)
	_dust.amount = VfxAssets.scaled(int(roundf(dust_count)))
	_dust.lifetime = SPRAY_LIFE if water else DUST_LIFE
	var pm := _dust.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = (1.2 if water else 2.5) * k
	pm.direction = Vector3.UP
	pm.spread = 14.0 if water else 65.0
	pm.initial_velocity_min = (12.0 if water else 5.0) * sqrt(k)
	pm.initial_velocity_max = (24.0 if water else 12.0) * sqrt(k)
	pm.gravity = Vector3(0.0, -9.8 if water else -1.5, 0.0)
	pm.damping_min = 0.1 if water else 1.2
	pm.damping_max = 0.4 if water else 2.2
	pm.scale_min = (1.4 if water else 2.0) * sqrt(k)
	pm.scale_max = (2.6 if water else 3.8) * sqrt(k)
	pm.scale_curve = VfxAssets.curve("dust_scale", PackedVector2Array([Vector2(0, 0.4), Vector2(1, 1.3)]))
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 0.0
	if water:
		pm.color_ramp = VfxAssets.ramp("spray",
				PackedColorArray([Color(0.95, 0.98, 1.0, 0.0), Color(0.96, 0.99, 1.0, 0.95), Color(0.8, 0.9, 1.0, 0.0)]),
				PackedFloat32Array([0.0, 0.25, 1.0]))
	else:
		pm.color_ramp = VfxAssets.ramp("dust",
				PackedColorArray([Color(0.62, 0.55, 0.42, 0.0), Color(0.58, 0.52, 0.42, 0.75), Color(0.4, 0.36, 0.3, 0.0)]),
				PackedFloat32Array([0.0, 0.3, 1.0]))
	_dust.emitting = true


func _setup_debris(k: float, aircraft: bool, ground: bool) -> void:
	_debris.visible = aircraft or (ground and k > 0.8)
	var count := DEBRIS_BASE + DEBRIS_PER_K * k
	if aircraft:
		count *= 2.0
	_debris.amount = VfxAssets.scaled(int(roundf(count)))
	_debris.lifetime = DEBRIS_LIFE
	var pm := _debris.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0 * k
	pm.direction = Vector3.UP
	pm.spread = 120.0
	pm.initial_velocity_min = 5.0 * sqrt(k)
	pm.initial_velocity_max = 14.0 * sqrt(k)
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	_debris.emitting = true


## Pool hook: the caller has already set visible/position. Used once per pool cycle.
func is_finished() -> bool:
	return _age >= _total


## Ends this explosion early (used when too many are active; it fades on the next frame).
func cut_short() -> void:
	_total = minf(_total, _age + 0.05)


func _process(delta: float) -> void:
	_age += delta
	var p := clampf(_age / _fire_life, 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - p, 3.0)
	_fire_mat.set_shader_parameter("progress", p)
	_fire.scale = Vector3.ONE * _fire_diam * (0.35 + 0.65 * grow)
	if _ring.visible:
		_ring_mat.set_shader_parameter("progress", clampf(_age / _ring_life, 0.0, 1.0))
	if _age >= _total:
		_finish()


func _finish() -> void:
	for emitter in [_smoke, _sparks, _dust, _debris]:
		(emitter as GPUParticles3D).emitting = false
	visible = false
	if _pool != null:
		_pool.give(self)
	_pool = null
