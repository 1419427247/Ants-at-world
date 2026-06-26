## UV 种子 Pass — 固体像素写入自身 UV 到 RG，空区像素写入自身 UV 到 BA
## 形态学腐蚀：障碍物/光源整体内缩，使距离场从物体内部开始计算

extends ComputePass
class_name SeedPass

## 腐蚀半径（像素单位，1=3×3 核内缩1圈）
@export var seed_erosion_radius: int = 1

func _init() -> void:
	shader_path = "res://addons/gi2d/shaders/seed.glsl"


func _get_push_data() -> PackedByteArray:
	var push_constant_data: PackedByteArray = PackedByteArray()
	push_constant_data.resize(4)
	push_constant_data.encode_s32(0, seed_erosion_radius)
	return push_constant_data


## 输出 RGBA16F：RG=最近固体UV, BA=最近空区UV
func _get_output_format(_source_format: int) -> int:
	return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
