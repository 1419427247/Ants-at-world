## 跳洪泛洪 Pass — 3×3 邻域查找最近种子 UV

extends ComputePass
class_name JumpFloodPass

## 步长除数（自动计算 step = max(1, size / divisor)）
@export var jump_flood_step_divisor: int = 0

## 是否使用方形步长（true 时 step_x = step_y，避免各向异性条纹）
@export var use_square_step: bool = true

var _step_x: int = 0
var _step_y: int = 0


func _init() -> void:
	shader_path = "res://experiments/gi/jump_flood.glsl"


func _before_dispatch(source_width: int, source_height: int) -> void:
	if jump_flood_step_divisor > 0:
		_step_x = maxi(1, int(source_width / jump_flood_step_divisor))
		_step_y = maxi(1, int(source_height / jump_flood_step_divisor))
		if use_square_step:
			var square_step = maxi(_step_x, _step_y)
			_step_x = square_step
			_step_y = square_step


func _get_push_data() -> PackedByteArray:
	if _step_x > 0 or _step_y > 0:
		return PackedInt32Array([_step_x, _step_y]).to_byte_array()
	return PackedByteArray()
