// Round 47: leaves and needles -- photo-scanned leaf cards (Poly Haven, CC0)
// that sway in the wind, let the light through from behind, and cut out
// cleanly. UV.x runs from where a card meets its branch (0) to its tip (1):
// the tip moves, the base stays.
// Round 48: leaves between the camera and you thin out (a dither), so a
// tree never hides you.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.07;
uniform float alpha_cut = 0.5;
uniform float translucency = 0.35;
uniform float see_through = 2.6;
global uniform vec3 player_pos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = clamp(UV.x, 0.0, 1.0);
	float t = TIME;
	VERTEX += vec3(sin(t * 1.3 + wp.x * 0.35 + wp.z * 0.2), sin(t * 2.1 + wp.y) * 0.4, cos(t * 1.1 + wp.z * 0.35)) * sway * bend;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * tint.rgb * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	if (see_through > 0.0) {
		vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 seg = (player_pos + vec3(0.0, 1.0, 0.0)) - cam;
		float l2 = max(dot(seg, seg), 0.0001);
		float h = clamp(dot(wp - cam, seg) / l2, 0.0, 1.0);
		float d = length(wp - (cam + seg * h));
		if (h < 0.97 && d < see_through) {
			float keep = smoothstep(see_through * 0.45, see_through, d);
			float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
			if (n > keep) {
				discard;
			}
		}
	}
	ROUGHNESS = 0.8;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * translucency;
}
