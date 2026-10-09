// Afterburner flame cone and shock diamonds. Mesh: CylinderMesh with the narrow end at the nozzle
// (local +Y), so v_t = 0 at the nozzle and 1 at the far end of the plume.
// intensity 0..1 scales the whole plume; shock_strength 0..1 shows the diamond banding.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 core_color : source_color = vec4(0.8, 0.88, 1.0, 1.0);
uniform vec4 outer_color : source_color = vec4(1.0, 0.44, 0.1, 1.0);
uniform vec4 shock_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float cone_length = 6.0;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float shock_strength : hint_range(0.0, 1.0) = 0.0;
uniform float shock_spacing = 1.4;

varying float v_t;

void vertex() {
	v_t = clamp(0.5 - VERTEX.y / cone_length, 0.0, 1.0);
}

void fragment() {
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float n = texture(noise_tex, vec2(UV.x * 2.0, v_t * 1.5 - TIME * 2.2)).r;
	float flick = 0.9 + 0.1 * sin(TIME * 53.0) * sin(TIME * 17.0);
	float length_var = 1.0 + 0.35 * (n - 0.5);
	float shape = 1.0 - smoothstep(0.0, 1.0, v_t * length_var);
	float core_t = clamp(facing * 1.2 - 0.1, 0.0, 1.0);
	vec3 col = mix(outer_color.rgb, core_color.rgb, core_t * (1.0 - v_t * 0.7));

	float band = 0.5 + 0.5 * cos(v_t * cone_length / shock_spacing * 6.2831853);
	float shocks = pow(band, 8.0) * (1.0 - v_t) * shock_strength * pow(facing, 2.0);
	col = mix(col, shock_color.rgb, clamp(shocks, 0.0, 1.0));

	float a = (shape * pow(facing, 0.7) * (0.6 + 0.4 * n) + shocks) * intensity * flick;
	ALBEDO = col * (0.9 + 0.5 * core_t);
	ALPHA = clamp(a, 0.0, 1.0);
}
