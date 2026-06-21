#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba8) uniform restrict readonly image2D input_image;
layout(set = 0, binding = 1, rgba8) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 coords = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(output_image);

    if (coords.x >= size.x || coords.y >= size.y) {
        return;
    }

    vec4 color = imageLoad(input_image, coords);

    // 非透明像素：输出 UV 坐标 (U=R, V=G)
    if (color.a > 0.0) {
        vec2 uv = vec2(float(coords.x) / float(size.x), float(coords.y) / float(size.y));
        imageStore(output_image, coords, vec4(uv.x, uv.y, 0.0, 1.0));
    }
    // 透明像素：输出黑色透明
    else {
        imageStore(output_image, coords, vec4(0.0, 0.0, 0.0, 0.0));
    }
}
