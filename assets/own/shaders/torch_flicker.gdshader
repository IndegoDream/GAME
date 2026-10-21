shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.35, 0.22, 0.12, 1.0);
uniform vec4 fire_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
uniform float base_glow : hint_range(0.0, 6.0) = 1.8;
uniform float flicker_speed = 9.0;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.35;
float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
void fragment() {
	float t = TIME * flicker_speed;
	float f = mix(h1(floor(t)), h1(floor(t) + 1.0), fract(t));
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.7;
	EMISSION = fire_color.rgb * base_glow * (1.0 - flicker_amount + flicker_amount * f);
}
