shader_type canvas_item;

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
	vec4 GI = texture(TEXTURE, UV);
	vec3 tonemapped = aces_tonemap(GI.rgb);
	COLOR = vec4(lin_to_srgb(tonemapped), 1.0);
}
