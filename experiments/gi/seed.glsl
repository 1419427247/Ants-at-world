#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D input_image;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 pixel_color = imageLoad(input_image, coordinates);

    if (pixel_color.a > 0.0) {
        // 边缘修补：如果上下左右任一邻居不是种子，则丢弃此像素
        // 让光源内缩一圈，避免 raymarch 停在光源边缘产生锯齿和黑影抖动
        bool is_edge_pixel = false;
        is_edge_pixel = is_edge_pixel || (coordinates.x > 0 && imageLoad(input_image, coordinates - ivec2(1, 0)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.x < texture_size.x - 1 && imageLoad(input_image, coordinates + ivec2(1, 0)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.y > 0 && imageLoad(input_image, coordinates - ivec2(0, 1)).a <= 0.0);
        is_edge_pixel = is_edge_pixel || (coordinates.y < texture_size.y - 1 && imageLoad(input_image, coordinates + ivec2(0, 1)).a <= 0.0);

        if (is_edge_pixel) {
            imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 0.0));
        } else {
            // 种子像素：存储自身 UV 坐标 (U=R, V=G), A=1
            vec2 uv_coordinates = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));
            imageStore(output_image, coordinates, vec4(uv_coordinates.x, uv_coordinates.y, 0.0, 1.0));
        }
    } else {
        // 空白像素：A=0
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 0.0));
    }
}
