#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// binding 0: Voronoi 结果（RGBA16F: RG=最近固体UV, BA=最近空区UV, 哨兵 <0）
layout(set = 0, binding = 0) uniform sampler2D voronoi_image;
// binding 1: 输出（RGBA16F）
//   R  = 到最近异质点的距离
//   GB = 指向最近异质点的方向向量（归一化）
//   A  = 1.0
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D output_image;

void main() {
    ivec2 coordinates = ivec2(gl_GlobalInvocationID.xy);
    ivec2 texture_size = imageSize(output_image);

    if (coordinates.x >= texture_size.x || coordinates.y >= texture_size.y) return;

    vec4 voronoi = texture(voronoi_image, (vec2(coordinates) + 0.5) / vec2(texture_size));
    vec2 pixel_uv = vec2(float(coordinates.x) / float(texture_size.x), float(coordinates.y) / float(texture_size.y));

    // 判断当前像素是固体还是空区：固体 voxel 的 RG 等于自身 UV
    bool is_solid = distance(voronoi.xy, pixel_uv) < 0.001;

    vec2 nearest_uv;
    float nearest_dist;

    if (is_solid) {
        // 固体 → 最近异质点是空区
        if (voronoi.z >= 0.0) {
            nearest_uv = voronoi.zw;
            float d = distance(pixel_uv, nearest_uv);
            nearest_dist = d < 0.001 ? 0.0 : d;
        } else {
            nearest_uv = vec2(0.0);
            nearest_dist = 1.0;
        }
    } else {
        // 空区 → 最近异质点是固体
        if (voronoi.x >= 0.0) {
            nearest_uv = voronoi.xy;
            float d = distance(pixel_uv, nearest_uv);
            nearest_dist = d < 0.001 ? 0.0 : d;
        } else {
            nearest_uv = vec2(0.0);
            nearest_dist = 1.0;
        }
    }

    // 计算方向（归一化向量，指向最近异质点）
    vec2 dir_to_hetero = nearest_dist > 0.001 ? normalize(nearest_uv - pixel_uv) : vec2(0.0);

    // 输出：R=距离, GB=方向, A=1
    imageStore(output_image, coordinates, vec4(nearest_dist, dir_to_hetero, 1.0));
}
