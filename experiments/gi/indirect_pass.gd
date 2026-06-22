## 间接光照 Pass — 多跳间接光照（2-bounce GI）
##
## 输入：直接光照结果（RaymarchPass）+ 场景纹理 + 距离场
## 对每个被照亮的非发光像素，追踪次级光线收集间接光

extends ComputePass
class_name IndirectPass

## 每像素次级光线数
@export var indirect_num_samples: int = 4
## 间接光衰减系数
@export var indirect_attenuation: float = 5.0
## 最大搜索距离（归一化）
@export var indirect_max_distance: float = 0.5
## 最大步进次数
@export var indirect_max_steps: int = 24
## 发光阈值
@export var indirect_emissive_threshold: float = 1.0
## 步进安全系数
@export var indirect_step_safety: float = 0.8
## 间接光强度倍数
@export var indirect_strength: float = 0.5


func _init() -> void:
	shader_path = "res://experiments/gi/indirect_pass.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(28)
	push_constant_data.encode_s32(0, indirect_num_samples)
	push_constant_data.encode_float(4, indirect_attenuation)
	push_constant_data.encode_float(8, indirect_max_distance)
	push_constant_data.encode_s32(12, indirect_max_steps)
	push_constant_data.encode_float(16, indirect_emissive_threshold)
	push_constant_data.encode_float(20, indirect_step_safety)
	push_constant_data.encode_float(24, indirect_strength)
	return push_constant_data
