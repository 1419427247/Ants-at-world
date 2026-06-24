#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（发光体颜色）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出（直接光照 + 反弹漫反射光照）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场
layout(set = 0, binding = 2) uniform sampler2D distance_image;
// binding 3: 法线图（extra_input[0] = PassNormal）
layout(set = 0, binding = 3) uniform sampler2D normal_image;

layout(push_constant, std430) uniform UniformParameters {
    int number_samples;          // 每像素光线数
    float attenuation;           // 衰减系数
    float maximum_distance;      // 最大搜索距离（归一化）
    int maximum_steps;           // 每段步进最大步数
    float emissive_threshold;    // 发光阈值
    float step_safety;           // 步进安全系数（<1.0）
    float rotation_offset;       // 射线初始旋转偏移（弧度）
    float noise_strength;        // 逐像素随机角度偏移强度
    int max_bounces;             // 最大反弹次数
} uniform_parameters;

// 逐像素伪随机数（经典 hash）
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ------------------------------------------------------------
// 光线步进 + 多次反弹
// 每条光线遇到非发光障碍物时：
//   1. 读取障碍物漫反射颜色，混合到累积光照中
//   2. 根据法线图计算反射方向
//   3. 继续步进（最多 max_bounces 次反弹）
// 遇到发光体时收集直接光照并终止
// ------------------------------------------------------------
vec3 march_ray(
    vec2 origin_uv, vec2 direction,
    vec2 scene_texture_size_vec, float min_step_uv
) {
    vec2 position = origin_uv;
    float total_distance_2d = 0.0;
    vec3 accumulated_light = vec3(0.0);
    vec2 current_dir = direction;
    float bounce_attenuation = 1.0;
    int bounce = 0;
    int max_bounces = uniform_parameters.max_bounces;

    // 总步数 = 每段步数 × (最大反弹 + 1)
    int max_steps_total = uniform_parameters.maximum_steps * (max_bounces + 1);

    for (int step_index = 0; step_index < max_steps_total; step_index++) {
        vec2 scene_coords_f = position * scene_texture_size_vec;
        ivec2 tc = ivec2(scene_coords_f);

        if (tc.x < 0 || tc.x >= int(scene_texture_size_vec.x) ||
            tc.y < 0 || tc.y >= int(scene_texture_size_vec.y)) break;

        // 有向距离场：R = 到最近异质点距离
        float step_dist = texture(distance_image, position).r;

        // 足够接近异质表面
        if (step_dist < 0.01) {
            vec4 surface = texture(scene_image, position);
            float brightness = max(surface.r, max(surface.g, surface.b));

            // --- 发光体：收集光照，光线终止 ---
            if (brightness > uniform_parameters.emissive_threshold) {
                float att = 1.0 / (1.0 + total_distance_2d * uniform_parameters.attenuation);
                accumulated_light += surface.rgb * att * bounce_attenuation;
                break;
            }

            // --- 非发光障碍物：反弹（不贡献颜色，只改变方向+衰减） ---
            if (surface.a > 0.001) {
                if (bounce < max_bounces) {
                    // 读取法线图 → 解码 2D 表面法线方向
                    // NormalPass 输出 = n*0.5+0.5，n=normalize(-gradient, 1.0)
                    // 解码后 n.xy = 指向空区方向的表面法线
                    vec2 n = normalize(texture(normal_image, position).xy * 2.0 - 1.0);

                    // 根据表面法线计算反射方向
                    current_dir = reflect(current_dir, n);

                    // 沿反射方向微偏移避免自碰撞
                    position += current_dir * min_step_uv * 3.0;
                    total_distance_2d = 0.0;
                    bounce++;
                    bounce_attenuation *= 0.5;
                    continue;
                } else {
                    break; // 已达最大反弹次数，阻挡
                }
            }

            // 空区表面附近：按距离场精细步进
            float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
            position += current_dir * step_size;
            total_distance_2d += step_size;
            continue;
        }

        if (total_distance_2d > uniform_parameters.maximum_distance) break;

        float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
        position += current_dir * step_size;
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
    ivec2 scene_texture_size = textureSize(scene_image, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 scene_texture_size_vec = vec2(scene_texture_size);
    float min_step_uv = 1.0 / float(scene_texture_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 自身是发光体 → 直接输出自身颜色
    vec4 self_pixel = texture(scene_image, uv_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness > uniform_parameters.emissive_threshold) {
        imageStore(output_image, coordinates, self_pixel);
        return;
    }

    // 自身是障碍物 → 输出自身颜色（作为其他光线反弹的源）
    if (self_pixel.a > 0.0) {
        imageStore(output_image, coordinates, vec4(self_pixel.rgb, 1.0));
        return;
    }

    // 空区：发射多条光线 + 多次反弹
    vec3 total_light = vec3(0.0);
    float pixel_noise = hash12(uv_coordinates) * uniform_parameters.noise_strength;

    for (int sample_index = 0; sample_index < uniform_parameters.number_samples; sample_index++) {
        float angle = uniform_parameters.rotation_offset + pixel_noise
            + 6.28318530718 * float(sample_index) / float(uniform_parameters.number_samples);
        vec2 direction = vec2(cos(angle), sin(angle));
        total_light += march_ray(uv_coordinates, direction, scene_texture_size_vec, min_step_uv);
    }

    total_light /= float(uniform_parameters.number_samples);
    imageStore(output_image, coordinates, vec4(total_light, 1.0));
}
