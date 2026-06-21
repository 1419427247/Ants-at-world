class_name MillipedeController extends CreatureController
## 千足虫控制器 — 波浪步态（Wave Gait）
##
## 生物力学参考：
## - 千足虫使用波浪步态：腿从后向前依次迈步，形成传播波
## - 占空比高（~0.75），大部分时间大部分腿着地，非常稳定
## - 每体节左右两条腿相位差0.5（交替）
## - 相邻体节相位差小（~5%周期），形成连续波浪
## - 腿短而密，单关节（Hip→Foot），直接控制骨骼方向
## - 每体节有独立局部朝向，转弯时腿跟随身体曲线
## - 身体由细短长方形体节拼成

# ===================== 脊柱关节 =====================
@export var head: ChainJoint
@export var segment_joints: Array[ChainJoint] = []
@export var tail: ChainJoint

# ===================== 腿部数据 =====================
class LegData extends RefCounted:
	var hip: JointBone
	var foot: JointBone
	var body_attachment: ChainJoint
	var segment_index: int
	var side: float
	var phase_offset: float
	var stepping: bool
	var step_progress: float
	var step_start: Vector2
	var step_mid: Vector2
	var step_end: Vector2
	var ground_position: Vector2   # 脚在地面上的世界坐标
	var error_distance: float
	var stance_time: float

var legs: Array[LegData] = []

var _reference_leg_length: float = 0.0

# ===================== 步态参数 =====================
var _gait_phase: float = 0.0
var _duty_factor: float = 0.75
var _stride_length: float = 0.0
var _phase_per_segment: float = 0.05  # 相邻体节相位差（20段，总波宽~1.0）

# ===================== 腿部参数 =====================
var _leg_length: float = 5.0     # 脚骨骼长度
var _rest_side: float = 5.0      # 静止时脚到髋部的距离
var _hip_offset: float = 6.0     # 髋部到体节中心的距离

# 每体节的局部朝向
var _segment_forwards: Array[Vector2] = []


func _ready() -> void:
	_velocity_lerp_rate = 10.0
	_init_legs()


func _process(delta: float) -> void:
	_update_body_direction(delta)
	_update_segment_forwards()
	_update_hip_positions()
	_update_gait(delta)


# ===================== 初始化腿部（动态创建节点） =====================

func _init_legs() -> void:
	var seg_count: int = segment_joints.size()
	_segment_forwards.resize(seg_count)

	for i in range(seg_count):
		var seg_joint: ChainJoint = segment_joints[i]
		var base_phase: float = (seg_count - 1 - i) * _phase_per_segment

		# 左腿
		var leg_l: LegData = LegData.new()
		leg_l.body_attachment = seg_joint
		leg_l.segment_index = i
		leg_l.side = -1.0
		leg_l.phase_offset = base_phase
		leg_l.stepping = false
		leg_l.step_progress = 0.0
		leg_l.stance_time = 0.0

		var leg_l_node: Node2D = Node2D.new()
		leg_l_node.name = "LegL"
		seg_joint.add_child(leg_l_node)

		var hip_l: JointBone = JointBone.new()
		hip_l.name = "Hip"
		hip_l.position = Vector2(0, -_hip_offset)
		leg_l_node.add_child(hip_l)
		leg_l.hip = hip_l

		var foot_l: JointBone = JointBone.new()
		foot_l.name = "Foot"
		foot_l.position = Vector2(0, -_leg_length)
		foot_l.length = _leg_length
		hip_l.add_child(foot_l)
		leg_l.foot = foot_l

		legs.append(leg_l)

		# 右腿（相位偏移0.5）
		var leg_r: LegData = LegData.new()
		leg_r.body_attachment = seg_joint
		leg_r.segment_index = i
		leg_r.side = 1.0
		leg_r.phase_offset = fmod(base_phase + 0.5, 1.0)
		leg_r.stepping = false
		leg_r.step_progress = 0.0
		leg_r.stance_time = 0.0

		var leg_r_node: Node2D = Node2D.new()
		leg_r_node.name = "LegR"
		seg_joint.add_child(leg_r_node)

		var hip_r: JointBone = JointBone.new()
		hip_r.name = "Hip"
		hip_r.position = Vector2(0, _hip_offset)
		leg_r_node.add_child(hip_r)
		leg_r.hip = hip_r

		var foot_r: JointBone = JointBone.new()
		foot_r.name = "Foot"
		foot_r.position = Vector2(0, _leg_length)
		foot_r.length = _leg_length
		hip_r.add_child(foot_r)
		leg_r.foot = foot_r

		legs.append(leg_r)

	# 初始化脚部到静止位置
	_update_segment_forwards()
	_update_hip_positions()
	for leg_data: LegData in legs:
		var local_right: Vector2 = _segment_forwards[leg_data.segment_index].rotated(PI * 0.5)
		var rest_pos: Vector2 = leg_data.hip.global_position + local_right * _rest_side * leg_data.side
		leg_data.ground_position = rest_pos
		_set_foot_world_position(leg_data, rest_pos)

	# 计算参考骨骼长度
	var total_len: float = 0.0
	for leg_data: LegData in legs:
		total_len += leg_data.foot.length
	_reference_leg_length = total_len / legs.size()
	_stride_length = _reference_leg_length * 7.2


# ===================== 直接控制脚骨骼 =====================

func _set_foot_world_position(leg_data: LegData, world_pos: Vector2) -> void:
	# 将世界坐标转换为髋部局部坐标，设置脚骨骼方向
	var foot_local: Vector2 = leg_data.hip.to_local(world_pos)
	var length: float = leg_data.foot.length
	if foot_local.length() > 0.001:
		leg_data.foot.position = foot_local.normalized() * length
	else:
		leg_data.foot.position = Vector2(length, 0)


# ===================== 身体朝向 =====================

func _update_body_direction(delta: float) -> void:
	# 更新身体朝向
	if head and segment_joints.size() > 0:
		var first_seg: ChainJoint = segment_joints[0]
		var spine_dir: Vector2 = head.global_position - first_seg.global_position
		if spine_dir.length() > 0.1:
			var target_forward: Vector2 = spine_dir.normalized()
			_smoothed_forward = _smoothed_forward.lerp(target_forward, delta * 8.0).normalized()
			body_forward = _smoothed_forward

	_update_velocity_estimation(delta)


# ===================== 体节局部朝向 =====================

func _update_segment_forwards() -> void:
	var seg_count: int = segment_joints.size()
	for i in range(seg_count):
		var current: Vector2 = segment_joints[i].global_position
		var prev: Vector2
		if i == 0:
			prev = head.global_position if head else current
		else:
			prev = segment_joints[i - 1].global_position
		var dir: Vector2 = current - prev
		if dir.length() > 0.1:
			_segment_forwards[i] = dir.normalized()
		else:
			_segment_forwards[i] = body_forward


# ===================== 髋部定位 =====================

func _update_hip_positions() -> void:
	for leg_data: LegData in legs:
		var i: int = leg_data.segment_index
		var local_forward: Vector2 = _segment_forwards[i]
		var local_right: Vector2 = local_forward.rotated(PI * 0.5)
		leg_data.hip.global_position = leg_data.body_attachment.global_position + local_right * _hip_offset * leg_data.side


# ===================== 步态算法（波浪步态） =====================

func _update_gait(delta: float) -> void:
	var body_speed: float = _body_velocity.length()

	if body_speed > 1.0:
		_gait_phase += body_speed * delta / _stride_length
		_gait_phase = fmod(_gait_phase, 1.0)

	for leg_data: LegData in legs:
		_update_single_leg(leg_data, delta, body_speed)


func _update_single_leg(leg_data: LegData, delta: float, body_speed: float) -> void:
	var i: int = leg_data.segment_index
	var local_forward: Vector2 = _segment_forwards[i]
	var local_right: Vector2 = local_forward.rotated(PI * 0.5)
	var rest_position: Vector2 = leg_data.hip.global_position + local_right * _rest_side * leg_data.side

	if leg_data.stepping:
		# 摆动相：贝塞尔曲线
		var step_speed: float = 10.0 + body_speed * 0.1
		leg_data.step_progress = minf(1.0, leg_data.step_progress + delta * step_speed)
		var t: float = leg_data.step_progress
		var u: float = 1.0 - t
		var pos: Vector2 = leg_data.step_start * (u * u) + leg_data.step_mid * (2 * u * t) + leg_data.step_end * (t * t)
		_set_foot_world_position(leg_data, pos)

		if leg_data.step_progress >= 1.0:
			leg_data.stepping = false
			leg_data.ground_position = leg_data.step_end
			_set_foot_world_position(leg_data, leg_data.step_end)
	else:
		# 支撑相：脚固定在地面
		leg_data.stance_time += delta
		_set_foot_world_position(leg_data, leg_data.ground_position)

		# 计算误差
		leg_data.error_distance = (leg_data.ground_position - rest_position).length()

		# 相位驱动
		var local_phase: float = fmod(_gait_phase + leg_data.phase_offset, 1.0)
		var in_swing_window: bool = local_phase >= _duty_factor
		var rhythm_trigger: bool = in_swing_window and body_speed > 2.0 and leg_data.stance_time > 0.1

		# 误差驱动
		var error_trigger: bool = leg_data.error_distance > _reference_leg_length * 4.0
		var emergency_trigger: bool = leg_data.error_distance > _reference_leg_length * 6.4

		if emergency_trigger or rhythm_trigger or error_trigger:
			_start_step(leg_data, rest_position, local_right, body_speed)


func _start_step(leg_data: LegData, rest_position: Vector2, local_right: Vector2, body_speed: float) -> void:
	leg_data.stepping = true
	leg_data.step_progress = 0.0
	leg_data.stance_time = 0.0
	leg_data.step_start = leg_data.ground_position

	# 预测落点
	var step_speed: float = 10.0 + body_speed * 0.1
	var step_duration: float = 1.0 / maxf(step_speed, 1.0)
	var predicted_move: Vector2 = _body_velocity * step_duration
	leg_data.step_end = rest_position + predicted_move

	# 贝塞尔曲线控制点：向外侧抬起
	var lift_height: float = _reference_leg_length * 2.4 + minf(body_speed * 0.08, _reference_leg_length * 1.2)
	leg_data.step_mid = (leg_data.step_start + leg_data.step_end) * 0.5 + local_right * leg_data.side * lift_height
