#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: 场景纹理（Alpha 通道存表面高度/障碍物标记）
layout(set = 0, binding = 0) uniform sampler2D scene_image;
// binding 1: 输出法线图 RGB=法线*0.5+0.5, A=1.0
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform UniformParameters {
    int blur_radius; // Sobel 采样半径（1=3×3, 2=5×5）
} uniform_parameters;

const int WG = 16;
const int MAX_R = 4;
const int TILE = WG + 2 * MAX_R; // 24
shared float height_tile[TILE * TILE];

const vec3 UP_NORMAL = vec3(0.0, 0.0, 1.0);

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);
    ivec2 local = ivec2(gl_LocalInvocationID.xy);

    int r = min(max(uniform_parameters.blur_radius, 1), MAX_R);

    // === Phase 1: 协作加载 tile 到共享内存 ===
    int linear_id = local.y * WG + local.x;
    int tile_total = TILE * TILE;

    for (int idx = linear_id; idx < tile_total; idx += WG * WG) {
        int tx = idx % TILE;
        int ty = idx / TILE;
        ivec2 gpos = ivec2(gl_WorkGroupID.xy) * WG + ivec2(tx - MAX_R, ty - MAX_R);
        gpos = clamp(gpos, ivec2(0), texture_size - 1);
        vec2 tuv = (vec2(gpos) + 0.5) / vec2(texture_size);
        height_tile[idx] = textureLod(scene_image, tuv, 0.0).a;
    }

    barrier();

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    // === Phase 2: 从共享内存做 Sobel ===
    int cx = MAX_R + local.x;
    int cy = MAX_R + local.y;
    float center_alpha = height_tile[cy * TILE + cx];

    if (center_alpha < 0.001) {
        imageStore(output_image, coordinates, vec4(UP_NORMAL * 0.5 + 0.5, 1.0));
        return;
    }

    float gx = 0.0, gy = 0.0;

    for (int j = -r; j <= r; j++) {
        for (int i = -r; i <= r; i++) {
            if (i == 0 && j == 0) continue;
            float h = height_tile[(cy + j) * TILE + (cx + i)];
            gx += h * float(i);
            gy += h * float(j);
        }
    }

    vec3 normal = normalize(vec3(-gx, -gy, 1.0));
    vec3 normal_enc = normal * 0.5 + 0.5;

    imageStore(output_image, coordinates, vec4(normal_enc, 1.0));
}
