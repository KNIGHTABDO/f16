class_name Carrier
extends Node3D
## Procedural modern aircraft carrier (Nimitz / Ford class).
##
## Group: "floating", "damageable", "team_0"
## Public API:
##   get_deck_transform() -> Transform3D
##   get_wire_positions() -> Array[Vector3]
##   get_cat_positions() -> Array[Dictionary]
##   deck_height_at(local_x: float, local_z: float) -> float (NaN when outside)
##   get_velocity() -> Vector3
##   get_target_kind() -> String ("ship")
##   take_damage(amount, source, hit_pos)

const SPEED_KTS := 15.0
const SPEED_MS := 15.0 * 0.514444 # ~7.7167 m/s
const DECK_HEIGHT := 19.5
const ANGLED_DECK_ANGLE_RAD := deg_to_rad(9.2) # ~9 degrees to port

var team: int = 0
var alive: bool = true
var max_health: float = 12000.0
var health: float = 12000.0
var heading_deg: float = 270.0

var _deck_node: Node3D
var _wires_local: Array[Vector3] = []
var _cats_local: Array[Dictionary] = []
var _hitbox: Hitbox


func setup(world_pos: Vector3, heading: float = 270.0) -> void:
	add_to_group("floating")
	add_to_group("damageable")
	add_to_group("team_0")

	heading_deg = heading
	position = WorldOrigin.to_local(Vector3(world_pos.x, Ground.sea_level if Ground.is_loaded() else 0.0, world_pos.z))
	rotation.y = deg_to_rad(heading)

	_build_carrier_mesh()
	_setup_catapults_and_wires()
	_setup_hitbox()


func get_deck_transform() -> Transform3D:
	return global_transform.translated_local(Vector3(0.0, DECK_HEIGHT, 0.0))


func get_velocity() -> Vector3:
	return -global_transform.basis.z.normalized() * SPEED_MS


func get_target_kind() -> String:
	return "ship"


func take_damage(amount: float, source: Node, hit_pos: Vector3) -> void:
	if not alive:
		return
	health -= amount
	if has_node("/root/Events"):
		var events = get_node("/root/Events")
		if events.has_signal("damaged"):
			events.emit_signal("damaged", self, amount, source)
	if health <= 0.0:
		alive = false
		if has_node("/root/Events"):
			var events = get_node("/root/Events")
			if events.has_signal("target_destroyed"):
				events.emit_signal("target_destroyed", self, source)


func get_wire_positions() -> Array:
	var out: Array = []
	for lw in _wires_local:
		out.append(to_global(lw))
	return out


func get_cat_positions() -> Array:
	var out: Array = []
	for c in _cats_local:
		var p_local: Vector3 = c["local_pos"]
		var h_offset: float = float(c.get("heading_offset", 0.0))
		out.append({
			"position": to_global(p_local),
			"heading_deg": fposmod(heading_deg + h_offset, 360.0),
			"length": float(c.get("length", 90.0)),
			"name": String(c.get("name", "CAT"))
		})
	return out


func deck_height_at(local_x: float, local_z: float) -> float:
	var p := to_local(Vector3(local_x, global_position.y, local_z))
	# Check XZ footprint of flight deck
	# Bow at -166m, stern at +166m
	if p.z < -166.0 or p.z > 166.0:
		return NAN

	# Taper towards bow
	var max_half_w := 38.4
	if p.z < -110.0:
		var t := (p.z + 110.0) / -56.0
		max_half_w = lerpf(38.4, 14.0, t)

	# Angled deck overhang on port side (-X)
	var min_x := -max_half_w
	var max_x := max_half_w * 0.85 # starboard side
	if p.z > -80.0 and p.z < 120.0:
		min_x = -42.0 # angled deck sponsor overhang

	if p.x >= min_x and p.x <= max_x:
		return global_position.y + DECK_HEIGHT

	return NAN


func _physics_process(delta: float) -> void:
	if alive:
		var fwd := -global_transform.basis.z.normalized()
		global_position += fwd * (SPEED_MS * delta)
		reset_physics_interpolation()


func _build_carrier_mesh() -> void:
	# Materials
	var mat_hull := StandardMaterial3D.new()
	mat_hull.albedo_color = Color(0.42, 0.45, 0.48) # haze grey
	mat_hull.roughness = 0.7

	var mat_deck := StandardMaterial3D.new()
	mat_deck.albedo_color = Color(0.18, 0.20, 0.22) # dark non-skid
	mat_deck.roughness = 0.85

	var mat_markings_white := StandardMaterial3D.new()
	mat_markings_white.albedo_color = Color(0.92, 0.92, 0.90)
	mat_markings_white.roughness = 0.6

	var mat_markings_yellow := StandardMaterial3D.new()
	mat_markings_yellow.albedo_color = Color(0.95, 0.78, 0.15)
	mat_markings_yellow.roughness = 0.6

	var mat_markings_red := StandardMaterial3D.new()
	mat_markings_red.albedo_color = Color(0.85, 0.22, 0.20)
	mat_markings_red.roughness = 0.6

	var mat_island := StandardMaterial3D.new()
	mat_island.albedo_color = Color(0.48, 0.50, 0.52)
	mat_island.roughness = 0.6

	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.1, 0.22, 0.28)
	mat_glass.metallic = 0.7
	mat_glass.roughness = 0.2

	# 1. Main Hull
	var hull := MeshInstance3D.new()
	var hull_box := BoxMesh.new()
	hull_box.size = Vector3(40.0, 18.0, 310.0)
	hull.mesh = hull_box
	hull.material_override = mat_hull
	hull.position = Vector3(0.0, 9.0, 0.0)
	add_child(hull)

	# Bow wedge
	var bow := MeshInstance3D.new()
	var bow_prism := PrismMesh.new()
	bow_prism.size = Vector3(40.0, 18.0, 25.0)
	bow.mesh = bow_prism
	bow.material_override = mat_hull
	bow.rotation.x = -PI * 0.5
	bow.position = Vector3(0.0, 9.0, -165.0)
	add_child(bow)

	# 2. Flight Deck
	_deck_node = Node3D.new()
	_deck_node.position = Vector3(0.0, DECK_HEIGHT, 0.0)
	add_child(_deck_node)

	var deck := MeshInstance3D.new()
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(76.0, 1.5, 330.0)
	deck.mesh = deck_box
	deck.material_override = mat_deck
	deck.position = Vector3(0.0, -0.75, 0.0)
	_deck_node.add_child(deck)

	# Angled Deck Sponsor (overhang on port side)
	var sponsor := MeshInstance3D.new()
	var sp_box := BoxMesh.new()
	sp_box.size = Vector3(18.0, 1.5, 230.0)
	sponsor.mesh = sp_box
	sponsor.material_override = mat_deck
	sponsor.position = Vector3(-35.0, -0.75, 20.0)
	_deck_node.add_child(sponsor)

	# 3. Flight Deck Markings
	# Angled landing strip: centerline (dashed white & yellow)
	var strip_len := 235.0
	var strip_node := Node3D.new()
	strip_node.position = Vector3(-6.0, 0.02, 30.0)
	strip_node.rotation.y = ANGLED_DECK_ANGLE_RAD
	_deck_node.add_child(strip_node)

	# Centerline dashes along angled deck
	for k in range(16):
		var dash := MeshInstance3D.new()
		var dash_quad := QuadMesh.new()
		dash_quad.size = Vector2(0.9, 8.0)
		dash.mesh = dash_quad
		dash.material_override = mat_markings_yellow if (k % 2 == 0) else mat_markings_white
		dash.rotation.x = -PI * 0.5
		dash.position = Vector3(0.0, 0.01, -strip_len * 0.5 + float(k) * 14.0)
		strip_node.add_child(dash)

	# Foul lines (red & white boundary of landing strip)
	for side in [-1.0, 1.0]:
		var foul := MeshInstance3D.new()
		var foul_quad := QuadMesh.new()
		foul_quad.size = Vector2(0.4, strip_len)
		foul.mesh = foul_quad
		foul.material_override = mat_markings_red
		foul.rotation.x = -PI * 0.5
		foul.position = Vector3(side * 12.5, 0.01, 0.0)
		strip_node.add_child(foul)

	# Bow Catapults 1 & 2 (yellow tramlines)
	for x_offset in [8.0, -8.0]:
		var cat_line := MeshInstance3D.new()
		var cq := QuadMesh.new()
		cq.size = Vector2(0.4, 90.0)
		cat_line.mesh = cq
		cat_line.material_override = mat_markings_yellow
		cat_line.rotation.x = -PI * 0.5
		cat_line.position = Vector3(x_offset, 0.02, -115.0)
		_deck_node.add_child(cat_line)

	# Hull designator "78" on the bow
	var bow_num := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(16.0, 16.0)
	bow_num.mesh = bq
	bow_num.material_override = mat_markings_white
	bow_num.rotation.x = -PI * 0.5
	bow_num.position = Vector3(0.0, 0.02, -152.0)
	_deck_node.add_child(bow_num)

	# 4. Island Superstructure (starboard side)
	var island := Node3D.new()
	island.position = Vector3(29.0, 0.0, -10.0)
	_deck_node.add_child(island)

	var island_body := MeshInstance3D.new()
	var ib_mesh := BoxMesh.new()
	ib_mesh.size = Vector3(9.0, 18.0, 34.0)
	island_body.mesh = ib_mesh
	island_body.material_override = mat_island
	island_body.position = Vector3(0.0, 9.0, 0.0)
	island.add_child(island_body)

	# Pri-Fly observation cab overlooking flight deck
	var prifly := MeshInstance3D.new()
	var pf_mesh := BoxMesh.new()
	pf_mesh.size = Vector3(4.5, 3.5, 12.0)
	prifly.mesh = pf_mesh
	prifly.material_override = mat_glass
	prifly.position = Vector3(-4.0, 16.5, 6.0)
	island.add_child(prifly)

	# Radar Masts & Antennas
	var mast := MeshInstance3D.new()
	var m_cyl := CylinderMesh.new()
	m_cyl.top_radius = 0.6
	m_cyl.bottom_radius = 1.0
	m_cyl.height = 16.0
	mast.mesh = m_cyl
	mast.material_override = mat_island
	mast.position = Vector3(0.0, 26.0, -6.0)
	island.add_child(mast)

	# Radar dome
	var radome := MeshInstance3D.new()
	var r_sphere := SphereMesh.new()
	r_sphere.radius = 2.2
	r_sphere.height = 3.6
	radome.mesh = r_sphere
	radome.material_override = mat_markings_white
	radome.position = Vector3(0.0, 21.0, 8.0)
	island.add_child(radome)

	# 5. Aircraft Elevators (4 platforms: 3 starboard, 1 port)
	for el_pos in [Vector3(39.0, -0.6, -60.0), Vector3(39.0, -0.6, 35.0), Vector3(39.0, -0.6, 75.0), Vector3(-39.0, -0.6, 75.0)]:
		var el := MeshInstance3D.new()
		var el_mesh := BoxMesh.new()
		el_mesh.size = Vector3(14.0, 1.2, 24.0)
		el.mesh = el_mesh
		el.material_override = mat_hull
		el.position = el_pos
		_deck_node.add_child(el)


func _setup_catapults_and_wires() -> void:
	# Arresting wires (4 wires across recovery path near stern)
	# Recovery strip center is at (-6, DECK_HEIGHT, 30), heading ANGLED_DECK_ANGLE_RAD
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.1, 0.1, 0.1)
	wire_mat.metallic = 0.9
	wire_mat.roughness = 0.3

	_wires_local.clear()
	for i in range(4):
		# Spaced ~12m apart starting from stern of landing strip
		var wire_z_strip := 65.0 + float(i) * 12.0
		var wire_pos_rel := Vector3(0.0, 0.15, wire_z_strip).rotated(Vector3.UP, ANGLED_DECK_ANGLE_RAD)
		var wire_pos := Vector3(-6.0, DECK_HEIGHT, 30.0) + wire_pos_rel
		_wires_local.append(wire_pos)

		var wire_mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = 24.0
		wire_mesh.mesh = cyl
		wire_mesh.material_override = wire_mat
		wire_mesh.rotation.y = ANGLED_DECK_ANGLE_RAD + PI * 0.5
		wire_mesh.rotation.z = PI * 0.5
		wire_mesh.position = wire_pos
		add_child(wire_mesh)

	# Catapults: 2 on bow (Cat 1, Cat 2), 2 on waist (Cat 3, Cat 4)
	_cats_local = [
		{
			"name": "Cat 1",
			"local_pos": Vector3(8.0, DECK_HEIGHT + 0.1, -70.0),
			"heading_offset": 0.0,
			"length": 90.0
		},
		{
			"name": "Cat 2",
			"local_pos": Vector3(-8.0, DECK_HEIGHT + 0.1, -70.0),
			"heading_offset": 0.0,
			"length": 90.0
		},
		{
			"name": "Cat 3",
			"local_pos": Vector3(-18.0, DECK_HEIGHT + 0.1, -15.0),
			"heading_offset": rad_to_deg(ANGLED_DECK_ANGLE_RAD),
			"length": 85.0
		},
		{
			"name": "Cat 4",
			"local_pos": Vector3(-28.0, DECK_HEIGHT + 0.1, -10.0),
			"heading_offset": rad_to_deg(ANGLED_DECK_ANGLE_RAD),
			"length": 85.0
		}
	]


func _setup_hitbox() -> void:
	_hitbox = Hitbox.new()
	_hitbox.target = self
	_hitbox.collision_layer = 1 << 2 # layer 3: ground units / ships

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(76.0, 24.0, 332.0)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, 12.0, 0.0)
	_hitbox.add_child(col_shape)
	add_child(_hitbox)
