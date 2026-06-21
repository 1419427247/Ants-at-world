## 空间降噪 Pass — 双边滤波，平滑噪声保留边缘

extends ComputePass
class_name DenoisePass

## 滤波核半径（像素）
@export var denoise_radius: int = 3
## 空间高斯标准差
@export var denoise_spatial_sigma: float = 2.0
## 颜色双边标准差（越小越保边）
@export var denoise_color_sigma: float = 0.15


func _init() -> void:
	shader_path = "res://experiments/gi/denoise.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(12)
	push_constant_data.encode_s32(0, denoise_radius)
	push_constant_data.encode_float(4, denoise_spatial_sigma)
	push_constant_data.encode_float(8, denoise_color_sigma)
	return push_constant_data
