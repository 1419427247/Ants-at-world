## 自定义纹理类 — 从 ComputePass 输出 RID 创建 Texture2D

class_name TextureFromPass extends TextureRect

@export var compute_pass: ComputePass

func _ready() -> void:
	texture = Texture2DRD.new()

func _process(delta: float) -> void:
	texture.texture_rd_rid = compute_pass.get_output_resource_id()
