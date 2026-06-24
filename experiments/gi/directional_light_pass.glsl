#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 亮度纹理（Alpha 通道存地面高度）
layout(set = 0, binding = 0) uniform sampler2D luminance_texture;
// binding 1: 输出（R=可见性, G=遮挡物距离/最大距离, B=0, A=1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=方向, A=1）
layout(set = 0, binding = 2) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    vec2  direction;           // 平行光 2D 方向（光传播方向，归一化）
    float height;              // 平行光高度（仰角）
    float max_distance;        // 最大搜索距离（归一化）
    float step_safety;         // 步进安全系数
    int   max_steps;           // 最大步进次数
    int   pcf_samples;         // PCF 抖动静样次数（≥1，越大阴影越柔和）
} uniform_parameters;

// ------------------------------------------------------------
// 平行光阴影测试：沿光源反方向步进，用线性抬升高度判断遮挡
// 返回可见性（0/1），通过 blocker_dist 传出光线被阻挡时的行进距离
// ------------------------------------------------------------
float directional_light_visibility(
    vec2 origin_uv, float origin_height,
    vec2 luminance_size_vec, float min_step_uv,
    out float blocker_dist
) {
    vec2 position = origin_uv;
    float total_distance = 0.0;
    // 宽高比修正：UV 空间是正方形，视口是长方形，需修正方向使屏幕上角度正确
    vec2 aspect_vec = vec2(1.0, luminance_size_vec.x / luminance_size_vec.y);
    vec2 trace_dir = -normalize(uniform_parameters.direction * aspect_vec);

    // 检测带宽度随分辨率自适应（4~16 像素），整条射线恒定，提到循环外
    float surface_threshold = clamp(luminance_size_vec.x / 128.0, 4.0, 16.0) * min_step_uv;

    for (int i = 0; i < uniform_parameters.max_steps; i++) {
        ivec2 tc = ivec2(position * luminance_size_vec);
        if (tc.x < 0 || tc.x >= int(luminance_size_vec.x) ||
            tc.y < 0 || tc.y >= int(luminance_size_vec.y)) break;

        // 有向距离场：R=到最近异质点距离
        float step_dist = texture(distance_image, position).r;

        // 足够接近异质表面
        if (step_dist < surface_threshold) {
            float ground_height = texture(luminance_texture, position).a;

            float t = total_distance / uniform_parameters.max_distance;
            float ray_height = mix(origin_height, uniform_parameters.height, t);

            if (ground_height > ray_height + 0.001) {
                blocker_dist = total_distance;
                return 0.0;
            }

            position += trace_dir * min_step_uv * 2.0;
            total_distance += min_step_uv * 2.0;
            continue;
        }

        if (total_distance > uniform_parameters.max_distance) break;

        float step_size = max(step_dist * uniform_parameters.step_safety, min_step_uv);
        position += trace_dir * step_size;
        total_distance += step_size;
    }

    blocker_dist = uniform_parameters.max_distance;
    return 1.0;
}

// ------------------------------------------------------------
// 主函数
// ------------------------------------------------------------

// 逐像素伪随机数
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 luminance_size = textureSize(luminance_texture, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 luminance_size_vec = vec2(luminance_size);
    float min_step_uv = 1.0 / float(luminance_size.x);
    // 宽高比修正
    vec2 aspect_vec = vec2(1.0, luminance_size_vec.x / luminance_size_vec.y);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 读取起点高度
    float origin_height = texture(luminance_texture, uv_coordinates).a;

    // PCF 沿光源垂直方向抖动：阴影边缘垂直于光线方向，沿此方向抖动柔化效果最佳
    vec2 light_dir = normalize(uniform_parameters.direction * aspect_vec);
    vec2 perp_dir = vec2(-light_dir.y, light_dir.x);  // 垂直方向（90° 旋转）

    int pcf = max(uniform_parameters.pcf_samples, 1);

    float total_visibility = 0.0;
    float total_blocker_dist = 0.0;

    for (int j = 0; j < pcf; j++) {
        // 沿垂直方向抖动（±2 像素范围，比全方向 ±0.5 像素覆盖更宽的边缘）
        float jitter = hash12(vec2(coordinates + ivec2(j * 137, j * 73))) - 0.5;
        vec2 jittered_uv = uv_coordinates + perp_dir * jitter * min_step_uv * 4.0;

        float bd;
        float vis = directional_light_visibility(
            jittered_uv, origin_height, luminance_size_vec, min_step_uv, bd
        );
        total_visibility += vis;
        total_blocker_dist += bd;
    }

    float visibility = total_visibility / float(pcf);
    float blocker_distance = total_blocker_dist / float(pcf);

    // 输出：R=可见性(软), G=遮挡距离(归一化), B=0, A=1
    imageStore(output_image, coordinates, vec4(visibility, blocker_distance / uniform_parameters.max_distance, 0.0, 1.0));
}
