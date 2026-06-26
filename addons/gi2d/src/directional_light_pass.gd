## 平行光 Pass — 沿固定方向投射平行光（带高度场阴影 + PCF 柔化）

extends ComputePass
class_name DirectionalLightPass

## 平行光方向（2D 归一化方向，光传播方向，如 vec2(-1, 0) = 从右照来）
@export var light_direction: Vector2 = Vector2(-1.0, 0.0)
## 平行光高度（类似太阳仰角，越高越不容易被遮挡）
@export var light_height: float = 32.0
## 最大搜索距离（世界单位）
@export var light_max_distance: float = 1500.0
## 步进安全系数
@export var light_step_safety: float = 0.8
## 最大步进次数
@export var light_max_steps: int = 32
## PCF 沿光源垂直方向抖动静样次数（1=关闭，越大阴影越柔和但越慢）
@export var light_pcf_samples: int = 2


func _init() -> void:
	shader_path = "res://addons/gi2d/shaders/directional_light_pass.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = _get_fragment_info_prefix()
	push_constant_data.resize(36)
	var dir := light_direction.normalized()
	push_constant_data.encode_float(8, dir.x)
	push_constant_data.encode_float(12, dir.y)
	push_constant_data.encode_float(16, light_height)
	push_constant_data.encode_float(20, light_max_distance)
	push_constant_data.encode_float(24, light_step_safety)
	push_constant_data.encode_s32(28, light_max_steps)
	push_constant_data.encode_s32(32, light_pcf_samples)
	return push_constant_data
