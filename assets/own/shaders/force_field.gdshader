shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
uniform vec4 color : source_color = vec4(0.35, 0.8, 1.0, 1.0);
uniform float edge_power : hint_range(0.5, 8.0) = 2.5;
uniform float scan_speed = 0.6;
uniform float scan_lines = 18.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.7;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), edge_power);
	float scan = 0.5 + 0.5 * sin((local_pos.y * scan_lines) - TIME * scan_speed * 6.2831);
	float a = clamp(fres + 0.12 + 0.18 * scan, 0.0, 1.0) * opacity;
	ALBEDO = color.rgb;
	ALPHA = a;
}
