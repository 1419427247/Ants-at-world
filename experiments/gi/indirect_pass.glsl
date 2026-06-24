#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（source_viewport，判断发光体/障碍物/空区）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出（直接光照 + 间接光照，完整 GI）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: PassRM 输出（extra_input[0]，障碍物位置存有自身颜色，作为反弹光源）
layout(set = 0, binding = 2) uniform sampler2D passrm_image;
// binding 3: 有向距离场（extra_input[1] = PassDF）
layout(set = 0, binding = 3) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int   num_samples;          // 每像素次级光线数
    float attenuation;          // 间接光衰减系数
    float maximum_distance;     // 最大搜索距离
    int   maximum_steps;        // 最大步进次数
    float emissive_threshold;   // 发光阈值
    float step_safety;          // 步进安全系数
    float indirect_strength;    // 间接光强度倍数
    float rotation_offset;      // 射线初始旋转偏移（弧度）
    float noise_strength;       // 逐像素随机角度偏移强度（0=无, 1=全随机）
} uniform_parameters;

// 逐像素伪随机数
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ------------------------------------------------------------
// 次级光线步进：收集被照亮表面的间接光
// 命中障碍物时，从 PassRM 读取障碍物颜色作为反弹光源
// ------------------------------------------------------------
vec3 march_indirect_ray(
    vec2 origin_uv, vec2 direction,
    vec2 scene_texture_size_vec, float min_step_uv
) {
    vec2 position = origin_uv;
    float total_distance_2d = 0.0;

    for (int step_index = 0; step_index < uniform_parameters.maximum_steps; step_index++) {
        vec2 scene_coords_f = position * scene_texture_size_vec;
        ivec2 texture_coordinates = ivec2(scene_coords_f);

        if (texture_coordinates.x < 0 || texture_coordinates.x >= int(scene_texture_size_vec.x) ||
            texture_coordinates.y < 0 || texture_coordinates.y >= int(scene_texture_size_vec.y)) break;

        float step_dist = texture(distance_image, position).r;

        // 足够接近异质表面
        if (step_dist < 0.01) {
            vec4 surface = texture(scene_image, position);
            float scene_brightness = max(surface.r, max(surface.g, surface.b));

            // 发光体：不作为间接光来源
            if (scene_brightness >= uniform_parameters.emissive_threshold) {
                break;
            }

            // 非发光固体：从 PassRM 读取障碍物颜色作为反弹光源
            if (surface.a > 0.0) {
                vec3 bounce_color = texture(passrm_image, position).rgb;
                float bounce_brightness = max(bounce_color.r, max(bounce_color.g, bounce_color.b));

                if (bounce_brightness > 0.001) {
                    float att = 1.0 / (1.0 + total_distance_2d * uniform_parameters.attenuation);
                    return bounce_color * att * uniform_parameters.indirect_strength;
                }
                break;
            }

            // 空区表面附近：按距离场精细步进
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

    return vec3(0.0);
}

// ------------------------------------------------------------
// 主函数：输出直接光 + 间接光（完整 GI）
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = textureSize(scene_image, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 scene_texture_size_vec = vec2(scene_texture_size);
    float min_step_uv = 1.0 / float(scene_texture_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 从 PassRM 获取直接光照（空区=步进光照，障碍物=自身颜色，发光体=发光颜色）
    vec4 direct_light = texture(passrm_image, uv_coordinates);

    // 自身是发光体或障碍物：直接输出 PassRM 结果
    vec4 self_pixel = texture(scene_image, uv_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness >= uniform_parameters.emissive_threshold || self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, direct_light);
        return;
    }

    // 追踪次级光线，收集间接光
    vec3 indirect_light = vec3(0.0);
    float pixel_noise = hash12(uv_coordinates) * uniform_parameters.noise_strength;

    for (int sample_index = 0; sample_index < uniform_parameters.num_samples; sample_index++) {
        float angle = uniform_parameters.rotation_offset + pixel_noise
            + 6.28318530718 * float(sample_index) / float(uniform_parameters.num_samples);
        vec2 direction = vec2(cos(angle), sin(angle));
        indirect_light += march_indirect_ray(uv_coordinates, direction, scene_texture_size_vec, min_step_uv);
    }

    indirect_light /= float(uniform_parameters.num_samples);

    // 输出：直接光照 + 间接光照
    vec3 result = direct_light.rgb + indirect_light;
    imageStore(output_image, coordinates, vec4(result, 1.0));
}
