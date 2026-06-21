## 光线投射 Pass — 利用距离场步进采样发光体（直接光照）

extends ComputePass
class_name RaymarchPass

## 每像素光线数（时间累积会大幅补偿低采样）
@export var raymarch_num_samples: int = 8
## 衰减系数
@export var raymarch_attenuation: float = 3.0
## 最大搜索距离（归一化 0-1）
@export var raymarch_max_distance: float = 0.8
## 最大步进次数
@export var raymarch_max_steps: int = 32
## 发光阈值（任意通道 >= 此值视为发光体，纯白=1.0，HDR 可更大）
@export var raymarch_emissive_threshold: float = 1.0
## 步进安全系数（<1.0 防止步进越过薄壁导致漏光）
@export var raymarch_step_safety: float = 0.8


func _init() -> void:
	shader_path = "res://experiments/gi/raymarch.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(28)
	push_constant_data.encode_s32(0, raymarch_num_samples)
	push_constant_data.encode_float(4, raymarch_attenuation)
	push_constant_data.encode_float(8, raymarch_max_distance)
	push_constant_data.encode_s32(12, raymarch_max_steps)
	push_constant_data.encode_float(16, raymarch_emissive_threshold)
	push_constant_data.encode_float(20, raymarch_step_safety)
	push_constant_data.encode_float(24, input_scale)
	return push_constant_data
