class_name MillipedeRenderer extends Node2D
## 千足虫渲染器 — 细长方形体节 + 密集短腿

var controller: MillipedeController

# 颜色
var body_color: Color = Color(0.25, 0.1, 0.06, 1.0)
var body_highlight: Color = Color(0.35, 0.18, 0.1, 1.0)
var body_shadow: Color = Color(0.15, 0.05, 0.03, 1.0)
var leg_color: Color = Color(0.2, 0.08, 0.05, 1.0)
var eye_color: Color = Color(0.02, 0.02, 0.02, 1.0)
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.12)

# 体节尺寸
var seg_half_w: float = 7.0   # 体节长方形半宽（沿身体方向）
var seg_half_h: float = 7.0   # 体节长方形半高（垂直身体方向）


func _ready() -> void:
	controller = get_parent().get_node("Controller") as MillipedeController


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not controller:
		return
	if not controller.head:
		return
	_draw_shadow()
	_draw_body()
	_draw_legs()
	_draw_head_details()


# ===================== 阴影 =====================

func _draw_shadow() -> void:
	var joints: Array[ChainJoint] = []
	if controller.tail:
		joints.append(controller.tail)
	for seg in controller.segment_joints:
		joints.append(seg)
	if controller.head:
		joints.append(controller.head)
	for joint: ChainJoint in joints:
		var local_pos: Vector2 = to_local(joint.global_position) + Vector2(3.0, 5.0)
		draw_rect(Rect2(local_pos.x - seg_half_w, local_pos.y - seg_half_h, seg_half_w * 2, seg_half_h * 2), shadow_color)


# ===================== 身体绘制（细长方形体节） =====================

func _draw_body() -> void:
	# 收集所有脊柱关节（从尾到头）
	var spine_joints: Array[ChainJoint] = []
	if controller.tail:
		spine_joints.append(controller.tail)
	for i in range(controller.segment_joints.size() - 1, -1, -1):
		spine_joints.append(controller.segment_joints[i])
	if controller.head:
		spine_joints.append(controller.head)

	if spine_joints.size() < 2:
		return

	# 绘制每个体节
	var has_tail: bool = controller.tail != null
	var has_head: bool = controller.head != null

	for i in range(spine_joints.size()):
		var joint: ChainJoint = spine_joints[i]
		var local_pos: Vector2 = to_local(joint.global_position)

		# 计算体节朝向
		var direction: Vector2 = Vector2.RIGHT
		if i < spine_joints.size() - 1:
			direction = (spine_joints[i + 1].global_position - joint.global_position).normalized()
		elif i > 0:
			direction = (joint.global_position - spine_joints[i - 1].global_position).normalized()
		var angle: float = direction.angle()

		var is_head: bool = has_head and i == spine_joints.size() - 1
		var is_tail: bool = has_tail and i == 0

		if is_head:
			# 头部半圆：中心往身体方向偏移，平边连接身体，弧面朝前
			var head_center: Vector2 = local_pos - direction * seg_half_h
			_draw_semicircle(head_center, direction, seg_half_h, body_color)
		elif is_tail:
			# 尾部半圆：direction指向身体，需反转；中心往身体方向偏移，弧面朝后
			var tail_center: Vector2 = local_pos + direction * seg_half_h
			_draw_semicircle(tail_center, -direction, seg_half_h, body_color)
		else:
			# 中间体节：细长方形
			var hw: float = seg_half_w
			var hh: float = seg_half_h
			var points: PackedVector2Array = [
				local_pos + Vector2(-hw, -hh).rotated(angle),
				local_pos + Vector2(hw, -hh).rotated(angle),
				local_pos + Vector2(hw, hh).rotated(angle),
				local_pos + Vector2(-hw, hh).rotated(angle),
			]
			draw_colored_polygon(points, body_color)

			# 高光线（背部）
			var highlight_offset: Vector2 = Vector2(0, -hh * 0.5).rotated(angle)
			draw_line(local_pos + Vector2(-hw * 0.7, 0).rotated(angle) + highlight_offset,
					local_pos + Vector2(hw * 0.7, 0).rotated(angle) + highlight_offset,
					body_highlight, 1.0)


# ===================== 腿部绘制 =====================

## 绘制半圆形（平边垂直于direction，弧面朝direction方向）
func _draw_semicircle(center: Vector2, direction: Vector2, radius: float, color: Color) -> void:
	var angle: float = direction.angle()
	var points: PackedVector2Array = []
	var steps: int = 12
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var a: float = angle - PI * 0.5 + t * PI
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	draw_colored_polygon(points, color)


func _draw_legs() -> void:
	for leg_data: MillipedeController.LegData in controller.legs:
		if not leg_data.hip or not leg_data.foot:
			continue
		var hip_local: Vector2 = to_local(leg_data.hip.global_position)
		var foot_local: Vector2 = to_local(leg_data.foot.global_position)

		# 脚部阴影（仅支撑相）
		if not leg_data.stepping:
			draw_circle(foot_local + Vector2(2, 3), 3.0, shadow_color)

		# 腿部线段
		draw_line(hip_local, foot_local, leg_color, 1.5)

		# 脚部小点
		draw_circle(foot_local, 1.6, leg_color)


# ===================== 头部细节 =====================

func _draw_head_details() -> void:
	if not controller.head or controller.segment_joints.is_empty():
		return

	var head_dir: Vector2 = (controller.head.global_position - controller.segment_joints[0].global_position).normalized()
	var head_right: Vector2 = head_dir.rotated(PI * 0.5)
	var head_local: Vector2 = to_local(controller.head.global_position)

	# 眼睛（定位在头部半圆内部）
	# 半圆中心在 head_local - head_dir * seg_half_h，半径 seg_half_h
	var eye_offset_forward: float = -2.0  # 从head关节往回偏移，落在半圆内
	var eye_offset_side: float = 3.6
	var eye_radius: float = 2.0

	var left_eye: Vector2 = head_local + head_dir * eye_offset_forward + head_right * eye_offset_side
	var right_eye: Vector2 = head_local + head_dir * eye_offset_forward - head_right * eye_offset_side

	draw_circle(left_eye, eye_radius + 0.6, Color(0.3, 0.2, 0.15))
	draw_circle(right_eye, eye_radius + 0.6, Color(0.3, 0.2, 0.15))
	draw_circle(left_eye, eye_radius, eye_color)
	draw_circle(right_eye, eye_radius, eye_color)
