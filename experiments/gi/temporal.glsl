#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 当前帧 GI — 主输入
layout(set = 0, binding = 0) uniform sampler2D current_frame_image;
// binding 1: 输出
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 历史累积结果 — 额外输入
layout(set = 0, binding = 2) uniform sampler2D history_image;

layout(push_constant, std430) uniform UniformParameters {
    float blend_factor; // 当前帧权重（0.0=全历史，1.0=全当前）
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 current_pixel = texture(current_frame_image, (vec2(coordinates) + 0.5) / vec2(texture_size));
    vec4 history_pixel = texture(history_image, (vec2(coordinates) + 0.5) / vec2(texture_size));

    // AABB Clamp：计算当前帧 3×3 邻域的 min/max，将历史值裁剪到此范围
    // 消除运动时的拖尾残影（ghosting）
    vec3 aabb_minimum = current_pixel.rgb;
    vec3 aabb_maximum = current_pixel.rgb;
    for (int offset_y = -1; offset_y <= 1; offset_y++) {
        for (int offset_x = -1; offset_x <= 1; offset_x++) {
            ivec2 neighbor_coordinates = clamp(coordinates + ivec2(offset_x, offset_y), ivec2(0), texture_size - 1);
            vec3 neighbor_color = texture(current_frame_image, (vec2(neighbor_coordinates) + 0.5) / vec2(texture_size)).rgb;
            aabb_minimum = min(aabb_minimum, neighbor_color);
            aabb_maximum = max(aabb_maximum, neighbor_color);
        }
    }
    vec3 history_clamped = clamp(history_pixel.rgb, aabb_minimum, aabb_maximum);

    // 指数移动平均（使用裁剪后的历史值）
    vec3 final_result = mix(history_clamped, current_pixel.rgb, uniform_parameters.blend_factor);

    imageStore(output_image, coordinates, vec4(final_result, 1.0));
}
