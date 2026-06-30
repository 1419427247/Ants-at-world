extends Camera2D

## 2D 摄像机控制器
## WASD / 方向键移动 | 滚轮缩放 | 中键拖拽
##
## 挂载到任意节点，自动查找 Camera2D。
## 可选连接 GI 重投影，消除摄像机移动时的 Temporal 拖影。

signal camera_moved

# 移动
@export var move_speed: float = 800.0
## 移动速度是否随 zoom 反比缩放（zoom 越大移动越慢）
@export var zoom_affects_speed: bool = true

# 缩放
@export var zoom_min: float = 0.3
@export var zoom_max: float = 3.0
@export var zoom_step: float = 1.15

# 中键拖拽
@export var enable_drag: bool = true

@onready var _camera: Camera2D = _resolve_camera()

var _last_camera_pos: Vector2
var _drag_origin: Vector2
var _drag_cam_origin: Vector2
var _dragging: bool = false

func _resolve_camera() -> Camera2D:
	# 尝试父节点
	var p := get_parent()
	if p is Camera2D:
		return p
	# 尝试子节点
	for child in get_children():
		if child is Camera2D:
			return child
	# 场景中查找
	var root := get_tree().current_scene
	if root:
		return root.find_child("*", true, false) as Camera2D
	return null


func _ready() -> void:
	if not _camera:
		push_warning("CameraController: 未找到 Camera2D")
		return
	_last_camera_pos = global_position


func _process(delta: float) -> void:
	var dir := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if dir == Vector2.ZERO:
		# 备选 WASD
		var wasd := Vector2.ZERO
		if Input.is_key_pressed(KEY_D): wasd.x += 1
		if Input.is_key_pressed(KEY_A): wasd.x -= 1
		if Input.is_key_pressed(KEY_S): wasd.y += 1
		if Input.is_key_pressed(KEY_W): wasd.y -= 1
		dir = wasd

	if dir == Vector2.ZERO:
		return

	var speed := move_speed / (zoom.x if zoom_affects_speed else 1.0)
	global_position += dir.normalized() * speed * delta


# ---------------------------------------------------------------------------
# 输入事件
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / zoom_step)
			MOUSE_BUTTON_MIDDLE:
				if enable_drag:
					if event.pressed:
						_dragging = true
						_drag_origin = get_global_mouse_position()
						_drag_cam_origin = global_position
					else:
						_dragging = false

	if event is InputEventMouseMotion and _dragging:
		global_position = _drag_cam_origin - (event.global_position - _drag_origin) / zoom.x



func _zoom(factor: float) -> void:
	var z := clampf(zoom.x * factor, zoom_min, zoom_max)
	zoom = Vector2(z, z)
