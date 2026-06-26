#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入（H pass = 降噪后原图；V pass = H pass 输出）
layout(set = 0, binding = 0) uniform sampler2D input_image;
// binding 1: 输出
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 原始输入（仅 V pass 使用，用于 Unsharp Mask）
layout(set = 0, binding = 2) uniform sampler2D original_image;

layout(push_constant, std430) uniform UniformParameters {
    float strength;     // 锐化强度（仅 V pass 使用）
    int   radius;       // 模糊核半径（像素）
    float sigma;        // 高斯标准差
    int   direction;    // 0=水平模糊, 1=垂直模糊+Unsharp
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(texture_size);
    float two_sigma_sq = 2.0 * uniform_parameters.sigma * uniform_parameters.sigma;
    int r = uniform_parameters.radius;

    // 1D 高斯模糊（可分离），norm_factor 被最终 wsum 归一化约掉，无需计算
    vec4 blur_sum = vec4(0.0);
    float wsum = 0.0;

    if (uniform_parameters.direction == 0) {
        // === H pass: 水平 1D 高斯模糊 ===
        float step_x = 1.0 / float(texture_size.x);
        for (int i = -r; i <= r; i++) {
            vec4 col = texture(input_image, uv + vec2(float(i) * step_x, 0.0));
            float w = exp(-float(i * i) / two_sigma_sq);
            blur_sum += col * w;
            wsum += w;
        }
        imageStore(output_image, coordinates, blur_sum / wsum);
    } else {
        // === V pass: 垂直 1D 高斯模糊 + Unsharp Mask ===
        float step_y = 1.0 / float(texture_size.y);
        for (int i = -r; i <= r; i++) {
            vec4 col = texture(input_image, uv + vec2(0.0, float(i) * step_y));
            float w = exp(-float(i * i) / two_sigma_sq);
            blur_sum += col * w;
            wsum += w;
        }
        vec4 blurred = blur_sum / wsum;
        vec4 original = texture(original_image, uv);
        vec4 detail = original - blurred;
        imageStore(output_image, coordinates, original + detail * uniform_parameters.strength);
    }
}
