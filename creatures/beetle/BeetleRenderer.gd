class_name BeetleRenderer extends Node2D
## 金龟子渲染器 — 金属绿色身体、硬翅鞘、棒状触角

var controller: BeetleController

# 颜色 — 金属绿
var body_color: Color = Color(0.06, 0.14, 0.08, 1.0)
var body_highlight: Color = Color(0.14, 0.28, 0.16, 1.0)
var body_shadow: Color = Color(0.03, 0.07, 0.04, 1.0)
var elytra_color: Color = Color(0.05, 0.18, 0.10, 1.0)
var elytra_highlight: Color = Color(0.12, 0.32, 0.18, 1.0)
var leg_color: Color = Color(0.04, 0.10, 0.06, 1.0)
var antenna_color: Color = Color(0.05, 0.12, 0.07, 1.0)
var eye_color: Color = Color(0.02, 0.02, 0.02, 1.0)
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.12)


func _ready() -> void:
	controller = get_parent().get_node("Controller") as BeetleController


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not controller:
		return
	if not controller.head or not controller.thorax:
		return
	_draw_shadow()
	_draw_legs()
	_draw_body_segments()
	_draw_antennae()


# ===================== 阴影 =====================

func _draw_shadow() -> void:
	var joints: Array[ChainJoint] = []
	if controller.elytra:
		joints.append(controller.elytra)
	if controller.thorax:
		joints.append(controller.thorax)
	if controller.head:
		joints.append(controller.head)
	for joint: ChainJoint in joints:
		var local_pos: Vector2 = to_local(joint.global_position) + Vector2(2, 3)
		draw_circle(local_pos, joint.radius + 2.0, shadow_color)


# ===================== 分节身体绘制 =====================

func _draw_body_segments() -> void:
	# 从尾到头绘制
	var segments: Array = []
	if controller.elytra:
		segments.append({"joint": controller.elytra, "type": "elytra"})
	if controller.thorax:
		segments.append({"joint": controller.thorax, "type": "thorax"})
	if controller.head:
		segments.append({"joint": controller.head, "type": "head"})

	# 连接线
	for i: int in range(segments.size() - 1):
		var curr: ChainJoint = segments[i]["joint"]
		var next: ChainJoint = segments[i + 1]["joint"]
		var curr_local: Vector2 = to_local(curr.global_position)
		var next_local: Vector2 = to_local(next.global_position)
		draw_line(curr_local, next_local, body_color, 3.0)

	# 绘制每个体节
	for seg: Dictionary in segments:
		var joint: ChainJoint = seg["joint"]
		var seg_type: String = seg["type"]
		var local_pos: Vector2 = to_local(joint.global_position)
		var direction: Vector2 = _get_segment_direction(joint, segments)
		var angle: float = direction.angle()

		match seg_type:
			"head":
				_draw_head_segment(local_pos, angle, joint.radius)
			"thorax":
				_draw_thorax_segment(local_pos, angle, joint.radius)
			"elytra":
				_draw_elytra_segment(local_pos, angle, joint.radius)

	_draw_eyes()


func _get_segment_direction(joint: ChainJoint, segments: Array) -> Vector2:
	var idx: int = -1
	for i: int in range(segments.size()):
		if segments[i]["joint"] == joint:
			idx = i
			break
	if idx < 0:
		return Vector2.RIGHT

	var prev_joint: ChainJoint = null
	var next_joint: ChainJoint = null
	if idx > 0:
		prev_joint = segments[idx - 1]["joint"]
	if idx < segments.size() - 1:
		next_joint = segments[idx + 1]["joint"]

	if prev_joint and next_joint:
		return (next_joint.global_position - prev_joint.global_position).normalized()
	elif next_joint:
		return (next_joint.global_position - joint.global_position).normalized()
	elif prev_joint:
		return (joint.global_position - prev_joint.global_position).normalized()
	return Vector2.RIGHT


func _draw_head_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 头部：宽圆盾形
	var points: PackedVector2Array = []
	var seg_count: int = 16
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.0
		var ry: float = radius * 1.1
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 金属高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.15, radius * 0.3, body_highlight)


func _draw_thorax_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 胸部：前窄后宽的梯形盾板
	var points: PackedVector2Array = []
	var hw_front: float = radius * 0.8
	var hw_back: float = radius * 1.3
	var hh: float = radius * 0.9
	points.append(pos + Vector2(-hh, -hw_front).rotated(angle))
	points.append(pos + Vector2(hh, -hw_back).rotated(angle))
	points.append(pos + Vector2(hh, hw_back).rotated(angle))
	points.append(pos + Vector2(-hh, hw_front).rotated(angle))
	draw_colored_polygon(points, body_color)
	# 中线高光
	var mid_front: Vector2 = pos + Vector2(-hh * 0.5, 0).rotated(angle)
	var mid_back: Vector2 = pos + Vector2(hh * 0.5, 0).rotated(angle)
	draw_line(mid_front, mid_back, body_highlight, 1.5)


func _draw_elytra_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 翅鞘：大而宽的圆顶形，覆盖腹部
	var points: PackedVector2Array = []
	var seg_count: int = 20
	var rx: float = radius * 1.6
	var ry: float = radius * 1.3
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, elytra_color)

	# 翅鞘中线（左右翅分界线）
	var mid_start: Vector2 = pos + Vector2(-rx * 0.8, 0).rotated(angle)
	var mid_end: Vector2 = pos + Vector2(rx * 0.8, 0).rotated(angle)
	draw_line(mid_start, mid_end, body_shadow, 1.5)

	# 翅鞘纵向条纹（3条平行线）
	for offset: float in [-0.4, 0.0, 0.4]:
		var stripe_start: Vector2 = pos + Vector2(-rx * 0.5, ry * offset).rotated(angle)
		var stripe_end: Vector2 = pos + Vector2(rx * 0.5, ry * offset).rotated(angle)
		draw_line(stripe_start, stripe_end, elytra_highlight, 0.8)

	# 金属高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.3, radius * 0.4, elytra_highlight)


func _draw_eyes() -> void:
	if not controller.head or not controller.thorax:
		return
	var head_direction: Vector2 = (controller.head.global_position - controller.thorax.global_position).normalized()
	var head_right: Vector2 = head_direction.rotated(PI * 0.5)
	var head_local: Vector2 = to_local(controller.head.global_position)

	var eye_offset_forward: float = controller.head.radius * 0.3
	var eye_offset_side: float = controller.head.radius * 0.7
	var eye_radius: float = 1.8

	var left_eye: Vector2 = head_local + head_direction * eye_offset_forward + head_right * eye_offset_side
	var right_eye: Vector2 = head_local + head_direction * eye_offset_forward - head_right * eye_offset_side

	draw_circle(left_eye, eye_radius + 0.5, body_shadow)
	draw_circle(right_eye, eye_radius + 0.5, body_shadow)
	draw_circle(left_eye, eye_radius, eye_color)
	draw_circle(right_eye, eye_radius, eye_color)
	draw_circle(left_eye + Vector2(-0.4, -0.4), 0.6, Color.WHITE)
	draw_circle(right_eye + Vector2(-0.4, -0.4), 0.6, Color.WHITE)


# ===================== 腿部绘制 =====================

func _draw_legs() -> void:
	for leg_data: BeetleController.LegData in controller.legs:
		if not leg_data.hip or not leg_data.knee or not leg_data.foot:
			continue
		var hip_local: Vector2 = to_local(leg_data.hip.global_position)
		var knee_local: Vector2 = to_local(leg_data.knee.global_position)
		var foot_local: Vector2 = to_local(leg_data.foot.global_position)

		# 脚部阴影
		if not leg_data.stepping:
			draw_circle(foot_local + Vector2(1, 2), 2.5, shadow_color)

		# 腿部线段 — 金龟子腿更粗壮
		draw_line(hip_local, knee_local, leg_color, 3.0)
		draw_line(knee_local, foot_local, leg_color, 2.0)

		# 关节圆点
		draw_circle(hip_local, 2.2, body_color)
		draw_circle(knee_local, 1.8, leg_color)
		draw_circle(foot_local, 1.2, leg_color)


# ===================== 触角绘制 =====================

func _draw_antennae() -> void:
	for antenna_data: BeetleController.AntennaData in controller.antennae:
		if not antenna_data.base or not antenna_data.tip:
			continue

		var points: PackedVector2Array = []
		points.append(to_local(antenna_data.base.global_position))
		for segment: JointBone in antenna_data.segments:
			if segment:
				points.append(to_local(segment.global_position))
		points.append(to_local(antenna_data.tip.global_position))

		if points.size() < 2:
			continue

		# 绘制触角 — 从粗到细
		for i: int in range(points.size() - 1):
			var width: float = 2.2 * (1.0 - float(i) / float(points.size()))
			draw_line(points[i], points[i + 1], antenna_color, maxf(width, 1.0))

		# 棒状触角末端：膨大的球
		var tip_pos: Vector2 = points[points.size() - 1]
		draw_circle(tip_pos, 2.5, antenna_color)
		draw_circle(tip_pos, 1.5, body_highlight)
