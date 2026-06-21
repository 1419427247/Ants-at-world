class_name SnailRenderer extends Node2D
## 蜗牛渲染器 — 柔软身体 + 螺旋壳 + 触角

var controller: SnailController

# 颜色 — 柔和棕灰色
var body_color: Color = Color(0.72, 0.65, 0.55, 1.0)
var body_highlight: Color = Color(0.82, 0.76, 0.66, 1.0)
var body_shadow: Color = Color(0.55, 0.48, 0.40, 1.0)
var shell_color: Color = Color(0.65, 0.45, 0.30, 1.0)
var shell_highlight: Color = Color(0.78, 0.58, 0.42, 1.0)
var shell_stripe: Color = Color(0.45, 0.28, 0.18, 1.0)
var tentacle_color: Color = Color(0.68, 0.60, 0.50, 1.0)
var eye_color: Color = Color(0.02, 0.02, 0.02, 1.0)
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.10)


func _ready() -> void:
	controller = get_parent().get_node("Controller") as SnailController


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not controller:
		return
	if not controller.head or not controller.body:
		return
	_draw_shadow()
	_draw_body()
	_draw_shell()
	_draw_tentacles()


# ===================== 阴影 =====================

func _draw_shadow() -> void:
	var joints: Array[ChainJoint] = []
	if controller.shell:
		joints.append(controller.shell)
	if controller.body:
		joints.append(controller.body)
	if controller.head:
		joints.append(controller.head)
	for joint: ChainJoint in joints:
		var local_pos: Vector2 = to_local(joint.global_position) + Vector2(2, 3)
		draw_circle(local_pos, joint.radius + 3.0, shadow_color)


# ===================== 身体绘制 =====================

func _draw_body() -> void:
	# 蜗牛身体：柔软的足，从壳到头逐渐变细
	var segments: Array = []
	if controller.shell:
		segments.append({"joint": controller.shell, "type": "shell_base"})
	if controller.body:
		segments.append({"joint": controller.body, "type": "body"})
	if controller.head:
		segments.append({"joint": controller.head, "type": "head"})

	# 绘制连接的柔软身体（从头到尾的连续轮廓）
	if segments.size() >= 2:
		_draw_soft_body(segments)

	# 绘制头部
	if controller.head:
		var head_local: Vector2 = to_local(controller.head.global_position)
		var head_dir: Vector2 = _get_segment_direction(controller.head, segments)
		var angle: float = head_dir.angle()
		# 头部：圆润的椭圆
		var points: PackedVector2Array = []
		var seg_count: int = 16
		for i: int in range(seg_count):
			var a: float = TAU * i / seg_count
			var rx: float = controller.head.radius * 0.9
			var ry: float = controller.head.radius * 1.0
			var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
			points.append(head_local + p)
		if points.size() >= 3:
			draw_colored_polygon(points, body_color)
		# 高光
		draw_circle(head_local + Vector2(cos(angle), sin(angle)) * controller.head.radius * 0.2, controller.head.radius * 0.3, body_highlight)


func _draw_soft_body(segments: Array) -> void:
	# 绘制柔软的足部：从头到尾的连续形状
	# 收集所有关节位置和朝向
	var positions: Array[Vector2] = []
	var radii: Array[float] = []
	for seg: Dictionary in segments:
		var joint: ChainJoint = seg["joint"]
		positions.append(to_local(joint.global_position))
		# 从尾到头逐渐变细
		var r: float = joint.radius
		if seg["type"] == "shell_base":
			r *= 1.2
		elif seg["type"] == "head":
			r *= 0.8
		radii.append(r)

	if positions.size() < 2:
		return

	# 构建上下轮廓
	var upper: PackedVector2Array = []
	var lower: PackedVector2Array = []

	for i: int in range(positions.size()):
		var pos: Vector2 = positions[i]
		var r: float = radii[i]
		# 计算切线方向
		var tangent: Vector2
		if i == 0:
			tangent = (positions[1] - pos).normalized()
		elif i == positions.size() - 1:
			tangent = (pos - positions[i - 1]).normalized()
		else:
			tangent = (positions[i + 1] - positions[i - 1]).normalized()
		var normal: Vector2 = tangent.rotated(PI * 0.5)
		upper.append(pos + normal * r)
		lower.append(pos - normal * r)

	# 合并为闭合多边形
	var polygon: PackedVector2Array = []
	for p: Vector2 in upper:
		polygon.append(p)
	for i: int in range(lower.size() - 1, -1, -1):
		polygon.append(lower[i])

	if polygon.size() >= 3:
		draw_colored_polygon(polygon, body_color)

	# 腹部高光线（沿身体中线）
	for i: int in range(positions.size() - 1):
		draw_line(positions[i], positions[i + 1], body_highlight, 1.0)


# ===================== 壳绘制 =====================

func _draw_shell() -> void:
	if not controller.shell:
		return
	var shell_local: Vector2 = to_local(controller.shell.global_position)
	var shell_dir: Vector2
	if controller.body:
		shell_dir = (controller.shell.global_position - controller.body.global_position).normalized()
	else:
		shell_dir = controller.body_forward
	var angle: float = shell_dir.angle()

	var base_radius: float = controller.shell.radius * 1.8

	# 壳主体：大椭圆（螺塔）
	var body_points: PackedVector2Array = []
	var body_steps: int = 24
	for i: int in range(body_steps):
		var a: float = TAU * i / body_steps
		var rx: float = base_radius
		var ry: float = base_radius * 0.9
		body_points.append(shell_local + Vector2(cos(a) * rx, sin(a) * ry).rotated(angle))
	if body_points.size() >= 3:
		draw_colored_polygon(body_points, shell_color)

	# 螺旋线：从中心向外螺旋2.5圈
	var spiral_steps: int = 60
	var max_r: float = base_radius * 0.85
	var turns: float = 2.5
	var prev: Vector2
	for i: int in range(spiral_steps + 1):
		var t: float = float(i) / float(spiral_steps)
		var r: float = max_r * t
		var a: float = angle - PI * 0.5 + t * turns * TAU  # 从朝后方向开始顺时针绕
		var pt: Vector2 = shell_local + Vector2(cos(a), sin(a)) * r
		if i > 0:
			draw_line(prev, pt, shell_stripe, 1.5 * (1.0 - t * 0.5))
		prev = pt

	# 壳口（开口朝前，与身体连接处）
	var opening_center: Vector2 = shell_local - shell_dir * base_radius * 0.3
	var opening_points: PackedVector2Array = []
	var opening_steps: int = 12
	for i: int in range(opening_steps + 1):
		var a: float = angle + PI * 0.5 + float(i) / float(opening_steps) * PI
		var r: float = base_radius * 0.45
		opening_points.append(opening_center + Vector2(cos(a), sin(a)) * r)
	if opening_points.size() >= 3:
		draw_colored_polygon(opening_points, shell_highlight)

	# 壳高光
	draw_circle(shell_local + shell_dir * base_radius * 0.25, base_radius * 0.2, shell_highlight)


# ===================== 触角绘制 =====================

func _draw_tentacles() -> void:
	for tentacle_data: SnailController.TentacleData in controller.tentacles:
		if not tentacle_data.base or not tentacle_data.tip:
			continue

		var points: PackedVector2Array = []
		points.append(to_local(tentacle_data.base.global_position))
		for segment: JointBone in tentacle_data.segments:
			if segment:
				points.append(to_local(segment.global_position))
		points.append(to_local(tentacle_data.tip.global_position))

		if points.size() < 2:
			continue

		# 绘制触角 — 从粗到细
		for i: int in range(points.size() - 1):
			var width: float = 2.0 * (1.0 - float(i) / float(points.size()))
			draw_line(points[i], points[i + 1], tentacle_color, maxf(width, 0.8))

		# 长触角末端：眼睛
		if tentacle_data.is_long:
			var tip_pos: Vector2 = points[points.size() - 1]
			# 眼球
			draw_circle(tip_pos, 2.0, body_shadow)
			draw_circle(tip_pos, 1.5, eye_color)
			# 高光
			draw_circle(tip_pos + Vector2(-0.4, -0.4), 0.5, Color.WHITE)
		else:
			# 短触角末端：小圆点
			var tip_pos: Vector2 = points[points.size() - 1]
			draw_circle(tip_pos, 1.2, tentacle_color)


# ===================== 辅助 =====================

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
