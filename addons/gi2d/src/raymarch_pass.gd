## 光线投射 Pass — 利用距离场步进采样发光体（直接光照）
## 遇到发光体时收集光照，遇到非发光障碍物时终止。

extends ComputePass
class_name RaymarchPass

## 每像素光线数（时间累积会大幅补偿低采样）
@export var raymarch_num_samples: int = 32
## 衰减系数
@export var raymarch_attenuation: float = 3.0
## 最大搜索距离（世界单位，乘以 world_to_uv 转为 UV）
@export var raymarch_max_distance: float = 1500.0
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

var _frame_index: int = 0


func _init() -> void:
	shader_path = "res://addons/gi2d/shaders/raymarch.glsl"

func _process(delta: float) -> void:
	_frame_index += 1
	super(delta)

func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = _get_fragment_info_prefix()
	push_constant_data.resize(40)
	push_constant_data.encode_s32(8, raymarch_num_samples)
	push_constant_data.encode_float(12, raymarch_attenuation)
	push_constant_data.encode_float(16, raymarch_max_distance)
	push_constant_data.encode_s32(20, raymarch_max_steps)
	push_constant_data.encode_float(24, raymarch_emissive_threshold)
	push_constant_data.encode_float(28, raymarch_step_safety)
	push_constant_data.encode_float(32, raymarch_noise_strength)
	push_constant_data.encode_s32(36, _frame_index)
	return push_constant_data
