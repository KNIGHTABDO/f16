class_name ShaderWarmup
extends RefCounted
## Compiles the world and effect shaders before the first frame that shows them. Pipelines are built on first
## draw, which shows as a hitch the first time a shader is visible in flight. Each shader gets a sub-pixel quad
## just in front of the camera for FRAMES frames, while the loading screen is still up. Called from
## WorldBuilder.build(), so loading screens need no change.

const FRAMES := 3
const SHADERS := [
	"res://core/vfx/afterburner.gdshader",
	"res://core/vfx/fireball.gdshader",
	"res://core/vfx/ribbon.gdshader",
	"res://core/vfx/shockwave.gdshader",
	"res://core/vfx/vapor.gdshader",
	"res://core/world/cirrus.gdshader",
	"res://core/world/city_facade.gdshader",
	"res://core/world/clouds.gdshader",
	"res://core/world/ocean.gdshader",
	"res://core/world/rain.gdshader",
	"res://core/world/runway.gdshader",
	"res://core/world/terrain.gdshader",
	"res://core/world/vegetation.gdshader",
]


## Adds the warmup quads under `parent` and removes them after FRAMES frames. Does not block the caller.
static func run(parent: Node3D, camera: Camera3D) -> void:
	if camera == null or not parent.is_inside_tree():
		return
	var holder := Node3D.new()
	holder.name = "ShaderWarmup"
	parent.add_child(holder)
	holder.global_position = camera.global_position - camera.global_basis.z * 1.5
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.001
	for path in SHADERS:
		var shader := load(path) as Shader
		if shader == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = ShaderMaterial.new()
		(mi.material_override as ShaderMaterial).shader = shader
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	var tree := parent.get_tree()
	for i in FRAMES:
		await tree.process_frame
	if is_instance_valid(holder):
		holder.queue_free()
