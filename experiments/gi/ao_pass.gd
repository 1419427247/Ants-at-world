## 环境光遮蔽 Pass — 标准 2D SSAO + SDF 直接估算

extends ComputePass
class_name AOPass

## 每像素采样方向数（接入 Temporal 后可降至 8）
@export var ao_num_samples: int = 8
## 采样半径（UV 空间，0-1）
@export var ao_radius: float = 0.05
## 遮蔽强度系数（越大越暗）
@export var ao_intensity: float = 0.5
## SDF 直接估算的缩放系数（越大 AO 衰减越快，推荐 30-80）
@export var ao_sdf_scale: float = 50.0


func _init() -> void:
	shader_path = "res://experiments/gi/ao_pass.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(16)
	push_constant_data.encode_s32(0, ao_num_samples)
	push_constant_data.encode_float(4, ao_radius)
	push_constant_data.encode_float(8, ao_intensity)
	push_constant_data.encode_float(12, ao_sdf_scale)
	return push_constant_data
