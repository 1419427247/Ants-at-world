#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入纹理
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D input_image;
// binding 1: 输出纹理
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int radius;          // 模糊核半径
    float sigma;         // 高斯标准差
    int channel_mask;    // 通道掩码：bit 0=R, bit 1=G, bit 2=B, bit 3=A
    int direction;       // 方向：0=水平, 1=垂直
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 center_pixel = imageLoad(input_image, coordinates);

    float sigma_sq = uniform_parameters.sigma * uniform_parameters.sigma;
    float two_sigma_sq = 2.0 * sigma_sq;
    float norm_factor = 1.0 / sqrt(3.14159265359 * two_sigma_sq);

    vec4 blur_sum = vec4(0.0);
    float weight_sum = 0.0;

    // 可分离模糊：方向由 uniform_parameters.direction 指定
    bool is_horizontal = (uniform_parameters.direction == 0);

    for (int offset = -uniform_parameters.radius; offset <= uniform_parameters.radius; offset++) {
        // 根据方向选择采样偏移
        int sample_offset = is_horizontal ? offset : 0;
        int sample_offset_y = is_horizontal ? 0 : offset;

        ivec2 sample_coords = clamp(coordinates + ivec2(sample_offset, sample_offset_y), ivec2(0), texture_size - 1);
        vec4 sample_pixel = imageLoad(input_image, sample_coords);

        float dist_sq = float(offset * offset);
        float weight = norm_factor * exp(-dist_sq / two_sigma_sq);

        blur_sum += sample_pixel * weight;
        weight_sum += weight;
    }

    vec4 blurred = blur_sum / weight_sum;

    // 混合：启用的通道用模糊结果，禁用的通道保留原值
    vec4 result = center_pixel;

    if ((uniform_parameters.channel_mask & 1) != 0) result.r = blurred.r;
    if ((uniform_parameters.channel_mask & 2) != 0) result.g = blurred.g;
    if ((uniform_parameters.channel_mask & 4) != 0) result.b = blurred.b;
    if ((uniform_parameters.channel_mask & 8) != 0) result.a = blurred.a;

    imageStore(output_image, coordinates, result);
}
