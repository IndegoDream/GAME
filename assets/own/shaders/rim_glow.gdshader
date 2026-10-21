shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.25, 0.25, 0.28, 1.0);
uniform vec4 rim_color : source_color = vec4(0.3, 1.0, 0.7, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 4.0) = 1.5;
uniform float pulse_speed = 1.6;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.25;
void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	float pulse = 1.0 - pulse_amount + pulse_amount * sin(TIME * pulse_speed);
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.6;
	EMISSION = rim_color.rgb * fres * rim_strength * pulse;
}
