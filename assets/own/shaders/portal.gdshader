shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 inner : source_color = vec4(0.9, 1.0, 1.0, 1.0);
uniform vec4 outer : source_color = vec4(0.2, 0.9, 0.6, 1.0);
uniform float swirl = 4.0;
uniform float spin_speed = 0.35;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;

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
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + swirl * r - TIME * spin_speed * 6.2831;
	float arms = 0.5 + 0.5 * sin(ang * 3.0 + fbm(p * 3.0 + TIME * 0.2) * 3.0);
	float ring = smoothstep(1.0, 0.7, r) * smoothstep(0.0, 0.25, r);
	vec3 col = mix(outer.rgb, inner.rgb, pow(1.0 - r, 2.0));
	ALBEDO = col * (0.35 + 0.9 * arms);
	ALPHA = ring * opacity * (0.4 + 0.6 * arms);
}
