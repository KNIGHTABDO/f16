class_name WeaponModels
extends RefCounted
## Procedural low-poly meshes for missiles, bombs, rockets and pylons. All models point along local -Z.

const BODY := Color(0.82, 0.84, 0.86)
const DARK := Color(0.2, 0.21, 0.23)
const OLIVE := Color(0.32, 0.36, 0.26)
const SEEKER := Color(0.1, 0.1, 0.12)

static var _mats := {}


static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.2
	_mats[key] = m
	return m


static func _cyl(parent: Node3D, r0: float, r1: float, length: float, z: float, c: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r0
	cm.height = length
	cm.radial_segments = 8
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _mat(c)
	mi.rotation.x = -PI * 0.5  # cylinder axis Y -> -Z (top radius at the nose)
	mi.position.z = z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _fins(parent: Node3D, z: float, span: float, chord: float, c: Color, count := 4) -> void:
	for k in count:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, span, chord)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _mat(c)
		mi.position = Vector3(0, 0, z)
		mi.rotation.z = TAU * k / count + PI * 0.25
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


## Returns a Node3D with the model for a weapons.json entry. Length/radius depend on the type.
static func build(weapon_id: String, w: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = weapon_id
	match str(w.get("type", "")):
		"ir_missile":
			_cyl(root, 0.065, 0.065, 2.4, 0.0, BODY)
			_cyl(root, 0.065, 0.02, 0.35, -1.37, SEEKER)
			_fins(root, 0.9, 0.45, 0.3, DARK)
			_fins(root, -0.95, 0.5, 0.35, DARK)
		"radar_missile":
			_cyl(root, 0.09, 0.09, 3.6, 0.0, BODY)
			_cyl(root, 0.09, 0.03, 0.5, -2.05, BODY.darkened(0.2))
			_fins(root, 1.0, 0.5, 0.4, DARK)
			_fins(root, -1.6, 0.6, 0.45, DARK)
		"ag_missile":
			_cyl(root, 0.15, 0.15, 2.4, 0.0, OLIVE.lightened(0.45))
			_cyl(root, 0.15, 0.1, 0.4, -1.4, SEEKER)
			_fins(root, 0.5, 0.65, 0.5, DARK)
			_fins(root, -1.0, 0.45, 0.35, DARK)
		"bomb":
			_cyl(root, 0.18, 0.18, 1.6, 0.0, OLIVE)
			_cyl(root, 0.18, 0.04, 0.4, -1.0, OLIVE)
			_cyl(root, 0.18, 0.1, 0.3, 0.95, OLIVE)
			_fins(root, 1.0, 0.55, 0.3, DARK)
		"guided_bomb":
			_cyl(root, 0.2, 0.2, 1.7, 0.0, OLIVE)
			_cyl(root, 0.2, 0.08, 0.5, -1.1, SEEKER)
			_fins(root, -0.2, 0.75, 0.3, DARK)
			_fins(root, 1.0, 0.65, 0.35, DARK)
		"rocket":
			_cyl(root, 0.035, 0.035, 1.3, 0.0, OLIVE)
			_cyl(root, 0.035, 0.0, 0.15, -0.7, DARK)
			_fins(root, 0.55, 0.14, 0.12, DARK)
		_:
			_cyl(root, 0.08, 0.08, 2.0, 0.0, BODY)
	return root


## Length in meters of the model (for muzzle offsets).
static func length_of(w: Dictionary) -> float:
	match str(w.get("type", "")):
		"ir_missile": return 2.9
		"radar_missile": return 3.9
		"ag_missile": return 2.6
		"bomb": return 2.2
		"guided_bomb": return 2.6
		"rocket": return 1.3
	return 2.0


## Hardpoint positions (local aircraft coords) alternating right/left, under the wings and fuselage.
static func hardpoint_positions(span: float, length: float, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(count, 2)
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := float(i / 2)
		var x := side * (span * (0.12 + 0.07 * rank) + 0.35)
		if i >= 6:
			x = 0.0
		var z := length * (-0.02 + 0.015 * rank)
		out.append(Vector3(x, -0.55 - 0.05 * rank, z))
	return out
