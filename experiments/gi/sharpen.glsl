#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 降噪后输入
layout(set = 0, binding = 0) uniform sampler2D input_image;
// binding 1: 锐化后输出
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    float strength;     // 锐化强度
    int   radius;       // 模糊核半径（像素）
    float sigma;        // 高斯标准差
    int   _pad;
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(texture_size);

    // 高斯模糊得到低频版本
    float sigma_sq = uniform_parameters.sigma * uniform_parameters.sigma;
    float two_sigma_sq = 2.0 * sigma_sq;
    float norm = 1.0 / sqrt(3.14159265359 * two_sigma_sq);

    vec4 blur_sum = vec4(0.0);
    float wsum = 0.0;

    int r = uniform_parameters.radius;
    for (int j = -r; j <= r; j++) {
        for (int i = -r; i <= r; i++) {
            vec2 sample_uv = uv + vec2(float(i), float(j)) / vec2(texture_size);
            vec4 col = texture(input_image, sample_uv);
            float dist_sq = float(i * i + j * j);
            float w = norm * exp(-dist_sq / two_sigma_sq);
            blur_sum += col * w;
            wsum += w;
        }
    }

    vec4 blurred = blur_sum / wsum;

    // Unsharp Mask: 原图 + (原图 - 模糊) * 强度
    vec4 original = texture(input_image, uv);
    vec4 detail = original - blurred;
    vec4 result = original + detail * uniform_parameters.strength;

    imageStore(output_image, coordinates, result);
}
