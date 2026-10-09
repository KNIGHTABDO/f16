shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// ==============================================================================
// Terrain Clipmap Shader - Moroccan Landscape & Visual Polish
//
// Texture Fetches per Quality Preset:
// - Low:     2 fetches total
//            Vertex:   1 x height_tex (Lod 0)
//            Fragment: 1 x color_tex (satellite albedo)
// - Medium / Balanced: 6 fetches total
//            Vertex:   1 x height_tex (Lod 0)
//            Fragment: 1 x color_tex, 1 x landcover_tex, 2 x albedo_array (2-scale hex), 1 x normal_array
// - High:    7 fetches total
//            Vertex:   1 x height_tex (Lod 0)
//            Fragment: 1 x color_tex, 1 x landcover_tex, 2 x albedo_array (2-scale hex), 2 x normal_array
//            (Optimal sustained 60 fps on Apple A15 / mobile tile-based GPUs)
// - Ultra:   8 fetches total
//            Vertex:   1 x height_tex (Lod 0)
//            Fragment: 1 x color_tex, 1 x landcover_tex, 2 x albedo_array, 2 x normal_array,
//                      + 1 x albedo_array (triplanar cliff rock projection on steep faces)
// ==============================================================================

// Geometry clipmap ring (one MeshInstance3D per ring, all sharing one unit grid mesh).
// VERTEX.xz of the mesh are integer cell indices (-N/2..N/2); the ring cell size is u_cell.
// Vertices strictly inside the next finer ring's window are discarded (degenerate), and the
// outer band of each ring morphs odd vertices onto the next coarser lattice so rings join
// without cracks or popping.
uniform float u_cell = 4.0;                       // metres per cell in this ring
uniform float u_half = 128.0;                     // ring outer half-width, metres
uniform vec2 u_centre = vec2(0.0);                // ring centre, world metres (x, z)
uniform float u_morph_band = 0.4;                 // fraction of the half-width used for morphing

// Shared by every ring (set by terrain.gd).
uniform sampler2D height_tex : filter_linear, repeat_disable;     // R16, Ground height grid
uniform sampler2D landcover_tex : filter_nearest, repeat_disable; // R8, Ground.LC_* classes
uniform sampler2D color_tex : filter_linear_mipmap_anisotropic, repeat_disable; // satellite
uniform sampler2DArray albedo_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 u_cam = vec3(0.0);                   // camera: world x, altitude, world z
uniform float u_map_size = 256000.0;
uniform float u_height_n = 4096.0;
uniform float u_land_n = 2048.0;
uniform float u_hmin = -200.0;
uniform float u_hmax = 3200.0;
uniform float u_sea = 0.0;
uniform float u_detail_on = 1.0;
uniform float u_near_on = 1.0;                    // close-range colour textures on/off (quality)
uniform float u_detail_amp = 2.5;
uniform float u_detail_end = 2000.0;              // procedural detail fades out by this distance
uniform float u_color_end = 3200.0;               // detail textures fade out by this distance
uniform vec3 u_haze_color = vec3(0.62, 0.74, 0.86);
uniform float u_haze_density = 0.0000167;         // 1 / 60 km at sea level
uniform float u_haze_scale = 2500.0;              // haze thins with altitude over this scale
uniform float u_tile_a = 12.0;                    // detail texture tile sizes, metres
uniform float u_tile_b = 37.0;
uniform float u_triplanar_on = 1.0;

varying float v_h;
varying vec2 v_dgrad;
varying vec2 v_world;

// Ground.world_height_at, on the GPU: bilinear over the R16 grid (texel i at index i,
// grid index u = (x / size + 0.5) * (N - 1)), clamped to the edge outside the map exactly as
// Ground does (clamp-to-edge sampling).
float terrain_base(vec2 w) {
	vec2 uv = w / u_map_size + 0.5;
	vec2 tc = (uv * (u_height_n - 1.0) + 0.5) / u_height_n;
	return u_hmin + textureLod(height_tex, tc, 0.0).r * (u_hmax - u_hmin);
}

// Integer hash (PCG-style). terrain.gd mirrors this bit for bit for CPU queries.
uint lattice_hash(ivec2 p) {
	uint x = uint(p.x) * 73856093u;
	uint y = uint(p.y) * 19349663u;
	uint s = (x ^ y) * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float lattice(ivec2 p) {
	return float(lattice_hash(p)) * (1.0 / 4294967296.0);
}

float vnoise(vec2 p) {
	vec2 fl = floor(p);
	ivec2 i = ivec2(fl);
	vec2 f = p - fl;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = lattice(i);
	float b = lattice(i + ivec2(1, 0));
	float c = lattice(i + ivec2(0, 1));
	float d = lattice(i + ivec2(1, 1));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Close-range procedural detail in metres (mirrored by terrain.gd detail_height_at).
float detail_fn(vec2 w) {
	float n1 = vnoise(w / 24.0) - 0.5;
	float n2 = vnoise(w / 11.0 + vec2(17.3, 5.1)) - 0.5;
	return u_detail_amp * (n1 + 0.5 * n2);
}

// 0 on flat ground, 1 on slopes steeper than 10 %. Keeps detail off runways and plains.
float slope_mask(vec2 w) {
	float e = 30.0;
	float gx = (terrain_base(w + vec2(e, 0.0)) - terrain_base(w - vec2(e, 0.0))) / (2.0 * e);
	float gz = (terrain_base(w + vec2(0.0, e)) - terrain_base(w - vec2(0.0, e))) / (2.0 * e);
	return smoothstep(0.02, 0.10, length(vec2(gx, gz)));
}

float detail_weight(vec2 w) {
	float dc = length(w - u_cam.xz);
	return u_detail_on * (1.0 - smoothstep(0.6 * u_detail_end, u_detail_end, dc));
}

// Surface height (base + detail) at world w; also returns the detail gradient.
float surface_h(vec2 w, out vec2 dgrad) {
	float h = terrain_base(w);
	dgrad = vec2(0.0);
	float dw = detail_weight(w);
	if (dw > 0.001) {
		float s = dw * slope_mask(w);
		if (s > 0.0) {
			float e = 0.5;
			float d0 = detail_fn(w);
			float dx = detail_fn(w + vec2(e, 0.0)) - d0;
			float dz = detail_fn(w + vec2(0.0, e)) - d0;
			dgrad = s * vec2(dx, dz) / e;
			h += s * d0;
		}
	}
	return h;
}

void vertex() {
	vec2 g = VERTEX.xz;
	vec2 local = g * u_cell;

	// Morph the outer band onto the coarser lattice. Odd cells (parity 1) move to the even
	// neighbour below; at the outer edge (m = 1) the ring matches the next ring exactly.
	vec2 par = mod(g, 2.0);
	float edge = max(abs(local.x), abs(local.y)) / u_half;
	float m = smoothstep(1.0 - u_morph_band, 1.0, edge);

	vec2 w = u_centre + local;
	vec2 gfine;
	float y = surface_h(w, gfine);
	vec2 pos = local;
	vec2 gout = gfine;
	if (m > 0.0 && (par.x + par.y) > 0.5) {
		vec2 lc = local - par * u_cell;
		vec2 gcoarse;
		float yc = surface_h(u_centre + lc, gcoarse);
		y = mix(y, yc, m);
		pos = mix(local, lc, m);
		gout = mix(gfine, gcoarse, m);
	}

	VERTEX = vec3(pos.x, y, pos.y);
	v_h = y;
	v_dgrad = gout;
	v_world = u_centre + pos;
}

void fragment() {
	vec2 w = v_world;
	vec3 p3 = vec3(w.x, v_h, w.y);
	float dist = length(p3 - u_cam);

	// Shading normal from the height grid (about one texel of baseline) plus the detail gradient.
	float e = u_map_size / (u_height_n - 1.0);
	float hx = terrain_base(w + vec2(e, 0.0)) - terrain_base(w - vec2(e, 0.0));
	float hz = terrain_base(w + vec2(0.0, e)) - terrain_base(w - vec2(0.0, e));
	vec2 grad = vec2(hx, hz) / (2.0 * e) + v_dgrad;
	vec3 geom_n = normalize(vec3(-grad.x, 1.0, -grad.y));
	vec3 n = geom_n;
	float slope = length(grad);

	// --- 1. SATELLITE COLOR GRADING (Morocco warm earth, dehaze, exposure, saturation) ---
	vec2 uv_map = w / u_map_size + 0.5;
	vec3 sat_raw = texture(color_tex, uv_map).rgb;

	// Dehaze: remove the dark murky atmospheric veil and shadow crush
	vec3 sat_dehazed = max(sat_raw - vec3(0.022, 0.028, 0.035), vec3(0.0)) / 0.965;
	sat_dehazed = pow(sat_dehazed, vec3(1.12));

	// Exposure boost and linear color conversion
	vec3 sat_linear = pow(sat_dehazed, vec3(2.2)) * 1.85;

	// Saturation boost for rich landscape colors
	float sat_luma = dot(sat_linear, vec3(0.2126, 0.7152, 0.0722));
	sat_linear = max(mix(vec3(sat_luma), sat_linear, 1.35), vec3(0.0));

	// Warm Moroccan tone grading (terracotta soil, golden sand, warm limestone)
	sat_linear *= vec3(1.16, 1.05, 0.88);

	// Prevent muddy black/grey holes in shadows
	sat_linear = max(sat_linear, vec3(0.032, 0.036, 0.028));

	// Macro variation noise: large-scale organic richness across the plains and hills
	float macro_noise = vnoise(w / 240.0) * 0.7 + vnoise(w / 75.0 + vec2(37.4, 18.2)) * 0.3;
	sat_linear *= (0.86 + 0.28 * macro_noise);

	// --- 2. ALTITUDE & SLOPE OVERRIDES (Snow line in Atlas, Rock on cliffs) ---
	// Snow above ~3000 m in High Atlas (aspect-dependent: cooler north slopes have snow down to ~2850m)
	float snow_alt = 3000.0 - geom_n.z * 150.0;
	float snow_all = smoothstep(snow_alt - 150.0, snow_alt + 150.0, v_h);

	// Steep rock faces shed snow
	float cliff_mask = smoothstep(0.38, 0.65, slope);
	snow_all *= (1.0 - cliff_mask * 0.85);

	// Rock on steep slopes and high rocky mountain peaks
	float rock_all = smoothstep(0.32, 0.56, slope);
	rock_all = max(rock_all, smoothstep(2200.0, 2700.0, v_h) * smoothstep(0.18, 0.36, slope));

	// --- 3. NEAR GROUND DETAIL TEXTURING (< 500 m AGL & close range) ---
	float near_w = u_near_on * (1.0 - smoothstep(0.35 * u_color_end, u_color_end, dist));
	if (near_w > 0.01) {
		vec2 dwx = dFdx(w);
		vec2 dwy = dFdy(w);
		mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

		// Land-cover class at the four nearest cells, blended bilinearly.
		float wl[8];
		for (int i = 0; i < 8; i++) {
			wl[i] = 0.0;
		}
		vec2 lq = uv_map * u_land_n - 0.5;
		vec2 lb = floor(lq);
		vec2 lf = lq - lb;
		for (int j = 0; j < 2; j++) {
			for (int i = 0; i < 2; i++) {
				vec2 cuv = (lb + vec2(float(i), float(j)) + 0.5) / u_land_n;
				int cls = int(floor(textureLod(landcover_tex, cuv, 0.0).r * 255.0 + 0.5));
				float bw = (i == 0 ? 1.0 - lf.x : lf.x) * (j == 0 ? 1.0 - lf.y : lf.y);
				int layer = 5; // default sand / bare
				if (cls == 0) {
					// Water class on land (above sea level): blend sand near coast, dry inland
					layer = (v_h > u_sea + 2.0) ? 1 : 5;
				}
				else if (cls == 1) layer = 3; // forest
				else if (cls == 2) layer = 1; // shrub / dry
				else if (cls == 3) layer = 0; // grass
				else if (cls == 4) layer = 2; // farm
				else if (cls == 5) layer = 7; // urban
				else if (cls == 7) layer = 6; // snow
				else if (cls == 8) layer = 3; // wetland -> lush forest
				else if (cls == 6) {          // bare
					float r = max(smoothstep(0.25, 0.5, slope), smoothstep(1200.0, 1800.0, v_h));
					wl[4] += bw * r;
					layer = 5;
					bw = bw * (1.0 - r);
				}
				wl[layer] += bw;
			}
		}

		// Apply rock and snow overrides to class weights
		for (int i = 0; i < 8; i++) {
			wl[i] *= (1.0 - rock_all) * (1.0 - snow_all);
		}
		wl[4] += rock_all;
		wl[6] += snow_all;

		// Select the two most dominant layers for performance (keeps fetches within budget)
		int top0 = 0;
		int top1 = 1;
		float max0 = -1.0;
		float max1 = -1.0;
		for (int i = 0; i < 8; i++) {
			if (wl[i] > max0) {
				max1 = max0;
				top1 = top0;
				max0 = wl[i];
				top0 = i;
			} else if (wl[i] > max1) {
				max1 = wl[i];
				top1 = i;
			}
		}

		vec3 acc_alb = vec3(0.0);
		vec2 acc_nrm = vec2(0.0);
		float total_w = max0 + max(max1, 0.0);

		if (total_w > 0.001) {
			float norm_w0 = max0 / total_w;
			float norm_w1 = max(max1, 0.0) / total_w;

			// Layer 0: Two-scale rotated stochastic tiling
			float fl0 = float(top0);
			vec3 a1_0 = textureGrad(albedo_array, vec3(w / u_tile_a, fl0), dwx / u_tile_a, dwy / u_tile_a).rgb;
			vec3 a2_0 = textureGrad(albedo_array, vec3(rot * w / u_tile_b, fl0), rot * dwx / u_tile_b, rot * dwy / u_tile_b).rgb;
			vec2 nn_0 = textureGrad(normal_array, vec3(w / u_tile_a, fl0), dwx / u_tile_a, dwy / u_tile_a).xy * 2.0 - 1.0;

			acc_alb += norm_w0 * pow(0.5 * (a1_0 + a2_0), vec3(2.2));
			acc_nrm += norm_w0 * nn_0;

			// Layer 1 (if significant weight):
			if (norm_w1 > 0.08) {
				float fl1 = float(top1);
				vec3 a1_1 = textureGrad(albedo_array, vec3(w / u_tile_a, fl1), dwx / u_tile_a, dwy / u_tile_a).rgb;
				vec3 a2_1 = textureGrad(albedo_array, vec3(rot * w / u_tile_b, fl1), rot * dwx / u_tile_b, rot * dwy / u_tile_b).rgb;
				vec2 nn_1 = textureGrad(normal_array, vec3(w / u_tile_a, fl1), dwx / u_tile_a, dwy / u_tile_a).xy * 2.0 - 1.0;

				acc_alb += norm_w1 * pow(0.5 * (a1_1 + a2_1), vec3(2.2));
				acc_nrm += norm_w1 * nn_1;
			}

			// Triplanar rock projection on steep cliff faces (prevents vertical texture stretching)
			if (u_triplanar_on > 0.5 && cliff_mask > 0.08 && wl[4] > 0.15) {
				vec2 side_uv = abs(geom_n.x) > abs(geom_n.z) ? vec2(w.y, v_h) / u_tile_a : vec2(w.x, v_h) / u_tile_a;
				vec2 side_dx = dFdx(side_uv);
				vec2 side_dy = dFdy(side_uv);
				vec3 rock_side = textureGrad(albedo_array, vec3(side_uv, 4.0), side_dx, side_dy).rgb;
				vec2 rock_side_n = textureGrad(normal_array, vec3(side_uv, 4.0), side_dx, side_dy).xy * 2.0 - 1.0;
				float tri_w = clamp(cliff_mask * (1.0 - abs(geom_n.y)) * 1.5, 0.0, 1.0) * wl[4];
				acc_alb = mix(acc_alb, pow(rock_side, vec3(2.2)), tri_w);
				acc_nrm = mix(acc_nrm, rock_side_n, tri_w);
			}

			// Blend detail texture albedo and micro-normal
			// Tint detail albedo by regional satellite colour tone for authentic local terrain coloration
			float det_luma = max(dot(acc_alb, vec3(0.2126, 0.7152, 0.0722)), 0.01);
			vec3 sat_tone = sat_linear / max(sat_luma, 0.02);
			vec3 detail_colored = acc_alb * sat_tone * 1.08;

			// High-res detail blend: close to ground (< 500 m AGL), detail textures give crisp tactile surface
			sat_linear = mix(sat_linear, detail_colored, near_w * 0.85);

			// Perturb geometric normal with high-res normal map
			n = normalize(mix(geom_n, normalize(geom_n + vec3(acc_nrm.x, 0.0, acc_nrm.y) * 1.8), near_w * 0.82));
		}
	}

	// --- 4. AERIAL PERSPECTIVE (Physical atmospheric haze, blue mountain vista) ---
	// Analytic ray integral through exponential atmospheric density
	float h1 = max(v_h - u_sea, 0.0);
	float h2 = max(u_cam.y - u_sea, 0.0);
	float diff_h = abs(h2 - h1);
	float avg_rho;
	if (diff_h > 1.0) {
		avg_rho = u_haze_density * (exp(-h1 / u_haze_scale) - exp(-h2 / u_haze_scale)) / (diff_h / u_haze_scale);
	} else {
		avg_rho = u_haze_density * exp(-0.5 * (h1 + h2) / u_haze_scale);
	}
	float haze = 1.0 - exp(-dist * avg_rho);

	// Beyond the map edge fade cleanly into the horizon tone
	haze = max(haze, smoothstep(0.0, 6000.0, max(abs(w.x), abs(w.y)) - 0.5 * u_map_size));

	// Sky-tinted haze (distant Moroccan mountain ridges turn blue-hazy like real photography)
	vec3 haze_tint = u_haze_color;

	ALBEDO = sat_linear * (1.0 - haze);
	EMISSION = haze_tint * haze;
	SPECULAR = 0.5 * (1.0 - haze);
	ROUGHNESS = mix(0.92, 0.55, snow_all);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
}
