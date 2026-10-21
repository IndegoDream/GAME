shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 shallow : source_color = vec4(0.1, 0.3, 0.35, 0.65);
uniform vec4 deep : source_color = vec4(0.02, 0.07, 0.1, 0.9);
uniform float wave_height = 0.03;
uniform float wave_speed = 0.5;
uniform float scale = 4.0;

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

void vertex() {
	float w = fbm(VERTEX.xz * scale * 0.5 + TIME * wave_speed * 0.3);
	VERTEX.y += (w - 0.5) * wave_height;
}
void fragment() {
	vec2 p = UV * scale + vec2(TIME * wave_speed * 0.05, 0.0);
	float e = 0.02;
	float h = fbm(p);
	float hx = fbm(p + vec2(e, 0.0));
	float hy = fbm(p + vec2(0.0, e));
	NORMAL_MAP = vec3(0.5 + (h - hx) * 6.0, 0.5 + (h - hy) * 6.0, 1.0);
	float depth_mix = clamp(h * 1.4, 0.0, 1.0);
	vec4 c = mix(shallow, deep, depth_mix);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
