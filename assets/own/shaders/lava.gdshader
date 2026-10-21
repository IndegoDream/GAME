shader_type spatial;
uniform vec4 crust_color : source_color = vec4(0.07, 0.05, 0.045, 1.0);
uniform vec4 lava_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);
uniform float scale = 3.0;
uniform float flow_speed = 0.12;
uniform float glow : hint_range(0.0, 6.0) = 2.5;

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

void fragment() {
	vec2 uv = UV * scale;
	vec2 flow = vec2(TIME * flow_speed, TIME * flow_speed * 0.6);
	float n = fbm(uv + flow + fbm(uv * 1.7 - flow) * 1.5);
	float seam = smoothstep(0.42, 0.56, n);
	float hot = 1.0 - seam;
	ALBEDO = mix(lava_color.rgb * 0.4, crust_color.rgb, seam);
	ROUGHNESS = mix(0.3, 0.95, seam);
	EMISSION = lava_color.rgb * hot * glow * (0.8 + 0.2 * sin(TIME * 2.0 + n * 9.0));
}
