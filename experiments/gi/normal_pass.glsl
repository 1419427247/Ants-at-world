#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（Alpha 通道存表面高度/障碍物标记，
//   alpha=0 → 空区，法线指向上方；
//   alpha>0 → 障碍物表面，从邻域高度梯度计算法线）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出法线图
//   RGB = 法线向量（编码到 0-1 范围：n*0.5+0.5）
//   A   = 1.0
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int blur_radius; // Sobel 采样半径（1=3×3, 2=5×5）
} uniform_parameters;

// 空区法线：指向正面（垂直于屏幕向外）
const vec3 UP_NORMAL = vec3(0.0, 0.0, 1.0);

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(texture_size);
    vec2 pixel_size = vec2(1.0) / vec2(texture_size);

    float center_alpha = texture(scene_image, uv).a;

    // alpha=0：空区，法线指向上方
    if (center_alpha < 0.001) {
        imageStore(output_image, coordinates, vec4(UP_NORMAL * 0.5 + 0.5, 1.0));
        return;
    }

    int r = max(uniform_parameters.blur_radius, 1);

    // Sobel 算子计算高度梯度
    // 梯度方向 = 高度增加最快的方向
    float gx = 0.0, gy = 0.0;

    for (int j = -r; j <= r; j++) {
        for (int i = -r; i <= r; i++) {
            if (i == 0 && j == 0) continue;

            vec2 sample_uv = uv + vec2(float(i) * pixel_size.x, float(j) * pixel_size.y);
            float h = texture(scene_image, sample_uv).a;

            float wx = float(i);
            float wy = float(j);

            gx += h * wx;
            gy += h * wy;
        }
    }

    // 由高度梯度构造表面法线
    //   (gx, gy) = 高度梯度（指向高度升高的方向）
    //   表面法线 = normalize(-gx, -gy, 1.0)
    //   z=1 确保法线指向观察者，越陡峭的坡度 → x,y 分量越大
    vec3 normal = normalize(vec3(-gx, -gy, 1.0));

    // 编码到 0-1 范围
    vec3 normal_enc = normal * 0.5 + 0.5;

    imageStore(output_image, coordinates, vec4(normal_enc, 1.0));
}
