## 时间累积 Pass — 帧间指数移动平均，等效数千采样

extends ComputePass
class_name TemporalPass

## 当前帧混合权重（越低越平滑但延迟越大）
@export var temporal_blend_factor: float = 0.1

var _history_texture: RID
var _history_valid: bool = false

func _init() -> void:
	shader_path = "res://experiments/gi/temporal.glsl"

func _ready() -> void:
	super._ready()
	# 先创建 1×1 占位历史纹理，确保 _get_internal_extra_resource_ids 总是返回有效 RID
	# 避免 _inputs_ready 因历史纹理无效而阻止 _process 执行
	_create_history_texture(1, 1, RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(4)
	# 首帧 blend=1.0（直接用当前帧），之后用设定值
	var blend_factor: float = 1.0 if not _history_valid else temporal_blend_factor
	push_constant_data.encode_float(0, blend_factor)
	return push_constant_data


## 创建/重建历史纹理
func _create_history_texture(width: int, height: int, data_format: RenderingDevice.DataFormat) -> void:
	if _history_texture.is_valid():
		rendering_device.free_rid(_history_texture)
		_history_texture = RID()

	var texture_format: RDTextureFormat = RDTextureFormat.new()
	texture_format.width = width
	texture_format.height = height
	texture_format.format = data_format
	texture_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	var texture_view: RDTextureView = RDTextureView.new()
	_history_texture = rendering_device.texture_create(texture_format, texture_view)
	_history_valid = false


## 输出纹理创建时，同步重建历史纹理（使用正确的尺寸）
func _on_output_texture_created() -> void:
	_create_history_texture(_output_width, _output_height, _output_format)


## 历史纹理作为内部额外输入（binding 2）
## 始终返回单元素数组，保证 uniform set binding 2 始终存在
func _get_internal_extra_resource_ids() -> Array[RID]:
	return [_history_texture]


## dispatch 后将输出复制到历史纹理供下一帧使用
func _after_dispatch() -> void:
	if _history_texture.is_valid() and output_texture_resource_id.is_valid():
		rendering_device.texture_copy(
			output_texture_resource_id, _history_texture,
			Vector3.ZERO, Vector3.ZERO,
			Vector3(_output_width, _output_height, 1),
			0, 0, 0, 0
		)
		_history_valid = true


func _exit_tree() -> void:
	if _history_texture.is_valid():
		rendering_device.free_rid(_history_texture)
		_history_texture = RID()
	super._exit_tree()
