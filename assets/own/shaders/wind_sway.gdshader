shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.12;
uniform float speed = 1.2;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.5;
void vertex() {
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float phase = (MODEL_MATRIX[3].x + MODEL_MATRIX[3].z) * 0.7;
	VERTEX.x += sin(TIME * speed + phase + VERTEX.y * 2.0) * sway * h * h;
	VERTEX.z += cos(TIME * speed * 0.8 + phase) * sway * 0.5 * h * h;
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * tint;
	if (t.a < alpha_cut) { discard; }
	ALBEDO = t.rgb;
	ROUGHNESS = 0.9;
}
