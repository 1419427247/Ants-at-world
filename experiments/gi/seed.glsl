#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 从 ScalePass 输入（rgba16f），读取 alpha 判断可见性
layout(set = 0, binding = 0, rgba16f) uniform restrict readonly image2D input_image;
// binding 1: 输出 RGBA16F
//   RG = 最近固体种子 UV（哨兵 -1）
//   BA = 最近空区种子 UV（哨兵 -1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 pixel_color = imageLoad(input_image, coordinates);
    vec2 uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));

    // 边缘修补：上下左右任一邻居不是种子则视为边缘
    bool is_edge_pixel = false;
    if (pixel_color.a > 0.0) {
        is_edge_pixel = is_edge_pixel || (coordinates.x > 0 && imageLoad(input_image, coordinates - ivec2(1, 0)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.x < texture_size.x - 1 && imageLoad(input_image, coordinates + ivec2(1, 0)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.y > 0 && imageLoad(input_image, coordinates - ivec2(0, 1)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.y < texture_size.y - 1 && imageLoad(input_image, coordinates + ivec2(0, 1)).a <= 0.0);
    }

    if (pixel_color.a > 0.0 && !is_edge_pixel) {
        // 固体像素：RG=自身UV（固体种子），BA=哨兵（尚不知最近空区）
        imageStore(output_image, coordinates, vec4(uv, -1.0, -1.0));
    } else {
        // 空区像素（含边缘腐蚀掉的）：RG=哨兵，BA=自身UV（空区种子）
        imageStore(output_image, coordinates, vec4(-1.0, -1.0, uv));
    }
}
