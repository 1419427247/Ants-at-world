## 向鼠标位置自动移动的小球
extends Sprite2D
class_name MouseBall

## 移动速度系数（越大跟随越快；值 3~8）
@export var follow_speed: float = 5.0
## 小球半径（像素）
@export var ball_radius: float = 8.0
## 小球颜色
@export var ball_color: Color = Color(0.3, 0.7, 1.0, 1.0)

var _target_pos: Vector2

func _ready() -> void:
	_target_pos = position

func _process(delta: float) -> void:
	_target_pos = get_global_mouse_position()
	global_position = global_position.lerp(_target_pos, minf(1.0, delta * follow_speed))
