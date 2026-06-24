shader_type canvas_item;

render_mode blend_mix;

// 输入纹理
uniform sampler2D screen_texture: source_color,hint_screen_texture;       // 原始场景图

uniform sampler2D diffuse_texture: hint_default_transparent;         // 光线追踪输出（PassSharpen）
uniform sampler2D gi_texture;         // 光线追踪输出（PassSharpen）
uniform sampler2D directional_texture;  // 平行光 R=可见性
uniform sampler2D ao_texture;           // 环境光遮蔽 R=AO因子

// 合成参数
uniform float indirect_strength : hint_range(0.0, 4.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 directional_light_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 directional_shadow_color : source_color = vec3(0.0, 0.0, 0.0);

vec3 lin_to_srgb(vec3 color) {
	vec3 x = color * 12.92;
	vec3 y = 1.055 * pow(clamp(color, 0.0, 1.0), vec3(0.4166667)) - 0.055;
	vec3 clr;
	clr.r = (color.r < 0.0031308) ? x.r : y.r;
	clr.g = (color.g < 0.0031308) ? x.g : y.g;
	clr.b = (color.b < 0.0031308) ? x.b : y.b;
	return clr;
}

// ACES Filmic 色调映射
vec3 aces_tonemap(vec3 color) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

void fragment() {
	vec4 screen_color = texture(screen_texture, SCREEN_UV);
	screen_color.rgb += texture(diffuse_texture, SCREEN_UV).rgb;

	vec3 gi_color = texture(gi_texture, SCREEN_UV).rgb * indirect_strength;
	float directional_mask = texture(directional_texture, SCREEN_UV).r;  // 0=阴影, 1=光照
	vec3 directional_color = mix(directional_shadow_color.rgb, directional_light_color.rgb, directional_mask);

	float ao_mask = texture(ao_texture, SCREEN_UV).r;
	vec3 ao_color = vec3(clamp(1.0 - ao_mask * ao_strength, 0.1, 1.0));

	// AO 仅影响间接光，不影响直接光（直接阴影由 directional_mask 处理）
	vec3 combined_light = gi_color * ao_color + directional_color;

	vec3 result = combined_light * screen_color.rgb;

	// 色调映射 + sRGB
	vec3 tonemapped = aces_tonemap(result);
	COLOR = vec4(lin_to_srgb(tonemapped), screen_color.a);
	
	//COLOR.rgb = gi_color;
}
