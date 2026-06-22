## 纹理缩放 Pass — 将输入纹理缩放到指定尺寸（双线性/bicubic 插值）
extends ComputePass
class_name ScalePass

## 目标宽度（0=保持源尺寸）
@export var scale_target_width: int = 0
## 目标高度（0=保持源尺寸）
@export var scale_target_height: int = 0
## 插值模式：0=双线性（下采样友好），1=bicubic（上采样更锐利，保留 GI 边缘）
@export var scale_mode: int = 0

func _init() -> void:
	shader_path = "res://experiments/gi/scale.glsl"

func _get_output_dimensions(source_width: int, source_height: int) -> Vector2i:
	var target_width: int = scale_target_width if scale_target_width > 0 else source_width
	var target_height: int = scale_target_height if scale_target_height > 0 else source_height
	return Vector2i(target_width, target_height)

func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(4)
	push_constant_data.encode_s32(0, scale_mode)
	return push_constant_data
