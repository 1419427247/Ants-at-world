## UV 种子 Pass — 固体像素写入自身 UV 到 RG，空区像素写入自身 UV 到 BA
extends ComputePass
class_name SeedPass

func _init() -> void:
	shader_path = "res://experiments/gi/seed.glsl"


## 输出 RGBA16F：RG=最近固体UV, BA=最近空区UV
func _get_output_format(_source_format: int) -> int:
	return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
