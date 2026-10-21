// Round 48: the land beyond the edge of the map -- grass in the valleys,
// rock where it's steep or high, snow on the peaks (more in Frost).
// World-space triplanar so a hill a kilometre wide never stretches.
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(0.85, 0.9, 0.75, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.75, 0.72, 0.68, 1.0);
uniform float snow_line = 70.0;
uniform float scale = 0.08;
// round 63: roads drawn into the ground -- soft, curving edges instead of
// square tiles, and the same roads running on past the map into the land
// (a mask over the map and the land around it: Level.road_mask)
uniform float use_roads = 0.0;
uniform sampler2D road_mask : filter_linear, repeat_disable;
uniform sampler2D road_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 road_tint : source_color = vec4(0.82, 0.78, 0.72, 1.0);
uniform float road_scale = 0.22;
// round 63: Frost's snow lying on the low ground too, patchy, thinner on the roads
uniform float snow_cover = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 tri(sampler2D t, vec3 p, vec3 n) {
	vec3 b = pow(abs(n), vec3(4.0));
	b /= (b.x + b.y + b.z);
	return texture(t, p.zy * scale).rgb * b.x + texture(t, p.xz * scale).rgb * b.y + texture(t, p.xy * scale).rgb * b.z;
}

void fragment() {
	float steep = 1.0 - clamp(wnorm.y, 0.0, 1.0);
	float rock = smoothstep(0.25, 0.55, steep) + smoothstep(25.0, 55.0, wpos.y);
	rock = clamp(rock, 0.0, 1.0);
	vec3 g = tri(grass_tex, wpos, wnorm) * grass_tint.rgb;
	vec3 r = tri(rock_tex, wpos * 0.5, wnorm) * rock_tint.rgb;
	vec3 col = mix(g, r, rock);
	float snow = smoothstep(snow_line, snow_line + 15.0, wpos.y + sin(wpos.x * 0.05) * 6.0) * smoothstep(0.75, 0.3, steep);
	col = mix(col, vec3(0.92, 0.94, 0.98), snow);
	if (use_roads > 0.5) {
		// the edge wanders a little (noise) so a road never has a ruled line
		vec2 warp = vec2(vnoise(wpos.xz * 0.35), vnoise(wpos.zx * 0.35 + 7.0)) - 0.5;
		vec2 uv = (wpos.xz + warp * 1.1 - mask_rect.xy) / mask_rect.zw;
		// five taps: the mask is a metre a pixel, so soften it into curves
		vec2 px = vec2(1.6) / mask_rect.zw;
		float m = texture(road_mask, uv).r * 0.36
			+ (texture(road_mask, uv + vec2(px.x, 0.0)).r + texture(road_mask, uv - vec2(px.x, 0.0)).r
			+ texture(road_mask, uv + vec2(0.0, px.y)).r + texture(road_mask, uv - vec2(0.0, px.y)).r) * 0.16;
		float edge = vnoise(wpos.xz * 1.3) * 0.22;
		float road = smoothstep(0.30, 0.62, m + edge - 0.11) * (1.0 - rock) * (1.0 - snow);
		vec3 rc = texture(road_tex, wpos.xz * road_scale).rgb * road_tint.rgb;
		// a worn verge: the grass browns a little before the stones start
		col = mix(col, col * vec3(0.92, 0.86, 0.72), smoothstep(0.12, 0.4, m) * (1.0 - rock));
		col = mix(col, rc, road);
		col = mix(col, vec3(0.88, 0.91, 0.97), snow_cover * (0.45 + 0.5 * vnoise(wpos.xz * 0.09)) * (1.0 - road * 0.65));
	} else {
		col = mix(col, vec3(0.88, 0.91, 0.97), snow_cover * (0.45 + 0.5 * vnoise(wpos.xz * 0.09)));
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, snow);
}

// Wrapped light: a hill facing away from a low sun still reads as a hill
// (sky-lit), not a black cut-out against the mountains.
void light() {
	float w = clamp(dot(NORMAL, LIGHT) * 0.6 + 0.4, 0.0, 1.0);
	DIFFUSE_LIGHT += w * w * ATTENUATION * LIGHT_COLOR / PI;
}
