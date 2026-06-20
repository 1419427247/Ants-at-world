@tool
class_name ChainJoint extends Node2D
## 程序化链式关节 — 自动跟随前一个关节，支持距离缓冲和角度约束
## radius: 到前一个关节的目标距离（正向跟随的距离约束用）
## minimum_distance / maximum_distance: 距离缓冲区偏移，实际缓冲 = [minimum_distance + radius, maximum_distance + radius]
## anchored = true 时，此关节位置由外部控制（如 AntController），不参与正向跟随

@export var radius: float = 5.0
@export var minimum_distance: float = 0.0
@export var maximum_distance: float = 5.0

@export var minimum_angle_degrees: float = -90.0
@export var maximum_angle_degrees: float = 90.0

@export var interpolation_speed: float = 30.0

@export var anchored: bool = false

@export_enum("Always", "Editor Only", "Never") var debug_draw: int = 1

func _ready() -> void:
	top_level = true


func _process(delta: float) -> void:
	if not anchored:
		var previous_joint: ChainJoint = _get_previous_joint()
		if previous_joint:
			_follow_previous_joint(previous_joint, delta)

	queue_redraw()


func _get_previous_joint() -> ChainJoint:
	var parent_node: Node = get_parent()
	if not parent_node:
		return null
	# 如果是第一个子节点且父节点是 ChainJoint，跟随父节点
	if parent_node is ChainJoint and get_index() == 0:
		return parent_node as ChainJoint
	var self_index: int = get_index()
	if self_index <= 0:
		return null
	var previous_child: Node = parent_node.get_child(self_index - 1)
	if previous_child is ChainJoint:
		return previous_child
	return null


func _follow_previous_joint(previous_joint: ChainJoint, delta: float) -> void:
	var previous_position: Vector2 = previous_joint.global_position
	var offset_to_self: Vector2 = global_position - previous_position
	var current_distance: float = offset_to_self.length()

	# 缓冲区：距离在 [minimum_distance + radius, maximum_distance + radius] 内不约束
	var buffer_minimum: float = minimum_distance + previous_joint.radius + radius
	var buffer_maximum: float = maximum_distance + previous_joint.radius + radius

	if current_distance >= buffer_minimum and current_distance <= buffer_maximum:
		# 在缓冲区内，仅做角度约束
		_apply_angle_constraint(previous_joint, delta)
		return

	var direction: Vector2
	if current_distance < 0.001:
		direction = Vector2.LEFT.rotated(previous_joint.global_rotation)
	else:
		direction = offset_to_self.normalized()

	# 距离约束：超出缓冲区时拉回到边界
	var constrained_distance: float = clampf(current_distance, buffer_minimum, buffer_maximum)

	# 角度约束：相对于前一段方向
	var preceding_joint: ChainJoint = previous_joint._get_previous_joint()
	if preceding_joint:
		var previous_segment_angle: float = (previous_joint.global_position - preceding_joint.global_position).angle()
		var self_angle: float = direction.angle()
		var angle_difference: float = _angle_difference(self_angle, previous_segment_angle)
		var minimum_angle_radians: float = deg_to_rad(minimum_angle_degrees)
		var maximum_angle_radians: float = deg_to_rad(maximum_angle_degrees)
		angle_difference = clampf(angle_difference, minimum_angle_radians, maximum_angle_radians)
		direction = Vector2(cos(previous_segment_angle + angle_difference), sin(previous_segment_angle + angle_difference))

	var target_position: Vector2 = previous_position + direction * constrained_distance
	# 朝向：从自身指向前一个关节（线段指向前一个关节）
	var target_rotation: float = (-direction).angle()

	# lerp 插值
	var weight: float = minf(1.0, interpolation_speed * delta)
	global_position = lerp(global_position, target_position, weight)
	global_rotation = _lerp_angle(global_rotation, target_rotation, weight)


func _apply_angle_constraint(previous_joint: ChainJoint, delta: float) -> void:
	# 在缓冲区内，只约束角度不约束距离
	var preceding_joint: ChainJoint = previous_joint._get_previous_joint()
	if not preceding_joint:
		return

	var offset_to_self: Vector2 = global_position - previous_joint.global_position
	if offset_to_self.length() < 0.001:
		return

	var direction: Vector2 = offset_to_self.normalized()
	var previous_segment_angle: float = (previous_joint.global_position - preceding_joint.global_position).angle()
	var self_angle: float = direction.angle()
	var angle_difference: float = _angle_difference(self_angle, previous_segment_angle)
	var minimum_angle_radians: float = deg_to_rad(minimum_angle_degrees)
	var maximum_angle_radians: float = deg_to_rad(maximum_angle_degrees)

	if angle_difference < minimum_angle_radians or angle_difference > maximum_angle_radians:
		angle_difference = clampf(angle_difference, minimum_angle_radians, maximum_angle_radians)
		direction = Vector2(cos(previous_segment_angle + angle_difference), sin(previous_segment_angle + angle_difference))
		var current_distance: float = offset_to_self.length()
		var target_position: Vector2 = previous_joint.global_position + direction * current_distance
		var target_rotation: float = (-direction).angle()

		var weight: float = minf(1.0, interpolation_speed * delta)
		global_position = lerp(global_position, target_position, weight)
		global_rotation = _lerp_angle(global_rotation, target_rotation, weight)


# ===================== 工具方法 =====================

static func _angle_difference(angle_a: float, angle_b: float) -> float:
	var difference: float = angle_a - angle_b
	while difference > PI:
		difference -= TAU
	while difference < -PI:
		difference += TAU
	return difference


static func _lerp_angle(from_angle: float, to_angle: float, weight: float) -> float:
	var difference: float = _angle_difference(to_angle, from_angle)
	return from_angle + difference * weight


func _draw() -> void:
	# 0 = Always, 1 = Editor Only, 2 = Never
	if debug_draw == 2:
		return
	if debug_draw == 1 and not Engine.is_editor_hint():
		return
	# 关节圆
	draw_circle(Vector2.ZERO, radius, Color(0.3, 0.6, 0.3, 0.3))
	draw_circle(Vector2.ZERO, radius, Color(0.3, 0.6, 0.3), false, 1.0)
	# 方向线段
	draw_line(Vector2.ZERO, Vector2.RIGHT * radius, Color(0.3, 0.6, 0.3), 1.0)
