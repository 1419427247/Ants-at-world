extends Node

## Godot 原版 2D 光照演示场景
## 与 GI Demo 对比：使用 Godot 内置 Light2D + LightOccluder2D + CanvasModulate
## 左键生成发光球，右键生成大白球，R 重置，空格随机生成，S 切换阴影

const WALL_COLOR := Color(0.35, 0.35, 0.45)
const PLATFORM_COLOR := Color(0.45, 0.45, 0.55)
const BALL_COLORS: Array[Color] = [
	Color(2.5, 0.3, 0.3),    # 霓虹红
	Color(0.3, 2.5, 0.3),    # 霓虹绿
	Color(0.3, 0.3, 2.5),    # 霓虹蓝
	Color(2.5, 2.5, 0.3),    # 霓虹黄
	Color(2.5, 0.3, 2.5),    # 霓虹品红
	Color(0.3, 2.5, 2.5),    # 霓虹青
	Color(2.5, 1.5, 0.3),    # 橙色
	Color(1.5, 0.3, 2.5),    # 紫色
]

@export var max_balls: int = 25
@export var ball_radius: float = 14.0
@export var light_texture: Texture2D

var _ball_count: int = 0
var _color_index: int = 0
var _shadows_enabled: bool = true

@onready var _camera: Camera2D = $Camera2D
@onready var _arena: Node2D = $Arena
@onready var _balls: Node2D = $Balls
@onready var _dir_light: DirectionalLight2D = $DirectionalLight2D


func _ready() -> void:
	_build_arena()
	_spawn_initial_balls()


func _create_radial_texture() -> Texture2D:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size * 0.5
	for y in size:
		for x in size:
			var dx := float(x) - center
			var dy := float(y) - center
			var dist := sqrt(dx * dx + dy * dy) / center
			var alpha = clamp(1.0 - dist, 0.0, 1.0)
			alpha = alpha * alpha * alpha  # 三次衰减，模拟点光源
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


# === Arena 构建 ===

func _build_arena() -> void:
	_add_box(Vector2(960, 1000), Vector2(1600, 30), WALL_COLOR)   # 地板
	_add_box(Vector2(960, 100), Vector2(1600, 30), WALL_COLOR)    # 天花板
	_add_box(Vector2(150, 550), Vector2(30, 900), WALL_COLOR)     # 左墙
	_add_box(Vector2(1770, 550), Vector2(30, 900), WALL_COLOR)    # 右墙
	_add_box(Vector2(550, 780), Vector2(300, 18), PLATFORM_COLOR)
	_add_box(Vector2(1370, 680), Vector2(300, 18), PLATFORM_COLOR)
	_add_box(Vector2(960, 480), Vector2(250, 18), PLATFORM_COLOR)
	_add_box(Vector2(380, 620), Vector2(180, 18), PLATFORM_COLOR)
	_add_box(Vector2(1550, 820), Vector2(180, 18), PLATFORM_COLOR)
	_add_box(Vector2(700, 880), Vector2(40, 200), PLATFORM_COLOR)
	_add_box(Vector2(1220, 880), Vector2(40, 200), PLATFORM_COLOR)


func _add_box(pos: Vector2, size: Vector2, color: Color) -> void:
	var body := StaticBody2D.new()
	body.position = pos

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	# 可见多边形
	var half := size * 0.5
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	poly.color = color
	body.add_child(poly)

	# 光照遮挡器（投射阴影）
	var occ := LightOccluder2D.new()
	var occ_poly := OccluderPolygon2D.new()
	occ_poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	occ_poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	occ.occluder = occ_poly
	body.add_child(occ)

	_arena.add_child(body)


# === 球体生成 ===

func _spawn_initial_balls() -> void:
	var positions := [
		Vector2(500, 200), Vector2(700, 150), Vector2(960, 200),
		Vector2(1200, 150), Vector2(1400, 200),
		Vector2(800, 300), Vector2(1100, 300),
	]
	for pos in positions:
		spawn_ball(pos)


func spawn_ball(pos: Vector2, radius: float = -1.0, color: Color = Color()) -> void:
	if _ball_count >= max_balls:
		var oldest := _balls.get_child(0)
		if oldest:
			oldest.queue_free()
			_ball_count -= 1

	if radius < 0:
		radius = ball_radius
	if color == Color():
		color = BALL_COLORS[_color_index % BALL_COLORS.size()]
		_color_index += 1

	var body := RigidBody2D.new()
	body.position = pos
	body.gravity_scale = 1.0

	var mat := PhysicsMaterial.new()
	mat.bounce = 0.65
	mat.friction = 0.1
	body.physics_material_override = mat

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)

	# 可见圆形
	var circle_poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var seg := 20
	for i in seg:
		var a := i * TAU / seg
		pts.append(Vector2(cos(a), sin(a)) * radius)
	circle_poly.polygon = pts
	circle_poly.color = color
	body.add_child(circle_poly)

	# 点光源
	var light := PointLight2D.new()
	light.texture = light_texture
	light.color = color
	light.texture_scale = 8
	light.shadow_enabled = _shadows_enabled
	light.energy = 0.25
	body.add_child(light)

	_balls.add_child(body)
	_ball_count += 1


func reset_balls() -> void:
	for child in _balls.get_children():
		child.queue_free()
	_ball_count = 0
	_color_index = 0
	_spawn_initial_balls()


func _toggle_shadows() -> void:
	_shadows_enabled = not _shadows_enabled
	_dir_light.shadow_enabled = _shadows_enabled
	for ball in _balls.get_children():
		for child in ball.get_children():
			if child is PointLight2D:
				child.shadow_enabled = _shadows_enabled


# === 输入 ===

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				spawn_ball(_camera.get_global_mouse_position())
			MOUSE_BUTTON_RIGHT:
				spawn_ball(_camera.get_global_mouse_position(), 28.0, Color(3.0, 3.0, 3.0))
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				reset_balls()
			KEY_SPACE:
				spawn_ball(Vector2(400 + randf() * 1120, 150))
			KEY_S:
				_toggle_shadows()
			KEY_C:
				for child in _balls.get_children():
					child.queue_free()
				_ball_count = 0
