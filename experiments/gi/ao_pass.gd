## 环境光遮蔽 Pass — 距离场引导采样计算遮挡因子

extends ComputePass
class_name AOPass

## 每像素采样点数（接入 Temporal 后可降至 8）
@export var ao_num_samples: int = 8
## 采样半径（归一化 0-1）
@export var ao_radius: float = 0.05
## 遮蔽强度系数（越大越暗）
@export var ao_intensity: float = 1.0
## 遮蔽衰减指数
@export var ao_falloff: float = 1.0
## 高度偏移，防止自遮挡
@export var ao_bias: float = 0.01
## 距离场引导权重（0=纯黄金角度, 1=纯距离场引导）
@export var ao_df_guide_weight: float = 0.5


func _init() -> void:
	shader_path = "res://experiments/gi/ao_pass.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(24)
	push_constant_data.encode_s32(0, ao_num_samples)
	push_constant_data.encode_float(4, ao_radius)
	push_constant_data.encode_float(8, ao_intensity)
	push_constant_data.encode_float(12, ao_falloff)
	push_constant_data.encode_float(16, ao_bias)
	push_constant_data.encode_float(20, ao_df_guide_weight)
	return push_constant_data