shader_type spatial;
uniform vec4 ice_color : source_color = vec4(0.65, 0.85, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.35, 0.4, 0.5, 1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.8;
uniform float sparkle_scale = 40.0;

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
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	float sp = step(0.985, hash(floor(UV * sparkle_scale))) * (0.5 + 0.5 * sin(TIME * 3.0 + hash(floor(UV * sparkle_scale)) * 20.0));
	vec3 col = mix(base_color.rgb, ice_color.rgb, amount);
	ALBEDO = col;
	ROUGHNESS = mix(0.8, 0.12, amount);
	METALLIC = 0.0;
	EMISSION = ice_color.rgb * (fres * 0.8 + sp * 2.0) * amount;
}
