#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（Alpha 通道判断障碍物）
layout(set = 0, binding = 0) uniform sampler2D scene_texture;
// binding 1: 输出（R=AO因子, GBA=1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 有向距离场（RGBA16F: R=到最近异质点距离, GB=方向, A=1）
layout(set = 0, binding = 2) uniform sampler2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    // --- 公共片元信息（前 8 字节） ---
    vec2 world_to_uv;             // 世界→UV 缩放: uv = world * world_to_uv

    // --- Pass 特有参数（世界单位制） ---
    int   num_samples;      // 采样方向数
    float radius;           // 采样半径（世界单位）
    float sdf_scale;        // SDF 直接估算的缩放系数
} uniform_parameters;

const float PI = 3.14159265359;

// 逐像素伪随机数
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ------------------------------------------------------------
// 主函数：标准 2D SSAO + SDF 直接估算
//
// 两层 AO 合并：
//   1. SDF 直接估算（各向同性基础项）
//      ao_sdf = exp(-sdf * scale)
//      距表面越近 → sdf 越小 → ao 越大（遮挡越强）
//
//   2. 射线追踪 AO（方向性细化）
//      沿 N 个方向做 sphere tracing（SDF 引导自适应步长）
//      命中表面时按距离计算遮挡：越近遮挡越强
// ------------------------------------------------------------
void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = textureSize(scene_texture, 0);

    if (coordinates.x >= output_texture_size.x || coordinates.y >= output_texture_size.y) return;

    float pixel_size = 1.0 / float(scene_texture_size.x);
    vec2 aspect_vec = vec2(1.0, float(scene_texture_size.x) / float(scene_texture_size.y));
    float uv_radius = uniform_parameters.radius * uniform_parameters.world_to_uv.x;

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(output_texture_size);

    // 自身是障碍物：无 AO（输出 0）
    if (texture(scene_texture, uv).a > 0.0) {
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
        return;
    }

    // --- 1. SDF 直接估算 AO（各向同性基础项） ---
    float center_sdf = texture(distance_image, uv).r;
    float sdf_ao = exp(-center_sdf * uniform_parameters.sdf_scale);

    // --- 2. 射线追踪 AO（方向性细化） ---
    float rotation = hash12(vec2(coordinates)) * 2.0 * PI;
    float total_occlusion = 0.0;

    for (int i = 0; i < uniform_parameters.num_samples; i++) {
        float angle = rotation + 2.0 * PI * float(i) / float(uniform_parameters.num_samples);
        vec2 dir = normalize(vec2(cos(angle), sin(angle)) * aspect_vec);

        // SDF 引导自适应步进（sphere tracing）
        float t = pixel_size * 2.0;
        float dir_occlusion = 0.0;

        for (int step = 0; step < 16; step++) {
            if (t > uv_radius) break;

            vec2 sample_uv = uv + dir * t;
            if (sample_uv.x < 0.0 || sample_uv.x > 1.0 ||
                sample_uv.y < 0.0 || sample_uv.y > 1.0) break;

            float sample_sdf = texture(distance_image, sample_uv).r;

            // 命中障碍物表面（SDF 接近 0）
            if (sample_sdf < pixel_size) {
                // 距离越近，遮挡越强
                dir_occlusion = 1.0 - t / uv_radius;
                break;
            }

            // 自适应步长：用 SDF 距离安全推进
            t += max(sample_sdf * 0.8, pixel_size);
        }

        total_occlusion += dir_occlusion;
    }

    total_occlusion /= float(uniform_parameters.num_samples);

    // 合并：取 SDF 基础项和射线项的最大值
    float ao = max(sdf_ao, total_occlusion);
    ao = clamp(ao, 0.0, 1.0);

    // 输出：R=AO因子（1=完全遮挡，0=无遮挡）
    imageStore(output_image, coordinates, vec4(ao, 0.0, 0.0, 1.0));
}
