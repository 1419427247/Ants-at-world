## 锐化 Pass — 可分离 Unsharp Mask
## H+V 两遍串联等效 2D 卷积，采样从 (2r+1)² 降至 2×(2r+1)
## V pass 需要 extra_input_sources 指向原始输入（H pass 之前的 pass）

extends ComputePass
class_name SharpenPass

## 锐化强度（越大越锐利，建议 0.3-1.0，仅 V pass 使用）
@export var sharpen_strength: float = 0.5
## 模糊半径（像素，越大影响范围越广）
@export var sharpen_blur_radius: int = 2
## 高斯标准差
@export var sharpen_sigma: float = 2.0
## 滤波方向（0=水平模糊, 1=垂直模糊+Unsharp）
@export var sharpen_direction: int = 0

func _init() -> void:
	shader_path = "res://experiments/gi/sharpen.glsl"

func _get_push_data() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(16)
	data.encode_float(0, sharpen_strength)
	data.encode_s32(4, sharpen_blur_radius)
	data.encode_float(8, sharpen_sigma)
	data.encode_s32(12, sharpen_direction)
	return data
