shader_type sky;
// Eliet's sky (round 37 -- Robert: "make the world more realistic, give it a
// sky... clouds, stars"). One shader for every hour: a gradient that follows
// the real clock (daylight 0 = night .. 1 = day, dusk warms the horizon), a
// sun by day and a moon by night, two layers of drifting clouds lit by them,
// and a field of stars that only shows when it's dark (and twinkles).

uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform float dusk : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_dir = vec3(0.4, 0.6, -0.5);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_speed = 0.004;
uniform vec3 day_top : source_color = vec3(0.30, 0.50, 0.82);
uniform vec3 day_horizon : source_color = vec3(0.74, 0.82, 0.90);
uniform vec3 night_top : source_color = vec3(0.012, 0.018, 0.05);
uniform vec3 night_horizon : source_color = vec3(0.06, 0.08, 0.15);
uniform vec3 dusk_horizon : source_color = vec3(0.98, 0.55, 0.30);

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
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, -1.0, 1.0);
	float h = pow(1.0 - clamp(up, 0.0, 1.0), 2.4);
	vec3 top = mix(night_top, day_top, daylight);
	vec3 hor = mix(night_horizon, day_horizon, daylight);
	hor = mix(hor, dusk_horizon, dusk * 0.75);
	vec3 col = mix(top, hor, h);
	if (up < 0.0) {
		// below the horizon: a hazy ground colour, so nothing reads as void
		col = mix(hor * 0.55, hor * 0.3, clamp(-up * 3.0, 0.0, 1.0));
	}
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	// the sun (by day) or the moon (by night): a disc and a glow
	if (daylight > 0.05) {
		col += vec3(1.0, 0.92, 0.75) * pow(sdot, 1800.0) * 18.0 * daylight;
		col += mix(vec3(1.0, 0.6, 0.35), vec3(1.0, 0.95, 0.85), daylight) * pow(sdot, 12.0) * 0.35 * daylight;
	}
	vec3 md = normalize(vec3(-sd.x, abs(sd.y) * 0.8 + 0.3, -sd.z));
	float mdot = max(dot(d, md), 0.0);
	float night = 1.0 - smoothstep(0.0, 0.45, daylight);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.99965, 0.9998, mdot) * 1.6 * night;
	col += vec3(0.5, 0.6, 0.85) * pow(mdot, 60.0) * 0.18 * night;
	// stars: a fixed field on the dome, twinkling, gone by day
	if (up > 0.0 && night > 0.01) {
		vec3 sp = d * 220.0;
		vec3 cell = floor(sp);
		float r = hash3(cell);
		if (r > 0.9965) {
			vec3 c = cell + vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 5.1));
			float dist = length(sp - c);
			float tw = 0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 60.0);
			col += vec3(0.9, 0.93, 1.0) * smoothstep(0.55, 0.0, dist) * tw * night * (0.6 + 1.4 * fract(r * 977.0)) * smoothstep(0.0, 0.25, up);
		}
		// the faint band of the sky-river
		float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.2, 1.0))) * 3.2, 2.0));
		col += vec3(0.25, 0.27, 0.35) * band * fbm(d.xz * 9.0 + d.y * 4.0) * 0.35 * night * smoothstep(0.0, 0.3, up);
	}
	// clouds: two layers projected on a high flat roof, drifting
	if (up > 0.02) {
		vec2 uv = d.xz / (up + 0.08);
		float t = TIME * cloud_speed;
		float c1 = fbm(uv * 1.1 + vec2(t, t * 0.4));
		float c2 = fbm(uv * 2.6 - vec2(t * 1.7, t * 0.6) + 4.0);
		float cov = mix(0.62, 0.38, cloud_cover);
		float dens = smoothstep(cov, cov + 0.28, c1 * 0.72 + c2 * 0.38);
		dens *= smoothstep(0.02, 0.22, up);
		// lit from the sun (or the moon), darker underneath, warm at dusk
		float lit = 0.55 + 0.45 * pow(max(dot(d, sd), 0.0), 3.0);
		vec3 cday = mix(vec3(0.62, 0.65, 0.72), vec3(1.0, 0.99, 0.97), lit);
		cday = mix(cday, vec3(1.0, 0.72, 0.5), dusk * 0.6);
		vec3 cnight = vec3(0.07, 0.08, 0.12) + vec3(0.12, 0.13, 0.17) * pow(mdot, 6.0);
		vec3 ccol = mix(cnight, cday, daylight);
		col = mix(col, ccol, dens * 0.9);
	}
	COLOR = col;
}
