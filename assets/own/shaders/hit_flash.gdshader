shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.6, 0.55, 0.5, 1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec4 flash_color : source_color = vec4(1.0, 0.95, 0.9, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
void fragment() {
	vec3 base = use_tex ? texture(albedo_tex, UV).rgb * albedo.rgb : albedo.rgb;
	ALBEDO = mix(base, flash_color.rgb, flash);
	EMISSION = flash_color.rgb * flash * 1.5;
	ROUGHNESS = roughness;
}
