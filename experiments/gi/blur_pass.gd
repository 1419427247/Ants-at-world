## 通道模糊 Pass — 对指定通道执行可分离高斯模糊

extends ComputePass
class_name BlurPass

## 模糊核半径（像素）
@export var blur_radius: int = 4
## 高斯标准差
@export var blur_sigma: float = 3.0
## 是否模糊 R 通道
@export var blur_r: bool = true
## 是否模糊 G 通道
@export var blur_g: bool = true
## 是否模糊 B 通道
@export var blur_b: bool = true
## 是否模糊 A 通道
@export var blur_a: bool = false
## 模糊方向：0=水平, 1=垂直
@export var blur_direction: int = 0


func _init() -> void:
	shader_path = "res://experiments/gi/blur.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(16)

	# 通道掩码：bit 0=R, bit 1=G, bit 2=B, bit 3=A
	var channel_mask: int = 0
	if blur_r: channel_mask |= 1
	if blur_g: channel_mask |= 2
	if blur_b: channel_mask |= 4
	if blur_a: channel_mask |= 8

	push_constant_data.encode_s32(0, blur_radius)
	push_constant_data.encode_float(4, blur_sigma)
	push_constant_data.encode_s32(8, channel_mask)
	push_constant_data.encode_s32(12, blur_direction)
	return push_constant_data
