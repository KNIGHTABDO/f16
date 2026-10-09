shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Rain streaks wrapped inside a box around the camera. The node is top-level and follows the
// camera, so MODEL_MATRIX[3] is the camera position and drops are placed in node-local space.
// INSTANCE_CUSTOM.rgb is a random seed per drop in 0..1.

uniform vec3 box = vec3(70.0, 45.0, 70.0);
uniform vec3 fall = vec3(0.0, -18.0, 0.0);  // m/s, wind included
uniform float streak = 1.2;                 // streak length, m
uniform float width = 0.035;                // half width, m
uniform float strength = 1.0;
uniform vec3 tint = vec3(0.70, 0.75, 0.82);

varying float v_a;

void vertex() {
	vec3 p = mod(INSTANCE_CUSTOM.rgb * box + fall * TIME, box) - box * 0.5;
	vec3 fdir = normalize(fall);
	vec3 wpos = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 fwd = INV_VIEW_MATRIX[2].xyz;
	// Billboard around the fall axis: quad X = camera right, quad Y = fall direction.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * width, 0.0), vec4(fdir * streak * 0.5, 0.0),
		vec4(fwd, 0.0), vec4(wpos, 1.0));
	float dn = length(p.xz) / (box.x * 0.5);
	float dy = abs(p.y) / (box.y * 0.5);
	v_a = strength * (1.0 - smoothstep(0.6, 1.0, dn)) * (1.0 - smoothstep(0.7, 1.0, dy));
}

void fragment() {
	float edge = 1.0 - smoothstep(0.6, 1.0, abs(UV.x * 2.0 - 1.0));
	ALBEDO = tint;
	ALPHA = v_a * 0.55 * edge;
}
