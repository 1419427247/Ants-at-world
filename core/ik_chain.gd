@tool
class_name IKChain extends Node2D
## IK 反向动力学链 — 递归容器
##
## IKChain 既可以作为链的容器（包含子 IKChain），
## 也可以作为链中的一个关节段（leaf 节点，拥有 radius 等属性）。
## 由 IKRoot 统一管理骨骼和求解。

## 是否启用关节角度约束（对应 CCDIK 的 enable_constraint）
@export var enable_constraint: bool = true:
	set(value):
		enable_constraint = value
		queue_redraw()

## 是否反转角度约束。为 true 时，关节只能在 min~max 之外的角度活动
@export var constraint_angle_invert: bool = true:
	set(value):
		constraint_angle_invert = value
		queue_redraw()

## 关节允许旋转的最小角度（度）
@export var minimum_angle_degrees: float = -180.0:
	set(value):
		minimum_angle_degrees = value
		queue_redraw()

## 关节允许旋转的最大角度（度）
@export var maximum_angle_degrees: float = 180.0:
	set(value):
		maximum_angle_degrees = value
		queue_redraw()

## 是否从关节处旋转骨骼，而非从骨骼的末端旋转
@export var rotate_from_joint: bool = false

var root: IKRoot
var parent_chain: IKChain

var bone: Bone2D = Bone2D.new()


func _ready() -> void:
	parent_chain = get_parent() as IKChain
	set_notify_transform(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	global_transform = bone.global_transform


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func _draw() -> void:
	var bone_color: Color = Color(0.4, 0.7, 1.0, 0.7)
	var joint_color: Color = Color(0.3, 0.9, 0.5, 0.8)
	var constraint_color: Color = Color(1.0, 0.5, 0.0, 0.7)
	var allowed_color: Color = Color(0.3, 1.0, 0.5, 0.5)
	if parent_chain:
		draw_line(Vector2.ZERO, to_local(parent_chain.global_position), bone_color, 1.0)
	_draw_constraint_angles(constraint_color, allowed_color)
	draw_circle(Vector2.ZERO, 2.0, joint_color)


func _draw_constraint_angles(restricted_color: Color, allowed_color: Color) -> void:
	# 未启用约束或全范围无约束时跳过绘制
	if not enable_constraint or (minimum_angle_degrees <= -180.0 and maximum_angle_degrees >= 180.0):
		return

	# 参考方向：骨骼朝外的方向（从父节点指向自身）
	var forward: Vector2 = Vector2.RIGHT
	if parent_chain:
		var parent_pos: Vector2 = to_local(parent_chain.global_position)
		if parent_pos.length_squared() > 0.0:
			forward = -parent_pos.normalized()

	var ref_angle: float = forward.angle()
	var min_angle: float = ref_angle + deg_to_rad(minimum_angle_degrees)
	var max_angle: float = ref_angle + deg_to_rad(maximum_angle_degrees)

	var arc_radius: float = 6.0
	var line_len: float = 5.0

	# 绘制约束边界线（标出 min 和 max）
	draw_line(Vector2.ZERO, Vector2.from_angle(min_angle) * line_len, restricted_color, 1.5)
	draw_line(Vector2.ZERO, Vector2.from_angle(max_angle) * line_len, restricted_color, 1.5)

	# 绘制弧线：反转约束时 min→max 之间为受限区域，否则为允许区域
	var arc_color: Color = restricted_color if constraint_angle_invert else allowed_color
	var arc_start: float = min_angle
	var arc_end: float = max_angle

	var steps: int = maxi(4, absi(int(rad_to_deg(arc_end - arc_start) / 5.0)))
	var points: PackedVector2Array = []
	points.resize(steps + 1)
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = arc_start + (arc_end - arc_start) * t
		points[i] = Vector2.from_angle(a) * arc_radius
	draw_polyline(points, arc_color, 1.0)
