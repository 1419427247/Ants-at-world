#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D input_image;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int step_x;
    int step_y;
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec2 position_uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));

    vec4 current_pixel = imageLoad(input_image, coordinates);
    vec2 best_uv = current_pixel.xy;
    float best_distance = 1e10;
    bool found_seed = current_pixel.a > 0.0;

    if (found_seed) {
        best_distance = distance(position_uv, best_uv);
    }

    // 检查 3x3 邻域，偏移量为 (step_x, step_y)
    for (int offset_x = -1; offset_x <= 1; offset_x++) {
        for (int offset_y = -1; offset_y <= 1; offset_y++) {
            if (offset_x == 0 && offset_y == 0) continue;

            ivec2 neighbor_coordinates = coordinates + ivec2(offset_x * uniform_parameters.step_x, offset_y * uniform_parameters.step_y);
            if (neighbor_coordinates.x < 0 || neighbor_coordinates.x >= texture_size.x || neighbor_coordinates.y < 0 || neighbor_coordinates.y >= texture_size.y) continue;

            vec4 neighbor_pixel = imageLoad(input_image, neighbor_coordinates);
            if (neighbor_pixel.a <= 0.0) continue;

            vec2 neighbor_uv = neighbor_pixel.xy;
            float distance_value = distance(position_uv, neighbor_uv);
            if (distance_value < best_distance) {
                best_distance = distance_value;
                best_uv = neighbor_uv;
                found_seed = true;
            }
        }
    }

    imageStore(output_image, coordinates, vec4(best_uv.x, best_uv.y, 0.0, found_seed ? 1.0 : 0.0));
}
