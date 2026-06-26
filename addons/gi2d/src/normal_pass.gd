## 法线图生成 Pass — 从场景纹理 Alpha 计算障碍物表面法线
##
## 原理：利用 Alpha 通道表示的表面高度，通过 Sobel 算子计算高度梯度，
## 梯度方向 → 高度场法线方向。alpha=0 的空区法线指向正面（0,0,1）。

extends ComputePass
class_name NormalPass

## Sobel 采样半径（1=3×3, 2=5×5，越大法线越平滑）
@export var normal_blur_radius: int = 1

func _init() -> void:
	shader_path = "res://addons/gi2d/shaders/normal_pass.glsl"

func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(4)
	push_constant_data.encode_s32(0, normal_blur_radius)
	return push_constant_data
