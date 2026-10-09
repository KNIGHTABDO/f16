class_name WorldSky
extends Node
## Time of day, weather, Environment, sun light and horizon colour for the world.
##
## The sky dome is sky.gdshader (single-scattering Rayleigh + Mie). scatter() below is its CPU mirror, so the
## horizon colour handed to Terrain and Ocean (aerial perspective) matches the sky. Keep the constants in sync.
## Units: Godot axes (+X east, +Y up, -Z north). Directions point towards the sun or moon.

const SKY_SHADER := preload("res://core/world/sky.gdshader")
const LATITUDE_DEG := 35.8  # Strait of Gibraltar
const DECLINATION_DEG := 21.0  # sun declination, a summer sky
const SUN_ENERGY := 40.0  # sky scattering irradiance, same value as the shader default
const MOON_ENERGY := 1.2  # moon scattering irradiance at full night
const HAZE_DENSITY := 0.0000167  # per metre at sea level, clear weather (matches Terrain/Ocean defaults)
const NIGHT_START := -0.02  # sin(sun elevation) where night begins to fade in
const NIGHT_FULL := -0.12  # sin(sun elevation) at full night
const FOG_INSIDE_DENSITY := 0.02  # white-out density while the camera is inside a cloud
const FOG_INSIDE_COLOR := Color(0.82, 0.84, 0.87)
const BETA_R := Vector3(0.0058, 0.0135, 0.0331)  # Rayleigh scattering per km at sea level
const H_R := 8.5  # Rayleigh scale height, km
const BETA_M := 0.0167  # Mie extinction per km, clear
const H_M := 1.2  # Mie scale height, km
const MIE_G := 0.8

const TIME_HOURS := {
	"dawn": 5.9, "morning": 8.5, "noon": 12.0, "afternoon": 15.5,
	"sunset": 18.7, "dusk": 19.4, "night": 23.0,
}
## turbidity: Mie multiplier; cover: cloud greying of the dome; haze: aerial haze density multiplier.
const WEATHER := {
	"clear": {"turb": 1.0, "cover": 0.0, "haze": 1.0},
	"scattered": {"turb": 1.1, "cover": 0.2, "haze": 1.2},
	"overcast": {"turb": 1.5, "cover": 0.9, "haze": 1.8},
	"storm": {"turb": 1.8, "cover": 1.0, "haze": 2.6},
	"haze": {"turb": 3.0, "cover": 0.25, "haze": 4.5},
}
const PRESETS := {
	"low": {"shadows": false, "shadow_dist": 0.0, "glow": false, "radiance": Sky.RADIANCE_SIZE_128},
	"balanced": {"shadows": true, "shadow_dist": 1500.0, "glow": true, "radiance": Sky.RADIANCE_SIZE_256},
	"high": {"shadows": true, "shadow_dist": 2500.0, "glow": true, "radiance": Sky.RADIANCE_SIZE_256},
	"ultra": {"shadows": true, "shadow_dist": 3000.0, "glow": true, "radiance": Sky.RADIANCE_SIZE_256},
}

var env: Environment
var sun: DirectionalLight3D
var hours := 14.0
var weather := "clear"
var sun_dir := Vector3(0.0, 0.8, 0.5)  # towards the sun
var moon_dir := Vector3(0.0, 0.5, -0.5)  # towards the moon
var night := 0.0  # 0 day .. 1 full night
var flash := 0.0  # lightning brightening, 0..1, set by Weather
var inside_cloud := 0.0  # 0..1, white-out while inside a cloud, set by Clouds
var _sky: Sky
var _mat: ShaderMaterial
var _preset := "balanced"
var _shadows_on := true
var _horizon := Color(0.62, 0.74, 0.86)  # linear radiance at the horizon


## Creates the Sky, Environment and shader material and configures the sun light. Call once.
func setup(world_env: WorldEnvironment, sun_light: DirectionalLight3D, preset: String) -> void:
	sun = sun_light
	_mat = ShaderMaterial.new()
	_mat.shader = SKY_SHADER
	_sky = Sky.new()
	_sky.sky_material = _mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0  # the dome itself is not hazed; distant geometry is (terrain shader + fog)
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	world_env.environment = env
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	set_quality(preset)
	set_conditions(hours, weather)


## Shadow distance, glow and radiance resolution by preset ("low", "balanced", "high", "ultra").
func set_quality(preset: String) -> void:
	_preset = preset if PRESETS.has(preset) else "balanced"
	var cfg: Dictionary = PRESETS[_preset]
	_shadows_on = bool(cfg["shadows"])
	sun.shadow_enabled = _shadows_on
	sun.directional_shadow_max_distance = float(cfg["shadow_dist"])
	env.glow_enabled = bool(cfg["glow"])
	_sky.radiance_size = int(cfg["radiance"])
	_sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_apply()


## Sets the time of day (hours, 0..24, local solar time) and weather name. Recomputes everything.
func set_conditions(h: float, weather_name: String) -> void:
	hours = fposmod(h, 24.0)
	weather = weather_name if WEATHER.has(weather_name) else "clear"
	var hour_angle := deg_to_rad((hours - 12.0) * 15.0)
	var lat := deg_to_rad(LATITUDE_DEG)
	var dec := deg_to_rad(DECLINATION_DEG)
	var sin_alt := sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hour_angle)
	# Horizontal components of the equatorial-to-horizontal transform, in Godot axes (x east, z = -north).
	sun_dir = Vector3(-cos(dec) * sin(hour_angle), sin_alt, sin(lat) * cos(dec) * cos(hour_angle) - cos(lat) * sin(dec)).normalized()
	moon_dir = Vector3(-sun_dir.x, maxf(0.3, -sun_dir.y), -sun_dir.z).normalized()
	night = clampf((-sun_dir.y + NIGHT_START) / (NIGHT_START - NIGHT_FULL), 0.0, 1.0)
	_apply()


## Lightning and cloud white-out, both 0..1. Cheap: only touches the Environment.
func set_flash(k: float) -> void:
	flash = clampf(k, 0.0, 1.0)
	_apply_environment()


func set_inside_cloud(k: float) -> void:
	inside_cloud = clampf(k, 0.0, 1.0)
	_apply_environment()


## Linear sky radiance at the horizon, averaged over azimuth. Terrain and Ocean take it as sRGB (use linear_to_srgb()).
func horizon_color() -> Color:
	return _horizon


func haze_density() -> float:
	return HAZE_DENSITY * haze_multiplier()


func haze_multiplier() -> float:
	return float(WEATHER[weather]["haze"])


func cloud_cover() -> float:
	return float(WEATHER[weather]["cover"])


func turbidity() -> float:
	return float(WEATHER[weather]["turb"])


func is_day() -> bool:
	return sun_dir.y > 0.0


## Time name ("noon", "sunset", ...) or a numeric string of hours, to hours.
static func hours_for(time_name: String) -> float:
	if TIME_HOURS.has(time_name):
		return float(TIME_HOURS[time_name])
	if time_name.is_valid_float():
		return time_name.to_float()
	push_warning("WorldSky: unknown time of day '%s', using noon" % time_name)
	return 12.0


## Single-scattering radiance towards v (unit, world) for sun direction l. Mirrors sky.gdshader scatter().
static func scatter(v: Vector3, l: Vector3, energy: float, turb: float) -> Vector3:
	var vy := maxf(v.y, 0.002)
	var mu := v.dot(l)
	var mv := _airmass(vy)
	var ms := _airmass(l.y)
	var a_r := BETA_R * (H_R * mv)
	var c_r := BETA_R * (H_R * ms)
	var i_r := _vexp(-a_r) * (H_R * mv) * _vg(c_r - a_r)
	var bm := BETA_M * turb
	var a_m := bm * H_M * mv
	var c_m := bm * H_M * ms
	var i_m := H_M * mv * exp(-a_m) * _g1(c_m - a_m)
	var pr := 0.75 * (1.0 + mu * mu) / (4.0 * PI)
	var g2 := MIE_G * MIE_G
	var pm := 1.5 * (1.0 - g2) / (2.0 + g2) * (1.0 + mu * mu) / pow(1.0 + g2 - 2.0 * MIE_G * mu, 1.5) / (4.0 * PI)
	return energy * (BETA_R * pr * i_r + Vector3.ONE * (bm * pm * i_m))


static func _airmass(sin_elev: float) -> float:
	if sin_elev <= 0.0:
		return 40.0
	var e := rad_to_deg(asin(minf(sin_elev, 1.0)))
	return 1.0 / (sin_elev + 0.50572 * pow(e + 6.07995, -1.6364))


static func _g1(d: float) -> float:
	if absf(d) < 1e-4:
		return 1.0
	return (1.0 - exp(-d)) / d


static func _vg(d: Vector3) -> Vector3:
	return Vector3(_g1(d.x), _g1(d.y), _g1(d.z))


static func _vexp(d: Vector3) -> Vector3:
	return Vector3(exp(d.x), exp(d.y), exp(d.z))


func _apply() -> void:
	var turb := turbidity()
	var cover := cloud_cover()
	_mat.set_shader_parameter("sun_dir", sun_dir)
	_mat.set_shader_parameter("sun_color", Vector3.ONE)
	_mat.set_shader_parameter("sun_energy", SUN_ENERGY)
	_mat.set_shader_parameter("moon_dir", moon_dir)
	_mat.set_shader_parameter("moon_energy", MOON_ENERGY * night)
	_mat.set_shader_parameter("night", night)
	_mat.set_shader_parameter("turbidity", turb)
	_mat.set_shader_parameter("cloud_cover", cover)
	_horizon = _horizon_radiance(turb, cover)
	_mat.set_shader_parameter("ground_tint", Vector3(_horizon.r, _horizon.g, _horizon.b) * 0.35)

	# Sun light: colour from the transmittance of the air it shines through; dims under cloud and at dusk.
	var ms := _airmass(sun_dir.y)
	var tr := _vexp(-(BETA_R * (H_R * ms) + Vector3.ONE * (BETA_M * turb * H_M * ms)))
	var tmax := maxf(tr.x, maxf(tr.y, tr.z))
	var tint := (tr / tmax).lerp(Vector3.ONE, 0.5)
	sun.light_color = Color(tint.x, tint.y, tint.z)
	sun.light_energy = clampf(sun_dir.y * 4.0, 0.0, 1.0) * 1.1 * (1.0 - 0.55 * cover)
	sun.shadow_enabled = _shadows_on and sun_dir.y > 0.01
	var up := Vector3.UP if absf(sun_dir.y) < 0.98 else Vector3.FORWARD
	sun.basis = Basis.looking_at(-sun_dir, up)

	_apply_environment()


func _apply_environment() -> void:
	var haze := HAZE_DENSITY * haze_multiplier()
	var base := _horizon
	env.fog_density = lerpf(haze, FOG_INSIDE_DENSITY, inside_cloud)
	env.fog_light_color = base.lerp(FOG_INSIDE_COLOR, inside_cloud)
	# Ambient keeps a floor at night (dark blue from the moon and stars) and rises with lightning.
	env.ambient_light_energy = 1.0 + 0.6 * night + 2.0 * flash
	env.tonemap_exposure = 1.0 + 0.6 * flash


## Horizon radiance: the day and moon scattering averaged over eight azimuths at a shallow elevation.
func _horizon_radiance(turb: float, cover: float) -> Color:
	var sum := Vector3.ZERO
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		var v := Vector3(cos(a), 0.02, sin(a)).normalized()
		var col := scatter(v, sun_dir, SUN_ENERGY, turb)
		if night > 0.0:
			col += scatter(v, moon_dir, MOON_ENERGY * night, turb) * Vector3(0.75, 0.85, 1.0)
		var lum := col.dot(Vector3(0.2126, 0.7152, 0.0722))
		col = col.lerp(Vector3(lum * 0.98, lum * 1.0, lum * 1.04), cover * 0.6)
		sum += col
	sum /= 8.0
	return Color(sum.x, sum.y, sum.z)
