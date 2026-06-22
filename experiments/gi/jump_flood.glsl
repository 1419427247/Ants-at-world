#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 输入 RGBA16F
//   RG = 最近固体种子 UV（哨兵 x<0）
//   BA = 最近空区种子 UV（哨兵 z<0）
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D input_image;
// binding 1: 输出 RGBA16F（同结构）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int step_x;
    int step_y;
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec2 position_uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));

    vec4 current = imageLoad(input_image, coordinates);
    vec2 best_solid_uv = current.xy;
    vec2 best_empty_uv = current.zw;
    float best_solid_dist = 1e10;
    float best_empty_dist = 1e10;
    bool found_solid = best_solid_uv.x >= 0.0;
    bool found_empty = best_empty_uv.x >= 0.0;

    if (found_solid) best_solid_dist = distance(position_uv, best_solid_uv);
    if (found_empty) best_empty_dist = distance(position_uv, best_empty_uv);

    // 检查 3x3 邻域
    for (int offset_x = -1; offset_x <= 1; offset_x++) {
        for (int offset_y = -1; offset_y <= 1; offset_y++) {
            if (offset_x == 0 && offset_y == 0) continue;

            ivec2 nc = coordinates + ivec2(offset_x * uniform_parameters.step_x, offset_y * uniform_parameters.step_y);
            if (nc.x < 0 || nc.x >= texture_size.x || nc.y < 0 || nc.y >= texture_size.y) continue;

            vec4 neighbor = imageLoad(input_image, nc);

            // 更新最近固体
            if (neighbor.x >= 0.0) {
                float d = distance(position_uv, neighbor.xy);
                if (d < best_solid_dist) {
                    best_solid_dist = d;
                    best_solid_uv = neighbor.xy;
                    found_solid = true;
                }
            }

            // 更新最近空区
            if (neighbor.z >= 0.0) {
                float d = distance(position_uv, neighbor.zw);
                if (d < best_empty_dist) {
                    best_empty_dist = d;
                    best_empty_uv = neighbor.zw;
                    found_empty = true;
                }
            }
        }
    }

    vec2 out_solid = found_solid ? best_solid_uv : vec2(-1.0);
    vec2 out_empty = found_empty ? best_empty_uv : vec2(-1.0);
    imageStore(output_image, coordinates, vec4(out_solid, out_empty));
}
