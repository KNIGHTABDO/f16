// Vapour shell around the fuselage or over the wing (condensation at transonic speed or high G/AoA).
// Fresnel-weighted: thin at the middle, denser at the silhouette. intensity 0..1 set from script.
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 vapor_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float fresnel_power = 2.2;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, fresnel_power);
	float n = texture(noise_tex, UV * 1.5 + vec2(TIME * 0.04, -TIME * 0.02)).r;
	ALBEDO = vapor_color.rgb;
	ALPHA = clamp(intensity * max_alpha * (0.2 + 0.8 * rim) * (0.55 + 0.45 * n) * vapor_color.a, 0.0, 1.0);
}
