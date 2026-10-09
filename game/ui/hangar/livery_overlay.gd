class_name LiveryOverlay
extends RefCounted
## Paints a livery texture over an aircraft model. The models have no usable UVs, so the texture is projected
## triplanar in the aircraft's own space and the paint stays put while the model turns. Glass, lights, exhausts,
## wheels and rotors keep their own materials. Used by the hangar turntable and the in-flight visual.

const SHADER := preload("res://ui/hangar/livery_overlay.gdshader")
const SKIP_HINTS := ["glass", "canopy", "lens", "light", "lamp", "exhaust", "flame", "nozzle", "wheel", "tire", "tyre", "rotor", "prop", "blade", "intake", "pitot", "probe"]


## Paints every opaque, non-emissive surface under root. Calling it again swaps the livery.
static func apply(root: Node3D, tex: Texture2D) -> void:
	if root == null or tex == null:
		return
	for mi in _meshes(root):
		var surfaces: Array[int] = []
		for s in mi.mesh.get_surface_count():
			if not _skip_surface(mi, s):
				surfaces.append(s)
		if surfaces.is_empty():
			continue
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("livery_tex", tex)
		mat.set_shader_parameter("to_root", _to_root(mi, root))
		for s in surfaces:
			mi.set_surface_override_material(s, mat)


## Removes the livery and returns every surface to its own material.
static func clear(root: Node3D) -> void:
	if root == null:
		return
	for mi in _meshes(root):
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, null)


static func _meshes(root: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect_meshes(root, out)
	return out


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


static func _skip_surface(mi: MeshInstance3D, surface: int) -> bool:
	if _has_hint(str(mi.name) + " " + mi.mesh.resource_name):
		return true
	var mat := mi.get_active_material(surface)
	if mat == null:
		return false
	if _has_hint(mat.resource_name):
		return true
	if mat is BaseMaterial3D:
		var base := mat as BaseMaterial3D
		return base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.emission_enabled
	return false


static func _has_hint(text: String) -> bool:
	var lower := text.to_lower()
	for hint in SKIP_HINTS:
		if lower.contains(hint):
			return true
	return false


## Transform from a mesh's vertex space into the space of root (root's own transform excluded).
static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
