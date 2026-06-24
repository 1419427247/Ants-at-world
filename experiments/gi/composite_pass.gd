## 合成 Pass — 将间接光、平行光、AO 合并为最终光照结果

extends ComputePass
class_name CompositePass

## 间接光强度
@export var composite_indirect_strength: float = 1.0
## 平行光颜色
@export var composite_dir_color: Color = Color(1.0, 1.0, 1.0)
## 阴影颜色
@export var composite_shadow_color: Color = Color(0.0, 0.0, 0.0)
## AO 强度（0=禁用, 1=完全遮蔽）
@export var composite_ao_strength: float = 1.0


func _init() -> void:
	shader_path = "res://experiments/gi/composite_pass.glsl"

func _ready() -> void:
	super()
	source_viewport = get_viewport()

func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(48)
	push_constant_data.encode_float(0, composite_indirect_strength)
	push_constant_data.encode_float(4, composite_ao_strength)
	push_constant_data.encode_float(16, composite_dir_color.r)
	push_constant_data.encode_float(20, composite_dir_color.g)
	push_constant_data.encode_float(24, composite_dir_color.b)
	push_constant_data.encode_float(28, composite_dir_color.a)
	push_constant_data.encode_float(32, composite_shadow_color.r)
	push_constant_data.encode_float(36, composite_shadow_color.g)
	push_constant_data.encode_float(40, composite_shadow_color.b)
	push_constant_data.encode_float(44, composite_shadow_color.a)
	return push_constant_data
