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

// 共享内存 tile：16×16 工作组 + 2*MAX_R 光环
const int WG = 16;
const int MAX_R = 4;
const int TILE = WG + 2 * MAX_R; // 24
shared float alpha_tile[TILE * TILE];

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);
    ivec2 local = ivec2(gl_LocalInvocationID.xy);

    int r = min(max(uniform_parameters.erosion_radius, 1), MAX_R);

    // === Phase 1: 协作加载 tile 到共享内存 ===
    // 256 线程协作加载 TILE*TILE=576 个像素，每线程约 2 次 textureLod
    int linear_id = local.y * WG + local.x;
    int tile_total = TILE * TILE;

    for (int idx = linear_id; idx < tile_total; idx += WG * WG) {
        int tx = idx % TILE;
        int ty = idx / TILE;
        ivec2 gpos = ivec2(gl_WorkGroupID.xy) * WG + ivec2(tx - MAX_R, ty - MAX_R);
        gpos = clamp(gpos, ivec2(0), texture_size - 1);
        vec2 tuv = (vec2(gpos) + 0.5) / vec2(texture_size);
        alpha_tile[idx] = textureLod(input_image, tuv, 0.0).a;
    }

    barrier();

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    // === Phase 2: 从共享内存读取 ===
    int cx = MAX_R + local.x;
    int cy = MAX_R + local.y;
    float center_alpha = alpha_tile[cy * TILE + cx];

    vec2 uv = (vec2(coordinates) + 0.5) / vec2(texture_size);

    // 空区直接输出
    if (center_alpha <= 0.0) {
        imageStore(output_image, coordinates, vec4(-1.0, -1.0, uv));
        return;
    }

    // 固体像素：用 (2r+1)×(2r+1) 核做形态学腐蚀
    bool is_eroded = false;

    for (int j = -r; j <= r && !is_eroded; j++) {
        for (int i = -r; i <= r && !is_eroded; i++) {
            if (i == 0 && j == 0) continue;

            // 贴边像素：超出纹理边界视为空区，强制腐蚀
            ivec2 gpos = coordinates + ivec2(i, j);
            if (gpos.x < 0 || gpos.x >= texture_size.x ||
                gpos.y < 0 || gpos.y >= texture_size.y) {
                is_eroded = true;
                break;
            }

            float neighbor_alpha = alpha_tile[(cy + j) * TILE + (cx + i)];
            if (neighbor_alpha <= 0.0) {
                is_eroded = true;
            }
        }
    }

    if (!is_eroded) {
        imageStore(output_image, coordinates, vec4(uv, -1.0, -1.0));
    } else {
        imageStore(output_image, coordinates, vec4(-1.0, -1.0, uv));
    }
}
