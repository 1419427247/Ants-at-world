#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（Alpha 通道判断障碍物）
layout(set = 0, binding = 0) uniform sampler2D scene_texture;
// binding 1: 输出（R=AO因子, GBA=1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=方向, A=1）
layout(set = 0, binding = 2) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int   num_samples;         // 每像素采样点数
    float radius;              // 采样半径（归一化）
    float intensity;           // 遮蔽强度系数
    float falloff;             // 遮蔽衰减指数
    float bias;                // 偏移，防止自遮挡
    float df_guide_weight;     // 距离场引导权重（0=纯均匀, 1=纯距离场引导）
} uniform_parameters;

const float PI = 3.14159265359;

// 逐像素伪随机数
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ------------------------------------------------------------
// 主函数：基于距离场的 2D 环境光遮蔽
// 核心思路：沿各方向采样，检查射线是否被障碍物阻挡
// 被阻挡的方向越多、距离越近，AO 越强
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = textureSize(scene_texture, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 texture_size_vec = vec2(scene_texture_size);
    float pixel_size = 1.0 / float(scene_texture_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 自身是障碍物：无 AO
    float self_alpha = texture(scene_texture, uv_coordinates).a;
    if (self_alpha > 0.0) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // 自身距离场值
    float center_sdf = texture(distance_image, uv_coordinates).r;

    // 随机旋转偏移（每帧一致，避免闪烁）
    float rotation = hash12(vec2(coordinates)) * 2.0 * PI;

    float total_occlusion = 0.0;
    float sample_radius = uniform_parameters.radius;
    float guide_weight = uniform_parameters.df_guide_weight;

    for (int i = 0; i < uniform_parameters.num_samples; i++) {
        // 均匀角度分布 + 随机旋转偏移
        float base_angle = rotation + 2.0 * PI * float(i) / float(uniform_parameters.num_samples);

        // 距离场引导：在采样方向上查询距离场，偏向有遮挡的方向
        vec2 base_dir = vec2(cos(base_angle), sin(base_angle));

        // 沿方向步进，检查是否被障碍物阻挡
        float max_dist = sample_radius;
        float occlusion = 0.0;

        // 在采样方向上取几个点检查遮挡
        for (int step = 1; step <= 3; step++) {
            float t = max_dist * float(step) / 3.0;
            vec2 sample_uv = uv_coordinates + base_dir * t;

            // 边界检查：超出纹理范围 → 跳过此采样点，不贡献遮挡
            if (sample_uv.x < 0.0 || sample_uv.x > 1.0 ||
                sample_uv.y < 0.0 || sample_uv.y > 1.0) {
                continue;
            }

            float sample_sdf = texture(distance_image, sample_uv).r;

            // 距离场值很小 = 非常靠近障碍物 = 强遮挡
            // 距离场值为 0 = 在障碍物内部 = 完全遮挡
            if (sample_sdf < pixel_size) {
                // 在障碍物表面或内部
                float dist_factor = 1.0 - t / max_dist; // 越近越强
                occlusion += dist_factor / float(step);
            } else if (sample_sdf < t * 0.5) {
                // 障碍物在射线方向上较近
                float dist_factor = 1.0 - t / max_dist;
                float sdf_factor = 1.0 - sample_sdf / (t * 0.5);
                occlusion += dist_factor * sdf_factor * 0.5 / float(step);
            }
        }

        total_occlusion += occlusion;
    }

    total_occlusion /= float(uniform_parameters.num_samples);

    // 应用强度和衰减
    float ao = pow(total_occlusion * uniform_parameters.intensity, uniform_parameters.falloff);
    ao = clamp(ao, 0.0, 1.0);

    // 输出：R=AO因子（1=完全遮挡，0=无遮挡）
    imageStore(output_image, coordinates, vec4(ao, 0.0, 0.0, 1.0));
}
