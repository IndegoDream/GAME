shader_type spatial;
render_mode cull_disabled;
uniform vec4 albedo : source_color = vec4(0.55, 0.5, 0.45, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.3) = 0.08;
uniform float noise_scale = 4.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float n = fbm(local_pos.xy * noise_scale + local_pos.zz * noise_scale * 0.7);
	float edge = n - progress * 1.15 + 0.07;
	if (edge < 0.0) { discard; }
	float burn = 1.0 - smoothstep(0.0, edge_width, edge);
	ALBEDO = mix(albedo.rgb, edge_color.rgb * 0.3, burn);
	EMISSION = edge_color.rgb * burn * 3.0;
	ROUGHNESS = 0.8;
}
