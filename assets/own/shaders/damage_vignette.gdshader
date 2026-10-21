shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 hurt_color : source_color = vec4(0.75, 0.04, 0.04, 1.0);
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float low_health : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec3 scene = texture(screen_tex, SCREEN_UV).rgb;
	float d = distance(SCREEN_UV, vec2(0.5));
	float edge = smoothstep(0.25, 0.75, d);
	float grey = dot(scene, vec3(0.299, 0.587, 0.114));
	scene = mix(scene, vec3(grey), low_health * 0.6);
	float pulse = 0.85 + 0.15 * sin(TIME * 7.0);
	COLOR = vec4(mix(scene, hurt_color.rgb, edge * hurt * pulse), 1.0);
}
