## 间接光照 Pass — 多跳间接光照（2-bounce GI）
##
## 输入：source_viewport（场景纹理）+ PassRM（障碍物颜色作为反弹光源）+ 距离场
## 对空区像素追踪次级光线，命中障碍物时从 PassRM 读取颜色作为反弹光源
## 输出：纯间接光照（不含直接光），由 Composite 合成

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
@export var indirect_emissive_threshold: float = 0.01
## 步进安全系数
@export var indirect_step_safety: float = 0.8
## 间接光强度倍数
@export var indirect_strength: float = 0.5
## 射线初始旋转偏移（弧度）
@export var indirect_rotation_offset: float = 0.0
## 旋转速度（弧度/秒），视觉暂留效果
@export var indirect_rotation_speed: float = 0.0
## 逐像素随机角度偏移强度（0~1），消除对齐条纹
@export var indirect_noise_strength: float = 0.5


func _init() -> void:
	shader_path = "res://experiments/gi/indirect_pass.glsl"


func _process(delta: float) -> void:
	indirect_rotation_offset += indirect_rotation_speed * delta
	super._process(delta)


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(36)
	push_constant_data.encode_s32(0, indirect_num_samples)
	push_constant_data.encode_float(4, indirect_attenuation)
	push_constant_data.encode_float(8, indirect_max_distance)
	push_constant_data.encode_s32(12, indirect_max_steps)
	push_constant_data.encode_float(16, indirect_emissive_threshold)
	push_constant_data.encode_float(20, indirect_step_safety)
	push_constant_data.encode_float(24, indirect_strength)
	push_constant_data.encode_float(28, indirect_rotation_offset)
	push_constant_data.encode_float(32, indirect_noise_strength)
	return push_constant_data
