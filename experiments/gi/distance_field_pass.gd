## 距离场 Pass — 有向距离场
## 输出 RGBA16F：R=到最近异质点距离, GB=最近异质点 UV, A=1
extends ComputePass
class_name DistanceFieldPass


func _init() -> void:
	shader_path = "res://experiments/gi/distance_field.glsl"


## 输出 RGBA16F：R=距离, GB=指向最近异质点的方向向量, A=1
func _get_output_format(_source_format: int) -> int:
	return RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
