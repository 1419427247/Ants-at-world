@tool
class_name JointBone extends Node2D
## 自定义关节骨骼 — 从父节点到自身的骨骼段
##
## JointBone 的自身位置即骨骼末端（tip），骨骼段从父 JointBone 的位置延伸至自身。
## 父 JointBone 的位置即关节旋转中心。
## 在场景树中将 JointBone 作为另一个 JointBone 的子节点，即构成关节链。
## 配合 IKController 使用可实现手动 CCDIK 求解。

## 骨骼长度（仅在父节点为 JointBone 时可用）
@export var length: float = 16:
	get:
		var parent_bone: JointBone = get_parent_bone()
		if parent_bone:
			return length
		return 0.0

## 关节允许旋转的最小角度（度），相对于父骨骼方向
@export var minimum_angle_degrees: float = -180.0:
	set(value):
		minimum_angle_degrees = value
		queue_redraw()

## 关节允许旋转的最大角度（度），相对于父骨骼方向
@export var maximum_angle_degrees: float = 180.0:
	set(value):
		maximum_angle_degrees = value
		queue_redraw()

## 是否从关节根部旋转骨骼（而不是从骨骼末端旋转）
@export var rotate_from_joint: bool

func _init() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()
		## 确保与父骨骼的距离不超过 length
		var parent_bone: JointBone = get_parent_bone()
		if parent_bone:
			position = position.normalized() * length

	elif what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		notify_property_list_changed()




func _validate_property(property: Dictionary) -> void:
	if property.name == "length" and not (get_parent() is JointBone):
		property.usage = PROPERTY_USAGE_NONE

## 获取骨骼末端在世界空间中的位置（即本节点的全局位置）
func get_tip_position() -> Vector2:
	return global_position


## 获取关节根部在世界空间中的位置（即父 JointBone 的全局位置）
func get_joint_position() -> Vector2:
	var parent_bone: JointBone = get_parent_bone()
	if parent_bone:
		return parent_bone.global_position
	return global_position


## 获取父级 JointBone（如果父节点是 JointBone）
func get_parent_bone() -> JointBone:
	var p: Node = get_parent()
	return p as JointBone


## 获取所有子级 JointBone
func get_child_bones() -> Array[JointBone]:
	var bones: Array[JointBone] = []
	for child: Node in get_children():
		if child is JointBone:
			bones.append(child)
	return bones


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var bone_color: Color = Color(0.4, 0.7, 1.0, 0.7)
	var joint_color: Color = Color(0.3, 0.9, 0.5, 0.8)
	var tip_color: Color = Color(1.0, 0.3, 0.3, 0.8)
	var constraint_color: Color = Color(1.0, 0.5, 0.0, 0.7)
	var allowed_color: Color = Color(0.3, 1.0, 0.5, 0.5)

	# 将父节点位置转换到本骨骼的局部空间
	var parent_bone: JointBone = get_parent_bone()
	if parent_bone:
		var joint_local: Vector2 = to_local(parent_bone.global_position)
		# 骨骼段：从关节（父位置）到末端（本节点原点）
		draw_line(joint_local, Vector2.ZERO, bone_color, 2.0)
		# 关节圆（绘制在父位置）
		draw_circle(joint_local, 3.0, joint_color)

	# 末端点（本节点原点）
	draw_circle(Vector2.ZERO, 2.0, tip_color)

	# 角度约束可视化
	if parent_bone \
			and not (minimum_angle_degrees <= -180.0 and maximum_angle_degrees >= 180.0):
		_draw_constraint_arcs(constraint_color, allowed_color)


func _draw_constraint_arcs(restricted_color: Color, allowed_color: Color) -> void:
	var parent_bone: JointBone = get_parent_bone()
	if not parent_bone:
		return

	# 父骨骼关节位置（世界空间）
	var parent_joint_pos: Vector2
	var grandparent_bone := parent_bone.get_parent_bone()
	if grandparent_bone:
		parent_joint_pos = grandparent_bone.global_position
	else:
		var parent_node := parent_bone.get_parent() as Node2D
		if parent_node:
			parent_joint_pos = parent_node.global_position
		else:
			return

	# 参考方向 = 父骨骼方向（从父骨骼关节到父骨骼末端），在本骨骼局部空间中的角度
	var ref_angle: float
	var joint_local: Vector2 = to_local(parent_bone.global_position)
	var parent_joint_local: Vector2 = to_local(parent_joint_pos)
	if joint_local.is_equal_approx(parent_joint_local):
		# 父骨骼长度为零时，回退使用其旋转方向作为参考
		ref_angle = parent_bone.global_rotation - global_rotation
	else:
		ref_angle = (joint_local - parent_joint_local).angle()

	var min_angle: float = ref_angle + deg_to_rad(minimum_angle_degrees)
	var max_angle: float = ref_angle + deg_to_rad(maximum_angle_degrees)

	var arc_radius: float = 8.0
	var line_len: float = 6.0

	# 边界线（从关节位置绘制）
	draw_line(joint_local, joint_local + Vector2.from_angle(min_angle) * line_len, restricted_color, 1.5)
	draw_line(joint_local, joint_local + Vector2.from_angle(max_angle) * line_len, restricted_color, 1.5)

	# 辅助函数：绘制一段弧
	var draw_arc_segment := func(start_angle: float, end_angle: float, color: Color, radius: float = arc_radius) -> void:
		var steps: int = maxi(4, absi(int(rad_to_deg(end_angle - start_angle) / 5.0)))
		var pts: PackedVector2Array = []
		pts.resize(steps + 1)
		for j in range(steps + 1):
			var t: float = float(j) / float(steps)
			var a: float = start_angle + (end_angle - start_angle) * t
			pts[j] = joint_local + Vector2.from_angle(a) * radius
		draw_polyline(pts, color, 1.0)

	# 内弧（min→max 经过 ref_angle 方向）是允许区，绿色；外弧是限制区，橙色
	var inner_color: Color = allowed_color
	var outer_color: Color = restricted_color

	# 规范化角度，确定正方向弧段
	var norm_min: float = fmod(min_angle - ref_angle, TAU)
	var norm_max: float = fmod(max_angle - ref_angle, TAU)
	if norm_min < 0.0:
		norm_min += TAU
	if norm_max < 0.0:
		norm_max += TAU

	if norm_min < norm_max:
		# 从 min → ref_angle → max 是正方向短弧
		draw_arc_segment.call(min_angle, max_angle, inner_color)
		draw_arc_segment.call(max_angle, min_angle + TAU, outer_color, arc_radius * 0.6)
	else:
		# 从 max → ref_angle → min 是正方向短弧
		draw_arc_segment.call(max_angle, min_angle, inner_color)
		draw_arc_segment.call(min_angle, max_angle + TAU, outer_color, arc_radius * 0.6)

	# 当前骨骼方向指示线（从关节位置指向本骨骼末端方向）
	var bone_direction_angle: float = (Vector2.ZERO - joint_local).angle()
	var indicator_len: float = arc_radius + 3.0
	draw_line(joint_local, joint_local + Vector2.from_angle(bone_direction_angle) * indicator_len,
			Color(1.0, 1.0, 1.0, 0.9), 2.0)
