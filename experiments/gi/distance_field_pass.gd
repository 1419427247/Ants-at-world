## 距离场 Pass — 从 Voronoi 结果计算到最近表面的距离

extends ComputePass
class_name DistanceFieldPass


func _init() -> void:
	shader_path = "res://experiments/gi/distance_field.glsl"
