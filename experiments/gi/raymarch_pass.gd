## 光线投射 Pass — 利用距离场步进采样发光体（直接光照 + 多次反弹漫反射）
## 当光线遇到非发光障碍物时，根据法线图反射方向并混合障碍物漫反射颜色，
## 实现间接光弹射效果。需要 PassNormal 作为 extra_input。

extends ComputePass
class_name RaymarchPass

## 每像素光线数（时间累积会大幅补偿低采样）
@export var raymarch_num_samples: int = 32
## 衰减系数
@export var raymarch_attenuation: float = 3.0
## 最大搜索距离（归一化 0-1）
@export var raymarch_max_distance: float = 0.8
## 每段步进最大步数
@export var raymarch_max_steps: int = 32
## 发光阈值（任意通道 > 此值视为发光体，纯白=1.0，HDR 可更大）
@export var raymarch_emissive_threshold: float = 1
## 步进安全系数（<1.0 防止步进越过薄壁导致漏光）
@export var raymarch_step_safety: float = 0.8
## 逐像素随机角度偏移强度（0~1）。每个像素用 IGN 蓝噪声生成不同的随机值，
## 乘以此参数后加到光线角度上，消除对齐条纹/摩尔纹。
## 0=无噪点（光线对齐），1=全随机（最大分散），推荐 0.5~1.0。
@export var raymarch_noise_strength: float = 0.5
## 最大反弹次数。光线命中非发光障碍物时，根据法线图反射继续步进。
## 0=无反弹（即原先的直接光照行为），>0 可收集间接漫反射。
## 每次反弹按 bounce_attenuation 衰减强度，推荐 1~2，过高会导致性能开销增大。
@export var raymarch_max_bounces: int = 0
## 每次反弹的强度衰减系数（0-1）。0.5=每次反弹亮度减半。
@export var raymarch_bounce_attenuation: float = 0.5

var _frame_index: int = 0


func _init() -> void:
	shader_path = "res://experiments/gi/raymarch.glsl"

func _process(delta: float) -> void:
	_frame_index += 1
	super._process(delta)

func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(40)
	push_constant_data.encode_s32(0, raymarch_num_samples)
	push_constant_data.encode_float(4, raymarch_attenuation)
	push_constant_data.encode_float(8, raymarch_max_distance)
	push_constant_data.encode_s32(12, raymarch_max_steps)
	push_constant_data.encode_float(16, raymarch_emissive_threshold)
	push_constant_data.encode_float(20, raymarch_step_safety)
	push_constant_data.encode_float(24, raymarch_noise_strength)
	push_constant_data.encode_s32(28, raymarch_max_bounces)
	push_constant_data.encode_float(32, raymarch_bounce_attenuation)
	push_constant_data.encode_s32(36, _frame_index)
	return push_constant_data
