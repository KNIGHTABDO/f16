shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Runway surface with ICAO markings: threshold piano keys, runway designators (digits),
// dashed centreline, touchdown zones, and side stripes over an asphalt base.

uniform sampler2D asphalt_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D digits_tex : filter_linear_mipmap, repeat_disable;
uniform float runway_length = 3000.0;
uniform float runway_width = 45.0;
uniform vec2 num_d1 = vec2(1.0, 0.0); // e.g. "10"
uniform vec2 num_d2 = vec2(2.0, 8.0); // e.g. "28"
uniform vec3 asphalt_color = vec3(0.14, 0.14, 0.15);
uniform vec3 marking_color = vec3(0.90, 0.90, 0.88);
uniform float night = 0.0;

float sample_digit(float digit, vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	float d = clamp(floor(digit), 0.0, 9.0);
	vec2 tex_uv = vec2((d + uv.x) * 0.1, uv.y);
	return texture(digits_tex, tex_uv).a;
}

void fragment() {
	float u_m = UV.x * runway_width;
	float v_m = UV.y * runway_length;
	float center_dist = abs(u_m - runway_width * 0.5);

	// Tiled asphalt texture
	vec2 asp_uv = vec2(u_m * 0.15, v_m * 0.15);
	float asp_noise = texture(asphalt_tex, asp_uv).r;
	vec3 base_col = asphalt_color * (0.8 + 0.4 * asp_noise);

	float mark = 0.0;

	// 1. Runway edge lines (0.9m wide, 1.2m inset from edges)
	if ((u_m >= 1.2 && u_m <= 2.1) || (u_m >= runway_width - 2.1 && u_m <= runway_width - 1.2)) {
		mark = 1.0;
	}

	// 2. Threshold piano keys (at both ends: 6m to 36m from threshold, 1.8m stripes with 1.8m gaps)
	bool in_thresh_1 = (v_m >= 6.0 && v_m <= 36.0);
	bool in_thresh_2 = (v_m >= runway_length - 36.0 && v_m <= runway_length - 6.0);
	if ((in_thresh_1 || in_thresh_2) && (u_m >= 3.0 && u_m <= runway_width - 3.0)) {
		float p_mod = mod(u_m - 3.0, 3.6);
		if (p_mod < 1.8) {
			mark = 1.0;
		}
	}

	// Threshold solid transverse bars
	if ((v_m >= 1.5 && v_m <= 3.5) || (v_m >= runway_length - 3.5 && v_m <= runway_length - 1.5)) {
		if (u_m >= 2.0 && u_m <= runway_width - 2.0) {
			mark = 1.0;
		}
	}

	// 3. Runway designator numbers (15m high, positioned 42m to 57m from each threshold)
	// End 1 numbers:
	if (v_m >= 42.0 && v_m <= 57.0) {
		float ny = (v_m - 42.0) / 15.0; // 0 at bottom, 1 at top
		// Digit 1 (tens)
		float d1_x0 = runway_width * 0.5 - 5.5;
		float d1_x1 = runway_width * 0.5 - 0.8;
		if (u_m >= d1_x0 && u_m <= d1_x1) {
			float nx = (u_m - d1_x0) / (d1_x1 - d1_x0);
			mark = max(mark, sample_digit(num_d1.x, vec2(nx, ny)));
		}
		// Digit 2 (units)
		float d2_x0 = runway_width * 0.5 + 0.8;
		float d2_x1 = runway_width * 0.5 + 5.5;
		if (u_m >= d2_x0 && u_m <= d2_x1) {
			float nx = (u_m - d2_x0) / (d2_x1 - d2_x0);
			mark = max(mark, sample_digit(num_d1.y, vec2(nx, ny)));
		}
	}

	// End 2 numbers (rotated 180 degrees)
	if (v_m >= runway_length - 57.0 && v_m <= runway_length - 42.0) {
		float ny = (runway_length - 42.0 - v_m) / 15.0; // flipped so it faces opposite threshold
		// Digit 1 (tens)
		float d1_x0 = runway_width * 0.5 + 0.8;
		float d1_x1 = runway_width * 0.5 + 5.5;
		if (u_m >= d1_x0 && u_m <= d1_x1) {
			float nx = 1.0 - (u_m - d1_x0) / (d1_x1 - d1_x0);
			mark = max(mark, sample_digit(num_d2.x, vec2(nx, ny)));
		}
		// Digit 2 (units)
		float d2_x0 = runway_width * 0.5 - 5.5;
		float d2_x1 = runway_width * 0.5 - 0.8;
		if (u_m >= d2_x0 && u_m <= d2_x1) {
			float nx = 1.0 - (u_m - d2_x0) / (d2_x1 - d2_x0);
			mark = max(mark, sample_digit(num_d2.y, vec2(nx, ny)));
		}
	}

	// 4. Centreline: dashed 30m line, 20m gap, width 0.9m
	if (v_m > 62.0 && v_m < runway_length - 62.0) {
		if (center_dist <= 0.45 && mod(v_m, 50.0) < 30.0) {
			mark = 1.0;
		}
	}

	// 5. Touchdown zone bars at 150m, 300m, 450m from each threshold
	float dist_from_end = min(v_m, runway_length - v_m);
	if ((abs(dist_from_end - 150.0) < 11.0 || abs(dist_from_end - 300.0) < 11.0 || abs(dist_from_end - 450.0) < 11.0)) {
		if (center_dist >= 2.5 && center_dist <= 7.0) {
			float bar_mod = mod(center_dist - 2.5, 2.4);
			if (bar_mod < 1.4) {
				mark = 1.0;
			}
		}
	}

	vec3 col = mix(base_col, marking_color, clamp(mark, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
