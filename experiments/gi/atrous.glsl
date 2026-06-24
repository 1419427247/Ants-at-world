#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入（含噪声的 GI）
layout(set = 0, binding = 0) uniform sampler2D input_image;
// binding 1: 输出（滤波后）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=指向最近异质点的方向向量(归一化), A=1，作为深度引导）
layout(set = 0, binding = 2) uniform sampler2D depth_image;

layout(push_constant, std430) uniform UniformParameters {
    int step_size;          // 采样间隔（1, 2, 4, ... 每个 pass 翻倍）
    float color_sigma;      // 颜色双边标准差（越小越保边）
    float depth_sigma;      // 深度双边标准差（越小越保边）
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 center_pixel = texture(input_image, (vec2(coordinates) + 0.5) / vec2(texture_size));
    float center_depth = texture(depth_image, (vec2(coordinates) + 0.5) / vec2(texture_size)).r;

    // B3 样条小波权重（a-trous 标准核）
    // 5x5 核，距离 0/1/2 对应权重 c0/c1/c2
    const float c0 = 1.0;
    const float c1 = 2.0 / 3.0;
    const float c2 = 1.0 / 6.0;

    float color_inverse = 1.0 / (2.0 * uniform_parameters.color_sigma * uniform_parameters.color_sigma);
    float depth_inverse = 1.0 / (2.0 * uniform_parameters.depth_sigma * uniform_parameters.depth_sigma);

    vec3 color_sum = center_pixel.rgb * c0 * c0;
    float weight_sum = c0 * c0;

    int step = uniform_parameters.step_size;

    for (int offset_y = -2; offset_y <= 2; offset_y++) {
        for (int offset_x = -2; offset_x <= 2; offset_x++) {
            if (offset_x == 0 && offset_y == 0) continue;

            ivec2 sample_coordinates = coordinates + ivec2(offset_x * step, offset_y * step);
            sample_coordinates = clamp(sample_coordinates, ivec2(0), texture_size - 1);

            vec4 sample_pixel = texture(input_image, (vec2(sample_coordinates) + 0.5) / vec2(texture_size));

            // 空间权重（B3 小波，可分离：行权重 × 列权重）
            float weight_x = (abs(offset_x) == 1) ? c1 : (abs(offset_x) == 2 ? c2 : c0);
            float weight_y = (abs(offset_y) == 1) ? c1 : (abs(offset_y) == 2 ? c2 : c0);
            float weight_spatial = weight_x * weight_y;

            // 颜色权重（双边，保留边缘）
            vec3 color_difference = sample_pixel.rgb - center_pixel.rgb;
            float color_distance_squared = dot(color_difference, color_difference);
            float weight_color = exp(-color_distance_squared * color_inverse);

            // 深度权重（基于距离场，保留几何边缘 — 墙体边界不被错误融合）
            float sample_depth = texture(depth_image, (vec2(sample_coordinates) + 0.5) / vec2(texture_size)).r;
            float depth_diff = abs(sample_depth - center_depth);
            float weight_depth = exp(-depth_diff * depth_diff * depth_inverse);

            float combined_weight = weight_spatial * weight_color * weight_depth;
            color_sum += sample_pixel.rgb * combined_weight;
            weight_sum += combined_weight;
        }
    }

    vec3 filtered_result = color_sum / max(weight_sum, 0.0001);
    imageStore(output_image, coordinates, vec4(filtered_result, 1.0));
}
