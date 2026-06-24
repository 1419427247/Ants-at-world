#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 间接光照（主输入，ATrous 降噪后）
layout(set = 0, binding = 0) uniform sampler2D indirect_image;
// binding 1: 输出
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;
// binding 2: 平行光照结果
layout(set = 0, binding = 2) uniform sampler2D directional_image;
// binding 3: 环境光遮蔽（R=AO因子, 0=无遮挡, 1=完全遮挡）
layout(set = 0, binding = 3) uniform sampler2D ao_image;

layout(push_constant, std430) uniform UniformParameters {
    float indirect_strength;    // 间接光强度
    float ao_strength;          // AO 强度
    vec4 dir_color;             // 平行光颜色 (RGB)
    vec4 shadow_color;          // 阴影颜色 (RGB)
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec3 indirect = texture(indirect_image, (vec2(coordinates) + 0.5) / vec2(texture_size)).rgb;
    vec3 directional = texture(directional_image, (vec2(coordinates) + 0.5) / vec2(texture_size)).rrr;
    float ao = texture(ao_image, (vec2(coordinates) + 0.5) / vec2(texture_size)).r;

    // AO 因子：0=完全遮挡(黑), 1=无遮挡(亮)
    float ao_factor = mix(1.0, 1.0 - ao, uniform_parameters.ao_strength);

    // 平行光区域用 dir_color，阴影区域用 shadow_color，alpha 控制混合强度
    float directional_magnitude = max(directional.r, max(directional.g, directional.b));
    vec3 shadow_contrib = uniform_parameters.shadow_color.rgb * directional * uniform_parameters.shadow_color.a;
    vec3 light_contrib = uniform_parameters.dir_color.rgb * directional * uniform_parameters.dir_color.a;
    vec3 directional_contribution = mix(shadow_contrib, light_contrib, directional_magnitude);

    // 合成：间接光 + 平行光（颜色化），乘以 AO
    vec3 result = (indirect * uniform_parameters.indirect_strength
                 + directional_contribution) * ao_factor;

    imageStore(output_image, coordinates, vec4(result, 1.0));
}
