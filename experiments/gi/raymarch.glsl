#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（发光体颜色）— 主输入
layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D scene_image;
// binding 1: 输出
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;
// binding 2: 距离场纹理（R 通道存归一化距离）— 额外输入
layout(set = 0, binding = 2, rgba8) uniform restrict readonly image2D distance_image;

layout(push_constant, std430) uniform UniformParameters {
    int number_samples;          // 每像素光线数
    float attenuation;           // 衰减系数
    float maximum_distance;      // 最大搜索距离（归一化）
    int maximum_steps;           // 最大步进次数
    float emissive_threshold;    // 发光阈值（>= 此值视为发光体）
    float step_safety;           // 步进安全系数（<1.0 防止步进越过薄壁导致漏光）
    float input_scale;           // 输入采样密度（<1.0 时筛选像素计算间隔）
} uniform_parameters;

// 黄金角度（用于准随机光线方向）
const float GOLDEN_ANGLE = 2.399963229728653;

// 像素级哈希，生成 [0, 1) 伪随机数
float hash12(vec2 position) {
    position = fract(position * vec2(123.34, 456.21));
    position += dot(position, position + 45.32);
    return fract(position.x * position.y);
}

// 采样距离场，返回归一化距离值
float sample_distance(ivec2 coordinates) {
    return imageLoad(distance_image, coordinates).r;
}

// 采样场景颜色（含 alpha）
vec4 sample_scene(ivec2 coordinates) {
    return imageLoad(scene_image, coordinates);
}

// 沿一条光线步进，直接光照
vec3 march_ray(vec2 origin_uv, vec2 direction, ivec2 scene_texture_size) {
    vec2 position = origin_uv;
    float total_distance = 0.0;
    vec3 accumulated_light = vec3(0.0);

    for (int step_index = 0; step_index < uniform_parameters.maximum_steps; step_index++) {
        ivec2 texture_coordinates = ivec2(int(position.x * scene_texture_size.x), int(position.y * scene_texture_size.y));

        // 边界检查
        if (texture_coordinates.x < 0 || texture_coordinates.x >= scene_texture_size.x ||
            texture_coordinates.y < 0 || texture_coordinates.y >= scene_texture_size.y) break;

        float distance = sample_distance(texture_coordinates);

        // 接近表面时才采样场景颜色（减少 imageLoad 开销）
        if (distance < 0.003) {
            vec4 surface_color = sample_scene(texture_coordinates);
            float surface_brightness = max(surface_color.r, max(surface_color.g, surface_color.b));

            if (surface_brightness >= uniform_parameters.emissive_threshold) {
                // 发光体：收集光（2D 1/r 衰减）
                float attenuation_factor = 1.0 / (1.0 + total_distance * uniform_parameters.attenuation);
                accumulated_light += surface_color.rgb * attenuation_factor;
                break;
            } else {
                // 非发光体：吸收
                break;
            }
        }

        // 超过最大距离
        if (total_distance > uniform_parameters.maximum_distance) break;

        // 步进
        float step_size = max(distance * uniform_parameters.step_safety, 0.0005);
        position += direction * step_size;
        total_distance += step_size;
    }

    return accumulated_light;
}

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 output_texture_size = imageSize(output_image);
    ivec2 scene_texture_size = imageSize(scene_image);
    float sampling_scale = uniform_parameters.input_scale;

    // 按 input_scale 筛选线程
    ivec2 output_coordinates = ivec2(vec2(coordinates) / sampling_scale);
    if (output_coordinates.x >= output_texture_size.x || output_coordinates.y >= output_texture_size.y) return;

    // 输出坐标 → 场景 UV（均匀覆盖全场景）
    vec2 uv_coordinates = (vec2(output_coordinates) + 0.5) / vec2(output_texture_size);
    ivec2 scene_coordinates = ivec2(uv_coordinates * vec2(scene_texture_size));

    // 发光体早退：自身是光源，直接输出颜色
    vec4 self_pixel = sample_scene(scene_coordinates);
    float self_brightness = max(self_pixel.r, max(self_pixel.g, self_pixel.b));
    if (self_brightness >= uniform_parameters.emissive_threshold) {
        imageStore(output_image, output_coordinates, self_pixel);
        return;
    }

    vec3 total_light = vec3(0.0);

    // 像素级随机偏移，避免所有像素采样方向相同导致结构化噪声
    float pixel_offset = hash12(vec2(output_coordinates)) * GOLDEN_ANGLE;

    // 发射多条光线
    for (int sample_index = 0; sample_index < uniform_parameters.number_samples; sample_index++) {
        float angle = pixel_offset + GOLDEN_ANGLE * float(sample_index);
        vec2 direction = vec2(cos(angle), sin(angle));
        total_light += march_ray(uv_coordinates, direction, scene_texture_size);
    }

    total_light /= float(uniform_parameters.number_samples);

    imageStore(output_image, output_coordinates, vec4(total_light, 1.0));
}
