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
uniform float ao_strength = 1.0;
uniform vec4 directional_light_color : source_color = vec4(1.0, 1.0, 1.0,1.0);
uniform vec4 directional_near_shadow_color : source_color = vec4(0.0, 0.0, 0.0,1.0);
uniform vec4 directional_shadow_color : source_color = vec4(0.0, 0.0, 0.0,0.0);
uniform float shadow_dist_scale : hint_range(0.0, 4.0) = 1.0;
uniform float shadow_dist_bias : hint_range(-1.0, 1.0) = 0.0;

// 像素化：0=关闭，>0 表示每个像素块的边长（像素数）
uniform float pixel_size : hint_range(0.0, 32.0, 1.0) = 0.0;
uniform float grid_line_width : hint_range(0.0, 4.0, 0.5) = 0.0;
uniform vec4 grid_line_color : source_color = vec4(0.0, 0.0, 0.0, 0.3);

// GI 纹理 UV 映射（当 GILightViewport 有 margin 时用于边缘裁剪）
// gi_uv = gi_uv_offset + SCREEN_UV * gi_uv_scale
// margin=0 时 offset=(0,0), scale=(1,1)，gi_uv == SCREEN_UV，向后兼容。
uniform vec2 gi_uv_offset = vec2(0.0, 0.0);
uniform vec2 gi_uv_scale = vec2(1.0, 1.0);

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
	// 像素化：将 UV 对齐到 pixel_size 宽的网格
	vec2 uv = SCREEN_UV;
	 if (pixel_size > 0.5) {
	 	vec2 step = SCREEN_PIXEL_SIZE * pixel_size;
	 	uv = floor(uv / step) * step + step * 0.5;
	 }

	// GI 纹理 UV：将主视口 SCREEN_UV 映射到 GI 纹理中主相机视野对应的区域
	vec2 gi_uv = gi_uv_offset + uv * gi_uv_scale;
	vec4 screen_color = texture(screen_texture, uv);
	screen_color.rgb += texture(diffuse_texture, gi_uv).rgb;

	vec3 gi_color = texture(gi_texture, gi_uv).rgb * indirect_strength;

	float directional_mask = texture(directional_texture, gi_uv).r;  // 0=阴影, 1=光照
	directional_mask = clamp(directional_mask + ((texture(directional_texture, gi_uv).g + shadow_dist_bias) * shadow_dist_scale), 0.0, 1.0);

	vec4 directional_color = mix(directional_shadow_color, directional_light_color, directional_mask);

	float ao_mask = texture(ao_texture, gi_uv).r;
	// GI 和平行光都会填充 AO 的暗角
	float gi_lum = dot(gi_color, vec3(0.299, 0.587, 0.114));
	float any_light = max(gi_lum, directional_mask);
	float ao_dark = ao_mask * ao_strength * (1.0 - clamp(any_light, 0.0, 1.0));
	float ambient_level = clamp(0.3 * (1.0 - ao_dark), 0.0, 0.3);
	vec3 ambient = vec3(ambient_level);

	// GI 不受 AO 影响，方向光独立叠加
	vec3 lighting = max(gi_color, ambient) + directional_color.rgb;
	vec3 result = screen_color.rgb * lighting;

	// 色调映射 + sRGB
	vec3 tonemapped = aces_tonemap(result);
	COLOR = vec4(lin_to_srgb(tonemapped), screen_color.a);

	// 网格描边（仅在 pixel_size 开启时生效）
	if (pixel_size > 0.5 && grid_line_width > 0.001) {
		vec2 step = SCREEN_PIXEL_SIZE * pixel_size;
		vec2 grid_origin = floor(SCREEN_UV / step) * step;
		vec2 local = SCREEN_UV - grid_origin;
		vec2 lw = SCREEN_PIXEL_SIZE * grid_line_width;
		if (local.x < lw.x || local.x > step.x - lw.x ||
			local.y < lw.y || local.y > step.y - lw.y) {
			COLOR = mix(COLOR, grid_line_color, grid_line_color.a);
		}
	}
	
	//COLOR.rgb = gi_color;
}
