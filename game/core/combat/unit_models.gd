class_name UnitModels
extends RefCounted
## Procedural low-poly meshes for combat units and structures when no GLB exists.
## Units point along local -Z (Godot forward). Supports normal detail, LOD (merged silhouette),
## and charred wreck variants.

const COLOR_SAND := Color(0.72, 0.63, 0.46)
const COLOR_CAMO_BROWN := Color(0.48, 0.38, 0.28)
const COLOR_CAMO_GREEN := Color(0.38, 0.42, 0.30)
const COLOR_DARK_METAL := Color(0.20, 0.21, 0.22)
const COLOR_CONCRETE := Color(0.56, 0.55, 0.53)
const COLOR_STEEL := Color(0.45, 0.47, 0.50)
const COLOR_WRECK := Color(0.14, 0.13, 0.13)
const COLOR_SHIP_HULL := Color(0.48, 0.52, 0.55)
const COLOR_SHIP_DECK := Color(0.35, 0.38, 0.40)
const COLOR_WHITE := Color(0.85, 0.85, 0.86)

static var _mat_cache := {}


static func get_mat(color: Color, roughness := 0.7, metallic := 0.1) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [color.to_html(), roughness, metallic]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	_mat_cache[key] = mat
	return mat


static func get_size(kind: String) -> Vector3:
	match kind:
		"tank": return Vector3(3.6, 2.4, 7.2)
		"apc": return Vector3(3.0, 2.3, 6.5)
		"truck": return Vector3(2.5, 2.8, 7.0)
		"fuel_truck": return Vector3(2.5, 2.9, 7.5)
		"sam_sa6": return Vector3(3.4, 3.2, 7.0)
		"sam_sa2": return Vector3(4.8, 5.5, 6.0)
		"sam_sa15": return Vector3(3.5, 3.8, 7.5)
		"manpads": return Vector3(1.0, 1.8, 1.2)
		"aaa_zsu": return Vector3(3.2, 3.2, 6.5)
		"aaa_bofors": return Vector3(3.0, 2.5, 4.5)
		"radar": return Vector3(3.5, 4.5, 7.5)
		"patrol_boat": return Vector3(6.0, 4.5, 24.0)
		"frigate": return Vector3(14.0, 18.0, 95.0)
		"cargo_ship": return Vector3(20.0, 22.0, 130.0)
		"hangar": return Vector3(25.0, 10.0, 35.0)
		"shelter": return Vector3(22.0, 8.5, 28.0)
		"fuel_tank": return Vector3(18.0, 12.0, 18.0)
		"bunker": return Vector3(12.0, 5.0, 15.0)
		"tower": return Vector3(8.0, 25.0, 8.0)
		"ammo_dump": return Vector3(20.0, 4.0, 20.0)
		"comms": return Vector3(14.0, 18.0, 14.0)
		"bridge", "bridges": return Vector3(12.0, 8.0, 60.0)
		_: return Vector3(3.0, 2.5, 6.0)


static func build(kind: String, is_wreck := false, lod_far := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Model_" + kind
	var s := get_size(kind)

	if lod_far:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		mi.mesh = bm
		mi.position.y = s.y * 0.5
		mi.material_override = get_mat(COLOR_WRECK if is_wreck else COLOR_SAND)
		root.add_child(mi)
		return root

	var base_col := COLOR_WRECK if is_wreck else COLOR_SAND
	var dark_col := COLOR_WRECK if is_wreck else COLOR_DARK_METAL
	var steel_col := COLOR_WRECK if is_wreck else COLOR_STEEL

	match kind:
		"tank": _build_tank(root, base_col, dark_col, steel_col, is_wreck)
		"apc": _build_apc(root, base_col, dark_col, steel_col, is_wreck)
		"truck": _build_truck(root, base_col, dark_col, false, is_wreck)
		"fuel_truck": _build_truck(root, base_col, dark_col, true, is_wreck)
		"sam_sa6": _build_sam_sa6(root, base_col, dark_col, steel_col, is_wreck)
		"sam_sa2": _build_sam_sa2(root, base_col, dark_col, steel_col, is_wreck)
		"sam_sa15": _build_sam_sa15(root, base_col, dark_col, steel_col, is_wreck)
		"manpads": _build_manpads(root, base_col, dark_col, is_wreck)
		"aaa_zsu": _build_aaa_zsu(root, base_col, dark_col, steel_col, is_wreck)
		"aaa_bofors": _build_aaa_bofors(root, base_col, dark_col, steel_col, is_wreck)
		"radar": _build_radar(root, base_col, dark_col, steel_col, is_wreck)
		"patrol_boat": _build_patrol_boat(root, is_wreck)
		"frigate": _build_frigate(root, is_wreck)
		"cargo_ship": _build_cargo_ship(root, is_wreck)
		"hangar": _build_hangar(root, is_wreck)
		"shelter": _build_shelter(root, is_wreck)
		"fuel_tank": _build_fuel_tank(root, is_wreck)
		"bunker": _build_bunker(root, is_wreck)
		"tower": _build_tower(root, is_wreck)
		"ammo_dump": _build_ammo_dump(root, is_wreck)
		"comms": _build_comms(root, is_wreck)
		"bridge", "bridges": _build_bridge(root, is_wreck)
		_:
			_box(root, s, Vector3(0, s.y * 0.5, 0), base_col)

	return root


# ----- Helper mesh primitives -----

static func _box(parent: Node, size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = get_mat(col)
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node, r_bot: float, r_top: float, h: float, pos: Vector3, col: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bot
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot
	mi.material_override = get_mat(col)
	parent.add_child(mi)
	return mi


# ----- Vehicle Builders -----

static func _build_tank(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Tracks
	_box(root, Vector3(0.65, 0.75, 6.8), Vector3(-1.45, 0.45, 0), dark_col)
	_box(root, Vector3(0.65, 0.75, 6.8), Vector3(1.45, 0.45, 0), dark_col)
	# Hull
	_box(root, Vector3(2.4, 0.85, 6.6), Vector3(0, 0.8, 0), base_col)
	# Front glacis plate
	_box(root, Vector3(2.35, 0.4, 1.2), Vector3(0, 0.7, -3.1), COLOR_CAMO_BROWN if not is_wreck else dark_col, Vector3(-0.35, 0, 0))
	# Turret
	var turret_node := Node3D.new()
	turret_node.name = "Turret"
	turret_node.position = Vector3(0, 1.35, 0.2)
	root.add_child(turret_node)
	_box(turret_node, Vector3(2.1, 0.75, 2.8), Vector3(0, 0.35, 0), base_col)
	_box(turret_node, Vector3(1.8, 0.5, 0.9), Vector3(0, 0.3, -1.3), COLOR_CAMO_GREEN if not is_wreck else dark_col)
	# Barrel
	var barrel_node := Node3D.new()
	barrel_node.name = "Barrel"
	barrel_node.position = Vector3(0, 0.35, -1.4)
	turret_node.add_child(barrel_node)
	_cyl(barrel_node, 0.1, 0.09, 4.5, Vector3(0, 0, -2.25), steel_col, Vector3(-PI * 0.5, 0, 0))
	# Muzzle brake
	_cyl(barrel_node, 0.16, 0.16, 0.4, Vector3(0, 0, -4.5), dark_col, Vector3(-PI * 0.5, 0, 0))


static func _build_apc(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Wheels (8x8)
	for side in [-1.4, 1.4]:
		for z in [-2.2, -0.7, 0.8, 2.2]:
			_cyl(root, 0.5, 0.5, 0.35, Vector3(side, 0.5, z), dark_col, Vector3(0, 0, PI * 0.5))
	# Hull
	_box(root, Vector3(2.4, 1.1, 6.2), Vector3(0, 1.1, 0), base_col)
	# Sloped nose
	_box(root, Vector3(2.35, 0.6, 1.4), Vector3(0, 1.0, -2.8), COLOR_CAMO_GREEN if not is_wreck else dark_col, Vector3(-0.4, 0, 0))
	# Small autocannon turret
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.7, -0.4)
	root.add_child(turret)
	_box(turret, Vector3(1.2, 0.6, 1.4), Vector3(0, 0.25, 0), COLOR_CAMO_BROWN if not is_wreck else base_col)
	_cyl(turret, 0.05, 0.04, 2.2, Vector3(0, 0.3, -1.3), steel_col, Vector3(-PI * 0.5, 0, 0))


static func _build_truck(root: Node3D, base_col: Color, dark_col: Color, is_fuel: bool, is_wreck: bool) -> void:
	# Wheels (6x6)
	for side in [-1.15, 1.15]:
		for z in [-2.4, 1.2, 2.5]:
			_cyl(root, 0.52, 0.52, 0.3, Vector3(side, 0.52, z), dark_col, Vector3(0, 0, PI * 0.5))
	# Chassis frame
	_box(root, Vector3(1.2, 0.3, 6.6), Vector3(0, 0.75, 0), dark_col)
	# Cab
	_box(root, Vector3(2.3, 1.6, 2.2), Vector3(0, 1.7, -2.0), base_col)
	# Windshield / glass
	_box(root, Vector3(2.1, 0.7, 0.1), Vector3(0, 1.9, -3.05), Color(0.15, 0.2, 0.25))
	if is_fuel:
		# Tank cylinder
		_cyl(root, 1.05, 1.05, 4.4, Vector3(0, 1.9, 0.9), COLOR_WHITE if not is_wreck else dark_col, Vector3(-PI * 0.5, 0, 0))
	else:
		# Cargo bed / canvas
		_box(root, Vector3(2.35, 1.5, 4.2), Vector3(0, 1.8, 1.0), COLOR_CAMO_BROWN if not is_wreck else dark_col)


static func _build_sam_sa6(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Tracked chassis (same as tank base)
	_box(root, Vector3(0.6, 0.7, 6.5), Vector3(-1.4, 0.45, 0), dark_col)
	_box(root, Vector3(0.6, 0.7, 6.5), Vector3(1.4, 0.45, 0), dark_col)
	_box(root, Vector3(2.3, 0.9, 6.3), Vector3(0, 0.85, 0), base_col)
	# Launcher turret
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.35, 0)
	root.add_child(turret)
	_box(turret, Vector3(2.0, 0.6, 2.2), Vector3(0, 0.3, 0), base_col)
	# Launcher arm (angled up 25 deg)
	var arm := Node3D.new()
	arm.name = "LauncherArm"
	arm.position = Vector3(0, 0.6, 0)
	arm.rotation_degrees = Vector3(-25, 0, 0)
	turret.add_child(arm)
	_box(arm, Vector3(1.8, 0.2, 3.2), Vector3(0, 0, -0.6), dark_col)
	# 3x SA-6 missiles mounted on the rail
	for off_x in [-0.65, 0.0, 0.65]:
		var m := Node3D.new()
		m.name = "MissileMount"
		m.position = Vector3(off_x, 0.25, -0.6)
		arm.add_child(m)
		_cyl(m, 0.16, 0.16, 3.6, Vector3(0, 0, 0), COLOR_WHITE if not is_wreck else dark_col, Vector3(-PI * 0.5, 0, 0))
		_cyl(m, 0.16, 0.02, 0.6, Vector3(0, 0, -2.0), steel_col, Vector3(-PI * 0.5, 0, 0))


static func _build_sam_sa2(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Fixed cross base launcher pad
	_box(root, Vector3(4.5, 0.25, 0.8), Vector3(0, 0.15, 0), dark_col)
	_box(root, Vector3(0.8, 0.25, 4.5), Vector3(0, 0.15, 0), dark_col)
	# Rotating mount
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 0.3, 0)
	root.add_child(turret)
	_cyl(turret, 0.9, 0.8, 0.8, Vector3(0, 0.4, 0), base_col)
	# Single giant rail angled up 45 deg
	var rail := Node3D.new()
	rail.name = "LauncherArm"
	rail.position = Vector3(0, 0.8, 0)
	rail.rotation_degrees = Vector3(-45, 0, 0)
	turret.add_child(rail)
	_box(rail, Vector3(0.5, 0.3, 6.0), Vector3(0, 0, -1.5), dark_col)
	# Huge SA-2 missile (10m long)
	var m := Node3D.new()
	m.name = "MissileMount"
	m.position = Vector3(0, 0.4, -1.5)
	rail.add_child(m)
	_cyl(m, 0.32, 0.32, 7.5, Vector3(0, 0, 0), COLOR_WHITE if not is_wreck else dark_col, Vector3(-PI * 0.5, 0, 0))
	_cyl(m, 0.32, 0.05, 1.5, Vector3(0, 0, -4.2), steel_col, Vector3(-PI * 0.5, 0, 0))
	# Fins
	_box(m, Vector3(1.6, 0.04, 0.8), Vector3(0, 0, 2.5), steel_col)
	_box(m, Vector3(0.04, 1.6, 0.8), Vector3(0, 0, 2.5), steel_col)


static func _build_sam_sa15(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Tor tracked chassis
	_box(root, Vector3(0.65, 0.75, 7.0), Vector3(-1.45, 0.45, 0), dark_col)
	_box(root, Vector3(0.65, 0.75, 7.0), Vector3(1.45, 0.45, 0), dark_col)
	_box(root, Vector3(2.4, 1.1, 6.8), Vector3(0, 0.95, 0), base_col)
	# Big box turret (contains 8 VLS cells inside)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.5, 0.3)
	root.add_child(turret)
	_box(turret, Vector3(2.4, 1.2, 3.2), Vector3(0, 0.6, 0), base_col)
	# VLS hatch doors on top
	_box(turret, Vector3(1.6, 0.08, 2.2), Vector3(0, 1.24, 0), dark_col)
	# Tracking radar face on front of turret
	_box(turret, Vector3(1.3, 0.9, 0.2), Vector3(0, 0.7, -1.65), steel_col, Vector3(-0.2, 0, 0))
	# Foldable search radar antenna on rear
	var radar_dish := Node3D.new()
	radar_dish.name = "RadarDish"
	radar_dish.position = Vector3(0, 1.4, 1.1)
	turret.add_child(radar_dish)
	_box(radar_dish, Vector3(1.8, 0.8, 0.15), Vector3(0, 0.4, 0), COLOR_CAMO_GREEN if not is_wreck else dark_col)


static func _build_manpads(root: Node3D, base_col: Color, dark_col: Color, is_wreck: bool) -> void:
	# Soldier kneeling/standing holding shoulder launcher
	_box(root, Vector3(0.35, 0.7, 0.3), Vector3(0, 0.35, 0), COLOR_CAMO_GREEN if not is_wreck else dark_col)
	_box(root, Vector3(0.45, 0.65, 0.35), Vector3(0, 0.95, 0), base_col)
	_cyl(root, 0.14, 0.14, 0.25, Vector3(0, 1.4, 0), dark_col) # Helmet
	# Shoulder launch tube
	var tube := Node3D.new()
	tube.name = "LauncherArm"
	tube.position = Vector3(0.2, 1.25, 0)
	tube.rotation_degrees = Vector3(-20, 0, 0)
	root.add_child(tube)
	_cyl(tube, 0.07, 0.07, 1.7, Vector3(0, 0, -0.3), COLOR_CAMO_GREEN if not is_wreck else dark_col, Vector3(-PI * 0.5, 0, 0))


static func _build_aaa_zsu(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Tracked chassis
	_box(root, Vector3(0.6, 0.7, 6.2), Vector3(-1.3, 0.45, 0), dark_col)
	_box(root, Vector3(0.6, 0.7, 6.2), Vector3(1.3, 0.45, 0), dark_col)
	_box(root, Vector3(2.2, 0.9, 6.0), Vector3(0, 0.85, 0), base_col)
	# Turret
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, 0)
	root.add_child(turret)
	_box(turret, Vector3(2.1, 0.9, 2.6), Vector3(0, 0.45, 0), base_col)
	# Dish radar at rear of turret
	var dish := Node3D.new()
	dish.name = "RadarDish"
	dish.position = Vector3(0, 0.9, 1.1)
	turret.add_child(dish)
	_cyl(dish, 0.5, 0.5, 0.12, Vector3(0, 0.4, 0), steel_col, Vector3(PI * 0.5, 0, 0))
	# Gun mount & 4x 23mm barrels
	var gun_mount := Node3D.new()
	gun_mount.name = "GunMount"
	gun_mount.position = Vector3(0, 0.45, -1.3)
	turret.add_child(gun_mount)
	for x in [-0.3, -0.1, 0.1, 0.3]:
		_cyl(gun_mount, 0.04, 0.035, 2.8, Vector3(x, 0, -1.4), steel_col, Vector3(-PI * 0.5, 0, 0))


static func _build_aaa_bofors(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Wheeled carriage / outriggers
	_box(root, Vector3(2.6, 0.25, 3.8), Vector3(0, 0.3, 0), dark_col)
	# 4 wheels
	for s in [-1.4, 1.4]:
		for z in [-1.0, 1.0]:
			_cyl(root, 0.45, 0.45, 0.25, Vector3(s, 0.45, z), dark_col, Vector3(0, 0, PI * 0.5))
	# Turret
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 0.5, 0)
	root.add_child(turret)
	_box(turret, Vector3(1.6, 0.7, 1.6), Vector3(0, 0.35, 0), base_col)
	# Gun shield
	_box(turret, Vector3(1.8, 1.1, 0.1), Vector3(0, 0.8, -0.7), base_col)
	# Long 40mm barrel
	var gun := Node3D.new()
	gun.name = "GunMount"
	gun.position = Vector3(0, 0.7, -0.7)
	turret.add_child(gun)
	_cyl(gun, 0.08, 0.06, 3.8, Vector3(0, 0, -1.9), steel_col, Vector3(-PI * 0.5, 0, 0))
	_cyl(gun, 0.12, 0.12, 0.3, Vector3(0, 0, -3.8), dark_col, Vector3(-PI * 0.5, 0, 0)) # muzzle flash


static func _build_radar(root: Node3D, base_col: Color, dark_col: Color, steel_col: Color, is_wreck: bool) -> void:
	# Heavy truck / trailer chassis
	_box(root, Vector3(2.5, 1.2, 7.2), Vector3(0, 0.9, 0), base_col)
	# Cab
	_box(root, Vector3(2.4, 1.5, 2.2), Vector3(0, 1.6, -2.4), base_col)
	# Rotating pedestal
	var turret := Node3D.new()
	turret.name = "RadarDish"
	turret.position = Vector3(0, 1.6, 0.8)
	root.add_child(turret)
	_cyl(turret, 0.8, 0.6, 0.8, Vector3(0, 0.4, 0), dark_col)
	# Massive curved parabolic antenna mesh
	_box(turret, Vector3(4.8, 1.8, 0.3), Vector3(0, 1.6, 0), COLOR_CAMO_GREEN if not is_wreck else steel_col)
	_box(turret, Vector3(0.2, 0.8, 1.2), Vector3(0, 1.6, -0.6), steel_col) # Feed horn


# ----- Ships -----

static func _build_patrol_boat(root: Node3D, is_wreck: bool) -> void:
	var hull_col := COLOR_WRECK if is_wreck else COLOR_SHIP_HULL
	var deck_col := COLOR_WRECK if is_wreck else COLOR_SHIP_DECK
	# Hull
	_box(root, Vector3(5.5, 2.4, 22.0), Vector3(0, 0.8, 0), hull_col)
	# Bow wedge
	_box(root, Vector3(4.2, 2.2, 4.0), Vector3(0, 1.0, -11.5), hull_col, Vector3(-0.25, 0, 0))
	# Deck house / bridge
	_box(root, Vector3(3.8, 2.2, 8.0), Vector3(0, 2.8, -1.0), deck_col)
	# Mast & radar
	_cyl(root, 0.1, 0.08, 4.0, Vector3(0, 5.2, -1.0), COLOR_STEEL)
	# Bow gun mount (20mm)
	var gun := Node3D.new()
	gun.name = "GunMount"
	gun.position = Vector3(0, 2.2, -7.5)
	root.add_child(gun)
	_cyl(gun, 0.6, 0.5, 0.5, Vector3(0, 0.25, 0), deck_col)
	_cyl(gun, 0.04, 0.03, 2.0, Vector3(0, 0.4, -1.0), COLOR_DARK_METAL, Vector3(-PI * 0.5, 0, 0))


static func _build_frigate(root: Node3D, is_wreck: bool) -> void:
	var hull_col := COLOR_WRECK if is_wreck else COLOR_SHIP_HULL
	var deck_col := COLOR_WRECK if is_wreck else COLOR_SHIP_DECK
	# Main warship hull
	_box(root, Vector3(13.0, 6.0, 90.0), Vector3(0, 2.0, 0), hull_col)
	# Sleek tapered bow
	_box(root, Vector3(10.0, 6.0, 15.0), Vector3(0, 2.5, -45.0), hull_col, Vector3(-0.2, 0, 0))
	# Bridge superstructure
	_box(root, Vector3(10.0, 5.0, 24.0), Vector3(0, 6.8, -10.0), deck_col)
	_box(root, Vector3(8.0, 3.5, 12.0), Vector3(0, 10.5, -12.0), deck_col)
	# Masts with radars
	_cyl(root, 0.4, 0.2, 10.0, Vector3(0, 14.0, -8.0), COLOR_STEEL)
	var radar := Node3D.new()
	radar.name = "RadarDish"
	radar.position = Vector3(0, 18.0, -8.0)
	root.add_child(radar)
	_box(radar, Vector3(4.0, 1.2, 0.3), Vector3(0, 0, 0), COLOR_WHITE)
	# Forward naval gun turret (76mm)
	var gun := Node3D.new()
	gun.name = "GunMount"
	gun.position = Vector3(0, 5.3, -28.0)
	root.add_child(gun)
	_box(gun, Vector3(3.2, 1.8, 3.8), Vector3(0, 0.9, 0), deck_col)
	_cyl(gun, 0.12, 0.09, 4.5, Vector3(0, 1.2, -3.2), COLOR_STEEL, Vector3(-PI * 0.5, 0, 0))
	# SAM launcher / VLS box
	var sam := Node3D.new()
	sam.name = "Turret"
	sam.position = Vector3(0, 5.3, -19.0)
	root.add_child(sam)
	_box(sam, Vector3(4.5, 1.2, 5.5), Vector3(0, 0.6, 0), COLOR_DARK_METAL)
	# Helipad at stern
	_box(root, Vector3(11.0, 0.2, 18.0), Vector3(0, 5.1, 28.0), COLOR_DARK_METAL)


static func _build_cargo_ship(root: Node3D, is_wreck: bool) -> void:
	var hull_col := COLOR_WRECK if is_wreck else COLOR_SHIP_HULL
	var deck_col := COLOR_WRECK if is_wreck else COLOR_SHIP_DECK
	# Long hull
	_box(root, Vector3(18.0, 8.0, 125.0), Vector3(0, 2.5, 0), hull_col)
	# Container stacks
	var cols := [Color(0.8, 0.2, 0.2), Color(0.2, 0.4, 0.8), Color(0.2, 0.7, 0.3), Color(0.85, 0.65, 0.15)]
	for z in [-35.0, -15.0, 5.0, 25.0]:
		for x in [-4.5, 4.5]:
			var c: Color = cols[abs(int(x + z)) % cols.size()] if not is_wreck else COLOR_WRECK
			_box(root, Vector3(6.5, 6.0, 15.0), Vector3(x, 8.5, z), c)
	# Superstructure tower at aft
	_box(root, Vector3(14.0, 12.0, 16.0), Vector3(0, 11.5, 45.0), deck_col)
	# Smokestack
	_cyl(root, 1.4, 1.2, 6.0, Vector3(0, 18.5, 48.0), Color(0.8, 0.2, 0.2) if not is_wreck else COLOR_WRECK)


# ----- Structures -----

static func _build_hangar(root: Node3D, is_wreck: bool) -> void:
	var wall_col := COLOR_WRECK if is_wreck else COLOR_CONCRETE
	var roof_col := COLOR_WRECK if is_wreck else COLOR_STEEL
	# Walls
	_box(root, Vector3(25.0, 8.0, 35.0), Vector3(0, 4.0, 0), wall_col)
	# Curved/angled roof
	_box(root, Vector3(26.0, 3.5, 36.0), Vector3(0, 9.5, 0), roof_col, Vector3(0, 0, 0))
	# Front open door recess
	_box(root, Vector3(18.0, 7.0, 2.0), Vector3(0, 3.5, -17.0), COLOR_DARK_METAL)


static func _build_shelter(root: Node3D, is_wreck: bool) -> void:
	var conc := COLOR_WRECK if is_wreck else COLOR_CONCRETE
	# Hardened arched concrete shelter
	_box(root, Vector3(22.0, 7.5, 28.0), Vector3(0, 3.75, 0), conc)
	# Reinforced front blast doors
	_box(root, Vector3(14.0, 6.0, 1.5), Vector3(0, 3.0, -13.5), COLOR_DARK_METAL)


static func _build_fuel_tank(root: Node3D, is_wreck: bool) -> void:
	var white := COLOR_WRECK if is_wreck else COLOR_WHITE
	# Containment berm
	_box(root, Vector3(22.0, 1.2, 22.0), Vector3(0, 0.6, 0), COLOR_CONCRETE)
	# Giant storage tank cylinder
	_cyl(root, 7.5, 7.5, 10.0, Vector3(0, 5.8, 0), white)
	# Dome top
	_cyl(root, 7.5, 1.0, 1.8, Vector3(0, 11.5, 0), white)


static func _build_bunker(root: Node3D, is_wreck: bool) -> void:
	var conc := COLOR_WRECK if is_wreck else COLOR_CONCRETE
	# Low-profile heavy reinforced concrete bunker
	_box(root, Vector3(12.0, 3.8, 14.0), Vector3(0, 1.9, 0), conc)
	# Firing embrasures / slits
	_box(root, Vector3(6.0, 0.4, 0.5), Vector3(0, 2.4, -6.8), COLOR_DARK_METAL)


static func _build_tower(root: Node3D, is_wreck: bool) -> void:
	var steel := COLOR_WRECK if is_wreck else COLOR_STEEL
	# Lattice base
	_cyl(root, 2.8, 1.4, 20.0, Vector3(0, 10.0, 0), steel)
	# Top cabin / observation cab
	_box(root, Vector3(6.0, 3.5, 6.0), Vector3(0, 21.0, 0), COLOR_CONCRETE if not is_wreck else COLOR_WRECK)
	# Antenna mast
	_cyl(root, 0.15, 0.05, 6.0, Vector3(0, 25.5, 0), steel)


static func _build_ammo_dump(root: Node3D, is_wreck: bool) -> void:
	# Earthen revetment
	_box(root, Vector3(18.0, 2.2, 18.0), Vector3(0, 1.1, 0), COLOR_CAMO_BROWN)
	# Stored crates / munitions stacks inside
	for x in [-3.5, 3.5]:
		for z in [-3.5, 3.5]:
			_box(root, Vector3(3.2, 2.2, 3.2), Vector3(x, 1.5, z), COLOR_CAMO_GREEN if not is_wreck else COLOR_WRECK)


static func _build_comms(root: Node3D, is_wreck: bool) -> void:
	var wall := COLOR_WRECK if is_wreck else COLOR_CONCRETE
	var steel := COLOR_WRECK if is_wreck else COLOR_STEEL
	# Comms building
	_box(root, Vector3(12.0, 5.0, 12.0), Vector3(0, 2.5, 0), wall)
	# Big satellite dish on roof
	var dish := Node3D.new()
	dish.name = "RadarDish"
	dish.position = Vector3(0, 5.0, 0)
	root.add_child(dish)
	_cyl(dish, 2.5, 2.5, 0.4, Vector3(0, 2.2, 0), COLOR_WHITE, Vector3(0.5, 0, 0))
	_cyl(dish, 0.1, 0.05, 8.0, Vector3(3.5, 4.0, 3.5), steel)


static func _build_bridge(root: Node3D, is_wreck: bool) -> void:
	var conc := COLOR_WRECK if is_wreck else COLOR_CONCRETE
	# Road deck span
	_box(root, Vector3(10.0, 1.5, 60.0), Vector3(0, 5.0, 0), conc)
	# Guard rails
	_box(root, Vector3(0.4, 1.0, 60.0), Vector3(-4.8, 6.0, 0), COLOR_STEEL)
	_box(root, Vector3(0.4, 1.0, 60.0), Vector3(4.8, 6.0, 0), COLOR_STEEL)
	# Support pillars
	for z in [-18.0, 18.0]:
		_cyl(root, 1.8, 1.8, 6.0, Vector3(0, 2.5, z), conc)
