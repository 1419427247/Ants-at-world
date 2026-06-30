class_name GpuSimulationStrategy extends SimulationStrategy

## GPU 模拟策略 — 三阶段流水线 + 单层纹理
##
## 模式二：大规模并行（单层 data/output）
## 阶段 1（Kernel A）：意图广播 — 每个线程读源格子的 pixel 值，计算目标，写入 IntentBuf
## 阶段 2（Kernel B）：目标仲裁 — 每个线程对应目标格子，收集所有意图，选出最高优先级者 atomicCAS 锁定
## 阶段 3（Kernel C）：结果提交 — 锁定成功 → 写到目标，失败 → 回滚

var _shader_file:    RDShaderFile
var _pipeline:       RID
var _input_tex:      RID
var _output_tex:     RID
var _input_set:      RID
var _output_set:     RID
var _intent_buf:     RID
var _lock_buf:       RID
var _rd:             RenderingDevice
var _ready:          bool = false
var _chunk_size:     int  = 0


func bind_shader(shader_file: RDShaderFile) -> void:
	_shader_file = shader_file


func initialize(rendering_device: RenderingDevice, chunk_size: int) -> void:
	if _shader_file == null:
		return
	_rd = rendering_device
	_chunk_size = chunk_size

	var halo_size: int = chunk_size + 2
	var format: RDTextureFormat = RDTextureFormat.new()
	format.format        = RenderingDevice.DATA_FORMAT_R8_UINT
	format.width         = halo_size
	format.height        = halo_size
	format.depth         = 1
	format.array_layers  = 1
	format.mipmaps       = 1
	format.texture_type  = RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits    = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
						 | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
						 | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	format.samples       = RenderingDevice.TEXTURE_SAMPLES_1

	var spirv_data: RDShaderSPIRV = _shader_file.get_spirv()
	if spirv_data.is_empty():
		push_error("GpuSimulationStrategy: 着色器编译失败")
		return

	_pipeline = rendering_device.compute_pipeline_create(spirv_data)

	_input_tex  = rendering_device.texture_create(format, RDTextureView.new(), [])
	_output_tex = rendering_device.texture_create(format, RDTextureView.new(), [])

	var input_uniform: RDUniform = RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	input_uniform.binding      = 0
	input_uniform.add_id(_input_tex)
	_input_set = rendering_device.uniform_set_create([input_uniform], _pipeline, 0)

	var output_uniform: RDUniform = RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	output_uniform.binding      = 0
	output_uniform.add_id(_output_tex)
	_output_set = rendering_device.uniform_set_create([output_uniform], _pipeline, 1)

	_ready = true


func process(chunk: StateGrid.Chunk) -> void:
	if not _ready:
		return

	var state_grid: StateGrid = chunk.state_grid
	var chunk_size: int = state_grid.chunk_size
	var ghost_size: int = chunk_size + 2
	var total_halo_cells: int = ghost_size * ghost_size
	var chunk_coord: Vector2i = chunk.coord

	# ----------------------------------------------------------
	# 上传 input 纹理（从 chunk.cells 转换）
	# ----------------------------------------------------------
	var input_data: PackedByteArray = PackedByteArray()
	input_data.resize(total_halo_cells)
	for i: int in total_halo_cells:
		input_data[i] = chunk.cells[i].x
	_rd.texture_update(_input_tex, 0, input_data)

	# ----------------------------------------------------------
	# 清零 output 纹理
	# ----------------------------------------------------------
	var clear_bytes: PackedByteArray = PackedByteArray()
	clear_bytes.resize(total_halo_cells)
	clear_bytes.fill(0x00)
	_rd.texture_update(_output_tex, 0, clear_bytes)

	# ----------------------------------------------------------
	# 创建 IntentBuf + LockBuf
	# ----------------------------------------------------------
	if _intent_buf.is_valid():
		_rd.free_rid(_intent_buf)
	if _lock_buf.is_valid():
		_rd.free_rid(_lock_buf)

	var intent_bytes: PackedByteArray = PackedByteArray()
	intent_bytes.resize(total_halo_cells * 4)
	intent_bytes.fill(0xFF)
	_intent_buf = _rd.storage_buffer_create(total_halo_cells * 4, intent_bytes)

	var lock_bytes: PackedByteArray = PackedByteArray()
	lock_bytes.resize(total_halo_cells * 4)
	lock_bytes.fill(0x00)
	_lock_buf = _rd.storage_buffer_create(total_halo_cells * 4, lock_bytes)

	# ----------------------------------------------------------
	# 派发计算着色器
	# ----------------------------------------------------------
	var push_constants: PackedByteArray = PackedByteArray()
	push_constants.resize(32)
	push_constants.encode_s32(0,  chunk_coord.x)
	push_constants.encode_s32(4,  chunk_coord.y)
	push_constants.encode_s32(8,  0)   # target_id（单层模式下为 0，由 shader 自行判断 pixel 值）
	push_constants.encode_s32(12, 0)   # is_solid
	push_constants.encode_s32(16, 0)   # is_liquid
	push_constants.encode_s32(20, 255) # density
	push_constants.encode_s32(24, randi())  # frame_seed
	push_constants.encode_s32(28, 0)   # padding

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _input_set, 0)
	_rd.compute_list_bind_uniform_set(compute_list, _output_set, 1)
	_rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	_rd.compute_list_dispatch(compute_list, ceili(ghost_size / 8), ceili(ghost_size / 8), 1)
	_rd.compute_list_end()

	_rd.sync()

	# ----------------------------------------------------------
	# 回读 output → chunk.output_cells
	# ----------------------------------------------------------
	var output_bytes: PackedByteArray = _rd.texture_get_data(_output_tex, 0)
	for i: int in total_halo_cells:
		chunk.output_cells[i] = Vector4i(output_bytes[i], 0, 0, 0)
