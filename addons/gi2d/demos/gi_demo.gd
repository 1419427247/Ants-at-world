extends Node

## GI 物理演示场景
## 左键生成发光球，右键生成大白球，R 重置，空格随机生成，G 切换调试网格
## 方向键/WASD 移动摄像机，鼠标滚轮缩放

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

# 摄像机控制参数
const CAMERA_MOVE_SPEED := 800.0   # 基础移动速度（像素/秒，zoom=1 时）
const CAMERA_ZOOM_MIN := 0.3
const CAMERA_ZOOM_MAX := 3.0
const CAMERA_ZOOM_STEP := 1.15      # 每次滚轮缩放倍数

@export var max_balls: int = 96
@export var ball_radius: float = 14.0

var _ball_count: int = 0
var _color_index: int = 0
var _one_px: Texture2D
var _circle: Texture2D

var _last_camera_position: Vector2

@onready var _camera: Camera2D = $Camera
@onready var _arena: Node2D = $Arena
@onready var _balls: Node2D = $Balls
@onready var _gi_viewport: GILightViewport = $GILightViewport
@onready var _temporal_pass: TemporalPass = $CanvasLayer/Composite/PassTemporal

func _ready() -> void:
	_one_px = load("res://assets/1px.png")
	_circle = load("res://assets/circle.png")
	_build_arena()
	_spawn_initial_balls()
	_last_camera_position = _camera.position


func _process(delta: float) -> void:
	_handle_camera_movement(delta)
	_update_reprojection_velocity(delta)


# === 摄像机控制 ===

func _handle_camera_movement(delta: float) -> void:
	var input_dir := Vector2.ZERO
	# 方向键或 WASD
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0

	if input_dir == Vector2.ZERO:
		return

	# 移动速度随 zoom 反比缩放：zoom 越大屏幕每像素对应世界单位越小，移动越慢
	var speed := CAMERA_MOVE_SPEED / _camera.zoom.x
	_camera.position += input_dir.normalized() * speed * delta
	_last_camera_position = _camera.position


# --- 重投影速度（时域累积运动补偿） ---
# 将摄像机运动转换为 UV 空间的速度矢量，传递给 TemporalPass
# velocity = -(camera_delta) / (viewport_size * camera_zoom)
# 用于重投影历史帧采样位置，消除相机移动时的拖影
func _update_reprojection_velocity(delta: float) -> void:
	var current_pos := _camera.position
	var current_zoom := _camera.zoom
	var viewport_size := _gi_viewport.size

	# 位置变化量
	var pos_delta := current_pos - _last_camera_position
	_last_camera_position = current_pos

	if viewport_size == Vector2i.ZERO:
		return

	# UV 空间速度 = 世界位移 / (视口像素尺寸 * zoom)
	var velocity := Vector2(
		-pos_delta.x / (float(viewport_size.x) * current_zoom.x),
		-pos_delta.y / (float(viewport_size.y) * current_zoom.y)
	)

	_temporal_pass.temporal_velocity = velocity

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
	_add_box(Vector2(960, 480), Vector2(250, 18), BALL_COLORS.pick_random())
	_add_box(Vector2(380, 620), Vector2(180, 18), BALL_COLORS.pick_random())
	_add_box(Vector2(1550, 820), Vector2(180, 18), BALL_COLORS.pick_random())

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
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(CAMERA_ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(1.0 / CAMERA_ZOOM_STEP)
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				reset_balls()
			KEY_SPACE:
				spawn_ball(Vector2(400 + randf() * 1120, 150))
			KEY_C:
				for child in _balls.get_children():
					child.queue_free()
				_ball_count = 0


func _zoom_camera(factor: float) -> void:
	var new_zoom := _camera.zoom.x * factor
	new_zoom = clampf(new_zoom, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	_camera.zoom = Vector2(new_zoom, new_zoom)
