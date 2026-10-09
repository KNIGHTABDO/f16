// Expanding shock ring on flat ground (or water). Place a QuadMesh lying flat; its scale is the max radius.
// progress 0..1 is the ring radius as a fraction of the quad half-size.
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 ring_color : source_color = vec4(1.0, 0.86, 0.62, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float ring_width : hint_range(0.01, 0.5) = 0.12;
// Dust/spray disc inside the ring (0 = none).
uniform float disc : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = texture(noise_tex, UV * 2.0 + vec2(0.1, 0.3)).r;
	float w = ring_width * (1.0 - 0.6 * progress);
	float ring = exp(-pow((r - progress + (n - 0.5) * 0.09) / w, 2.0));
	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	float inner = (1.0 - smoothstep(0.0, progress + 0.001, r)) * disc * (1.0 - progress) * n;
	ALBEDO = ring_color.rgb;
	ALPHA = clamp((ring * 0.9 + inner * 0.3) * fade * intensity * ring_color.a, 0.0, 1.0);
}
