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
    vec2 trace_dir = -uniform_parameters.direction;

    for (int i = 0; i < uniform_parameters.max_steps; i++) {
        ivec2 tc = ivec2(position * luminance_size_vec);
        if (tc.x < 0 || tc.x >= int(luminance_size_vec.x) ||
            tc.y < 0 || tc.y >= int(luminance_size_vec.y)) break;

        // 有向距离场：R=到最近异质点距离
        float step_dist = texture(distance_image, position).r;

        if (step_dist < 0.01) {
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
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 luminance_size = textureSize(luminance_texture, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    vec2 luminance_size_vec = vec2(luminance_size);
    float min_step_uv = 1.0 / float(luminance_size.x);

    vec2 uv_coordinates = (vec2(coordinates) + 0.5) / vec2(output_texture_size);
    ivec2 luminance_coordinates = ivec2(uv_coordinates * luminance_size_vec);

    // 读取起点高度
    float origin_height = texture(luminance_texture, uv_coordinates).a;

    // 可见性测试，同时获取遮挡距离
    float blocker_distance;
    float visibility = directional_light_visibility(
        uv_coordinates, origin_height, luminance_size_vec, min_step_uv,
        blocker_distance
    );

    // 输出：R=可见性, G=遮挡距离(归一化), B=0, A=1
    imageStore(output_image, coordinates, vec4(visibility, blocker_distance / uniform_parameters.max_distance, 0.0, 1.0));
}
