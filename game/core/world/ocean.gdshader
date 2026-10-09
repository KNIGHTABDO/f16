shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Sea-level geometry clipmap (same ring scheme as terrain.gdshader; the finer ring's window is left out of
// the mesh on the CPU) with vertical sine waves near the camera.
uniform float u_cell = 8.0;
uniform float u_half = 128.0;
uniform vec2 u_centre = vec2(0.0);
uniform float u_morph_band = 0.4;
uniform vec3 u_cam = vec3(0.0);
uniform float u_sea = 0.0;

uniform float u_wave_amp = 1.0;
uniform float u_wave_fade0 = 1500.0;
uniform float u_wave_fade1 = 3200.0;

// Terrain height for water depth (same R16 grid and mapping as terrain.gdshader).
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float u_map_size = 256000.0;
uniform float u_height_n = 4096.0;
uniform float u_hmin = -200.0;
uniform float u_hmax = 3200.0;

uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 u_deep = vec3(0.006, 0.040, 0.085);
uniform vec3 u_shallow = vec3(0.05, 0.36, 0.34);

uniform vec3 u_haze_color = vec3(0.62, 0.74, 0.86);
uniform float u_haze_density = 0.0000167;
uniform float u_haze_scale = 2500.0;

varying vec2 v_world;

float terrain_base(vec2 w) {
	vec2 uv = w / u_map_size + 0.5;
	vec2 tc = (uv * (u_height_n - 1.0) + 0.5) / u_height_n;
	return u_hmin + textureLod(height_tex, tc, 0.0).r * (u_hmax - u_hmin);
}

// One deep-water-dispersion sine wave: height and horizontal gradient.
void add_wave(vec2 p, vec2 dir, float lambda, float amp, inout float h, inout vec2 g) {
	float k = 6.2831853 / lambda;
	float ph = k * dot(dir, p) + sqrt(9.81 * k) * TIME;
	h += amp * sin(ph);
	g += amp * k * cos(ph) * dir;
}

// Four waves, from swell (170 m) down to short chop (38 m). Heights in metres, gradient dh/dx, dh/dz.
void sea_waves(vec2 p, out float h, out vec2 g) {
	h = 0.0;
	g = vec2(0.0);
	add_wave(p, normalize(vec2(0.92, 0.39)), 170.0, 0.90 * u_wave_amp, h, g);
	add_wave(p, normalize(vec2(0.55, -0.83)), 110.0, 0.50 * u_wave_amp, h, g);
	add_wave(p, normalize(vec2(-0.30, 0.95)), 64.0, 0.22 * u_wave_amp, h, g);
	add_wave(p, normalize(vec2(0.80, -0.60)), 38.0, 0.09 * u_wave_amp, h, g);
}

float wave_fade(vec2 w) {
	return 1.0 - smoothstep(u_wave_fade0, u_wave_fade1, distance(w, u_cam.xz));
}

void vertex() {
	vec2 g = VERTEX.xz;
	vec2 local = g * u_cell;

	// Morph the outer band onto the coarser lattice, as in terrain.gdshader.
	vec2 par = mod(g, 2.0);
	float edge = max(abs(local.x), abs(local.y)) / u_half;
	float m = smoothstep(1.0 - u_morph_band, 1.0, edge);

	vec2 w = u_centre + local;
	float h;
	vec2 gr;
	sea_waves(w, h, gr);
	float y = h * wave_fade(w);
	vec2 pos = local;
	if (m > 0.0 && (par.x + par.y) > 0.5) {
		vec2 lc = local - par * u_cell;
		float hc;
		vec2 gc;
		sea_waves(u_centre + lc, hc, gc);
		float yc = hc * wave_fade(u_centre + lc);
		y = mix(y, yc, m);
		pos = mix(local, lc, m);
	}

	VERTEX = vec3(pos.x, u_sea + y, pos.y);
	v_world = u_centre + pos;
}

void fragment() {
	vec2 w = v_world;
	float dist = length(vec3(w.x, u_sea, w.y) - u_cam);

	// Water depth from the terrain (positive where the sea floor is below sea level).
	float depth = u_sea - terrain_base(w);

	// Wave normal from the analytic gradient, faded with distance like the vertices.
	float hw;
	vec2 gw;
	sea_waves(w, hw, gw);
	float fade = wave_fade(w);
	vec2 grad = gw * fade;

	// Two scrolling normal maps at different scales, the second rotated against the first.
	vec2 t = TIME * vec2(0.010, 0.006);
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 n1 = texture(normal_tex, w / 56.0 + t).xy * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, rot * w / 23.0 - t * 1.3).xy * 2.0 - 1.0;
	vec2 ripple = (n1 + n2) * 0.5 * 0.35;
	vec3 n = normalize(vec3(-grad.x - ripple.x, 1.0, -grad.y - ripple.y));

	// Colour: turquoise over the shelf, deep blue offshore.
	float shelf = 1.0 - exp(-max(depth, 0.0) / 9.0);
	vec3 col = mix(u_shallow, u_deep, shelf);

	// Foam on the shoreline and on steep crests.
	float fn = texture(foam_tex, w / 18.0 + t * 2.0).r;
	float shore = 1.0 - smoothstep(0.0, 1.8, depth);
	float crest = smoothstep(0.10, 0.45, length(grad));
	float foam = max(shore * smoothstep(0.30, 0.62, fn + 0.12), crest * smoothstep(0.50, 0.72, fn));
	foam = clamp(foam, 0.0, 1.0);
	col = mix(col, vec3(0.80, 0.86, 0.88), foam * 0.85);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.035, 0.85, foam);
	SPECULAR = 0.5;
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	// Aerial perspective, as on the land (the sea surface is at sea level).
	float haze = 1.0 - exp(-dist * u_haze_density);
	// Beyond the map edge the terrain is clamped (no data), so fade the sea there to the horizon tone too.
	haze = max(haze, smoothstep(0.0, 6000.0, max(abs(w.x), abs(w.y)) - 0.5 * u_map_size));
	ALBEDO *= (1.0 - haze);
	EMISSION = u_haze_color * haze;
	// Distant sea would otherwise mirror the bright sky at grazing angles on top of the haze.
	SPECULAR *= 1.0 - haze;
}
