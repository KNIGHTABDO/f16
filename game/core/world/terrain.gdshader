shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

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
uniform float u_near_on = 1.0;                  // close-range colour textures on/off (quality)
uniform float u_detail_amp = 2.5;
uniform float u_detail_end = 2000.0;              // procedural detail fades out by this distance
uniform float u_color_end = 2500.0;               // detail textures fade out by this distance
uniform vec3 u_haze_color = vec3(0.62, 0.74, 0.86);
uniform float u_haze_density = 0.0000167;         // 1 / 60 km at sea level
uniform float u_haze_scale = 2500.0;              // haze thins with altitude over this scale
uniform float u_tile_a = 12.0;                    // detail texture tile sizes, metres
uniform float u_tile_b = 37.0;

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
	vec3 n = normalize(vec3(-grad.x, 1.0, -grad.y));
	float slope = length(grad);

	// Far colour: satellite image (linear light).
	vec2 uv_map = w / u_map_size + 0.5;
	vec3 albedo = pow(texture(color_tex, uv_map).rgb, vec3(2.2));

	// Snow above the snow line and rock on steep faces override the class colour.
	float rock_all = smoothstep(0.35, 0.6, slope);
	float snow_all = smoothstep(2300.0, 2700.0, v_h);

	float near_w = u_near_on * (1.0 - smoothstep(0.6 * u_color_end, u_color_end, dist));
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
				int layer = 5;
				if (cls == 1) layer = 3;
				else if (cls == 2) layer = 1;
				else if (cls == 3) layer = 0;
				else if (cls == 4) layer = 2;
				else if (cls == 5) layer = 7;
				else if (cls == 7) layer = 6;
				else if (cls == 8) layer = 3;
				else if (cls == 6) {
					float r = max(smoothstep(0.25, 0.5, slope), smoothstep(1200.0, 1800.0, v_h));
					wl[4] += bw * r;
					layer = 5;
					bw = bw * (1.0 - r);
				}
				wl[layer] += bw;
			}
		}
		for (int i = 0; i < 8; i++) {
			wl[i] *= (1.0 - rock_all) * (1.0 - snow_all);
		}
		wl[4] += rock_all;
		wl[6] += snow_all;

		// Two scales of each tile, rotated against each other, to hide repetition.
		vec3 acc_alb = vec3(0.0);
		vec2 acc_nrm = vec2(0.0);
		float acc_w = 0.0;
		for (int L = 0; L < 8; L++) {
			float wgt = wl[L];
			if (wgt < 0.01) {
				continue;
			}
			float fl = float(L);
			vec3 a1 = textureGrad(albedo_array, vec3(w / u_tile_a, fl), dwx / u_tile_a, dwy / u_tile_a).rgb;
			vec3 a2 = textureGrad(albedo_array, vec3(rot * w / u_tile_b, fl), rot * dwx / u_tile_b, rot * dwy / u_tile_b).rgb;
			vec2 nn = textureGrad(normal_array, vec3(w / u_tile_a, fl), dwx / u_tile_a, dwy / u_tile_a).xy;
			acc_alb += wgt * pow(0.5 * (a1 + a2), vec3(2.2));
			acc_nrm += wgt * (nn * 2.0 - 1.0);
			acc_w += wgt;
		}
		if (acc_w > 0.001) {
			vec3 det_alb = acc_alb / acc_w;
			vec2 det_n = acc_nrm / acc_w;
			float lum = dot(det_alb, vec3(0.2126, 0.7152, 0.0722));
			float bright = clamp(lum / 0.2, 0.4, 2.0);
			// Keep the satellite colour as the base; detail adds brightness variation up close.
			albedo *= mix(1.0, bright, 0.7 * near_w);
			n = normalize(vec3(n.x + det_n.x * 0.5 * near_w, n.y, n.z + det_n.y * 0.5 * near_w));
		}
	}

	// Aerial perspective: distant ground fades into the horizon colour.
	float dens = u_haze_density * exp(-max(v_h - u_sea, 0.0) / u_haze_scale);
	float haze = 1.0 - exp(-dist * dens);
	// Beyond the map edge there is no data (height and colour are clamped), so fade to the horizon tone.
	haze = max(haze, smoothstep(0.0, 6000.0, max(abs(w.x), abs(w.y)) - 0.5 * u_map_size));

	ALBEDO = albedo * (1.0 - haze);
	EMISSION = u_haze_color * haze;
	SPECULAR = 0.5 * (1.0 - haze);
	ROUGHNESS = mix(0.92, 0.6, snow_all);
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
}
