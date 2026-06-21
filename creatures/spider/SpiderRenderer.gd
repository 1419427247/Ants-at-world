class_name SpiderRenderer extends Node2D
## 蜘蛛渲染器 — 分节绘制蜘蛛身体、腿和眼睛

var controller: SpiderController

# 颜色
var body_color: Color = Color(0.15, 0.1, 0.08, 1.0)
var body_highlight: Color = Color(0.25, 0.18, 0.14, 1.0)
var body_shadow: Color = Color(0.08, 0.05, 0.03, 1.0)
var leg_color: Color = Color(0.12, 0.08, 0.05, 1.0)
var eye_color: Color = Color(0.02, 0.02, 0.02, 1.0)
var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.12)


func _ready() -> void:
	controller = get_parent().get_node("Controller") as SpiderController


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not controller:
		return
	if not controller.cephalothorax or not controller.abdomen:
		return
	_draw_shadow()
	_draw_legs()
	_draw_body_segments()


# ===================== 阴影 =====================

func _draw_shadow() -> void:
	var joints: Array[ChainJoint] = []
	if controller.abdomen:
		joints.append(controller.abdomen)
	if controller.cephalothorax:
		joints.append(controller.cephalothorax)
	for joint: ChainJoint in joints:
		var local_pos: Vector2 = to_local(joint.global_position) + Vector2(2, 3)
		draw_circle(local_pos, joint.radius + 2.0, shadow_color)


# ===================== 分节身体绘制 =====================

func _draw_body_segments() -> void:
	# 按从尾到头的顺序绘制，使头胸部覆盖在最上层
	var segments: Array = []
	if controller.abdomen:
		segments.append({"joint": controller.abdomen, "type": "abdomen"})
	if controller.cephalothorax:
		segments.append({"joint": controller.cephalothorax, "type": "cephalothorax"})

	# 绘制连接线（体节之间的窄连接）
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

		# 计算体节朝向
		var direction: Vector2 = _get_segment_direction(joint, segments)
		var angle: float = direction.angle()

		# 根据体节类型选择绘制方式
		match seg_type:
			"cephalothorax":
				_draw_cephalothorax_segment(local_pos, angle, joint.radius)
			"abdomen":
				_draw_abdomen_segment(local_pos, angle, joint.radius)

	# 绘制眼睛（蜘蛛典型特征：8只眼）
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


func _draw_cephalothorax_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 头胸部：椭圆形（前窄后宽）
	var points: PackedVector2Array = []
	var seg_count: int = 16
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.2
		var ry: float = radius * 1.0
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.2, radius * 0.3, body_highlight)


func _draw_abdomen_segment(pos: Vector2, angle: float, radius: float) -> void:
	# 腹部：大而饱满的圆形
	var points: PackedVector2Array = []
	var seg_count: int = 18
	for i: int in range(seg_count):
		var a: float = TAU * i / seg_count
		var rx: float = radius * 1.3
		var ry: float = radius * 1.1
		var p: Vector2 = Vector2(cos(a) * rx, sin(a) * ry).rotated(angle)
		points.append(pos + p)
	if points.size() >= 3:
		draw_colored_polygon(points, body_color)
	# 高光
	draw_circle(pos + Vector2(cos(angle), sin(angle)) * radius * 0.25, radius * 0.35, body_highlight)
	# 腹部斑纹（深色阴影）
	draw_circle(pos - Vector2(cos(angle), sin(angle)) * radius * 0.3, radius * 0.25, body_shadow)


func _draw_eyes() -> void:
	if not controller.cephalothorax or not controller.abdomen:
		return
	# 蜘蛛眼睛朝向：从腹部指向头胸部前方
	var head_direction: Vector2 = (controller.cephalothorax.global_position - controller.abdomen.global_position).normalized()
	var head_right: Vector2 = head_direction.rotated(PI * 0.5)
	var head_local: Vector2 = to_local(controller.cephalothorax.global_position)
	var radius: float = controller.cephalothorax.radius

	# 前排4只小眼
	var front_eye_offset_forward: float = radius * 0.85
	var front_eye_radius: float = 1.3
	var front_eye_spreads: Array[float] = [-0.6, -0.2, 0.2, 0.6]
	for spread: float in front_eye_spreads:
		var eye_pos: Vector2 = head_local + head_direction * front_eye_offset_forward + head_right * radius * spread
		draw_circle(eye_pos, front_eye_radius + 0.4, Color(0.3, 0.2, 0.15))
		draw_circle(eye_pos, front_eye_radius, eye_color)
		draw_circle(eye_pos + Vector2(-0.3, -0.3), 0.4, Color.WHITE)

	# 后排4只大眼
	var back_eye_offset_forward: float = radius * 0.45
	var back_eye_radius: float = 1.8
	var back_eye_spreads: Array[float] = [-0.7, -0.25, 0.25, 0.7]
	for spread: float in back_eye_spreads:
		var eye_pos: Vector2 = head_local + head_direction * back_eye_offset_forward + head_right * radius * spread
		draw_circle(eye_pos, back_eye_radius + 0.4, Color(0.3, 0.2, 0.15))
		draw_circle(eye_pos, back_eye_radius, eye_color)
		draw_circle(eye_pos + Vector2(-0.4, -0.4), 0.5, Color.WHITE)


# ===================== 腿部绘制 =====================

func _draw_legs() -> void:
	for leg_data: SpiderController.LegData in controller.legs:
		if not leg_data.hip or not leg_data.knee or not leg_data.foot:
			continue
		var hip_local: Vector2 = to_local(leg_data.hip.global_position)
		var knee_local: Vector2 = to_local(leg_data.knee.global_position)
		var foot_local: Vector2 = to_local(leg_data.foot.global_position)

		# 脚部阴影
		if not leg_data.stepping:
			draw_circle(foot_local + Vector2(1, 2), 2.5, shadow_color)

		# 腿部线段 — 从粗到细
		draw_line(hip_local, knee_local, leg_color, 2.8)
		draw_line(knee_local, foot_local, leg_color, 2.0)

		# 关节圆点
		draw_circle(hip_local, 2.2, body_color)
		draw_circle(knee_local, 1.7, leg_color)
		draw_circle(foot_local, 1.2, leg_color)
