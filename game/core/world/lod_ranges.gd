class_name LodRanges
extends RefCounted
## Distance culling for aircraft and units. There are no per-part LOD meshes, so a visual beyond
## Settings.unit_draw_m fades out over FADE_M and is not drawn. Buildings and vegetation are MultiMesh
## batches (one draw call per batch) and are not culled per instance.

const FADE_M := 150.0


## Applies the unit draw distance to every GeometryInstance3D under `root`. Call once the tree is built.
static func apply_tree(root: Node) -> void:
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		apply(n as GeometryInstance3D)


static func apply(g: GeometryInstance3D) -> void:
	g.visibility_range_begin = 0.0
	g.visibility_range_end = Settings.unit_draw_m
	g.visibility_range_end_margin = FADE_M
	g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
