#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 从 ScalePass 输入（rgba16f），读取 alpha 判断可见性
layout(set = 0, binding = 0) uniform sampler2D input_image;
// binding 1: 输出 RGBA16F
//   RG = 最近固体种子 UV（哨兵 -1）
//   BA = 最近空区种子 UV（哨兵 -1）
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int erosion_radius; // 腐蚀半径（像素单位，1=3×3 核内缩1圈）
} uniform_parameters;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 pixel_color = texture(input_image, (vec2(coordinates) + 0.5) / vec2(texture_size));
    vec2 uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));

    // 空区直接输出
    if (pixel_color.a <= 0.0) {
        imageStore(output_image, coordinates, vec4(-1.0, -1.0, uv));
        return;
    }

    // 固体像素：用 3×3 核做形态学腐蚀
    // 只要 3×3 邻域内有空区像素，当前固体像素就被腐蚀为空区种子
    // 效果：光源/障碍物整体内缩 erosion_radius 像素
    int r = max(uniform_parameters.erosion_radius, 1);
    bool is_eroded = false;

    for (int j = -r; j <= r && !is_eroded; j++) {
        for (int i = -r; i <= r && !is_eroded; i++) {
            if (i == 0 && j == 0) continue;

            ivec2 nc = coordinates + ivec2(i, j);
            if (nc.x < 0 || nc.x >= texture_size.x ||
                nc.y < 0 || nc.y >= texture_size.y) {
                // 贴边像素：超出边界视为空区，强制腐蚀
                is_eroded = true;
                break;
            }

            vec2 neighbor_uv = (vec2(nc) + 0.5) / vec2(texture_size);
            if (texture(input_image, neighbor_uv).a <= 0.0) {
                is_eroded = true;
            }
        }
    }

    if (!is_eroded) {
        // 内核固体像素：RG=自身UV（固体种子），BA=哨兵
        imageStore(output_image, coordinates, vec4(uv, -1.0, -1.0));
    } else {
        // 边缘腐蚀掉的像素：当作空区种子
        imageStore(output_image, coordinates, vec4(-1.0, -1.0, uv));
    }
}
