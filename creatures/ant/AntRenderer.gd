class_name AntRenderer extends Node2D
## 蚂蚁渲染器 — 分节绘制蚂蚁身体、腿和触角

var controller: AntController

# 颜色
var body_color: Color = Color(0.18, 0.12, 0.08, 1.0)
var body_highlight: Color = Color(0.30, 0.22, 0.16, 1.0)
var body_shadow: Color = Color(0.10, 0.06, 0.03, 1.0)
var leg_color: Color = Color(0.14, 0.09, 0.05, 1.0)
var antenna_color: Color = Color(0.16, 0.11, 0.07, 1.0)
var eye_color: Color = Color(0.02, 0.02, 0.02, 1.0)
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.12)


func _ready() -> void:
	controller = get_parent().get_node("Controller") as AntController


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
	if controller.abdomen_first:
		joints.append(controller.abdomen_first)
	if controller.petiole:
		joints.append(controller.petiole)
	if controller.thorax:
		joints.append(controller.thorax)
	if controller.head:
		joints.append(controller.head)
	for joint: ChainJoint in joints:
		var local_pos: Vector2 = to_local(joint.global_position) + Vector2(2, 3)
		draw_circle(local_pos, joint.radius + 2.0, shadow_color)


# ===================== 分节身体绘制 =====================

func _draw_body_segments() -> void:
	# 按从尾到头的顺序绘制，使头部覆盖在最上层
	var segments: Array = []
	if controller.abdomen_first:
		segments.append({"joint": controller.abdomen_first, "type": "abdomen"})
	if controller.petiole:
		segments.append({"joint": controller.petiole, "type": "petiole"})
	if controller.thorax:
		segments.append({"joint": controller.thorax, "type": "thorax"})
	if controller.head:
		segments.append({"joint": controller.head, "type": "head"})

	# 绘制连接线（体节之间的窄连接）
	for i: int in range(segments.size() - 1):
		var curr: ChainJoint = segments[i]["joint"]
		var next: ChainJoint = segments[i + 1]["joint"]
		var curr_local: Vector2 = to_local(curr.global_position)
		var next_local: Vector2 = to_local(next.global_position)
		var connect_width: float = 2.5
		if segments[i]["type"] == "petiole" or segments[i + 1]["type"] == "petiole":
			connect_width = 1.5
		draw_line(curr_local, next_local, body_color, connect_width)

	# 绘制每个体节
	for seg: Dictionary in segments:
		var joint: ChainJoint = seg["joint"]
		var seg_type: String = seg["type"]
		var local_pos: Vector2 = to_local(joint.global_position)

		# 计算体节朝向
		var direction: Vector2 = _get_segment_direction(joint, segments)
		var angle: float = direction.angle()

		# 根据体节类型选择绘制方式
		match seg_type:
			"head":
				_draw_head_segment(local_pos, angle, joint.radius)
			"thorax":
				_draw_thorax_segment(local_pos, angle, joint.radius)
			"petiole":
				_draw_petiole_segment(local_pos, angle, joint.radius)
			"abdomen":
				_draw_abdomen_segment(local_pos, angle, joint.radius)

	# 绘制眼睛
	_draw_eyes()

	# 绘制上颚
	_draw_mandibles()


func _get_segment_direction(joint: ChainJoint, segments: Array) -> Vector2:
	var index: int = -1
	for i: int in range(segments.size()):
		if segments[i]["joint"] == joint:
			index = i
			break
	if index < 0:
		return Vector2.RIGHT

	var prev_joint: ChainJoint = null
	var next_joint: ChainJoint = null
	if index > 0:
		prev_joint = segments[index - 1]["joint"]
	if index < segments.size() - 1:
		next_joint = segments[index + 1]["joint"]

	if prev_joint and next_joint:
		return (next_joint.global_position - prev_joint.global_position).normalized()
	elif next_joint:
		return (next_joint.global_position - joint.global_position).normalized()
	elif prev_joint:
		return (joint.global_position - prev_joint.global_position).normalized()
	return Vector2.RIGHT


func _draw_head_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 头部：略扁的椭圆
	var points: PackedVector2Array = []
	var seg_count: int = 16
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.1
		var ry: float = radius * 0.9
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.2, radius * 0.35, body_highlight)


func _draw_thorax_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 胸部：圆润的椭圆
	var points: PackedVector2Array = []
	var seg_count: int = 16
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.2
		var ry: float = radius * 0.85
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.15, radius * 0.3, body_highlight)


func _draw_petiole_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 腰节：非常窄小的椭圆
	var points: PackedVector2Array = []
	var seg_count: int = 12
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 0.8
		var ry: float = radius * 0.6
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)


func _draw_abdomen_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 腹部：大而饱满的椭圆
	var points: PackedVector2Array = []
	var seg_count: int = 16
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.3
		var ry: float = radius * 1.0
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.25, radius * 0.35, body_highlight)


func _draw_eyes() -> void:
	if not controller.head or not controller.thorax:
		return
	var head_direction: Vector2 = (controller.head.global_position - controller.thorax.global_position).normalized()
	var head_right: Vector2 = head_direction.rotated(PI * 0.5)
	var head_local: Vector2 = to_local(controller.head.global_position)

	var eye_offset_forward: float = controller.head.radius * 0.5
	var eye_offset_side: float = controller.head.radius * 0.6
	var eye_radius: float = 2.0

	var left_eye: Vector2 = head_local + head_direction * eye_offset_forward + head_right * eye_offset_side
	var right_eye: Vector2 = head_local + head_direction * eye_offset_forward - head_right * eye_offset_side

	# 眼底
	draw_circle(left_eye, eye_radius + 0.5, Color(0.3, 0.2, 0.15))
	draw_circle(right_eye, eye_radius + 0.5, Color(0.3, 0.2, 0.15))
	# 眼球
	draw_circle(left_eye, eye_radius, eye_color)
	draw_circle(right_eye, eye_radius, eye_color)
	# 高光点
	draw_circle(left_eye + Vector2(-0.5, -0.5), 0.7, Color.WHITE)
	draw_circle(right_eye + Vector2(-0.5, -0.5), 0.7, Color.WHITE)


func _draw_mandibles() -> void:
	if not controller.head or not controller.thorax:
		return
	var head_direction: Vector2 = (controller.head.global_position - controller.thorax.global_position).normalized()
	var head_right: Vector2 = head_direction.rotated(PI * 0.5)
	var head_local: Vector2 = to_local(controller.head.global_position)

	var mandible_length: float = 7.0
	var mandible_spread: float = controller.head.radius * 0.5

	var left_base: Vector2 = head_local + head_direction * controller.head.radius * 0.9 + head_right * mandible_spread
	var right_base: Vector2 = head_local + head_direction * controller.head.radius * 0.9 - head_right * mandible_spread

	# 上颚：内弯钩形
	var left_tip: Vector2 = left_base + head_direction * mandible_length - head_right * 2.0
	var right_tip: Vector2 = right_base + head_direction * mandible_length + head_right * 2.0

	draw_line(left_base, left_tip, leg_color, 2.0)
	draw_line(right_base, right_tip, leg_color, 2.0)
	# 尖端小钩
	draw_line(left_tip, left_tip + head_direction * 1.5 + head_right * 1.0, leg_color, 1.5)
	draw_line(right_tip, right_tip + head_direction * 1.5 - head_right * 1.0, leg_color, 1.5)


# ===================== 腿部绘制 =====================

func _draw_legs() -> void:
	for leg_data: AntController.LegData in controller.legs:
		if not leg_data.hip or not leg_data.knee or not leg_data.foot:
			continue
		var hip_local: Vector2 = to_local(leg_data.hip.global_position)
		var knee_local: Vector2 = to_local(leg_data.knee.global_position)
		var foot_local: Vector2 = to_local(leg_data.foot.global_position)

		# 脚部阴影
		if not leg_data.stepping:
			draw_circle(foot_local + Vector2(1, 2), 2.5, shadow_color)

		# 腿部线段 — 从粗到细
		draw_line(hip_local, knee_local, leg_color, 2.5)
		draw_line(knee_local, foot_local, leg_color, 1.8)

		# 关节圆点
		draw_circle(hip_local, 2.0, body_color)
		draw_circle(knee_local, 1.5, leg_color)
		draw_circle(foot_local, 1.0, leg_color)


# ===================== 触角绘制 =====================

func _draw_antennae() -> void:
	for antenna_data: AntController.AntennaData in controller.antennae:
		if not antenna_data.base or not antenna_data.tip:
			continue

		# 收集触角所有关节位置
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
			var width: float = 2.0 * (1.0 - float(i) / float(points.size()))
			draw_line(points[i], points[i + 1], antenna_color, maxf(width, 0.8))

		# 触角尖端小点
		if points.size() > 0:
			draw_circle(points[points.size() - 1], 1.0, antenna_color)
