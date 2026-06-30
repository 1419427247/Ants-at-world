class_name StateGrid extends Node2D

## 分块元胞自动机网格 — 使用计算着色器渲染 preview

@export var chunk_size: int = 64:
	set(value):
		if chunks.is_empty(): chunk_size = maxi(value, 8)
		
const PREVIEW_COMPUTE = preload("uid://n1bajw5xis0y")
const EMPTY: int = 0
const BOUNDARY: int = 255


class Chunk:
	var state_grid: StateGrid
	var coord: Vector2i
	var ghost_size: int
	var cells:        Array[Vector4i]
	var output_cells: Array[Vector4i]
	var texture: Texture2DRD
	var voxel_count: int
	var _output_tex_rid: RID
	var _output_set_rid: RID
	var _dirty: bool = false

	func _init(size: int) -> void:
		ghost_size = size + 2
		var total: int = ghost_size * ghost_size
		cells.resize(total)
		cells.fill(Vector4i.ZERO)
		output_cells.resize(total)
		output_cells.fill(Vector4i.ZERO)
		texture = Texture2DRD.new()
		voxel_count = 0

	func commit_cells() -> void:
		## 将 output_cells 写回 cells，更新 voxel_count，清空 output_cells
		cells.assign(output_cells)
		voxel_count = cells.size() - cells.count(Vector4i.ZERO)
		output_cells.fill(Vector4i.ZERO)

	func commit_gpu(rd: RenderingDevice, pipeline: RID,
			shader_rid: RID, input_tex: RID,
			input_set: RID, palette_set: RID) -> void:
		## 上传 cells → GPU → 派发计算着色器 → 更新 texture
		# —— 上传 cells data 到 input 纹理 ——
		var total: int = ghost_size * ghost_size
		var cell_data: PackedByteArray = PackedByteArray()
		cell_data.resize(total)
		for i: int in total:
			cell_data[i] = cells[i].x
		rd.texture_update(input_tex, 0, cell_data)

		# —— 惰性创建 chunk 专属 output 纹理 ——
		if not _output_tex_rid.is_valid():
			var ofmt: RDTextureFormat = RDTextureFormat.new()
			ofmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
			ofmt.width = ghost_size
			ofmt.height = ghost_size
			ofmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
				| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			_output_tex_rid = rd.texture_create(ofmt, RDTextureView.new(), [])

			var uniform: RDUniform = RDUniform.new()
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform.binding = 0
			uniform.add_id(_output_tex_rid)
			_output_set_rid = rd.uniform_set_create([uniform], shader_rid, 1)

		# —— 派发计算着色器 ——
		var cl: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, input_set, 0)
		rd.compute_list_bind_uniform_set(cl, _output_set_rid, 1)
		rd.compute_list_bind_uniform_set(cl, palette_set, 2)
		var groups: int = (ghost_size + 7) / 8
		rd.compute_list_dispatch(cl, groups, groups, 1)
		rd.compute_list_end()

		texture.texture_rd_rid = _output_tex_rid
		_dirty = false

	func set_cell(coordinates: Vector2i, voxel: Color) -> void:
		coordinates += Vector2i.ONE
		var index: int = coordinates.y * ghost_size + coordinates.x
		if cells[index].x == 0 and voxel.a8 != 0:
			voxel_count += 1
		elif cells[index].x != 0 and voxel.a8 == 0:
			voxel_count -= 1
		cells[index] = Vector4i(voxel.a8, 0, 0, 0)
		_dirty = true

	func get_cell(coordinates: Vector2i) -> Color:
		coordinates += Vector2i.ONE
		var index: int = coordinates.y * ghost_size + coordinates.x
		return Color(0.0, 0.0, 0.0, float(cells[index].x) / 255.0)


var chunks: Dictionary[Vector2i, Chunk]
var strategy: SimulationStrategy


# RD 渲染基础设施（遵循 ComputePass 模式）
var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _palette_buf_rid: RID
var _input_tex_rid: RID
var _input_set_rid: RID
var _palette_set_rid: RID
var _rd_ready: bool = false


func _ready() -> void:
	_init_rd()


func _init_rd() -> void:
	_rd = RenderingServer.get_rendering_device()
	assert(_rd != null, "StateGrid: 无法获取 RenderingDevice")

	# 编译计算着色器（两步：shader_create_from_spirv → compute_pipeline_create）
	var spirv: RDShaderSPIRV = PREVIEW_COMPUTE.get_spirv()
	_shader_rid = _rd.shader_create_from_spirv(spirv)
	assert(_shader_rid.is_valid(), "StateGrid: 着色器编译失败")
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	assert(_pipeline_rid.is_valid(), "StateGrid: 管线创建失败")

	_create_palette()
	_create_io_textures()
	_create_uniform_sets()
	_rd_ready = true


func _create_palette() -> void:
	# 调色板 storage buffer（256 × RGBA8 uint，内存布局 R,G,B,A）
	var pal_data: PackedByteArray = PackedByteArray()
	pal_data.resize(256 * 4)
	for i: int in 256:
		var c: Color
		match i:
			0:  c = Color.TRANSPARENT
			1:  c = Color(0, 0.5, 0)
			2:  c = Color.YELLOW
			3:  c = Color.BLUE
			4:  c = Color(0, 0.6, 0.2)
			5:  c = Color(0.5, 0.3, 0.1)
			6:  c = Color(1, 0.3, 0)
			_:  c = Color.WHITE
		pal_data.encode_s32(i * 4, (int(c.a8) << 24) | (int(c.b8) << 16) | (int(c.g8) << 8) | c.r8)
	_palette_buf_rid = _rd.storage_buffer_create(256 * 4, pal_data)
	assert(_palette_buf_rid.is_valid(), "StateGrid: 调色板 buffer 创建失败")


func _create_io_textures() -> void:
	var gs: int = chunk_size + 2

	var ifmt: RDTextureFormat = RDTextureFormat.new()
	ifmt.format = RenderingDevice.DATA_FORMAT_R8_UINT
	ifmt.width = gs
	ifmt.height = gs
	ifmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_input_tex_rid = _rd.texture_create(ifmt, RDTextureView.new(), [])
	assert(_input_tex_rid.is_valid(), "StateGrid: input 纹理创建失败")


func _create_uniform_sets() -> void:
	# set 0: input cells（R8 image）
	var u_input: RDUniform = RDUniform.new()
	u_input.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_input.binding = 0
	u_input.add_id(_input_tex_rid)
	_input_set_rid = _rd.uniform_set_create([u_input], _shader_rid, 0)
	assert(_input_set_rid.is_valid(), "StateGrid: input uniform set 创建失败")

	# set 2: palette（storage buffer）
	var u_palette: RDUniform = RDUniform.new()
	u_palette.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_palette.binding = 0
	u_palette.add_id(_palette_buf_rid)
	_palette_set_rid = _rd.uniform_set_create([u_palette], _shader_rid, 2)
	assert(_palette_set_rid.is_valid(), "StateGrid: palette uniform set 创建失败")

func _exit_tree() -> void:
	if not _rd_ready:
		return
	# 释放 Chunk 输出纹理（uniform set → texture）
	for chunk: Chunk in chunks.values():
		if chunk._output_set_rid.is_valid():
			_rd.free_rid(chunk._output_set_rid)
		if chunk._output_tex_rid.is_valid():
			_rd.free_rid(chunk._output_tex_rid)
	# 释放顺序：uniform sets → textures/buffers → pipeline → shader
	for rid in [_input_set_rid, _palette_set_rid]:
		if rid.is_valid():
			_rd.free_rid(rid)
	for rid in [_input_tex_rid, _palette_buf_rid]:
		if rid.is_valid():
			_rd.free_rid(rid)
	if _pipeline_rid.is_valid():
		_rd.free_rid(_pipeline_rid)
	if _shader_rid.is_valid():
		_rd.free_rid(_shader_rid)
	_rd_ready = false

func update() -> void:
	if not _rd_ready:
		return
	var gs: int = chunk_size + 2

	# 1. 幽灵边界同步
	for chunk_key: Vector2i in chunks:
		var chunk: Chunk = chunks[chunk_key]
		if chunk.voxel_count == 0:
			continue
		var cx: int = chunk_key.x
		var cy: int = chunk_key.y
		var g: int = chunk.ghost_size

		var top_chunk: Chunk = chunks.get(Vector2i(cx, cy - 1), null)
		for lx: int in chunk_size:
			var px: int = lx + 1
			chunk.cells[px] = Vector4i(
				top_chunk.cells[chunk_size * top_chunk.ghost_size + px].x if top_chunk else 0, 0, 0, 0)

		var bottom_chunk: Chunk = chunks.get(Vector2i(cx, cy + 1), null)
		for lx: int in chunk_size:
			var px: int = lx + 1
			chunk.cells[(gs - 1) * g + px] = Vector4i(
				bottom_chunk.cells[bottom_chunk.ghost_size + px].x if bottom_chunk else 0, 0, 0, 0)

		var left_chunk: Chunk = chunks.get(Vector2i(cx - 1, cy), null)
		for ly: int in chunk_size:
			var py: int = ly + 1
			chunk.cells[py * g] = Vector4i(
				left_chunk.cells[py * left_chunk.ghost_size + chunk_size].x if left_chunk else 0, 0, 0, 0)

		var right_chunk: Chunk = chunks.get(Vector2i(cx + 1, cy), null)
		for ly: int in chunk_size:
			var py: int = ly + 1
			chunk.cells[py * g + (gs - 1)] = Vector4i(
				right_chunk.cells[py * right_chunk.ghost_size + 1].x if right_chunk else 0, 0, 0, 0)

	# 2. 全局收集动作
	var all_actions: Array = []
	var chunk_keys: Array[Vector2i] = chunks.keys()
	if strategy != null:
		for chunk_key: Vector2i in chunk_keys:
			var actions: Array = strategy.process(chunks[chunk_key])
			all_actions.append_array(actions)

	# 3. Phase 0：复制所有 chunk 内部区域到 output_cells
	for chunk_key: Vector2i in chunk_keys:
		var chunk: Chunk = chunks[chunk_key]
		for y: int in chunk_size:
			for x: int in chunk_size:
				var index: int = (y + 1) * gs + (x + 1)
				chunk.output_cells[index] = chunk.cells[index]

	# 4. 统一解算 + 写入
	_resolve_and_apply_actions(all_actions)

	# 5. commit 数据 + GPU 渲染
	for chunk_key: Vector2i in chunk_keys:
		var chunk: Chunk = chunks[chunk_key]
		chunk.commit_cells()
		if chunk._dirty:
			chunk.commit_gpu(_rd, _pipeline_rid,
					_shader_rid, _input_tex_rid, _input_set_rid, _palette_set_rid)

	queue_redraw()


# ==================================================================
# 动作解算
# ==================================================================
## 全局动作解算 — 防跨块写入冲突
##   SWAP: [SWAP, source, target]       读取 source 材质写入 target
##   SPAWN:[SPAWN,target, material_id]  直写材质到 target
func _resolve_and_apply_actions(actions: Array) -> void:
	if actions.is_empty():
		return

	var target_occupied: Dictionary[Vector2i, bool] = {}
	for a: Array in actions:
		var tgt_idx: int = a.size() - 1  # target 始终是倒数第二个元素
		target_occupied[a[tgt_idx]] = true

	var final_targets: Dictionary[Vector2i, bool] = {}
	for a: Array in actions:
		var type: int = a[0]

		if type == CpuSimulationStrategy.ActionType.SWAP:
			var source: Vector2i = a[1]
			var target: Vector2i = a[2]

			# 规则 1：source 被其他动作 target 占用 → 跳过
			if source in target_occupied and source != target:
				continue
			# 规则 2：target 已被占用 → 跳过
			if target in final_targets:
				continue
			final_targets[target] = true

			var material_id: int = _read_output_cell(source)
			if material_id == 0:
				continue
			_set_output_cell(source, 0)
			_set_output_cell(target, material_id)

		elif type == CpuSimulationStrategy.ActionType.SPAWN:
			var target: Vector2i = a[1]
			var material_id: int = a[2]

			if target in final_targets:
				continue
			final_targets[target] = true

			_set_output_cell(target, material_id)


## 在 output_cells 中写入材质 ID，自动处理跨块寻址
func _set_output_cell(world_pos: Vector2i, material_id: int) -> void:
	for chunk_key: Vector2i in chunks:
		var chunk: Chunk = chunks[chunk_key]
		var local_x: int = world_pos.x - chunk_key.x * chunk_size + 1
		var local_y: int = world_pos.y - chunk_key.y * chunk_size + 1
		if local_x >= 1 and local_x <= chunk_size and local_y >= 1 and local_y <= chunk_size:
			chunk.output_cells[local_y * chunk.ghost_size + local_x] = Vector4i(material_id, 0, 0, 0)
			chunk._dirty = true
			return

	# 目标不在任何已有 chunk 内 → 创建新 chunk
	sim_write(world_pos, Color(0.0, 0.0, 0.0, float(material_id) / 255.0))


## 从 output_cells 读取材质 ID，自动处理跨块寻址
func _read_output_cell(world_pos: Vector2i) -> int:
	for chunk_key: Vector2i in chunks:
		var chunk: Chunk = chunks[chunk_key]
		var local_x: int = world_pos.x - chunk_key.x * chunk_size + 1
		var local_y: int = world_pos.y - chunk_key.y * chunk_size + 1
		if local_x >= 1 and local_x <= chunk_size and local_y >= 1 and local_y <= chunk_size:
			return chunk.output_cells[local_y * chunk.ghost_size + local_x].x
	return 0


# ==================================================================
# 渲染
# ==================================================================
func _draw() -> void:
	var region: Rect2 = Rect2(Vector2i.ONE, Vector2i(chunk_size, chunk_size))
	for chunk_key: Vector2i in chunks:
		var chunk: Chunk = chunks[chunk_key]
		var pos: Vector2 = Vector2(chunk_key * chunk_size)
		if chunk.texture.texture_rd_rid.is_valid():
			draw_texture_rect_region(chunk.texture, Rect2(pos, region.size), region)

	var line_color: Color = Color(0.5, 0.5, 0.5, 0.3)
	for chunk_key: Vector2i in chunks:
		var pos: Vector2 = Vector2(chunk_key * chunk_size)
		draw_rect(Rect2(pos, Vector2(chunk_size, chunk_size)), line_color, false, 1.0)


# ==================================================================
# 模拟期数据访问
# ==================================================================
func sim_read(world_coordinates: Vector2i) -> Color:
	var chunk_key: Vector2i = _world_to_chunk_coordinates(world_coordinates.x, world_coordinates.y)
	var chunk: Chunk = chunks.get(chunk_key, null)
	if chunk == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var local: Vector2i = Vector2(world_coordinates).posmodv(Vector2(chunk_size, chunk_size))
	local += Vector2i.ONE
	return Color(0.0, 0.0, 0.0, float(chunk.cells[local.y * chunk.ghost_size + local.x].x) / 255.0)


func sim_write(world_coordinates: Vector2i, voxel: Color) -> void:
	var chunk_key: Vector2i = _world_to_chunk_coordinates(world_coordinates.x, world_coordinates.y)
	var chunk: Chunk = chunks.get(chunk_key, null)
	if chunk == null:
		chunk = Chunk.new(chunk_size)
		chunk.state_grid = self
		chunk.coord = chunk_key
		chunks[chunk_key] = chunk
	var local: Vector2i = Vector2(world_coordinates).posmodv(Vector2(chunk_size, chunk_size))
	local += Vector2i.ONE
	chunk.output_cells[local.y * chunk.ghost_size + local.x] = Vector4i(voxel.a8, 0, 0, 0)
	chunk._dirty = true


# ==================================================================
# 外部格子读写
# ==================================================================
func set_cell(world_coordinates: Vector2i, voxel: Color) -> void:
	var chunk_key: Vector2i = _world_to_chunk_coordinates(world_coordinates.x, world_coordinates.y)
	var chunk: Chunk = chunks.get(chunk_key, null)
	if chunk == null:
		chunk = Chunk.new(chunk_size)
		chunk.state_grid = self
		chunk.coord = chunk_key
		chunks[chunk_key] = chunk
	var local_coordinates: Vector2i = Vector2(world_coordinates).posmodv(Vector2(chunk_size, chunk_size))
	chunk.set_cell(local_coordinates, voxel)
	queue_redraw()


func get_cell(world_x: int, world_y: int) -> Color:
	var chunk_key: Vector2i = _world_to_chunk_coordinates(world_x, world_y)
	var chunk: Chunk = chunks.get(chunk_key, null)
	if chunk == null:
		return Color(0.0, 0.0, 0.0, 0.0)
	var local_coordinates: Vector2i = Vector2(world_x, world_y).posmodv(Vector2(chunk_size, chunk_size))
	return chunk.get_cell(local_coordinates)


func clear() -> void:
	for chunk: Chunk in chunks.values():
		chunk.cells.fill(Vector4i.ZERO)
		chunk.output_cells.fill(Vector4i.ZERO)
		chunk.voxel_count = 0
	queue_redraw()


# ==================================================================
# 内部
# ==================================================================
func _world_to_chunk_coordinates(world_x: int, world_y: int) -> Vector2i:
	return Vector2i(
		(world_x - posmod(world_x, chunk_size)) / chunk_size,
		(world_y - posmod(world_y, chunk_size)) / chunk_size
	)
