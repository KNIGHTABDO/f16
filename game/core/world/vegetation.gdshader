shader_type spatial;
render_mode cull_disabled, specular_disabled;

// Crossed alpha-tested quads. INSTANCE_CUSTOM = (species/4 + 1/8, variation, 0, 0). The species
// selects one 256 px column of tree_atlas.png (pine, olive, palm, shrub).

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint = vec3(1.0, 1.0, 1.0);

varying float v_var;

void vertex() {
	float sp = floor(INSTANCE_CUSTOM.r * 4.0);
	v_var = INSTANCE_CUSTOM.g;
	UV.x = (UV.x + sp) * 0.25;
	// Foliage lit as if the leaves face up, so the sun and sky light the crowns evenly.
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = t.rgb * mix(0.80, 1.12, v_var) * tint;
	ALPHA = t.a;
	ROUGHNESS = 0.9;
}
