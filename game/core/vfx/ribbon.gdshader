// Camera-facing ribbon for trails and contrails. Mesh layout (built by TrailFx / Contrail):
//   vertices come in pairs per trail point: UV.y = 0 or 1 (across), UV.x = 0 at the head (newest) .. 1 at the tail,
//   NORMAL = unit direction of travel at that point, COLOR = per-vertex colour with age fade in alpha.
// The ribbon container must have an identity basis so model and world directions match.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float half_width = 0.5;
uniform float taper : hint_range(0.0, 1.0) = 0.6;
uniform float alpha_mul : hint_range(0.0, 2.0) = 1.0;
uniform float edge_softness : hint_range(0.5, 4.0) = 1.4;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 tangent = NORMAL;
	if (dot(tangent, tangent) < 1e-6) {
		tangent = vec3(0.0, 0.0, 1.0);
	}
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - (origin + VERTEX));
	vec3 side = cross(normalize(tangent), to_cam);
	if (dot(side, side) < 1e-8) {
		side = vec3(1.0, 0.0, 0.0);
	}
	side = normalize(side);
	float s = UV.y * 2.0 - 1.0;
	VERTEX += side * s * half_width * (1.0 - taper * UV.x);
}

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb;
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALPHA = clamp(COLOR.a * alpha_mul * tint.a * pow(across, edge_softness), 0.0, 1.0);
}
