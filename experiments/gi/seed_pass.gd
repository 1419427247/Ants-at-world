## UV 种子 Pass — 非透明像素写入自身 UV 坐标

extends ComputePass
class_name SeedPass

func _init() -> void:
	shader_path = "res://experiments/gi/seed.glsl"
