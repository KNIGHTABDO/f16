shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Moroccan urban building facade shader with procedural windows, flat roofs,
// stucco variants, and warm window lighting at night.
// INSTANCE_CUSTOM = (color_tint, is_minaret, seed, 0)

uniform float night = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);

varying vec3 v_world_pos;
varying vec3 v_normal;
varying float v_tint;
varying float v_is_minaret;
varying float v_seed;

float hash2(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_tint = INSTANCE_CUSTOM.r;
	v_is_minaret = INSTANCE_CUSTOM.g;
	v_seed = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec3 n = normalize(v_normal);
	bool is_roof = abs(n.y) > 0.7;

	// Stucco base colors (Moroccan white, cream, warm ochre, sand)
	vec3 col_white = vec3(0.92, 0.90, 0.88);
	vec3 col_cream = vec3(0.88, 0.82, 0.73);
	vec3 col_ochre = vec3(0.82, 0.62, 0.44);
	vec3 col_sand  = vec3(0.85, 0.76, 0.65);

	vec3 wall_col = mix(col_white, col_cream, smoothstep(0.0, 0.33, v_tint));
	wall_col = mix(wall_col, col_ochre, smoothstep(0.33, 0.66, v_tint));
	wall_col = mix(wall_col, col_sand, smoothstep(0.66, 1.0, v_tint));

	vec3 emission_col = vec3(0.0);

	if (is_roof) {
		// Roof: terracotta / dark concrete flat roof
		vec3 roof_col = mix(vec3(0.45, 0.38, 0.32), vec3(0.35, 0.33, 0.32), fract(v_seed * 3.1));
		ALBEDO = roof_col;
		ROUGHNESS = 0.9;
	} else {
		// Wall facade with windows
		float h_coord = (abs(n.x) > 0.5) ? v_world_pos.z : v_world_pos.x;
		float v_coord = v_world_pos.y;

		float col_idx = floor(h_coord / 2.5);
		float floor_idx = floor(v_coord / 3.2);

		float u_win = fract(h_coord / 2.5);
		float v_win = fract(v_coord / 3.2);

		bool in_win = (u_win > 0.25 && u_win < 0.75 && v_win > 0.25 && v_win < 0.80);

		if (v_is_minaret > 0.5) {
			// Minaret: decorative green top band (#234E32)
			float top_fade = fract(v_coord * 0.1);
			if (top_fade > 0.75) {
				wall_col = mix(wall_col, vec3(0.14, 0.32, 0.20), 0.85);
			}
		}

		if (in_win) {
			// Window glass (day: dark blue-grey; night: warm yellow/amber lights)
			vec3 glass_day = vec3(0.12, 0.16, 0.22);
			float win_rand = hash2(vec2(col_idx, floor_idx) + v_seed * 47.0);
			bool is_lit = win_rand > 0.55;

			vec3 warm_light = vec3(1.0, 0.82, 0.45) * 2.8;
			ALBEDO = mix(glass_day, warm_light * 0.5, (is_lit ? 1.0 : 0.0) * night);
			if (is_lit && night > 0.01) {
				emission_col = warm_light * night;
			}
			ROUGHNESS = 0.25;
			SPECULAR = 0.6;
		} else {
			ALBEDO = wall_col;
			ROUGHNESS = 0.85;
			SPECULAR = 0.1;
		}
	}

	EMISSION = emission_col;
}
