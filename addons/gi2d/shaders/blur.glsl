#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入纹理
layout(set = 0, binding = 0) uniform sampler2D input_image;
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

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(texture_size);
    vec4 center_pixel = texture(input_image, uv);

    const float PI = 3.14159265359;
    float sigma = uniform_parameters.sigma;
    float two_sigma_sq = 2.0 * sigma * sigma;
    // 标准高斯归一化常数：1 / (σ * √(2π))
    float norm_factor = 1.0 / (sigma * sqrt(2.0 * PI));

    vec4 blur_sum = vec4(0.0);
    float weight_sum = 0.0;

    bool is_horizontal = (uniform_parameters.direction == 0);
    vec2 dir = is_horizontal ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec2 pixel_step = dir / vec2(texture_size);

    // 大 radius 时利用 textureLod + 纹理金字塔减少采样次数
    // stride 将采样数控制在 ~17 以内，lod 让硬件在低分辨率 mip 上预滤波
    const int MAX_SAMPLES = 17;
    int radius = uniform_parameters.radius;
    int stride = max(1, (2 * radius + 1) / MAX_SAMPLES);
    int effective_radius = radius / stride;
    float lod = stride > 1 ? log2(float(stride)) : 0.0;

    for (int offset = -effective_radius; offset <= effective_radius; offset++) {
        float pixel_offset = float(offset * stride);
        vec2 sample_uv = uv + pixel_step * pixel_offset;

        vec4 sample_pixel = textureLod(input_image, sample_uv, lod);

        float dist_sq = pixel_offset * pixel_offset;
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
