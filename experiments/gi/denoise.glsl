#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入（含噪声的 GI）
layout(set = 0, binding = 0) uniform sampler2D input_image;
// binding 1: 输出（降噪后）
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int kernel_radius;         // 滤波核半径（像素）
    float spatial_sigma;       // 空间高斯标准差
    float color_sigma;         // 颜色双边标准差
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 center_pixel = texture(input_image, (vec2(coordinates) + 0.5) / vec2(texture_size));

    vec3 color_sum = vec3(0.0);
    float weight_sum = 0.0;

    float spatial_inverse = 1.0 / (2.0 * uniform_parameters.spatial_sigma * uniform_parameters.spatial_sigma);
    float color_inverse = 1.0 / (2.0 * uniform_parameters.color_sigma * uniform_parameters.color_sigma);

    for (int offset_y = -uniform_parameters.kernel_radius; offset_y <= uniform_parameters.kernel_radius; offset_y++) {
        for (int offset_x = -uniform_parameters.kernel_radius; offset_x <= uniform_parameters.kernel_radius; offset_x++) {
            ivec2 sample_coordinates = coordinates + ivec2(offset_x, offset_y);

            // 边界 clamp
            sample_coordinates = clamp(sample_coordinates, ivec2(0), texture_size - 1);

            vec4 sample_color = texture(input_image, (vec2(sample_coordinates) + 0.5) / vec2(texture_size));

            // 空间权重（高斯）
            float spatial_distance_squared = float(offset_x * offset_x + offset_y * offset_y);
            float weight_spatial = exp(-spatial_distance_squared * spatial_inverse);

            // 颜色权重（双边）
            vec3 color_difference = sample_color.rgb - center_pixel.rgb;
            float color_distance_squared = dot(color_difference, color_difference);
            float weight_color = exp(-color_distance_squared * color_inverse);

            float combined_weight = weight_spatial * weight_color;
            color_sum += sample_color.rgb * combined_weight;
            weight_sum += combined_weight;
        }
    }

    vec3 denoised_result = color_sum / max(weight_sum, 0.0001);
    imageStore(output_image, coordinates, vec4(denoised_result, 1.0));
}
