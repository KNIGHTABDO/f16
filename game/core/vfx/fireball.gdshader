// Billboarded fireball / flare / burning-puff sprite. The quad's scale sets the world size.
// progress 0..1 drives the life cycle: hot core -> fireball body -> rolling dark smoke -> fade out.
// Used by ExplosionFx (fireball), FlareFx (flare ball, white-orange palette) and WreckFx (fire base).
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 hot_color : source_color = vec4(1.0, 0.93, 0.66, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.46, 0.13, 1.0);
uniform vec4 smoke_color : source_color = vec4(0.13, 0.12, 0.11, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
uniform float seed = 0.0;
// 0 = full life cycle (explosion), 1 = steady burning (no smoke, no fade until alpha is driven from script)
uniform float steady : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// Camera-facing quad. Keeps the scale from the model matrix, drops its rotation.
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv[0].xyz *= length(MODEL_MATRIX[0].xyz);
	mv[1].xyz *= length(MODEL_MATRIX[1].xyz);
	mv[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec2 q = p * 0.9 + vec2(seed * 0.37, seed * 0.11);
	float n1 = texture(noise_tex, q * 0.5 + vec2(0.0, -TIME * 0.35)).r;
	float n2 = texture(noise_tex, q * 1.3 + vec2(TIME * 0.2, -TIME * 0.6)).r;
	float warp = (n1 - 0.5) * 0.6 + (n2 - 0.5) * 0.28;
	float rr = r + warp * (0.35 + progress * 0.65);

	float body = 1.0 - smoothstep(0.55 + 0.25 * progress, 1.0, rr);
	float core = 1.0 - smoothstep(0.0, 0.38 * (1.0 - progress * 0.7), rr);
	float heat = clamp(core * 1.25 + body * 0.4 * (1.0 - progress), 0.0, 1.0);

	float smoke_t = smoothstep(0.35, 0.9, progress) * (1.0 - steady);
	vec3 fire_col = mix(mid_color.rgb, hot_color.rgb, clamp(heat * 1.4 - 0.2, 0.0, 1.0));
	vec3 smoke_col = smoke_color.rgb * (0.7 + 0.6 * n2);
	vec3 col = mix(fire_col, smoke_col, smoke_t);

	float fade = 1.0 - smoothstep(0.6, 1.0, progress) * (1.0 - steady);
	float a = body * (0.45 + 0.55 * n1) * fade * intensity;
	ALBEDO = col * (1.0 + core * 0.6);
	ALPHA = clamp(a, 0.0, 1.0);
}
