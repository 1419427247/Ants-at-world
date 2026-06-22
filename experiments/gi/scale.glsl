#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入纹理
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D input_image;
// binding 1: 输出纹理（目标尺寸）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int mode; // 0=双线性（下采样友好），1=bicubic（上采样更锐利）
} uniform_parameters;

// Catmull-Rom 三次插值权重（B-spline 族，锐利度适中，适合 GI 上采样）
vec4 cubic_weights(float t) {
    vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - t;
    vec4 s = n * n * n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vec4(x, y, z, w) * (1.0 / 6.0);
}

vec4 sample_bicubic(vec2 input_position, ivec2 input_size) {
    float fx = input_position.x - floor(input_position.x);
    float fy = input_position.y - floor(input_position.y);
    ivec2 base = ivec2(floor(input_position));

    vec4 wx = cubic_weights(fx);
    vec4 wy = cubic_weights(fy);

    vec4 result = vec4(0.0);
    for (int j = -1; j <= 2; j++) {
        for (int i = -1; i <= 2; i++) {
            ivec2 sample_coord = clamp(base + ivec2(i, j), ivec2(0), input_size - 1);
            vec4 sample_color = imageLoad(input_image, sample_coord);
            float weight = wy[j + 1] * wx[i + 1];
            result += sample_color * weight;
        }
    }
    return result;
}

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_size = imageSize(output_image);
    ivec2 input_size = imageSize(input_image);

    if (coordinates.x >= output_size.x || coordinates.y >= output_size.y) return;

    // 输出像素中心 → 归一化 UV → 输入像素坐标
    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_size);
    vec2 input_position = uv_coordinates * vec2(input_size) - 0.5;

    vec4 sampled_color;
    if (uniform_parameters.mode == 1) {
        // bicubic（上采样更锐利，保留 GI 边缘）
        sampled_color = sample_bicubic(input_position, input_size);
    } else {
        // 双线性（下采样友好，速度快）
        ivec2 base_coordinates = ivec2(floor(input_position));
        vec2 fraction = input_position - vec2(base_coordinates);

        ivec2 sample_coordinates_00 = clamp(base_coordinates, ivec2(0), input_size - 1);
        ivec2 sample_coordinates_10 = clamp(base_coordinates + ivec2(1, 0), ivec2(0), input_size - 1);
        ivec2 sample_coordinates_01 = clamp(base_coordinates + ivec2(0, 1), ivec2(0), input_size - 1);
        ivec2 sample_coordinates_11 = clamp(base_coordinates + ivec2(1, 1), ivec2(0), input_size - 1);

        vec4 color_00 = imageLoad(input_image, sample_coordinates_00);
        vec4 color_10 = imageLoad(input_image, sample_coordinates_10);
        vec4 color_01 = imageLoad(input_image, sample_coordinates_01);
        vec4 color_11 = imageLoad(input_image, sample_coordinates_11);

        vec4 color_top = mix(color_00, color_10, fraction.x);
        vec4 color_bottom = mix(color_01, color_11, fraction.x);
        sampled_color = mix(color_top, color_bottom, fraction.y);
    }

    imageStore(output_image, coordinates, sampled_color);
}
