## 计算着色器管线节点 — 抽象基类
##
## 统一 binding 布局：binding 0 = 主输入, binding 1 = 输出, binding 2+ = 额外输入
## 每个 Pass 自驱动执行，无需中央编排器。
## 主输入来源优先级：input_texture → source_viewport → primary_input → 前一个 ComputePass
## 输出纹理默认与源纹理同分辨率，子类可覆盖 _get_output_dimensions() 改变。

class_name ComputePass extends Node

## 是否启用此 Pass
@export var enabled: bool = true

## 输入纹理（设置后直接使用此纹理作为主输入，优先级最高）
@export var input_texture: Texture2D

## 源视口（设置后用视口纹理作为主输入）
@export var source_viewport: Viewport

## 主输入 Pass（source_viewport 为空时用该 Pass 的输出）
@export var primary_input: ComputePass

## 额外输入 Pass（按顺序绑定到 binding 2, 3, ...）
@export var extra_input_sources: Array[ComputePass]

## 输出目标 TextureRect（每帧更新该控件纹理，用于屏幕输出）
@export var output_target: TextureRect

var shader_path: String
var rendering_device: RenderingDevice
var shader_resource_id: RID
var pipeline_resource_id: RID
var output_texture_resource_id: RID
var uniform_set_resource_id: RID
var sampler_resource_id: RID
var display_texture: Texture2DRD = Texture2DRD.new()

## 帧计数器（每次成功 dispatch 后递增，供后续 Pass 判断是否有新输出）
var frame_counter: int = 0

var _output_width: int = 0
var _output_height: int = 0
var _output_format: RenderingDevice.DataFormat

# 依赖追踪
var _last_consumed_frame: Dictionary = {}  # ComputePass -> int
# 非 storage 纹理的兼容拷贝（仅视口纹理可能需要）
var _storage_copy_resource_id: RID
# uniform set 缓存
var _bound_source_resource_id: RID
var _bound_extra_resource_ids: Array[RID]
var _uniform_set_dirty: bool = true


func _ready() -> void:
	rendering_device = RenderingServer.get_rendering_device()
	assert(rendering_device != null, "无法获取主渲染设备")
	assert(shader_path != "", "shader_path 未设置 — 请使用子类")

	if not output_target:
		for child in get_children():
			if child is TextureRect:
				output_target = child
				break

	var shader_file: RDShaderFile = load(shader_path) as RDShaderFile
	assert(shader_file != null, "无法加载着色器: " + shader_path)
	var spirv_data: RDShaderSPIRV = shader_file.get_spirv()
	shader_resource_id = rendering_device.shader_create_from_spirv(spirv_data)
	assert(shader_resource_id.is_valid(), "着色器编译失败: " + shader_path)
	pipeline_resource_id = rendering_device.compute_pipeline_create(shader_resource_id)
	assert(pipeline_resource_id.is_valid(), "管线创建失败: " + shader_path)

	# 创建采样器（最近邻，无各向异性过滤）
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_resource_id = rendering_device.sampler_create(sampler_state)
	assert(sampler_resource_id.is_valid(), "采样器创建失败: " + shader_path)


# ======================== 子类钩子 ========================

func _before_dispatch(_source_width: int, _source_height: int) -> void:
	pass

func _after_dispatch() -> void:
	pass

func _get_push_data() -> PackedByteArray:
	return PackedByteArray()

func _on_output_texture_created() -> void:
	pass

func _get_internal_extra_resource_ids() -> Array[RID]:
	return []

## 输出纹理尺寸钩子，默认与源纹理同尺寸，子类可覆盖返回自定义尺寸
func _get_output_dimensions(source_width: int, source_height: int) -> Vector2i:
	return Vector2i(source_width, source_height)

## 输出纹理格式钩子，默认继承源格式；子类可覆盖以使用不同格式
## 例如距离场 Pass 可返回 R16_SFLOAT 提升精度并节省显存
func _get_output_format(source_format: int) -> int:
	return source_format


# ======================== 自驱动执行 ========================

func _process(delta: float) -> void:
	if not pipeline_resource_id.is_valid() or not enabled:
		return

	# ---- 获取主输入 RID ----
	var primary_resource_id: RID

	# ① input_texture 优先级最高
	if not primary_resource_id.is_valid() and input_texture:
		var input_resource_id: RID = input_texture.get_rid()
		if input_resource_id.is_valid():
			primary_resource_id = RenderingServer.texture_get_rd_texture(input_resource_id, false)

	# ② 次之：source_viewport
	if not primary_resource_id.is_valid() and source_viewport:
		var viewport_texture: ViewportTexture = source_viewport.get_texture()
		if viewport_texture:
			var viewport_resource_id: RID = viewport_texture.get_rid()
			if viewport_resource_id.is_valid():
				primary_resource_id = RenderingServer.texture_get_rd_texture(viewport_resource_id, false)

	# ③ 再之：primary_input
	if not primary_resource_id.is_valid() and primary_input:
		primary_resource_id = primary_input.get_output_resource_id()

	if not primary_resource_id.is_valid():
		var parent: Node = get_parent()
		if parent:
			var node_index: int = get_index()
			for i in range(node_index - 1, -1, -1):
				var sibling: Node = parent.get_child(i)
				if sibling is ComputePass:
					if sibling.enabled:
						primary_resource_id = (sibling as ComputePass).get_output_resource_id()
						break

	if not primary_resource_id.is_valid():
		return

	# ---- 获取外部额外输入 RID ----
	# 注意：内部额外输入（如 TemporalPass 的历史纹理）在 _on_output_texture_created 之后获取，
	# 因为该回调可能重建内部纹理，提前获取会拿到已释放的旧 RID
	var extra_resource_ids: Array[RID]
	for pass_node: ComputePass in extra_input_sources:
		extra_resource_ids.append(pass_node.get_output_resource_id())

	# ---- 检查输入就绪 ----
	if not primary_resource_id.is_valid():
		return
	var all_extra_valid: bool = true
	for resource_id in extra_resource_ids:
		if not resource_id.is_valid():
			all_extra_valid = false
			break
	if not all_extra_valid:
		return

	if source_viewport:
		for pass_node in extra_input_sources:
			if pass_node and pass_node.frame_counter <= int(_last_consumed_frame.get(pass_node, -1)):
				return
	else:
		if primary_input:
			if primary_input.frame_counter <= int(_last_consumed_frame.get(primary_input, -1)):
				return
		else:
			var parent: Node = get_parent()
			if parent:
				var node_index: int = get_index()
				for i in range(node_index - 1, -1, -1):
					var sibling: Node = parent.get_child(i)
					if sibling is ComputePass:
						if (sibling as ComputePass).frame_counter <= int(_last_consumed_frame.get(sibling as ComputePass, -1)):
							return
						break

		for pass_node in extra_input_sources:
			if pass_node and pass_node.frame_counter <= int(_last_consumed_frame.get(pass_node, -1)):
				return

	# ---- 创建输出纹理 ----
	var source_format_info: RDTextureFormat = rendering_device.texture_get_format(primary_resource_id)
	var source_width: int = source_format_info.width
	var source_height: int = source_format_info.height
	var source_format: int = source_format_info.format
	var output_format: int = _get_output_format(source_format)
	var output_dimensions: Vector2i = _get_output_dimensions(source_width, source_height)

	if output_dimensions.x != _output_width or output_dimensions.y != _output_height or output_format != _output_format or not output_texture_resource_id.is_valid():
		if output_texture_resource_id.is_valid():
			rendering_device.free_rid(output_texture_resource_id)
			output_texture_resource_id = RID()
		if uniform_set_resource_id.is_valid():
			rendering_device.free_rid(uniform_set_resource_id)
			uniform_set_resource_id = RID()

		_output_width = output_dimensions.x
		_output_height = output_dimensions.y
		_output_format = output_format

		var texture_format: RDTextureFormat = RDTextureFormat.new()
		texture_format.width = _output_width
		texture_format.height = _output_height
		texture_format.format = output_format
		texture_format.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		)
		var texture_view: RDTextureView = RDTextureView.new()
		output_texture_resource_id = rendering_device.texture_create(texture_format, texture_view)
		_uniform_set_dirty = true
		_on_output_texture_created()

	_before_dispatch(source_width, source_height)

	# 在 _on_output_texture_created 之后获取内部额外输入 RID
	# （TemporalPass 的历史纹理可能在该回调中被重建）
	extra_resource_ids.append_array(_get_internal_extra_resource_ids())

	# ---- 构建 uniform set ----
	if _uniform_set_dirty or primary_resource_id != _bound_source_resource_id or extra_resource_ids != _bound_extra_resource_ids:
		if uniform_set_resource_id.is_valid():
			rendering_device.free_rid(uniform_set_resource_id)
			uniform_set_resource_id = RID()

		var uniforms: Array[RDUniform] = []

		# binding 0: 主输入（sampler2D 只读采样）
		var input_uniform: RDUniform = RDUniform.new()
		input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		input_uniform.binding = 0
		input_uniform.add_id(sampler_resource_id)
		input_uniform.add_id(primary_resource_id)
		uniforms.append(input_uniform)

		# binding 1: 输出（image2D 可写）
		var output_uniform: RDUniform = RDUniform.new()
		output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		output_uniform.binding = 1
		output_uniform.add_id(output_texture_resource_id)
		uniforms.append(output_uniform)

		# binding 2+: 额外输入（sampler2D 只读采样）
		for i in range(extra_resource_ids.size()):
			var resource_id: RID = extra_resource_ids[i]
			if not resource_id.is_valid():
				resource_id = output_texture_resource_id
			var extra_uniform: RDUniform = RDUniform.new()
			extra_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			extra_uniform.binding = 2 + i
			extra_uniform.add_id(sampler_resource_id)
			extra_uniform.add_id(resource_id)
			uniforms.append(extra_uniform)

		uniform_set_resource_id = rendering_device.uniform_set_create(uniforms, shader_resource_id, 0)
		_bound_source_resource_id = primary_resource_id
		_bound_extra_resource_ids = extra_resource_ids.duplicate()
		_uniform_set_dirty = false

	# ---- dispatch ----
	var dispatch_groups_x: int = ceili(float(_output_width) / 16.0)
	var dispatch_groups_y: int = ceili(float(_output_height) / 16.0)

	var compute_list_id: int = rendering_device.compute_list_begin()
	rendering_device.compute_list_bind_compute_pipeline(compute_list_id, pipeline_resource_id)
	rendering_device.compute_list_bind_uniform_set(compute_list_id, uniform_set_resource_id, 0)

	var push_constant_data: PackedByteArray = _get_push_data()
	if push_constant_data.size() > 0:
		rendering_device.compute_list_set_push_constant(compute_list_id, push_constant_data, push_constant_data.size())

	rendering_device.compute_list_dispatch(compute_list_id, maxi(1, int(dispatch_groups_x)), maxi(1, int(dispatch_groups_y)), 1)
	rendering_device.compute_list_end()

	# ---- 输出结果 ----
	display_texture.texture_rd_rid = output_texture_resource_id

	# ---- 标记消费/递增帧 ----
	if not source_viewport:
		if primary_input:
			_last_consumed_frame[primary_input] = primary_input.frame_counter
		else:
			var parent: Node = get_parent()
			if parent:
				var node_index: int = get_index()
				for i in range(node_index - 1, -1, -1):
					var sibling: Node = parent.get_child(i)
					if sibling is ComputePass:
						_last_consumed_frame[sibling as ComputePass] = (sibling as ComputePass).frame_counter
						break
	for pass_node in extra_input_sources:
		if pass_node:
			_last_consumed_frame[pass_node] = pass_node.frame_counter

	frame_counter += 1
	_after_dispatch()


# ======================== 公开接口 ========================

func get_output_resource_id() -> RID:
	return output_texture_resource_id


func _exit_tree() -> void:
	display_texture.texture_rd_rid = RID()
	if uniform_set_resource_id.is_valid():
		rendering_device.free_rid(uniform_set_resource_id)
		uniform_set_resource_id = RID()
	if output_texture_resource_id.is_valid():
		rendering_device.free_rid(output_texture_resource_id)
		output_texture_resource_id = RID()
	if _storage_copy_resource_id.is_valid():
		rendering_device.free_rid(_storage_copy_resource_id)
		_storage_copy_resource_id = RID()

	if pipeline_resource_id.is_valid():
		rendering_device.free_rid(pipeline_resource_id)
		pipeline_resource_id = RID()
	if shader_resource_id.is_valid():
		rendering_device.free_rid(shader_resource_id)
		shader_resource_id = RID()
	if sampler_resource_id.is_valid():
		rendering_device.free_rid(sampler_resource_id)
		sampler_resource_id = RID()
