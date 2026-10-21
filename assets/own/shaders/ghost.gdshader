shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;
uniform vec4 color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float rim_power = 2.0;
uniform float band_speed = 0.4;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	float band = smoothstep(0.85, 1.0, sin(local_pos.y * 3.0 - TIME * band_speed * 6.2831) * 0.5 + 0.5);
	ALBEDO = color.rgb;
	EMISSION = color.rgb * (fres * 1.2 + band * 0.8);
	ALPHA = clamp((fres * 0.8 + 0.2 + band * 0.3) * opacity, 0.0, 1.0);
}
