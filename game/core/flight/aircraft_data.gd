class_name AircraftData
extends RefCounted
## Typed view of data/aircraft/<id>.json. Use AircraftData.load_id("f16c"); results are cached.
## Keys not typed here stay reachable through `raw`.

const DATA_DIR := "res://data/aircraft/"
const GRAVITY := 9.81

static var _cache: Dictionary = {}

var raw: Dictionary = {}
var id := ""
var display_name := ""
var short_name := ""
var category := ""
var nation := ""
var era := ""
var description := ""

# Visual
var model := ""
var model_scale := 1.0
var model_rotation_deg := Vector3.ZERO
var model_offset := Vector3.ZERO
var cockpit_eye := Vector3(0.0, 1.05, -4.6)
var chase_distance := 17.0
var chase_height := 3.5
var engine_sound := ""

# Geometry (meters, square meters)
var length := 15.0
var wing_span := 10.0
var wing_area := 27.87
var hit_radius := 6.0

# Mass and propulsion
var mass_empty := 8500.0  # kg
var mass_fuel := 3000.0  # kg, full tanks
var fuel_burn_dry := 0.9  # kg/s at full dry thrust
var fuel_burn_ab := 4.5  # kg/s at full afterburner
var engine := "jet"  # "jet" or "prop"
var thrust_dry := 76000.0  # N, sea level, military power
var thrust_ab := 127000.0  # N, sea level, full afterburner
var thrust_altitude_lapse := 0.75  # thrust scales with (rho / rho0) ^ lapse
var engine_spool_s := 3.0  # seconds, idle to full
var prop_power_kw := 0.0
var prop_efficiency := 0.0
var has_afterburner := true

# Aerodynamics
var cl0 := 0.05
var cl_alpha := 4.4  # per radian
var cl_max := 1.55
var alpha_stall_deg := 26.0
var cd0 := 0.0175
var induced_k := 0.13
var cd_wave_mach := 0.92
var cd_wave_max := 0.028
var cd_gear := 0.02
var cd_airbrake := 0.06
var side_force := 1.2  # side force coefficient per radian of sideslip
var stability := 1.0

# Limits and handling
var max_g := 9.0
var min_g := -3.0
var max_aoa_deg := 25.0
var roll_rate_deg := 280.0
var pitch_rate_deg := 26.0
var yaw_rate_deg := 10.0
var control_response := 6.0  # 1/s, how fast body rates follow commands
var fly_by_wire := true
var max_speed_kmh := 2120.0
var vne_kmh := 2400.0
var stall_speed_kmh := 230.0
var takeoff_speed_kmh := 280.0
var landing_speed_kmh := 260.0
var service_ceiling_m := 15240.0
var has_gear := true
var has_hook := false

# Combat
var health := 100.0
var gun_weapon := ""
var gun_ammo := 0
var gun_muzzles: Array[Vector3] = []
var flares := 0
var hardpoints := 0
var default_loadout := ""
var loadouts: Dictionary = {}


## Loads and caches data/aircraft/<aircraft_id>.json. Returns null (and logs) if it cannot be read.
static func load_id(aircraft_id: String) -> AircraftData:
	if _cache.has(aircraft_id):
		return _cache[aircraft_id]
	var path := DATA_DIR + aircraft_id + ".json"
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("AircraftData: cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AircraftData: %s is not a JSON object" % path)
		return null
	var data := AircraftData.new()
	data._fill(parsed)
	_cache[aircraft_id] = data
	return data


## Loadout list ([{weapon, count}, ...]) by name; "" = default loadout.
func loadout(loadout_name: String) -> Array:
	var key := loadout_name if loadout_name != "" else default_loadout
	return loadouts.get(key, [])


func mass_full() -> float:
	return mass_empty + mass_fuel


func thrust_max() -> float:
	return thrust_ab if has_afterburner else thrust_dry


func stall_speed_ms() -> float:
	return stall_speed_kmh / 3.6


func takeoff_speed_ms() -> float:
	return takeoff_speed_kmh / 3.6


func landing_speed_ms() -> float:
	return landing_speed_kmh / 3.6


func max_speed_ms() -> float:
	return max_speed_kmh / 3.6


func alpha_stall_rad() -> float:
	return deg_to_rad(alpha_stall_deg)


func max_aoa_rad() -> float:
	return deg_to_rad(max_aoa_deg)


func pitch_rate_rad() -> float:
	return deg_to_rad(pitch_rate_deg)


func roll_rate_rad() -> float:
	return deg_to_rad(roll_rate_deg)


func yaw_rate_rad() -> float:
	return deg_to_rad(yaw_rate_deg)


func _fill(src: Dictionary) -> void:
	raw = src
	id = str(src.get("id", ""))
	display_name = str(src.get("name", id))
	short_name = str(src.get("short_name", display_name))
	category = str(src.get("category", ""))
	nation = str(src.get("nation", ""))
	era = str(src.get("era", ""))
	description = str(src.get("description", ""))

	model = str(src.get("model", ""))
	model_scale = float(src.get("model_scale", 1.0))
	model_rotation_deg = _v3(src.get("model_rotation_deg", [0, 0, 0]))
	model_offset = _v3(src.get("model_offset", [0, 0, 0]))
	cockpit_eye = _v3(src.get("cockpit_eye", [0, 1.05, -4.6]))
	chase_distance = float(src.get("chase_distance", 17.0))
	chase_height = float(src.get("chase_height", 3.5))
	engine_sound = str(src.get("engine_sound", ""))

	length = float(src.get("length", 15.0))
	wing_span = float(src.get("wing_span", 10.0))
	wing_area = float(src.get("wing_area", 27.87))
	hit_radius = float(src.get("hit_radius", 6.0))

	mass_empty = float(src.get("mass_empty", 8500.0))
	mass_fuel = float(src.get("mass_fuel", 3000.0))
	fuel_burn_dry = float(src.get("fuel_burn_dry", 0.9))
	fuel_burn_ab = float(src.get("fuel_burn_ab", 4.5))
	engine = str(src.get("engine", "jet"))
	thrust_dry = float(src.get("thrust_dry", 76000.0))
	thrust_ab = float(src.get("thrust_ab", 127000.0))
	thrust_altitude_lapse = float(src.get("thrust_altitude_lapse", 0.75))
	engine_spool_s = float(src.get("engine_spool_s", 3.0))
	prop_power_kw = float(src.get("prop_power_kw", 0.0))
	prop_efficiency = float(src.get("prop_efficiency", 0.0))
	has_afterburner = bool(src.get("has_afterburner", engine == "jet"))

	cl0 = float(src.get("cl0", 0.05))
	cl_alpha = float(src.get("cl_alpha", 4.4))
	cl_max = float(src.get("cl_max", 1.55))
	alpha_stall_deg = float(src.get("alpha_stall_deg", 26.0))
	cd0 = float(src.get("cd0", 0.0175))
	induced_k = float(src.get("induced_k", 0.13))
	cd_wave_mach = float(src.get("cd_wave_mach", 0.92))
	cd_wave_max = float(src.get("cd_wave_max", 0.028))
	cd_gear = float(src.get("cd_gear", 0.02))
	cd_airbrake = float(src.get("cd_airbrake", 0.06))
	side_force = float(src.get("side_force", 1.2))
	stability = float(src.get("stability", 1.0))

	max_g = float(src.get("max_g", 9.0))
	min_g = float(src.get("min_g", -3.0))
	max_aoa_deg = float(src.get("max_aoa_deg", 25.0))
	roll_rate_deg = float(src.get("roll_rate_deg", 280.0))
	pitch_rate_deg = float(src.get("pitch_rate_deg", 26.0))
	yaw_rate_deg = float(src.get("yaw_rate_deg", 10.0))
	control_response = float(src.get("control_response", 6.0))
	fly_by_wire = bool(src.get("fly_by_wire", true))
	max_speed_kmh = float(src.get("max_speed_kmh", 2120.0))
	vne_kmh = float(src.get("vne_kmh", 2400.0))
	stall_speed_kmh = float(src.get("stall_speed_kmh", 230.0))
	takeoff_speed_kmh = float(src.get("takeoff_speed_kmh", 280.0))
	landing_speed_kmh = float(src.get("landing_speed_kmh", 260.0))
	service_ceiling_m = float(src.get("service_ceiling_m", 15240.0))
	has_gear = bool(src.get("has_gear", true))
	has_hook = bool(src.get("has_hook", false))

	health = float(src.get("health", 100.0))
	var gun: Dictionary = src.get("gun", {})
	gun_weapon = str(gun.get("weapon", ""))
	gun_ammo = int(gun.get("ammo", 0))
	gun_muzzles.clear()
	for m in gun.get("muzzles", []):
		gun_muzzles.append(_v3(m))
	flares = int(src.get("flares", 0))
	hardpoints = int(src.get("hardpoints", 0))
	default_loadout = str(src.get("default_loadout", ""))
	loadouts = src.get("loadouts", {})


static func _v3(v: Variant) -> Vector3:
	if typeof(v) == TYPE_ARRAY and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
