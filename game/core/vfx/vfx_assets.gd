class_name VfxAssets
extends RefCounted
## Shared, lazily built textures, shaders, materials and meshes for the VFX system.
## Everything is cached statically: effects reuse one material per look (fewer state changes, fewer
## draw calls) and nothing is allocated per spawned effect.

const TEX_DIR := "res://assets/textures/vfx/"
const SHADER_DIR := "res://core/vfx/"

## Particle amount multipliers per Settings.graphics_preset.
const PRESET_SCALE := {"low": 0.4, "balanced": 0.7, "high": 1.0, "ultra": 1.3}

static var _cache: Dictionary = {}


static func texture(file: String) -> Texture2D:
	var key := "t:" + file
	if not _cache.has(key):
		_cache[key] = load(TEX_DIR + file)
	return _cache[key] as Texture2D


static func shader(file: String) -> Shader:
	var key := "s:" + file
	if not _cache.has(key):
		_cache[key] = load(SHADER_DIR + file)
	return _cache[key] as Shader


## New ShaderMaterial. Not cached: each effect instance owns its uniforms.
static func shader_material(file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(file)
	m.set_shader_parameter("noise_tex", texture("noise.png"))
	return m


## Particle/sprite amount multiplier for the current graphics preset (0.4 .. 1.3).
static func amount_scale() -> float:
	return float(PRESET_SCALE.get(Settings.graphics_preset, 1.0))


## Scales an integer particle count by the preset, never below 1.
static func scaled(count: int) -> int:
	return maxi(1, roundi(float(count) * amount_scale()))


## Unshaded soft-sprite material. additive for glows, sparks and fire; alpha mix for smoke and dust.
## billboard: BaseMaterial3D.BILLBOARD_PARTICLES for GPUParticles3D, BILLBOARD_ENABLED for quads/multimesh.
## frames_h/frames_v: flipbook grid (used with ParticleProcessMaterial anim_* settings).
static func sprite_material(file: String, additive: bool, billboard: int, frames_h: int = 1, frames_v: int = 1) -> StandardMaterial3D:
	var key := "m:%s:%d:%d:%d:%d" % [file, int(additive), billboard, frames_h, frames_v]
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.billboard_mode = billboard
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = texture(file)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if frames_h * frames_v > 1:
		m.particles_anim_h_frames = frames_h
		m.particles_anim_v_frames = frames_v
		m.particles_anim_loop = true
	_cache[key] = m
	return m


## Plain unshaded translucent material (ribbon trails, vapour, debris smoke). Colour via vertex colour.
static func plain_material(additive: bool) -> StandardMaterial3D:
	var key := "p:%d" % int(additive)
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.vertex_color_use_as_albedo = true
	_cache[key] = m
	return m


## Lit material for debris chunks (sunlit, with an ember glow for burning pieces).
static func chunk_material(ember: bool) -> StandardMaterial3D:
	var key := "c:%d" % int(ember)
	if _cache.has(key):
		return _cache[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.15, 0.14) if not ember else Color(0.28, 0.2, 0.15)
	m.roughness = 0.9
	if ember:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.42, 0.1)
		m.emission_energy_multiplier = 1.4
	_cache[key] = m
	return m


static func quad() -> QuadMesh:
	if not _cache.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		_cache["quad"] = q
	return _cache["quad"] as QuadMesh


static func chunk_box() -> BoxMesh:
	if not _cache.has("chunk"):
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.18, 0.4)
		_cache["chunk"] = b
	return _cache["chunk"] as BoxMesh


## GPUParticles3D with local coordinates: particles live in the emitter's space, so the emitter (a
## child of World, group "floating") moves with WorldOrigin shifts and its particles move with it.
static func make_particles(amount: int, lifetime: float, draw_mesh: Mesh, draw_material: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = true
	p.one_shot = true
	p.emitting = false
	p.draw_pass_1 = draw_mesh
	p.material_override = draw_material
	p.process_material = ParticleProcessMaterial.new()
	return p


## Colour ramp (alpha included) for particle colour_ramp / color_ramp uniforms. Cached by key.
static func ramp(key: String, colors: PackedColorArray, offsets: PackedFloat32Array) -> GradientTexture1D:
	var k := "r:" + key
	if _cache.has(k):
		return _cache[k] as GradientTexture1D
	var g := Gradient.new()
	g.colors = colors
	g.offsets = offsets
	var t := GradientTexture1D.new()
	t.gradient = g
	_cache[k] = t
	return t


## Curve (0..1 over particle life) as a texture for scale_curve / alpha_curve. Cached by key.
static func curve(key: String, points: PackedVector2Array) -> CurveTexture:
	var k := "c:" + key
	if _cache.has(k):
		return _cache[k] as CurveTexture
	var c := Curve.new()
	c.clear_points()
	for p in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	_cache[k] = t
	return t


## Symmetric visibility box, so large effects are never culled while particles are alive.
static func big_aabb(radius: float, height: float) -> AABB:
	return AABB(Vector3(-radius, -radius * 0.5, -radius), Vector3(radius * 2.0, radius * 2.0 + height, radius * 2.0))
