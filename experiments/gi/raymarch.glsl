#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（发光体颜色）
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D scene_image;
// binding 1: 输出
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=异质点UV, A=1）
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int number_samples;          // 每像素光线数
    float attenuation;           // 衰减系数
    float maximum_distance;      // 最大搜索距离（归一化）
    int maximum_steps;           // 主步进最大步数
    float emissive_threshold;    // 发光阈值
    float step_safety;           // 步进安全系数（<1.0）
} uniform_parameters;

// 黄金角度
const float GOLDEN_ANGLE = 2.399963229728653;

// PCG 哈希
uint pcg_hash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float hash12(vec2 position) {
    uvec2 p = uvec2(position);
    uint v = p.x * 1973u + p.y * 9277u + 26699u;
    return float(pcg_hash(v)) * (1.0 / 4294967296.0);
}

vec4 sample_scene(ivec2 coordinates) {
    return imageLoad(scene_image, coordinates);
}

// ------------------------------------------------------------
// 光线步进：收集可见发光体（纯 2D，无高度）
// ------------------------------------------------------------
vec3 march_ray(
    vec2 origin_uv, vec2 direction,
    vec2 scene_texture_size_vec, float min_step_uv
) {
    vec2 position = origin_uv;
    float total_distance_2d = 0.0;
    vec3 accumulated_light = vec3(0.0);

    for (int step_index = 0; step_index < uniform_parameters.maximum_steps; step_index++) {
        vec2 scene_coords_f = position * scene_texture_size_vec;
        ivec2 texture_coordinates = ivec2(scene_coords_f);

        if (texture_coordinates.x < 0 || texture_coordinates.x >= int(scene_texture_size_vec.x) ||
            texture_coordinates.y < 0 || texture_coordinates.y >= int(scene_texture_size_vec.y)) break;

        // 有向距离场：R=到最近异质点距离
        float step_dist = imageLoad(distance_image, texture_coordinates).r;

        // 足够接近异质表面
        if (step_dist < 0.01) {
            vec4 surface = sample_scene(texture_coordinates);
            float brightness = max(surface.r, max(surface.g, surface.b));

            if (brightness >= uniform_parameters.emissive_threshold) {
                // 可见发光体，收集光照
                float att = 1.0 / (1.0 + total_distance_2d * uniform_parameters.attenuation);
                accumulated_light = surface.rgb * att;
                break;
            } else if (brightness > 0.001) {
                // 非发光但非黑色的像素视为障碍物：光线被阻挡
                break;
            } else {
                // 空区表面附近但没撞到固体：按距离场精细步进
                float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
                position += direction * step_size;
                total_distance_2d += step_size;
                continue;
            }
        }

        if (total_distance_2d > uniform_parameters.maximum_distance) break;

        float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
        position += direction * step_size;
        total_distance_2d += step_size;
    }

    return accumulated_light;
}

// ------------------------------------------------------------
// 主函数
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = imageSize(scene_image);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 scene_texture_size_vec = vec2(scene_texture_size);
    float min_step_uv = 1.0 / float(scene_texture_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);
    ivec2 scene_coordinates = ivec2(uv_coordinates * scene_texture_size_vec);

    vec4 self_pixel = sample_scene(scene_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));

    // 自身是发光体：直接输出
    if (self_brightness >= uniform_parameters.emissive_threshold) {
        imageStore(output_image, coordinates, self_pixel);
        return;
    }

    // 自身是障碍物（非发光固体）：直接输出黑色
    if (self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    vec3 total_light = vec3(0.0);

    float pixel_offset = hash12(vec2(coordinates)) * GOLDEN_ANGLE;

    for (int sample_index = 0; sample_index < uniform_parameters.number_samples; sample_index++) {
        float angle = pixel_offset + GOLDEN_ANGLE * float(sample_index);
        vec2 direction = vec2(cos(angle), sin(angle));
        total_light += march_ray(uv_coordinates, direction, scene_texture_size_vec, min_step_uv);
    }

    total_light /= float(uniform_parameters.number_samples);
    imageStore(output_image, coordinates, vec4(total_light, 1.0));
}
