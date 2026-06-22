#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 直接光照结果（RaymarchPass 输出）
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D direct_light_image;
// binding 1: 输出（直接 + 间接光照）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 场景纹理（判断发光体/障碍物）
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D scene_image;
// binding 3: 有向距离场
layout(set = 0, binding = 3, rgba16f) uniform restrict readonly image2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int   num_samples;          // 每像素次级光线数
    float attenuation;          // 间接光衰减系数
    float maximum_distance;     // 最大搜索距离
    int   maximum_steps;        // 最大步进次数
    float emissive_threshold;   // 发光阈值
    float step_safety;          // 步进安全系数
    float indirect_strength;    // 间接光强度倍数
} uniform_parameters;

const float GOLDEN_ANGLE = 2.399963229728653;

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

// ------------------------------------------------------------
// 次级光线步进：收集被照亮表面的间接光
// 与 RaymarchPass 不同，此处收集非发光但被照亮的表面
// ------------------------------------------------------------
vec3 march_indirect_ray(
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

        float step_dist = imageLoad(distance_image, texture_coordinates).r;

        // 足够接近异质表面
        if (step_dist < 0.01) {
            vec4 surface = imageLoad(scene_image, texture_coordinates);
            float scene_brightness = max(surface.r, max(surface.g, surface.b));

            // 跳过发光体（它们是直接光源，不作为间接光来源）
            if (scene_brightness >= uniform_parameters.emissive_threshold) {
                break;
            }

            // 非发光但非黑色的像素视为障碍物：收集间接光后停止
            if (scene_brightness > 0.001) {
                // 检查是否被照亮（直接光照结果中有颜色）
                vec3 direct_light = imageLoad(direct_light_image, texture_coordinates).rgb;
                float light_brightness = max(direct_light.r, max(direct_light.g, direct_light.b));

                if (light_brightness > 0.001) {
                    // 收集间接光：被照亮表面的颜色 × 距离衰减
                    float att = 1.0 / (1.0 + total_distance_2d * uniform_parameters.attenuation);
                    accumulated_light += direct_light * att * uniform_parameters.indirect_strength;
                }

                // 障碍物阻挡光线，停止
                break;
            }

            // 空区表面附近但没撞到固体：按距离场精细步进
            float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
            position += direction * step_size;
            total_distance_2d += step_size;
            continue;
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

    // 直接光照结果
    vec4 direct_light = imageLoad(direct_light_image, coordinates);

    // 自身是发光体或障碍物：直接输出直接光照结果
    vec4 self_pixel = imageLoad(scene_image, scene_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness >= uniform_parameters.emissive_threshold || self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, direct_light);
        return;
    }

    // 追踪次级光线，收集间接光
    vec3 indirect_light = vec3(0.0);
    float pixel_offset = hash12(vec2(coordinates)) * GOLDEN_ANGLE;

    for (int sample_index = 0; sample_index < uniform_parameters.num_samples; sample_index++) {
        float angle = pixel_offset + GOLDEN_ANGLE * float(sample_index);
        vec2 direction = vec2(cos(angle), sin(angle));
        indirect_light += march_indirect_ray(uv_coordinates, direction, scene_texture_size_vec, min_step_uv);
    }

    indirect_light /= float(uniform_parameters.num_samples);

    // 输出：直接光照 + 间接光照
    vec3 result = direct_light.rgb + indirect_light;
    imageStore(output_image, coordinates, vec4(result, 1.0));
}
