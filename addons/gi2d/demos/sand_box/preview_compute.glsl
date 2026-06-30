#[compute]
#version 450

// ============================================================
// 预览计算着色器 — cells (R8) → 调色板映射 → preview (RGBA8)
// ============================================================

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r8ui,          set = 0, binding = 0) uniform readonly  uimage2D input_cells;
layout(rgba8,         set = 1, binding = 0) uniform writeonly image2D output_preview;
layout(std430,        set = 2, binding = 0) readonly restrict buffer Palette { uint colors[]; } palette;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 sz = imageSize(input_cells);
	if (pos.x >= sz.x || pos.y >= sz.y) return;

	uint mat = imageLoad(input_cells, pos).r;
	imageStore(output_preview, pos, unpackUnorm4x8(palette.colors[mat]));
}
