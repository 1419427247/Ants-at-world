shader_type canvas_item;

// 输入纹理
uniform sampler2D screen_texture: hint_screen_texture;       // 原始场景图
uniform sampler2D gi_texture;         // 光线追踪输出（PassRM）
uniform sampler2D directional_texture;  // 平行光
uniform sampler2D ao_texture;           // 环境光遮蔽

// 合成参数
uniform float indirect_strength : hint_range(0.0, 4.0) = 1.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 dir_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.0627);

vec3 lin_to_srgb(vec3 color) {
	vec3 x = color * 12.92;
	vec3 y = 1.055 * pow(clamp(color, 0.0, 1.0), vec3(0.4166667)) - 0.055;
	vec3 clr;
	clr.r = (color.r < 0.0031308) ? x.r : y.r;
	clr.g = (color.g < 0.0031308) ? x.g : y.g;
	clr.b = (color.b < 0.0031308) ? x.b : y.b;
	return clr;
}

// ACES Filmic 色调映射 — 压缩 HDR 动态范围，保留高光细节
vec3 aces_tonemap(vec3 color) {
	const float a = 2.51;
	const float b = 0.03;
	const float c = 2.43;
	const float d = 0.59;
	const float e = 0.14;
	return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
}

void fragment() {
	vec4 scene_sample = texture(screen_texture, UV);
	vec3 scene = scene_sample.rgb;
	float scene_alpha = scene_sample.a;
	vec3 gi = texture(gi_texture, UV).rgb;
	vec3 directional = texture(directional_texture, UV).rrr;
	float ao = texture(ao_texture, UV).r;

	// AO 因子：0=完全遮挡(黑), 1=无遮挡(亮)
	float ao_factor = mix(1.0, 1.0 - ao, ao_strength);

	// 平行光区域用 dir_color，阴影区域用 shadow_color，alpha 控制混合强度
	vec3 shadow_contrib = shadow_color.rgb * (1.0 - directional.r) * shadow_color.a;
	vec3 light_contrib = dir_color.rgb * directional.r * dir_color.a;
	vec3 directional_contribution = mix(shadow_contrib, light_contrib, directional.g);

	// 合成：GI（含直接光+反弹）+ 平行光，AO 只影响光照层
	vec3 lighting = (gi + directional_contribution) * ao_factor;
	vec3 result = mix(vec3(0.0), scene + lighting, scene_alpha);

	// 色调映射 + sRGB
	vec3 tonemapped = aces_tonemap(result);
	COLOR = vec4(lin_to_srgb(tonemapped), scene_alpha);
}
