#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（发光体颜色）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出（直接光照 + 反弹漫反射光照）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场
layout(set = 0, binding = 2) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    // --- 公共片元信息（前 8 字节） ---
    vec2 world_to_uv;            // 世界→UV 缩放: uv = world * world_to_uv

    // --- Pass 特有参数（世界单位制） ---
    int number_samples;          // 每像素光线数
    float attenuation;           // 衰减系数
    float maximum_distance;      // 最大搜索距离（世界单位）
    int maximum_steps;           // 最大步进步数
    float emissive_threshold;    // 发光阈值
    float step_safety;           // 步进安全系数（<1.0）
    float noise_strength;        // 逐像素随机角度偏移强度
    int frame_index;             // 帧序号（时域变化种子）
} uniform_parameters;

// Interleaved Gradient Noise (Jorge Jimenez 2014)
// 蓝噪声近似，无需纹理，空间分布比白噪声均匀，配合时域累积收敛更快
float ign(vec2 pos) {
    return fract(52.9829189 * fract(0.06711056 * pos.x + 0.00583715 * pos.y));
}

// ------------------------------------------------------------
// 光线步进采样发光体（直接光照）
// 遇到发光体时收集光照并终止；遇到非发光障碍物时终止
// ------------------------------------------------------------
vec3 march_ray(
    vec2 origin_uv, vec2 direction,
    ivec2 scene_texture_size, float min_step_uv, float surface_threshold,
    float uv_max_distance
) {
    vec2 position = origin_uv;
    float total_distance = 0.0;
    vec3 accumulated_light = vec3(0.0);

    for (int step_index = 0; step_index < uniform_parameters.maximum_steps; step_index++) {
        vec2 scene_coords_f = position * vec2(scene_texture_size);
        ivec2 tc = ivec2(scene_coords_f);

        if (tc.x < 0 || tc.x >= scene_texture_size.x ||
            tc.y < 0 || tc.y >= scene_texture_size.y) break;

        // 有向距离场：R = 到最近异质点距离
        float step_dist = texture(distance_image, position).r;

        if (step_dist < surface_threshold) {
            vec4 surface = texture(scene_image, position);
            float brightness = max(surface.r, max(surface.g, surface.b));

            // --- 发光体：收集光照，光线终止 ---
            if (brightness > uniform_parameters.emissive_threshold) {
                float att = 1.0 / (1.0 + total_distance * uniform_parameters.attenuation);
                // 边缘淡入淡出：光源接近 GI 纹理边缘时亮度衰减，
                // 避免移动摄像机时光线突然出现/消失
                vec2 edge_dist = min(position, vec2(1.0) - position);
                float edge_fade = smoothstep(0.0, 0.1, min(edge_dist.x, edge_dist.y));
                accumulated_light += surface.rgb * att * edge_fade;
                break;
            }

            // --- 非发光障碍物：光线被阻挡，终止 ---
            if (surface.a > 0.001) {
                break;
            }

            // 空区表面附近：按距离场精细步进
            float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
            position += direction * step_size;
            total_distance += step_size;
            continue;
        }

        if (total_distance > uv_max_distance) break;

        float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
        position += direction * step_size;
        total_distance += step_size;
    }

    return accumulated_light;
}

// ------------------------------------------------------------
// 主函数
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = textureSize(scene_image, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    float min_step_uv = 1.0 / float(scene_texture_size.x);
    // 宽高比修正：UV 空间是正方形，视口是长方形，需修正方向使屏幕上为圆
    vec2 aspect_vec = vec2(1.0, float(scene_texture_size.x) / float(scene_texture_size.y));
    // 表面检测阈值（检测带宽度随分辨率自适应：4~16 像素），预算一次供所有光线复用
    float surface_threshold = clamp(float(scene_texture_size.x) / 128.0, 4.0, 16.0) * min_step_uv;
    // 最大搜索距离：世界单位 → UV 空间（乘以 world_to_uv 实现 zoom 补偿）
    float uv_max_distance = uniform_parameters.maximum_distance * uniform_parameters.world_to_uv.x;

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 自身是发光体 → 输出透明（不参与光照混合）
    vec4 self_pixel = texture(scene_image, uv_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness > uniform_parameters.emissive_threshold) {
        imageStore(output_image, coordinates, vec4(self_pixel.rgb, 1.0));
        return;
    }

    // 自身是障碍物 → 输出透明
    if (self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // 空区：发射多条光线，采样发光体收集直接光照
    vec3 total_light = vec3(0.0);
    // IGN 蓝噪声 + frame_index 时域偏移：每帧平移噪声模式，配合 Temporal Pass 加速收敛
    float pixel_noise = ign(coordinates + vec2(uniform_parameters.frame_index)) * uniform_parameters.noise_strength;

    for (int sample_index = 0; sample_index < uniform_parameters.number_samples; sample_index++) {
        float angle = pixel_noise
            + 6.28318530718 * float(sample_index) / float(uniform_parameters.number_samples);
        vec2 direction = normalize(vec2(cos(angle), sin(angle)) * aspect_vec);
        total_light += march_ray(uv_coordinates, direction, scene_texture_size, min_step_uv, surface_threshold, uv_max_distance);
    }

    total_light /= float(uniform_parameters.number_samples);
    imageStore(output_image, coordinates, vec4(total_light, 1.0));
}
