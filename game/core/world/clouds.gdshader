shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Cumulus puffs: camera-facing impostors on a QuadMesh of size 2 (VERTEX in -1..1).
// INSTANCE_CUSTOM = (seed, radius, threshold, 0). A cluster is active when threshold < cover;
// inactive puffs get zero size and are never rasterised. The puff centre is the instance origin.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);      // towards the sun, world
uniform vec3 sun_col = vec3(1.0, 0.97, 0.9);
uniform vec3 sky_col = vec3(0.5, 0.6, 0.75);     // shade colour (sky ambient)
uniform float bright = 1.0;                      // overall brightness
uniform float dark = 0.0;                        // storm base darkening, 0..1
uniform float cover = 0.5;                       // fraction of clusters present, 0..1

varying vec3 v_L;
varying float v_seed;

void vertex() {
	float r = INSTANCE_CUSTOM.g * (INSTANCE_CUSTOM.b < cover ? 1.0 : 0.0);
	v_seed = INSTANCE_CUSTOM.r;
	vec3 centre = MODEL_MATRIX[3].xyz;
	// Billboard: the quad faces the camera, centred on the puff.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(CAMERA_MATRIX[0], CAMERA_MATRIX[1], CAMERA_MATRIX[2], vec4(centre, 1.0));
	VERTEX.xy *= r;
	v_L = (VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		discard;
	}
	float rr = sqrt(r2);
	// Fake spherical normal in view space, so the sun-facing side of each puff is brighter.
	vec3 n = normalize(vec3(p.x, p.y, sqrt(max(1.0 - r2, 0.0))));
	// Noise warps the silhouette so puffs look cauliflower-like, not like discs.
	float nz = texture(noise_tex, UV * 0.9 + vec2(v_seed, fract(v_seed * 7.13))).r;
	float nz2 = texture(noise_tex, UV * 2.1 + vec2(fract(v_seed * 3.7), v_seed)).r;
	float edge = rr + (nz - 0.5) * 0.5 + (nz2 - 0.5) * 0.18;
	float a = 1.0 - smoothstep(0.80, 0.97, edge);
	if (a < 0.01) {
		discard;
	}
	float lit = clamp(dot(n, normalize(v_L)) * 0.65 + 0.45, 0.0, 1.0);
	// Lower part of each puff sits in shade; the top catches the sun.
	float top = smoothstep(-0.5, 0.7, n.y);
	vec3 col = mix(sky_col * 0.6, sun_col, clamp(lit * 0.8 + top * 0.25, 0.0, 1.0));
	col *= 0.9 + 0.2 * nz2;
	col = mix(col, vec3(0.40, 0.42, 0.48), dark * (1.0 - top * 0.6));
	ALBEDO = col * bright;
	ALPHA = a;
}
