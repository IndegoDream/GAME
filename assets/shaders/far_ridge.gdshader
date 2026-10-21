// Round 63: the far ranges -- mountains a kilometre and more away, drawn as a
// ring of silhouette around the world. Each ring is one layer; the farther a
// layer, the more it takes the colour of the haze between (aerial perspective),
// which is what makes a distance read as a distance. The ridge line is noise
// along the ring; below it the layer fades into the haze at its foot.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque;

uniform vec4 base : source_color = vec4(0.32, 0.36, 0.42, 1.0);
uniform vec4 haze : source_color = vec4(0.74, 0.8, 0.88, 1.0);
uniform float far_k = 0.5;          // 0 near ... 1 farthest: how much of the haze
uniform float freq = 9.0;           // ridges around the ring
uniform float seed = 1.0;
uniform float peak = 0.85;          // the highest a ridge reaches (0..1 of the strip)
uniform float low = 0.35;           // the lowest saddle
uniform float snow = 0.0;           // snow on the peaks (0..1)

float h11(float x) { return fract(sin(x * 127.1 + seed * 31.7) * 43758.5453); }

float n1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(h11(i), h11(i + 1.0), f);
}

float ridge(float x) {
	float v = 0.0;
	float a = 0.55;
	float f = 1.0;
	for (int o = 0; o < 5; o++) {
		v += a * (1.0 - abs(n1(x * f) * 2.0 - 1.0));
		f *= 2.13;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float x = UV.x * freq;
	float r = mix(low, peak, clamp(ridge(x) / 1.2, 0.0, 1.0));
	float y = 1.0 - UV.y;           // 0 at the foot, 1 at the top of the strip
	if (y > r) {
		discard;
	}
	vec3 c = mix(base.rgb, haze.rgb, far_k);
	// lighter toward the foot, where more air lies between
	c = mix(c, haze.rgb, smoothstep(r * 0.65, 0.0, y) * 0.55);
	// a little shade on one flank of each ridge
	float slope = ridge(x + 0.02) - ridge(x - 0.02);
	c *= 1.0 - clamp(slope * 1.4, -0.15, 0.25) * (1.0 - far_k);
	c = mix(c, mix(vec3(0.93, 0.95, 1.0), haze.rgb, far_k * 0.6), snow * smoothstep(r - 0.12, r - 0.02, y));
	ALBEDO = c;
}
