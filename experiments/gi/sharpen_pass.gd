## 锐化 Pass — Unsharp Mask，补偿降噪后的模糊

extends ComputePass
class_name SharpenPass

## 锐化强度（越大越锐利，建议 0.3-1.0）
@export var sharpen_strength: float = 0.5
## 模糊半径（像素，越大影响范围越广）
@export var sharpen_blur_radius: int = 2
## 高斯标准差
@export var sharpen_sigma: float = 2.0

func _init() -> void:
	shader_path = "res://experiments/gi/sharpen.glsl"

func _get_push_data() -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(16)
	data.encode_float(0, sharpen_strength)
	data.encode_s32(4, sharpen_blur_radius)
	data.encode_float(8, sharpen_sigma)
	data.encode_s32(12, 0)
	return data
