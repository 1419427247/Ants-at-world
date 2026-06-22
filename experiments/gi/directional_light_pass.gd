## 平行光 Pass — 沿固定方向投射平行光（带高度场阴影）

extends ComputePass
class_name DirectionalLightPass

## 平行光方向（2D 归一化方向，光传播方向，如 vec2(-1, 0) = 从右照来）
@export var light_direction: Vector2 = Vector2(-1.0, 0.0)
## 平行光高度（类似太阳仰角，越高越不容易被遮挡）
@export var light_height: float = 5.0
## 亮度（R 通道明暗值，单通道灰度平行光）
@export var light_brightness: float = 1.0
## 最大搜索距离（归一化 0-1）
@export var light_max_distance: float = 0.8
## 步进安全系数
@export var light_step_safety: float = 0.8
## 最大步进次数
@export var light_max_steps: int = 32


func _init() -> void:
	shader_path = "res://experiments/gi/directional_light_pass.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(24)
	var dir := light_direction.normalized()
	push_constant_data.encode_float(0, dir.x)
	push_constant_data.encode_float(4, dir.y)
	push_constant_data.encode_float(8, light_height)
	push_constant_data.encode_float(12, light_max_distance)
	push_constant_data.encode_float(16, light_step_safety)
	push_constant_data.encode_s32(20, light_max_steps)
	return push_constant_data
