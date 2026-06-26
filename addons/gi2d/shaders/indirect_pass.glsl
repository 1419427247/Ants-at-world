#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（发光体颜色，Alpha=障碍物标记）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出（直接 GI + 间接光，供 Composite 直接使用）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 经降噪后的直接光照图（PassSharpenV 输出），作为反弹光源 + 初始 GI 基础值
layout(set = 0, binding = 2) uniform sampler2D gi_image;
// binding 3: 有向距离场（PassDF 输出，RGBA16F: R=到最近异质点距离）
layout(set = 0, binding = 3) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    // --- 公共片元信息（前 8 字节） ---
    vec2 world_to_uv;             // 世界→UV 缩放: uv = world * world_to_uv

    // --- Pass 特有参数（世界单位制） ---
    int   num_samples;            // 每像素次级光线数
    float attenuation;            // 距离衰减系数
    float maximum_distance;       // 最大搜索距离（世界单位）
    int   maximum_steps;          // 每段最大步进次数
    float emissive_threshold;     // 发光阈值
    float step_safety;            // 步进安全系数
    float indirect_strength;      // 间接光强度倍数
    float rotation_offset;        // 射线初始旋转偏移（弧度）
    float noise_strength;         // 逐像素随机角度偏移强度（0=无, 1=全随机）
} uniform_parameters;

// 逐像素伪随机数
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ------------------------------------------------------------
// 次级光线步进：收集被 GI 照亮的表面发出的间接光（2-bounce）
//
// 沿初始方向步进，遇到表面时：
//   1. 发光体 → 直接收集发光颜色（直接光照的次级贡献）
//   2. 非发光表面 → 从 gi_image 读取该处的 GI 直接光照，作为反弹光源收集
//
// 这样，发光体照亮遮挡物 A → A 被 gi_image 记录 → 次级光线从遮挡物 B 出发，
// 命中 A 时读取 gi_image 中 A 的光照 → 实现 2-bounce 间接光（色彩溢出）
// ------------------------------------------------------------
vec3 march_indirect_ray(
    vec2 origin_uv, vec2 direction,
    ivec2 scene_texture_size, float min_step_uv, float surface_threshold,
    float uv_max_distance
) {
    vec2 position = origin_uv;
    float total_distance = 0.0;

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

            // --- 发光体：直接收集发光颜色（边缘渐隐防闪烁） ---
            if (brightness > uniform_parameters.emissive_threshold) {
                float att = 1.0 / (1.0 + total_distance * uniform_parameters.attenuation);
                vec2 edge_dist = min(position, vec2(1.0) - position);
                float edge_fade = smoothstep(0.0, 0.1, min(edge_dist.x, edge_dist.y));
                return surface.rgb * att * edge_fade * uniform_parameters.indirect_strength;
            }

            // --- 非发光表面：从 GI 光照图读取反弹光源 ---
            // gi_image 记录了该位置被直接 GI 照亮的光照值
            // 障碍物表面本身在 gi_image 中为黑（无直接光照），
            // 但紧邻空区像素在 gi_image 中有累积直接光照值，作为反弹光源
            vec3 gi_light = texture(gi_image, position).rgb;
            float gi_brightness = max(gi_light.r, max(gi_light.g, gi_light.b));

            if (gi_brightness > uniform_parameters.emissive_threshold) {
                float att = 1.0 / (1.0 + total_distance * uniform_parameters.attenuation);
                return gi_light * att * uniform_parameters.indirect_strength;
            }

            // 无光照贡献：终止（障碍物阻挡或空区无光照）
            break;
        }

        if (total_distance > uv_max_distance) break;

        float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
        position += direction * step_size;
        total_distance += step_size;
    }

    return vec3(0.0);
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
    // 宽高比修正：UV 空间是正方形，视口是长方形，需修正方向使光线各向同性
    vec2 aspect_vec = vec2(1.0, float(scene_texture_size.x) / float(scene_texture_size.y));
    // 表面检测阈值（检测带宽度随分辨率自适应：4~16 像素），预算一次供所有光线复用
    float surface_threshold = clamp(float(scene_texture_size.x) / 128.0, 4.0, 16.0) * min_step_uv;
    float uv_max_distance = uniform_parameters.maximum_distance * uniform_parameters.world_to_uv.x;

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 自身是发光体 → 不产生间接光
    vec4 self_pixel = texture(scene_image, uv_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness > uniform_parameters.emissive_threshold) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // 自身是障碍物 → 不产生间接光
    if (self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // 空区：从 gi_image 读取直接 GI 光照作为基础值
    vec3 direct_gi = texture(gi_image, uv_coordinates).rgb;

    // 发射次级光线收集间接光（2-bounce）
    vec3 total_indirect_light = vec3(0.0);
    float pixel_noise = hash12(vec2(coordinates)) * uniform_parameters.noise_strength;

    for (int sample_index = 0; sample_index < uniform_parameters.num_samples; sample_index++) {
        float angle = uniform_parameters.rotation_offset + pixel_noise
            + 6.28318530718 * float(sample_index) / float(uniform_parameters.num_samples);
        vec2 direction = normalize(vec2(cos(angle), sin(angle)) * aspect_vec);
        total_indirect_light += march_indirect_ray(
            uv_coordinates, direction,
            scene_texture_size, min_step_uv, surface_threshold,
            uv_max_distance
        );
    }

    total_indirect_light /= float(uniform_parameters.num_samples);

    // 输出：直接 GI + 间接光（Composite 直接使用）
    imageStore(output_image, coordinates, vec4(direct_gi + total_indirect_light, 1.0));
}
