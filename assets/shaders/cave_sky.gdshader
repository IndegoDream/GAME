shader_type sky;
// The roof of the deep (round 37 -- Robert: "give it a sky or ceiling"). What
// you see above the walls underground: a far, rough cavern vault -- dark rock
// with paler seams, a slow mist drifting under it, and specks of glowing
// mineral that pulse faintly, like stars that never learned to be stars.
// Tinted by the floor's own light (rock_tint, glow_tint).

uniform vec3 rock_tint : source_color = vec3(0.16, 0.14, 0.15);
uniform vec3 glow_tint : source_color = vec3(0.45, 0.8, 1.0);
uniform float glow_amount : hint_range(0.0, 2.0) = 0.8;
uniform float mist_amount : hint_range(0.0, 1.0) = 0.35;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = max(d.y, 0.0);
	vec2 uv = d.xz / (up + 0.25) * 2.2;
	// the rock: broken, layered, with pale seams where it cracked
	float r = fbm(uv * 1.3);
	float seam = smoothstep(0.02, 0.0, abs(fbm(uv * 0.7 + 7.0) - 0.5)) * 0.6;
	vec3 col = rock_tint * (0.45 + 0.9 * r) + rock_tint * seam * 1.4;
	// darker toward the horizon, where the vault falls away into the dark
	col *= mix(0.25, 1.0, smoothstep(0.0, 0.55, up));
	// glowing mineral specks
	vec3 sp = d * 160.0;
	vec3 cell = floor(sp);
	float h = hash3(cell);
	if (h > 0.992 && up > 0.05) {
		vec3 c = cell + vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 5.1));
		float pulse = 0.5 + 0.5 * sin(TIME * (0.4 + h * 1.3) + h * 40.0);
		col += glow_tint * smoothstep(0.6, 0.0, length(sp - c)) * pulse * glow_amount * (0.5 + fract(h * 911.0));
	}
	// a slow mist under the roof
	float m = fbm(uv * 0.55 + vec2(TIME * 0.006, TIME * 0.003));
	col = mix(col, rock_tint * 1.8 + vec3(0.03), smoothstep(0.45, 0.85, m) * mist_amount * smoothstep(0.0, 0.4, up));
	COLOR = col;
}
