## A-Trous 小波滤波 Pass — 可分离 1D 双边滤波
## H+V 两遍串联等效 2D 滤波，采样从 25 次/pass 降至 5 次/pass（2.5× 加速）
## 3 级（step=1,2,4）× 2 方向 = 6 pass，等效覆盖半径 8 像素

extends ComputePass
class_name ATrousPass

## 采样间隔（1=第一遍，2=第二遍，4=第三遍）
@export var atrous_step_size: int = 1
## 滤波方向（0=水平, 1=垂直）
@export var atrous_direction: int = 0
## 颜色双边标准差（越小越保边）
@export var atrous_color_sigma: float = 0.2
## 深度双边标准差（越小越保边；基于距离场）
@export var atrous_depth_sigma: float = 0.05


func _init() -> void:
	shader_path = "res://addons/gi2d/shaders/atrous.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(16)
	push_constant_data.encode_s32(0, atrous_step_size)
	push_constant_data.encode_s32(4, atrous_direction)
	push_constant_data.encode_float(8, atrous_color_sigma)
	push_constant_data.encode_float(12, atrous_depth_sigma)
	return push_constant_data
