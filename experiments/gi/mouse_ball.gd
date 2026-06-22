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
	_create_circle_texture()
	_target_pos = position


func _create_circle_texture() -> void:
	var diameter: int = int(ball_radius * 2.0 + 2.0)
	var img: Image = Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = ball_radius + 1.0
	var cy: float = ball_radius + 1.0
	var r_sq: float = ball_radius * ball_radius

	for y in range(diameter):
		for x in range(diameter):
			var dx: float = float(x) + 0.5 - cx
			var dy: float = float(y) + 0.5 - cy
			var d_sq: float = dx * dx + dy * dy
			if d_sq <= r_sq:
				var d: float = sqrt(d_sq)
				# 1px 平滑边缘
				var alpha: float = 1.0
				if d > ball_radius - 1.0:
					alpha = ball_radius - d
				img.set_pixel(x, y, Color(ball_color.r, ball_color.g, ball_color.b, alpha))

	texture = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	var vp_sub: SubViewport = get_parent() as SubViewport
	if not vp_sub:
		return

	var container: SubViewportContainer = vp_sub.get_parent() as SubViewportContainer
	if not container or container.size.x <= 0 or container.size.y <= 0:
		return

	# 鼠标在容器上的局部坐标 → 映射到 SubViewport 坐标系
	var mouse_local: Vector2 = container.get_local_mouse_position()
	var mapped_pos: Vector2 = Vector2(
		mouse_local.x / container.size.x * vp_sub.size.x,
		mouse_local.y / container.size.y * vp_sub.size.y
	)

	_target_pos = mapped_pos

	# 帧率无关的平滑插值跟随
	position = position.lerp(_target_pos, minf(1.0, delta * follow_speed))
