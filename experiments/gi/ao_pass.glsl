#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（Alpha 通道存地面高度）
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D scene_texture;
// binding 1: 输出（R=AO因子, GBA=1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=方向, A=1）
layout(set = 0, binding = 2, rgba16f) uniform restrict readonly image2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int   num_samples;         // 每像素采样点数
    float radius;              // 采样半径（归一化）
    float intensity;           // 遮蔽强度系数
    float falloff;             // 遮蔽衰减指数
    float bias;                // 高度偏移，防止自遮挡
    float df_guide_weight;     // 距离场引导权重（0=纯黄金角度, 1=纯距离场引导）
} uniform_parameters;

// 黄金角度
const float GOLDEN_ANGLE = 2.399963229728653;
const float PI = 3.14159265359;

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

// ------------------------------------------------------------
// 主函数：距离场引导采样，基于高度差计算遮挡
// 利用距离场方向分量（GB）优先在可能有遮挡的方向采样
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = imageSize(scene_texture);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 texture_size_vec = vec2(scene_texture_size);
    float pixel_size = 1.0 / float(scene_texture_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);
    ivec2 scene_coordinates = ivec2(uv_coordinates * texture_size_vec);

    // 读取中心点高度和距离场
    float center_height = imageLoad(scene_texture, scene_coordinates).a;
    vec4 df_center = imageLoad(distance_image, scene_coordinates);
    float center_sdf = df_center.r;

    // 随机旋转偏移
    float rotation = hash12(vec2(coordinates)) * 2.0 * PI;
    float cos_r = cos(rotation);
    float sin_r = sin(rotation);

    float total_occlusion = 0.0;
    float sample_radius = uniform_parameters.radius;
    float guide_weight = uniform_parameters.df_guide_weight;

    for (int i = 0; i < uniform_parameters.num_samples; i++) {
        // 黄金螺旋采样分布
        float golden_angle = GOLDEN_ANGLE * float(i);
        float radius_factor = sqrt((float(i) + 0.5) / float(uniform_parameters.num_samples));

        vec2 golden_offset = vec2(cos(golden_angle), sin(golden_angle)) * radius_factor * sample_radius;

        // 距离场引导：在采样路径中点查询距离场方向，偏移采样方向朝向附近表面
        vec2 mid_uv = uv_coordinates + golden_offset * 0.5;
        ivec2 mid_tc = ivec2(mid_uv * texture_size_vec);
        mid_tc = clamp(mid_tc, ivec2(0), ivec2(texture_size_vec) - 1);
        vec2 df_dir_mid = imageLoad(distance_image, mid_tc).gb;

        // 将距离场方向作为引导方向，与黄金角度方向混合
        vec2 guided_offset = df_dir_mid * radius_factor * sample_radius;
        vec2 blended_offset = mix(golden_offset, guided_offset, guide_weight);

        // 应用随机旋转
        vec2 rotated_offset = vec2(
            blended_offset.x * cos_r - blended_offset.y * sin_r,
            blended_offset.x * sin_r + blended_offset.y * cos_r
        );

        vec2 sample_uv = uv_coordinates + rotated_offset;
        ivec2 sample_tc = ivec2(sample_uv * texture_size_vec);

        // 边界检查
        if (sample_tc.x < 0 || sample_tc.x >= int(texture_size_vec.x) ||
            sample_tc.y < 0 || sample_tc.y >= int(texture_size_vec.y)) continue;

        // 采样距离场
        float sample_sdf = imageLoad(distance_image, sample_tc).r;

        // 如果采样点在物体内部或表面附近（距离 < 半径），产生遮挡
        if (sample_sdf < sample_radius * radius_factor * 0.5) {
            // 采样点高度
            float sample_height = imageLoad(scene_texture, sample_tc).a;

            // 高度差：采样点比中心点高则产生遮挡
            float height_diff = sample_height - center_height - uniform_parameters.bias;

            if (height_diff > 0.0) {
                // 距离衰减：越近遮挡越强
                float dist = length(rotated_offset);
                float dist_factor = 1.0 - smoothstep(0.0, sample_radius, dist);
                total_occlusion += dist_factor * height_diff * uniform_parameters.intensity;
            }
        }
    }

    total_occlusion /= float(uniform_parameters.num_samples);

    // 应用衰减
    float ao = pow(total_occlusion, uniform_parameters.falloff);
    ao = clamp(ao, 0.0, 1.0);

    // 输出：R=AO因子（1=完全遮挡，0=无遮挡）
    imageStore(output_image, coordinates, vec4(ao, 0.0, 0.0, 1.0));
}