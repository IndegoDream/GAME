// Round 52: the edges of the screen -- a soft cinematic vignette always, red
// when you're hit, a slow pulse when you're close to falling (HUD.gd).
shader_type canvas_item;

uniform float vignette = 0.32;
uniform float hurt = 0.0;
uniform float low = 0.0;
uniform float pulse = 0.0;
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0) / vec2(aspect * 0.5 + 0.5, 1.0);
	float d = length(p);
	float v = smoothstep(0.42, 0.95, d) * vignette;
	float edge = smoothstep(0.30, 0.90, d);
	float r = clamp(max(hurt, low * (0.55 + 0.45 * sin(pulse))), 0.0, 1.0) * edge;
	float a = clamp(v + r * 0.75, 0.0, 0.9);
	vec3 c = mix(vec3(0.0), vec3(0.5, 0.02, 0.02), clamp(r / (v + r + 0.0001), 0.0, 1.0));
	COLOR = vec4(c, a);
}
