class_name WorldBuilder
extends RefCounted
## World builder: assembles terrain, ocean, sky, clouds, weather, vegetation,
## cities, airbases, and carrier for a map in a single call.
##
## API:
##   WorldBuilder.build(world, map_id, time_of_day, weather, camera) -> Dictionary
##   WorldBuilder.update(delta)

static var _instance_data: Dictionary = {}
static var _camera_ref: Camera3D = null


static func build(world: Node3D, map_id: String, time_of_day: String, weather_name: String, camera: Camera3D) -> Dictionary:
	_camera_ref = camera
	if not Ground.is_loaded() or Ground.map_id != map_id:
		if not Ground.load_map(map_id):
			push_error("WorldBuilder: failed to load map '%s'" % map_id)
			return {}

	var preset := "balanced"
	if Settings != null and "graphics_preset" in Settings:
		preset = Settings.graphics_preset

	# 1. WorldEnvironment and Sun
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	world.add_child(sun)

	# 2. Procedural Sky
	var sky := WorldSky.new()
	sky.name = "Sky"
	world.add_child(sky)
	sky.setup(world_env, sun, preset)
	sky.set_conditions(WorldSky.hours_for(time_of_day), weather_name)

	# 3. Weather (rain, gusts, lightning)
	var weather := Weather.new()
	weather.name = "Weather"
	world.add_child(weather)
	weather.setup(camera, preset)
	weather.set_state(weather_name)

	# 4. Terrain
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	terrain.haze_color = sky.horizon_color()
	terrain.haze_density = sky.haze_density()
	terrain.set_camera(camera)
	terrain.apply_quality(preset)
	world.add_child(terrain)
	terrain.setup(map_id)

	# 5. Ocean
	var ocean := Ocean.new()
	ocean.name = "Ocean"
	ocean.haze_color = sky.horizon_color()
	ocean.haze_density = sky.haze_density()
	ocean.set_camera(camera)
	ocean.apply_quality(preset)
	world.add_child(ocean)
	ocean.setup(map_id, terrain)

	# 6. Clouds
	var clouds := Clouds.new()
	clouds.name = "Clouds"
	world.add_child(clouds)
	clouds.setup(preset)
	var storm_dark := 0.85 if weather_name == "storm" else 0.0
	clouds.set_cover(sky.cloud_cover(), storm_dark)

	# 7. Airbases
	var airbases_list: Array = []
	var avoid_rects: Array[Rect2] = []
	var airports_data: Array = Ground.meta.get("airports", [])
	for i in airports_data.size():
		var ap: Dictionary = airports_data[i]
		var airbase := Airbase.new()
		var icao: String = ap.get("icao", "BASE%02d" % i)
		airbase.name = icao
		# Tangier (GMTT) or Jerez (LEJR) or index 0 is main base (team 0)
		var is_main := (icao == "GMTT" or i == 0)
		airbase.setup(ap, is_main)
		world.add_child(airbase)
		airbases_list.append(airbase)
		avoid_rects.append(airbase.get_avoid_rect())
		airbase.set_night(sky.night)

	# 8. Vegetation
	var vegetation := Vegetation.new()
	vegetation.name = "Vegetation"
	world.add_child(vegetation)
	vegetation.setup(preset, avoid_rects)

	# 9. Cities
	var cities := Cities.new()
	cities.name = "Cities"
	world.add_child(cities)
	cities.setup(Ground.meta.get("places", []), preset, avoid_rects)
	cities.set_night(sky.night)

	# 10. Carrier
	var carrier := Carrier.new()
	carrier.name = "Carrier"
	var carrier_pos := Vector3(-45000.0, 0.0, 5000.0)
	var meta_carrier = Ground.meta.get("carrier", null)
	if meta_carrier is Dictionary:
		carrier_pos = Vector3(float(meta_carrier.get("x", -45000.0)), 0.0, float(meta_carrier.get("z", 5000.0)))
	elif map_id != "gibraltar":
		carrier_pos = Vector3(-15000.0, 0.0, -10000.0)
	carrier.setup(carrier_pos, 280.0)
	world.add_child(carrier)

	_instance_data = {
		"terrain": terrain,
		"ocean": ocean,
		"sky": sky,
		"clouds": clouds,
		"environment": world_env,
		"sun": sun,
		"airbases": airbases_list,
		"carrier": carrier,
		"weather": weather,
		"vegetation": vegetation,
		"cities": cities
	}

	# Prime first update tick
	update(0.016)

	return _instance_data


static func update(delta: float) -> void:
	if _instance_data.is_empty() or _camera_ref == null or not is_instance_valid(_camera_ref):
		return

	var cam_pos: Vector3 = _camera_ref.global_position
	var cam_world := WorldOrigin.to_world(cam_pos)

	var weather: Weather = _instance_data.get("weather", null)
	var sky: WorldSky = _instance_data.get("sky", null)
	var clouds: Clouds = _instance_data.get("clouds", null)
	var terrain: Terrain = _instance_data.get("terrain", null)
	var ocean: Ocean = _instance_data.get("ocean", null)
	var vegetation: Vegetation = _instance_data.get("vegetation", null)
	var cities: Cities = _instance_data.get("cities", null)
	var airbases: Array = _instance_data.get("airbases", [])

	if weather != null and is_instance_valid(weather):
		weather.update(delta)
		if sky != null and is_instance_valid(sky):
			sky.set_flash(weather.flash_level())

	if clouds != null and is_instance_valid(clouds) and sky != null and is_instance_valid(sky):
		sky.set_inside_cloud(clouds.inside_factor())
		var sun_dir := sky.sun_dir
		var sun_col := sky.sun.light_color * sky.sun.light_energy
		var shade_col := sky.horizon_color()
		clouds.update(delta, cam_world, sun_dir, sun_col, shade_col)

	if terrain != null and is_instance_valid(terrain) and sky != null and is_instance_valid(sky):
		terrain.haze_color = sky.horizon_color()
		terrain.haze_density = sky.haze_density()

	if ocean != null and is_instance_valid(ocean) and sky != null and is_instance_valid(sky):
		ocean.haze_color = sky.horizon_color()
		ocean.haze_density = sky.haze_density()

	if vegetation != null and is_instance_valid(vegetation):
		vegetation.update(delta, cam_world)

	if cities != null and is_instance_valid(cities) and sky != null and is_instance_valid(sky):
		cities.update(delta, cam_world)
		cities.set_night(sky.night)

	if sky != null and is_instance_valid(sky):
		for ab in airbases:
			if ab != null and is_instance_valid(ab) and ab.has_method("set_night"):
				ab.set_night(sky.night)
