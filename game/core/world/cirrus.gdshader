shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// High cirrus deck: a large plane at 9 km, alpha from two stretched octaves of tileable noise
// anchored in world space. The plane is re-centred under the camera every frame; `center` is
// the plane centre in world metres, so VERTEX.xz + center is the world position of a fragment.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 center = vec2(0.0);
uniform vec3 col = vec3(0.9, 0.9, 0.92);
uniform float amount = 0.4;
uniform float fade_m = 26000.0;

varying vec2 v_w;

void vertex() {
	v_w = VERTEX.xz + center;
}

void fragment() {
	vec2 q = v_w / vec2(14000.0, 5200.0);
	float n = texture(noise_tex, q + vec2(0.13, 0.41)).r * 0.6
		+ texture(noise_tex, q * 2.7 + vec2(0.7, 0.2)).r * 0.4;
	float streak = smoothstep(0.50, 0.82, n);
	float d = length(v_w - center);
	float fade = 1.0 - smoothstep(fade_m * 0.5, fade_m, d);
	ALBEDO = col;
	ALPHA = streak * fade * amount;
}
