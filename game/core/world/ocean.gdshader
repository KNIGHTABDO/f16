shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// ==============================================================================
// Ocean Clipmap Shader - Atlantic & Mediterranean Coastal Polish
//
// Texture fetches (identical on every preset; the presets change the ring count and the wave count only):
// - Vertex:   0 fetches. Gerstner waves are analytic ALU: one wave set per vertex, two on the morph band.
// - Fragment: 4 fetches: 1 x height_tex (water depth, Lod 0), 2 x normal_tex (scrolling ripples), 1 x foam_tex.
// - Waves per preset: Low 1, Medium / Balanced 2, High / Ultra 4.
// (Optimized for Apple A15 / mobile tile-based GPUs at sustained 60 fps)
// ==============================================================================

// Sea-level geometry clipmap (same ring scheme as terrain.gdshader; the finer ring's window is left out of
// the mesh on the CPU) with Gerstner wave displacement near the camera.
uniform float u_cell = 8.0;
uniform float u_half = 128.0;
uniform vec2 u_centre = vec2(0.0);
uniform float u_morph_band = 0.4;
uniform vec3 u_cam = vec3(0.0);
uniform float u_sea = 0.0;

uniform float u_wave_amp = 1.0;
uniform float u_wave_count = 4.0;
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
uniform vec3 u_deep = vec3(0.004, 0.024, 0.075);      // Atlantic / Mediterranean deep blue
uniform vec3 u_shallow = vec3(0.025, 0.40, 0.38);    // Clear turquoise coastal shelf

uniform vec3 u_haze_color = vec3(0.62, 0.74, 0.86);
uniform float u_haze_density = 0.0000167;
uniform float u_haze_scale = 2500.0;

varying vec2 v_world;
varying vec3 v_world_pos;

float terrain_base(vec2 w) {
	vec2 uv = w / u_map_size + 0.5;
	vec2 tc = (uv * (u_height_n - 1.0) + 0.5) / u_height_n;
	return u_hmin + textureLod(height_tex, tc, 0.0).r * (u_hmax - u_hmin);
}

// Gerstner wave function: calculates horizontal displacement (dx, dz), height (h), and surface gradient (g)
void add_gerstner_wave(vec2 p, vec2 dir, float lambda, float amp, float steepness, inout vec2 d_xz, inout float h, inout vec2 g) {
	float k = 6.2831853 / lambda;
	float w_speed = sqrt(9.81 * k);
	float ph = k * dot(dir, p) + w_speed * TIME;
	float c = cos(ph);
	float s = sin(ph);
	float q = clamp(steepness / (k * max(amp, 0.001) * u_wave_count), 0.0, 0.65);

	d_xz -= q * amp * dir * s;
	h += amp * c;
	g += amp * k * dir * (-s);
}

// Four Gerstner waves from long Atlantic swell down to wind chop
void ocean_gerstner_waves(vec2 p, out vec2 d_xz, out float h, out vec2 g) {
	d_xz = vec2(0.0);
	h = 0.0;
	g = vec2(0.0);

	// Swell 1 (160 m wavelength, Atlantic swell)
	add_gerstner_wave(p, normalize(vec2(0.92, 0.39)), 160.0, 0.85 * u_wave_amp, 0.35, d_xz, h, g);

	if (u_wave_count > 1.5) {
		// Swell 2 (95 m wavelength, cross swell)
		add_gerstner_wave(p, normalize(vec2(0.55, -0.83)), 95.0, 0.45 * u_wave_amp, 0.30, d_xz, h, g);
	}
	if (u_wave_count > 2.5) {
		// Short chop 1 (48 m wavelength)
		add_gerstner_wave(p, normalize(vec2(-0.30, 0.95)), 48.0, 0.22 * u_wave_amp, 0.25, d_xz, h, g);
		// Short chop 2 (24 m wavelength)
		add_gerstner_wave(p, normalize(vec2(0.80, -0.60)), 24.0, 0.09 * u_wave_amp, 0.20, d_xz, h, g);
	}
}

float wave_fade(vec2 w) {
	return 1.0 - smoothstep(u_wave_fade0, u_wave_fade1, distance(w, u_cam.xz));
}

void vertex() {
	vec2 g = VERTEX.xz;
	vec2 local = g * u_cell;

	// Morph the outer band onto the coarser lattice, matching terrain ring joins
	vec2 par = mod(g, 2.0);
	float edge = max(abs(local.x), abs(local.y)) / u_half;
	float m = smoothstep(1.0 - u_morph_band, 1.0, edge);

	vec2 w = u_centre + local;
	float fade = wave_fade(w);

	vec2 d_xz;
	float h;
	vec2 gr;
	ocean_gerstner_waves(w, d_xz, h, gr);

	vec2 pos = local + d_xz * fade;
	float y = h * fade;

	if (m > 0.0 && (par.x + par.y) > 0.5) {
		vec2 lc = local - par * u_cell;
		vec2 w_coarse = u_centre + lc;
		float fade_c = wave_fade(w_coarse);
		vec2 d_c;
		float hc;
		vec2 gc;
		ocean_gerstner_waves(w_coarse, d_c, hc, gc);
		pos = mix(pos, lc + d_c * fade_c, m);
		y = mix(y, hc * fade_c, m);
	}

	VERTEX = vec3(pos.x, u_sea + y, pos.y);
	v_world = u_centre + pos;
	// World space, like u_cam. MODEL_MATRIX would give scene space, which is offset by WorldOrigin.offset.
	v_world_pos = vec3(v_world.x, u_sea + y, v_world.y);
}

void fragment() {
	vec2 w = v_world;
	float dist = length(v_world_pos - u_cam);

	// Water depth from terrain height (positive where sea floor is below sea level)
	float depth = max(u_sea - terrain_base(w), 0.0);

	// Wave normal from analytic Gerstner wave gradient, faded with distance
	vec2 d_xz;
	float hw;
	vec2 gw;
	ocean_gerstner_waves(w, d_xz, hw, gw);
	float fade = wave_fade(w);
	vec2 grad = gw * fade;

	// Two scrolling normal maps for high-frequency wind ripples
	vec2 t = TIME * vec2(0.010, 0.006);
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 n1 = texture(normal_tex, w / 52.0 + t).xy * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, rot * w / 22.0 - t * 1.3).xy * 2.0 - 1.0;
	vec2 ripple = (n1 + n2) * 0.5 * 0.32;
	vec3 n = normalize(vec3(-grad.x - ripple.x, 1.0, -grad.y - ripple.y));

	// View vector and Fresnel reflection factor
	vec3 view_dir = normalize(u_cam - v_world_pos);
	float n_dot_v = clamp(dot(n, view_dir), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - n_dot_v, 5.0);

	// Water color: turquoise over coastal shelf, deep Atlantic/Med blue offshore
	float shelf = 1.0 - exp(-depth / 10.0);
	vec3 col = mix(u_shallow, u_deep, shelf);

	// Subsurface scattering on wave crests
	float sss = smoothstep(0.0, 1.0, hw) * fade;
	col += vec3(0.015, 0.05, 0.06) * sss;

	// Foam on shoreline and wave crests
	float fn = texture(foam_tex, w / 16.0 + t * 1.8).r;
	float shore = 1.0 - smoothstep(0.0, 2.2, depth);
	float crest = smoothstep(0.12, 0.40, length(grad));
	float foam = max(shore * smoothstep(0.28, 0.62, fn + 0.16), crest * smoothstep(0.48, 0.72, fn));
	foam = clamp(foam, 0.0, 1.0);

	// Blend white sea foam
	col = mix(col, vec3(0.88, 0.92, 0.95), foam * 0.90);

	// Sky reflection on water surface
	vec3 reflect_dir = reflect(-view_dir, n);
	vec3 sky_ref = mix(u_haze_color, u_haze_color * vec3(0.75, 0.90, 1.25), smoothstep(0.0, 0.6, max(reflect_dir.y, 0.0)));

	// Aerial perspective / haze
	float h2 = max(u_cam.y - u_sea, 0.0);
	float avg_rho;
	if (h2 > 1.0) {
		avg_rho = u_haze_density * (1.0 - exp(-h2 / u_haze_scale)) / (h2 / u_haze_scale);
	} else {
		avg_rho = u_haze_density * exp(-0.5 * h2 / u_haze_scale);
	}
	float haze = 1.0 - exp(-dist * avg_rho);
	haze = max(haze, smoothstep(0.0, 6000.0, max(abs(w.x), abs(w.y)) - 0.5 * u_map_size));

	// Output PBR material parameters
	ALBEDO = col * (1.0 - haze);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.035, 0.82, foam);
	SPECULAR = 0.5 * (1.0 - haze);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;

	// Emission includes horizon atmospheric haze and specular sky reflection
	vec3 water_emission = sky_ref * fresnel * 0.45 * (1.0 - haze);
	EMISSION = mix(water_emission, u_haze_color * haze, haze);
}
