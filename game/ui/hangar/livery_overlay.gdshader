shader_type spatial;

// Triplanar livery paint for models without usable UVs. Coordinates are in the aircraft's own space
// (to_root maps each mesh vertex into the root of the model), so the paint stays put while the model turns.
uniform sampler2D livery_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform mat4 to_root;
uniform float tile_m = 6.0;
uniform float blend_sharpness = 4.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float metallic : hint_range(0.0, 1.0) = 0.05;

varying vec3 root_pos;
varying vec3 root_nrm;

void vertex() {
	root_pos = (to_root * vec4(VERTEX, 1.0)).xyz;
	root_nrm = mat3(to_root) * NORMAL;
}

void fragment() {
	vec3 w = pow(abs(normalize(root_nrm)), vec3(blend_sharpness));
	w /= (w.x + w.y + w.z);
	vec3 p = root_pos / tile_m;
	vec3 paint = texture(livery_tex, p.zy).rgb * w.x
		+ texture(livery_tex, p.xz).rgb * w.y
		+ texture(livery_tex, p.xy).rgb * w.z;
	ALBEDO = paint;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
