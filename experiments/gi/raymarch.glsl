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
    float noise_strength;        // 逐像素随机角度偏移强度
    int max_bounces;             // 最大反弹次数
    float bounce_attenuation;    // 每次反弹的强度衰减系数（0-1）
    int frame_index;             // 帧序号（时域变化种子）
} uniform_parameters;

// Interleaved Gradient Noise (Jorge Jimenez 2014)
// 蓝噪声近似，无需纹理，空间分布比白噪声均匀，配合时域累积收敛更快
float ign(vec2 pos) {
    return fract(52.9829189 * fract(0.06711056 * pos.x + 0.00583715 * pos.y));
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
    ivec2 scene_texture_size, float min_step_uv
) {
    vec2 position = origin_uv;
    float total_distance_2d = 0.0;
    vec3 accumulated_light = vec3(0.0);
    vec2 current_dir = direction;
    float bounce_attenuation = 1.0;
    int bounce = 0;
    int max_bounces = uniform_parameters.max_bounces;
    // 足够接近异质表面（检测带宽度随分辨率自适应：4~16 像素）
    float surface_threshold = clamp(float(scene_texture_size.x) / 128.0, 4.0, 16.0) * min_step_uv;

    // 总步数 = 每段步数 × (最大反弹 + 1)
    int max_steps_total = uniform_parameters.maximum_steps * (max_bounces + 1);

    for (int step_index = 0; step_index < max_steps_total; step_index++) {
        // 累积亮度早退：反弹衰减过低时后续贡献可忽略
        if (bounce_attenuation < 0.001) break;

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
                    vec2 reflect_dir = reflect(current_dir, n);

                    // 沿反射方向微偏移避免自碰撞
                    position += current_dir * min_step_uv * 3.0;
                    total_distance_2d = 0.0;
                    bounce++;
                    bounce_attenuation *= uniform_parameters.bounce_attenuation;
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

    float min_step_uv = 1.0 / float(max(scene_texture_size.x,scene_texture_size.y));
    // 宽高比修正：UV 空间是正方形，视口是长方形，需修正方向使屏幕上为圆
    vec2 aspect_vec = vec2(1.0, float(scene_texture_size.x) / float(scene_texture_size.y));

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

    // 空区：发射多条光线 + 多次反弹
    vec3 total_light = vec3(0.0);
    // IGN 蓝噪声 + frame_index 时域偏移：每帧平移噪声模式，配合 Temporal Pass 加速收敛
    float pixel_noise = ign(coordinates + vec2(uniform_parameters.frame_index)) * uniform_parameters.noise_strength;

    for (int sample_index = 0; sample_index < uniform_parameters.number_samples; sample_index++) {
        float angle = pixel_noise
            + 6.28318530718 * float(sample_index) / float(uniform_parameters.number_samples);
        vec2 direction = normalize(vec2(cos(angle), sin(angle)) * aspect_vec);
        total_light += march_ray(uv_coordinates, direction, scene_texture_size, min_step_uv);
    }

    total_light /= float(uniform_parameters.number_samples);
    imageStore(output_image, coordinates, vec4(total_light, 1.0));
}
