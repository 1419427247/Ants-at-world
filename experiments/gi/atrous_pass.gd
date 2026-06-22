## A-Trous 小波滤波 Pass — 多 pass 渐进式双边滤波
## 每个 pass 用固定 5x5 核，采样间隔按 2 的幂次递增
## 3 个 pass（step=1, 2, 4）即可覆盖半径 8 像素，效率远高于单次大核双边滤波

extends ComputePass
class_name ATrousPass

## 采样间隔（1=第一遍，2=第二遍，4=第三遍）
@export var atrous_step_size: int = 1
## 颜色双边标准差（越小越保边）
@export var atrous_color_sigma: float = 0.2
## 深度双边标准差（越小越保边；基于距离场）
@export var atrous_depth_sigma: float = 0.05


func _init() -> void:
	shader_path = "res://experiments/gi/atrous.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(12)
	push_constant_data.encode_s32(0, atrous_step_size)
	push_constant_data.encode_float(4, atrous_color_sigma)
	push_constant_data.encode_float(8, atrous_depth_sigma)
	return push_constant_data
