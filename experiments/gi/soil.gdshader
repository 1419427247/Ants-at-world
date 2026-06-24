shader_type canvas_item;

// 泥土参数
uniform vec3 dirt_color : source_color = vec3(0.42, 0.28, 0.15);
uniform vec3 dark_color : source_color = vec3(0.30, 0.18, 0.08);
uniform vec3 light_color : source_color = vec3(0.55, 0.38, 0.22);
uniform float noise_scale : hint_range(0.5, 8.0) = 3.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float pebble_amount : hint_range(0.0, 0.3) = 0.08;

// 简化哈希
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// 2D 噪声
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM 分形噪声
float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV * noise_scale;

    // 基础地形噪声（大尺度变化）
    float base_noise = fbm(uv);

    // 细节噪声（小尺度纹理）
    float detail_noise = noise(uv * 4.0) * 0.3;

    // 混合基础颜色
    vec3 color = mix(dark_color, light_color, base_noise + detail_noise);

    // 粗糙度纹理
    float rough = noise(uv * 6.0 + 1.5);
    color = mix(color, color * (0.9 + 0.2 * rough), roughness);

    // 小石子
    float pebble_noise = noise(uv * 12.0);
    float pebble = smoothstep(1.0 - pebble_amount, 1.0, pebble_noise);
    vec3 pebble_color = vec3(0.5, 0.4, 0.3);
    color = mix(color, pebble_color, pebble * 0.6);

    // 有机斑点（深色腐殖质）
    float organic = noise(uv * 2.0 + 7.0);
    float spot = smoothstep(0.55, 0.7, organic);
    color = mix(color, dark_color * 0.8, spot * 0.25);

    COLOR = vec4(color, 1.0);
}
