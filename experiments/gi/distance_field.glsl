#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D voronoi_image;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 voronoi_pixel = imageLoad(voronoi_image, coordinates);
    vec2 pixel_uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));
    vec2 nearest_uv = voronoi_pixel.xy;

    float distance_value = distance(pixel_uv, nearest_uv);

    if (voronoi_pixel.a <= 0.0) {
        // 没有找到种子（全空区域）
        imageStore(output_image, coordinates, vec4(1.0, 1.0, 1.0, 0.0));
    } else if (distance_value < 0.001) {
        // 在表面像素上，距离为 0
        imageStore(output_image, coordinates, vec4(0.0, 0.0, 0.0, 1.0));
    } else {
        // 归一化距离（UV 空间）
        imageStore(output_image, coordinates, vec4(distance_value, distance_value, distance_value, 1.0));
    }
}
