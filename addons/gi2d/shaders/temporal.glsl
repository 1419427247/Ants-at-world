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
    float blend_factor;            // 基础当前帧权重（0.0=全历史，1.0=全当前）
    float variance_scale;          // 方差自适应缩放系数（0=禁用自适应）
    vec2  reprojection_uv_offset;  // 重投影 UV 偏移（运动矢量，0=无重投影）
} uniform_parameters;

// 逐像素亮度
float luminance(vec3 col) {
    return dot(col, vec3(0.299, 0.587, 0.114));
}

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    // 当前帧采样（已知整数坐标 → texelFetch 省去 UV 计算与插值）
    vec4 current_pixel = texelFetch(current_frame_image, coordinates, 0);

    // --- 1. 重投影：从历史纹理中读取上一帧对应位置 ---
    // reprojection_uv_offset = (0,0) 时退化为原始行为（无运动补偿）
    vec2 history_uv = (vec2(coordinates) + 0.5) / vec2(texture_size) + uniform_parameters.reprojection_uv_offset;
    vec4 history_pixel = texture(history_image, history_uv);

    // --- 2. AABB Clamp：消除残留拖影 ---
    // 计算当前帧 3×3 邻域的 min/max，将历史值裁剪到此范围
    // texelFetch 已知整数坐标，省去 UV 计算与硬件插值
    vec3 aabb_minimum = current_pixel.rgb;
    vec3 aabb_maximum = current_pixel.rgb;
    float lum_min = luminance(current_pixel.rgb);
    float lum_max = lum_min;

    for (int offset_y = -1; offset_y <= 1; offset_y++) {
        for (int offset_x = -1; offset_x <= 1; offset_x++) {
            if (offset_x == 0 && offset_y == 0) continue;
            ivec2 neighbor_coordinates = clamp(coordinates + ivec2(offset_x, offset_y), ivec2(0), texture_size - 1);
            vec3 neighbor_color = texelFetch(current_frame_image, neighbor_coordinates, 0).rgb;
            aabb_minimum = min(aabb_minimum, neighbor_color);
            aabb_maximum = max(aabb_maximum, neighbor_color);
            // 累加亮度范围用于方差自适应
            float l = luminance(neighbor_color);
            lum_min = min(lum_min, l);
            lum_max = max(lum_max, l);
        }
    }
    vec3 history_clamped = clamp(history_pixel.rgb, aabb_minimum, aabb_maximum);

    // --- 3. 自适应 blend_factor ---
    // 平坦区域（低亮度方差）→ 用基础 blend（多累积降噪）
    // 高频区域（高亮度方差）→ 用更高 blend（减少拖影）
    float adaptive_blend = uniform_parameters.blend_factor;
    if (uniform_parameters.variance_scale > 0.0) {
        float lum_range = max(lum_max - lum_min, 0.0001);
        float variance_factor = min(lum_range * uniform_parameters.variance_scale, 1.0);
        // variance=0(平坦) → blend=基础值；variance=大 → blend 趋近 1.0
        adaptive_blend = mix(uniform_parameters.blend_factor, 1.0, variance_factor);
    }

    // 指数移动平均（使用裁剪后的历史值 + 自适应 blend）
    vec3 final_result = mix(history_clamped, current_pixel.rgb, adaptive_blend);

    imageStore(output_image, coordinates, vec4(final_result, 1.0));
}
