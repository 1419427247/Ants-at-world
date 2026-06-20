#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba8, binding = 0) uniform restrict readonly image2D current_state;
layout(rgba8, binding = 1) uniform restrict writeonly image2D next_state;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(current_state);

    if (pos.x >= size.x || pos.y >= size.y) {
        return;
    }

    // 统计活邻居数（环形边界）
    int live_neighbors = 0;
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            if (dx == 0 && dy == 0) continue;
            ivec2 neighbor = pos + ivec2(dx, dy);
            // 环形边界环绕
            neighbor.x = (neighbor.x + size.x) % size.x;
            neighbor.y = (neighbor.y + size.y) % size.y;
            float val = imageLoad(current_state, neighbor).r;
            if (val > 0.5) live_neighbors++;
        }
    }

    float current = imageLoad(current_state, pos).r;
    float result = 0.0;

    if (current > 0.5) {
        // 活细胞：2或3个邻居则存活
        if (live_neighbors == 2 || live_neighbors == 3) {
            result = 1.0;
        }
    } else {
        // 死细胞：恰好3个邻居则新生
        if (live_neighbors == 3) {
            result = 1.0;
        }
    }

    imageStore(next_state, pos, vec4(result, result, result, 1.0));
}
