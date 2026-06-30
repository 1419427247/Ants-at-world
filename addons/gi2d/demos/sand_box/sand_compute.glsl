#[compute]
#version 450

// ============================================================
// 通用沙盒物理计算着色器 — 每个材质一个 Pass
//
// PushConstant: [chunk_x, chunk_y, target_material_id, is_solid, is_liquid, density_byte, frame_seed, 0]
// 每个 Pass 只处理匹配 target_material_id 的格子，
// 不匹配的格子原样复制到输出。Halo 格子始终写 0（防止幽灵数据路由到邻居块）。
// ============================================================

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(r8ui, set = 0, binding = 0) uniform readonly  uimage2D chunk_input;
layout(r8ui, set = 1, binding = 0) uniform writeonly uimage2D chunk_output;

layout(push_constant, std430) uniform PushConstants {
	int chunk_x;
	int chunk_y;
	int target_material_id;
	int is_solid_flag;
	int is_liquid_flag;
	int density_byte;
	int frame_seed;
	int padding_1;
} push_data;

const uint EMPTY    = 0u;
const uint SAND     = 1u;
const uint WATER    = 2u;
const uint DIRT     = 3u;
const uint GRASS    = 4u;
const uint WALL     = 5u;
const uint LAVA     = 6u;
const uint BOUNDARY = 255u;

const int HALO_SIZE = 66;


float random_hash(ivec2 position) {
	int hash_value = position.x * 374761393 + position.y * 668265263 + push_data.frame_seed * 1103515245;
	hash_value = (hash_value ^ (hash_value >> 13)) * 1274126177;
	return float(hash_value & 0x7fffffff) / float(0x7fffffff);
}


void main() {
	ivec2 global_id = ivec2(gl_GlobalInvocationID.xy);
	if (global_id.x >= HALO_SIZE || global_id.y >= HALO_SIZE) {
		return;
	}

	uint material = imageLoad(chunk_input, global_id).r;

	// Halo 边框永远写 0 — 防止邻居块数据被 _resolve_halo_writes 误路由
	if (global_id.x == 0 || global_id.x == HALO_SIZE - 1 || global_id.y == 0 || global_id.y == HALO_SIZE - 1) {
		imageStore(chunk_output, global_id, uvec4(0u, 0u, 0u, 0u));
		return;
	}

	// 只有匹配目标材质的格子才执行物理
	if (material != push_data.target_material_id) {
		imageStore(chunk_output, global_id, uvec4(material, 0u, 0u, 0u));
		return;
	}

	uint below         = imageLoad(chunk_input, global_id + ivec2( 0,  1)).r;
	uint below_left    = imageLoad(chunk_input, global_id + ivec2(-1,  1)).r;
	uint below_right   = imageLoad(chunk_input, global_id + ivec2( 1,  1)).r;
	uint left_neighbor = imageLoad(chunk_input, global_id + ivec2(-1,  0)).r;
	uint right_neighbor = imageLoad(chunk_input, global_id + ivec2( 1,  0)).r;

	uint result  = material;
	int  write_x = global_id.x;
	int  write_y = global_id.y;

	if (push_data.target_material_id == int(SAND)) {
		if (below == EMPTY) {
			write_y += 1; result = SAND;
		} else if (below == WATER) {
			imageStore(chunk_output, global_id, uvec4(WATER, 0u, 0u, 0u));
			write_y += 1; result = SAND;
		} else if (below_left == EMPTY) {
			write_x -= 1; write_y += 1; result = SAND;
		} else if (below_right == EMPTY) {
			write_x += 1; write_y += 1; result = SAND;
		}
	} else if (push_data.target_material_id == int(WATER)) {
		if (below == EMPTY) {
			write_y += 1; result = WATER;
		} else if (below_left == EMPTY) {
			write_x -= 1; write_y += 1; result = WATER;
		} else if (below_right == EMPTY) {
			write_x += 1; write_y += 1; result = WATER;
		} else if (left_neighbor == EMPTY && random_hash(global_id) < 0.5) {
			write_x -= 1; result = WATER;
		} else if (right_neighbor == EMPTY) {
			write_x += 1; result = WATER;
		}
	} else if (push_data.target_material_id == int(LAVA)) {
		if (below == WATER) {
			imageStore(chunk_output, global_id + ivec2(0, 1), uvec4(WALL, 0u, 0u, 0u));
			return;
		} else if (below == EMPTY) {
			write_y += 1; result = LAVA;
		} else if (below_left == EMPTY) {
			write_x -= 1; write_y += 1; result = LAVA;
		} else if (below_right == EMPTY) {
			write_x += 1; write_y += 1; result = LAVA;
		}
	}

	imageStore(chunk_output, ivec2(write_x, write_y), uvec4(result, 0u, 0u, 0u));
}
