class_name UnitFactory
extends RefCounted
## Factory for creating ground/sea combat units and static structures.
## UnitFactory.spawn(kind, team, local_pos, heading) -> CombatUnit

static func spawn(kind: String, team: int, local_pos: Vector3, heading: float = 0.0) -> CombatUnit:
	var unit: CombatUnit = null

	match kind:
		"tank", "apc", "truck", "fuel_truck":
			var gv := GroundVehicle.new()
			gv.setup_unit(kind, team)
			unit = gv

		"sam_sa6", "sam_sa2", "sam_sa15", "manpads":
			var sam := SamSite.new()
			sam.setup_sam(kind, team)
			unit = sam

		"aaa_zsu", "aaa_bofors":
			var aaa := AAA.new()
			aaa.setup_aaa(kind, team)
			unit = aaa

		"patrol_boat", "frigate", "cargo_ship":
			var ship := Ship.new()
			ship.setup_ship(kind, team)
			unit = ship

		"hangar", "shelter", "fuel_tank", "bunker", "tower", "ammo_dump", "comms", "radar", "bridge", "bridges":
			var st := Structure.new()
			st.setup_structure(kind, team)
			unit = st

		_:
			var def := GroundVehicle.new()
			def.setup_unit(kind, team)
			unit = def

	# Place on terrain or sea level
	var pos := local_pos
	if Ground.is_loaded():
		if unit is Ship:
			pos.y = Ground.sea_level
		elif kind != "bridge" and kind != "bridges":
			pos.y = Ground.surface_at(pos.x, pos.z)

	unit.position = pos
	unit.rotation.y = heading
	unit.name = "%s_%d" % [kind, team]

	return unit
