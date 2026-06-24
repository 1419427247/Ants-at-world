extends Node

## GI 物理演示场景
## 左键生成发光球，右键生成大白球，R 重置，空格随机生成，G 切换调试网格

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

var _ball_count: int = 0
var _color_index: int = 0
var _one_px: Texture2D
var _circle: Texture2D

@onready var _camera: Camera2D = $Camera2D
@onready var _arena: Node2D = $Arena
@onready var _balls: Node2D = $Balls
@onready var _gi_viewport: GILightViewport = $GILightViewport
@onready var _debug_grid: GridContainer = $GridContainer


func _ready() -> void:
	_one_px = load("res://assets/1px.png")
	_circle = load("res://assets/circle.png")
	_build_arena()
	_spawn_initial_balls()
	_debug_grid.visible = false


# === Arena 构建 ===

func _build_arena() -> void:
	# 外墙
	_add_box(Vector2(960, 1000), Vector2(1600, 30), WALL_COLOR)   # 地板
	_add_box(Vector2(960, 100), Vector2(1600, 30), WALL_COLOR)    # 天花板
	_add_box(Vector2(150, 550), Vector2(30, 900), WALL_COLOR)     # 左墙
	_add_box(Vector2(1770, 550), Vector2(30, 900), WALL_COLOR)    # 右墙

	# 平台（不同高度，测试阴影 + AO）
	_add_box(Vector2(550, 780), Vector2(300, 18), PLATFORM_COLOR)
	_add_box(Vector2(1370, 680), Vector2(300, 18), PLATFORM_COLOR)
	_add_box(Vector2(960, 480), Vector2(250, 18), PLATFORM_COLOR)
	_add_box(Vector2(380, 620), Vector2(180, 18), PLATFORM_COLOR)
	_add_box(Vector2(1550, 820), Vector2(180, 18), PLATFORM_COLOR)

	# 柱子（角落 AO 测试）
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

	var gi := GIElement.new()
	gi.gi_light_viewport = _gi_viewport

	var sprite := Sprite2D.new()
	sprite.texture = _one_px
	sprite.modulate = color
	sprite.scale = size
	gi.add_child(sprite)

	body.add_child(gi)
	_arena.add_child(body)


# === 球体生成 ===

func _spawn_initial_balls() -> void:
	var positions := [
		Vector2(500, 200),
		Vector2(700, 150),
		Vector2(960, 200),
		Vector2(1200, 150),
		Vector2(1400, 200),
		Vector2(800, 300),
		Vector2(1100, 300),
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

	var gi := GIElement.new()
	gi.gi_light_viewport = _gi_viewport

	var sprite := Sprite2D.new()
	sprite.texture = _circle
	sprite.modulate = color
	var tex_size := _circle.get_size()
	sprite.scale = Vector2(radius * 2.0 / tex_size.x, radius * 2.0 / tex_size.y)
	gi.add_child(sprite)

	body.add_child(gi)
	_balls.add_child(body)
	_ball_count += 1


func reset_balls() -> void:
	for child in _balls.get_children():
		child.queue_free()
	_ball_count = 0
	_color_index = 0
	_spawn_initial_balls()


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
			KEY_G:
				_debug_grid.visible = not _debug_grid.visible
			KEY_C:
				for child in _balls.get_children():
					child.queue_free()
				_ball_count = 0
