class_name BeetleController extends CreatureController
## 金龟子控制器 — 6腿IK + 三角步态，参考蚂蚁架构
## 特点：宽体、硬翅鞘、棒状触角、慢速稳健步态

# ===================== 脊柱关节 =====================
@export var head: ChainJoint
@export var thorax: ChainJoint
@export var elytra: ChainJoint

# ===================== 腿部数据 =====================
class LegData extends RefCounted:
	var hip: JointBone
	var knee: JointBone
	var foot: JointBone
	var ik_controller: IKController
	var body_attachment: ChainJoint
	var attach_offset: Vector2
	var rest_forward: float
	var rest_side: float
	var gait_group: int
	var stepping: bool
	var step_progress: float
	var step_start: Vector2
	var step_mid: Vector2
	var step_end: Vector2
	var error_distance: float
	var stance_time: float

var legs: Array[LegData] = []

# ===================== 触角数据 =====================
class AntennaData extends RefCounted:
	var base: JointBone
	var segments: Array[JointBone] = []
	var tip: JointBone
	var ik_controller: IKController
	var side: float

var antennae: Array[AntennaData] = []

# ===================== 运动状态 =====================
var group_a_stepping: bool = false
var group_b_stepping: bool = false
var _stride_accumulator: float = 0.0
var _stride_length: float = 0.0
var _next_gait_group: int = 0
var _reference_leg_length: float = 0.0


func _ready() -> void:
	_velocity_lerp_rate = 10.0
	_init_legs()
	_init_antennae()


func _process(delta: float) -> void:
	_update_body_direction(delta)
	_update_hip_positions()
	_update_gait(delta)
	_update_antenna_targets(delta)


# ===================== 初始化腿部 =====================

func _init_legs() -> void:
	# 金龟子腿配置：宽 stance，前腿短粗（挖掘），后腿长
	# 三角步态：A组=FL+MR+BL，B组=FR+ML+BR
	var leg_configs: Array = [
		[$"../Spine/Thorax/LegFL", thorax, Vector2(6, -10), 12.0, -22.0, 0],
		[$"../Spine/Thorax/LegFR", thorax, Vector2(6, 10), 12.0, 22.0, 1],
		[$"../Spine/Thorax/LegML", thorax, Vector2(-2, -12), 0.0, -24.0, 1],
		[$"../Spine/Thorax/LegMR", thorax, Vector2(-2, 12), 0.0, 24.0, 0],
		[$"../Spine/Thorax/LegBL", elytra, Vector2(-10, -10), -12.0, -22.0, 0],
		[$"../Spine/Thorax/LegBR", elytra, Vector2(-10, 10), -12.0, 22.0, 1],
	]

	for config: Array in leg_configs:
		var leg_data: LegData = LegData.new()
		leg_data.body_attachment = config[1] as ChainJoint
		leg_data.attach_offset = config[2] as Vector2
		leg_data.rest_forward = config[3] as float
		leg_data.rest_side = config[4] as float
		leg_data.gait_group = config[5] as int
		leg_data.stepping = false
		leg_data.step_progress = 0.0

		var leg_root: Node = config[0]
		leg_data.hip = leg_root.get_node("Hip") as JointBone
		leg_data.knee = leg_root.get_node("Hip/Knee") as JointBone
		leg_data.foot = leg_root.get_node("Hip/Knee/Foot") as JointBone
		var leg_name: String = leg_root.name
		leg_data.ik_controller = get_node("../IKTargets/" + leg_name + "Target") as IKController

		# 初始化脚部目标到静止位置
		var init_right: Vector2 = body_forward.rotated(PI * 0.5)
		var init_rest: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + init_right * leg_data.rest_side
		leg_data.ik_controller.global_position = init_rest

		legs.append(leg_data)

	# 计算参考骨骼长度
	var total_len: float = 0.0
	for leg_data: LegData in legs:
		total_len += leg_data.knee.length + leg_data.foot.length
	_reference_leg_length = total_len / legs.size()
	_stride_length = _reference_leg_length * 0.74


# ===================== 初始化触角 =====================

func _init_antennae() -> void:
	# 金龟子棒状触角：3段，末端膨大
	var antenna_configs: Array = [
		[$"../Spine/Head/AntennaL", -1.0],
		[$"../Spine/Head/AntennaR", 1.0],
	]

	for config: Array in antenna_configs:
		var antenna_data: AntennaData = AntennaData.new()
		antenna_data.side = config[1] as float

		var antenna_root: Node = config[0]
		antenna_data.base = antenna_root.get_node("Base") as JointBone
		antenna_data.segments.append(antenna_root.get_node("Base/Seg1") as JointBone)
		antenna_data.segments.append(antenna_root.get_node("Base/Seg1/Seg2") as JointBone)
		antenna_data.tip = antenna_root.get_node("Base/Seg1/Seg2/Tip") as JointBone
		var antenna_name: String = antenna_root.name
		antenna_data.ik_controller = get_node("../IKTargets/" + antenna_name + "Target") as IKController

		antennae.append(antenna_data)


# ===================== 身体朝向 =====================

func _update_body_direction(delta: float) -> void:
	# 更新身体朝向：用脊柱平均方向
	var spine_dir: Vector2 = Vector2.ZERO
	var spine_count: int = 0
	if head and thorax:
		spine_dir += head.global_position - thorax.global_position
		spine_count += 1
	if thorax and elytra:
		spine_dir += thorax.global_position - elytra.global_position
		spine_count += 1
	if spine_count > 0:
		spine_dir /= spine_count
		if spine_dir.length() > 0.1:
			var target_forward: Vector2 = spine_dir.normalized()
			_smoothed_forward = _smoothed_forward.lerp(target_forward, delta * 8.0).normalized()
			body_forward = _smoothed_forward

	_update_velocity_estimation(delta)


# ===================== 髋部定位 =====================

func _update_hip_positions() -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)
	for leg_data: LegData in legs:
		var attachment: ChainJoint = leg_data.body_attachment
		var hip_forward: float = leg_data.attach_offset.x
		var hip_side: float = leg_data.attach_offset.y
		leg_data.hip.global_position = attachment.global_position + body_forward * hip_forward + body_right * hip_side


# ===================== 步态算法（三角步态 + 贝塞尔弧线） =====================
# 参考蚂蚁三角步态 + 蜘蛛贝塞尔弧线

func _update_gait(delta: float) -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)
	var body_speed: float = _body_velocity.length()

	_stride_accumulator += body_speed * delta

	group_a_stepping = false
	group_b_stepping = false
	for leg_data: LegData in legs:
		if leg_data.stepping:
			if leg_data.gait_group == 0:
				group_a_stepping = true
			else:
				group_b_stepping = true

	var force_group: int = -1
	if not group_a_stepping and not group_b_stepping and _stride_accumulator >= _stride_length:
		_stride_accumulator -= _stride_length
		force_group = _next_gait_group
		_next_gait_group = 1 if _next_gait_group == 0 else 0

	for leg_data: LegData in legs:
		_update_single_leg(leg_data, delta, body_right, body_speed, force_group)


func _update_single_leg(leg_data: LegData, delta: float, body_right: Vector2, body_speed: float, force_group: int) -> void:
	var rest_position: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + body_right * leg_data.rest_side

	if leg_data.stepping:
		# 摆动相：贝塞尔曲线弧线
		var step_speed: float = 16.0 + minf(leg_data.error_distance, 30.0) * 0.4 + body_speed * 0.1
		leg_data.step_progress = minf(1.0, leg_data.step_progress + delta * step_speed)
		var t: float = 0.5 - 0.5 * cos(leg_data.step_progress * PI)  # ease-in-out

		var u: float = 1.0 - t
		var pos: Vector2 = leg_data.step_start * (u * u) + leg_data.step_mid * (2 * u * t) + leg_data.step_end * (t * t)
		leg_data.ik_controller.global_position = pos

		if leg_data.step_progress >= 1.0:
			leg_data.stepping = false
			leg_data.ik_controller.global_position = leg_data.step_end
	else:
		# 支撑相
		leg_data.stance_time += delta

		var desired_offset: Vector2 = body_forward * leg_data.rest_forward + body_right * leg_data.rest_side
		var actual_offset: Vector2 = leg_data.ik_controller.global_position - leg_data.hip.global_position
		var offset_error: Vector2 = actual_offset - desired_offset
		leg_data.error_distance = offset_error.length()

		var step_threshold: float = _reference_leg_length * 0.42
		var emergency_threshold: float = _reference_leg_length * 1.16
		var other_group_stepping: bool = group_b_stepping if leg_data.gait_group == 0 else group_a_stepping

		var error_trigger: bool = leg_data.error_distance > step_threshold and leg_data.stance_time > 0.15
		var rhythm_trigger: bool = force_group == leg_data.gait_group
		var emergency_trigger: bool = leg_data.error_distance > emergency_threshold and leg_data.stance_time > 0.05
		if (emergency_trigger) or ((error_trigger or rhythm_trigger) and not other_group_stepping):
			_start_step(leg_data, rest_position, body_right, body_speed)


func _start_step(leg_data: LegData, rest_position: Vector2, body_right: Vector2, body_speed: float) -> void:
	leg_data.stepping = true
	leg_data.step_progress = 0.0
	leg_data.stance_time = 0.0
	leg_data.step_start = leg_data.ik_controller.global_position

	var step_speed: float = 16.0 + minf(leg_data.error_distance, 30.0) * 0.4 + body_speed * 0.1
	var step_duration: float = 1.0 / maxf(step_speed, 1.0)
	var predicted_move: Vector2 = _body_velocity * step_duration
	leg_data.step_end = rest_position + predicted_move

	# 贝塞尔控制点：向外侧+前方抬起，高度随速度增加
	var side_sign: float = 1.0 if leg_data.rest_side > 0 else -1.0
	var lift_height: float = _reference_leg_length * 0.63 + minf(body_speed * 0.1, _reference_leg_length * 0.32)
	var lift_dir: Vector2 = (body_right * side_sign * 0.7 + body_forward * 0.3).normalized()
	leg_data.step_mid = (leg_data.step_start + leg_data.step_end) * 0.5 + lift_dir * lift_height


# ===================== 触角目标 =====================

func _update_antenna_targets(delta: float) -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)

	for antenna_data: AntennaData in antennae:
		var side: float = antenna_data.side
		# 触角基部：头部前方两侧
		var base_offset: Vector2 = body_forward * head.radius * 0.5 + body_right * side * head.radius * 0.6
		antenna_data.base.global_position = head.global_position + base_offset

		# 棒状触角：较短，末端膨大，摆动幅度小
		var base_position: Vector2 = antenna_data.base.global_position
		var sway_primary: float = sin(time * 1.5 + side * PI * 0.5) * 3.0
		var sway_secondary: float = sin(time * 4.0 + side * PI) * 1.0

		var forward_dist: float = 16.0
		var side_dist: float = side * 4.0 + sway_primary + sway_secondary

		var target_position: Vector2 = base_position + body_forward * forward_dist + body_right * side_dist
		antenna_data.ik_controller.global_position = target_position
