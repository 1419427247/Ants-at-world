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
    // 亮度公式: L = 0.299*R + 0.587*G + 0.114*B
    float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    imageStore(output_image, coords, vec4(vec3(gray), 1.0));
}
