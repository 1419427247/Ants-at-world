class_name SpiderController extends Node2D
## 蜘蛛控制器 — 基于交替四足步态（Alternating Tetrapod Gait）
##
## 生物力学参考：
## - 蜘蛛使用交替四足步态，任一时刻4条腿着地保证稳定
## - 占空比(duty factor)约0.68，即每条腿68%时间在地面支撑
## - 步态呈后向波浪：后腿先迈步，前腿后迈步（4→3→1→2序列）
## - 腿1、2主要拉身体前进，腿3、4主要推身体前进
## - 速度越快占空比越低，高速时甚至出现短暂腾空相
## - 摆动相轨迹为贝塞尔弧线，向外侧+前方抬起

# ===================== 脊柱关节 =====================
@export var head_anchor: ChainJoint
@export var cephalothorax: ChainJoint
@export var abdomen: ChainJoint

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
	var phase_offset: float      # 相位偏移，控制迈步时序
	var stepping: bool
	var step_progress: float
	var step_start: Vector2
	var step_mid: Vector2        # 贝塞尔曲线控制点
	var step_end: Vector2
	var error_distance: float
	var stance_time: float       # 支撑相持续时间

var legs: Array[LegData] = []

# ===================== 运动状态 =====================
var move_speed: float = 100.0
var body_forward: Vector2 = Vector2.RIGHT
var _smoothed_forward: Vector2 = Vector2.RIGHT
var _body_velocity: Vector2 = Vector2.ZERO
var _last_head_anchor_pos: Vector2 = Vector2.ZERO
var _velocity_initialized: bool = false

# ===================== 步态参数 =====================
var _gait_phase: float = 0.0          # 全局步态相位 [0, 1)
var _duty_factor: float = 0.68         # 占空比：蜘蛛典型值~0.68
var _stride_length: float = 35.0       # 步幅长度（像素）


func _ready() -> void:
	_init_legs()


func _process(delta: float) -> void:
	_update_head_movement(delta)
	_update_hip_positions()
	_update_gait(delta)


# ===================== 初始化腿部 =====================

func _init_legs() -> void:
	# 腿部配置: [路径, 附着关节, 附着偏移, 静止前向, 静止侧向, 相位偏移]
	# 交替四足步态：A组(L1+R2+L3+R4) 和 B组(R1+L2+R3+L4) 交替迈步
	# 组内用微小相位偏移制造后向波浪（4→3→1→2序列）
	# 后腿偏移最大（先进入摆动窗），前腿偏移最小
	var leg_configs: Array = [
		# A组 — 在全局相位~0.68进入摆动相
		[$"Spine/Cephalothorax/Leg1L", cephalothorax, Vector2(12, -12), 14.0, -28.0, 0.03],
		[$"Spine/Cephalothorax/Leg2R", cephalothorax, Vector2(4, 14), 4.0, 30.0, 0.00],
		[$"Spine/Cephalothorax/Leg3L", cephalothorax, Vector2(-4, -14), -4.0, -30.0, 0.06],
		[$"Spine/Cephalothorax/Leg4R", cephalothorax, Vector2(-12, 12), -14.0, 28.0, 0.09],
		# B组 — 在全局相位~0.18进入摆动相
		[$"Spine/Cephalothorax/Leg1R", cephalothorax, Vector2(12, 12), 14.0, 28.0, 0.53],
		[$"Spine/Cephalothorax/Leg2L", cephalothorax, Vector2(4, -14), 4.0, -30.0, 0.50],
		[$"Spine/Cephalothorax/Leg3R", cephalothorax, Vector2(-4, 14), -4.0, 30.0, 0.56],
		[$"Spine/Cephalothorax/Leg4L", cephalothorax, Vector2(-12, -12), -14.0, -28.0, 0.59],
	]

	for config: Array in leg_configs:
		var leg_data: LegData = LegData.new()
		leg_data.body_attachment = config[1] as ChainJoint
		leg_data.attach_offset = config[2] as Vector2
		leg_data.rest_forward = config[3] as float
		leg_data.rest_side = config[4] as float
		leg_data.phase_offset = config[5] as float
		leg_data.stepping = false
		leg_data.step_progress = 0.0
		leg_data.stance_time = 0.0

		var leg_root: Node = config[0]
		leg_data.hip = leg_root.get_node("Hip") as JointBone
		leg_data.knee = leg_root.get_node("Hip/Knee") as JointBone
		leg_data.foot = leg_root.get_node("Hip/Knee/Foot") as JointBone
		var leg_name: String = leg_root.name
		leg_data.ik_controller = get_node("IKTargets/" + leg_name + "Target") as IKController

		# 初始化脚部目标到静止位置
		var init_right: Vector2 = body_forward.rotated(PI * 0.5)
		var init_rest: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + init_right * leg_data.rest_side
		leg_data.ik_controller.global_position = init_rest

		legs.append(leg_data)


# ===================== 头部移动 =====================

func _update_head_movement(delta: float) -> void:
	var mouse_position: Vector2 = get_global_mouse_position()
	var direction: Vector2 = mouse_position - head_anchor.global_position
	var distance: float = direction.length()

	if distance > 1.0:
		var move_distance: float = minf(distance, move_speed * delta)
		head_anchor.global_position += direction.normalized() * move_distance

	# 估算身体速度
	if _velocity_initialized and delta > 0.0:
		var instant_velocity: Vector2 = (head_anchor.global_position - _last_head_anchor_pos) / delta
		_body_velocity = _body_velocity.lerp(instant_velocity, minf(1.0, delta * 14.0))
	_last_head_anchor_pos = head_anchor.global_position
	_velocity_initialized = true

	# 更新身体朝向
	var spine_dir: Vector2 = Vector2.ZERO
	if cephalothorax and abdomen:
		spine_dir = cephalothorax.global_position - abdomen.global_position
	if spine_dir.length() > 0.1:
		var target_forward: Vector2 = spine_dir.normalized()
		_smoothed_forward = _smoothed_forward.lerp(target_forward, delta * 12.0).normalized()
		body_forward = _smoothed_forward


# ===================== 髋部定位 =====================

func _update_hip_positions() -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)
	for leg_data: LegData in legs:
		var attachment: ChainJoint = leg_data.body_attachment
		var hip_forward: float = leg_data.attach_offset.x
		var hip_side: float = leg_data.attach_offset.y
		leg_data.hip.global_position = attachment.global_position + body_forward * hip_forward + body_right * hip_side


# ===================== 步态算法（交替四足步态 + 后向波浪） =====================
# 基于连续步态相位驱动，每条腿有独立相位偏移
# 占空比0.68：每条腿68%时间在地面（支撑相），32%时间在空中（摆动相）
# A组在相位~0.68进入摆动，B组在相位~0.18进入摆动，自然交替
# 组内后腿偏移更大，先进入摆动窗，形成4→3→1→2波浪序列

func _update_gait(delta: float) -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)
	var body_speed: float = _body_velocity.length()

	# 推进步态相位（与身体速度成正比，静止时不推进）
	if body_speed > 1.0:
		_gait_phase += body_speed * delta / _stride_length
		_gait_phase = fmod(_gait_phase, 1.0)

	for leg_data: LegData in legs:
		_update_single_leg(leg_data, delta, body_right, body_speed)


func _update_single_leg(leg_data: LegData, delta: float, body_right: Vector2, body_speed: float) -> void:
	var rest_position: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + body_right * leg_data.rest_side

	if leg_data.stepping:
		_update_swing(leg_data, delta, body_speed)
	else:
		# 支撑相：脚固定在地面
		leg_data.stance_time += delta

		# 计算误差
		var desired_offset: Vector2 = body_forward * leg_data.rest_forward + body_right * leg_data.rest_side
		var actual_offset: Vector2 = leg_data.ik_controller.global_position - leg_data.hip.global_position
		leg_data.error_distance = (actual_offset - desired_offset).length()

		# 相位驱动：检查是否进入摆动窗
		var local_phase: float = fmod(_gait_phase + leg_data.phase_offset, 1.0)
		var in_swing_window: bool = local_phase >= _duty_factor
		var rhythm_trigger: bool = in_swing_window and body_speed > 2.0 and leg_data.stance_time > 0.1

		# 误差驱动：误差过大时触发
		var error_trigger: bool = leg_data.error_distance > 20.0

		# 紧急触发：误差极大时强制迈步
		var emergency_trigger: bool = leg_data.error_distance > 32.0

		if emergency_trigger or rhythm_trigger or error_trigger:
			_start_step(leg_data, rest_position, body_right, body_speed)


func _start_step(leg_data: LegData, rest_position: Vector2, body_right: Vector2, body_speed: float) -> void:
	leg_data.stepping = true
	leg_data.step_progress = 0.0
	leg_data.stance_time = 0.0
	leg_data.step_start = leg_data.ik_controller.global_position

	# 预测落点：沿身体速度方向前移
	var step_speed: float = 16.0 + body_speed * 0.12
	var step_duration: float = 1.0 / maxf(step_speed, 1.0)
	var predicted_move: Vector2 = _body_velocity * step_duration
	leg_data.step_end = rest_position + predicted_move

	# 贝塞尔曲线控制点：向外侧+前方抬起
	var side_sign: float = 1.0 if leg_data.rest_side > 0 else -1.0
	var lift_height: float = 14.0 + minf(body_speed * 0.08, 8.0)
	# 抬起方向：偏向外侧 + 偏向前方
	var lift_dir: Vector2 = (body_right * side_sign * 0.6 + body_forward * 0.4).normalized()
	leg_data.step_mid = (leg_data.step_start + leg_data.step_end) * 0.5 + lift_dir * lift_height


func _update_swing(leg_data: LegData, delta: float, body_speed: float) -> void:
	# 摆动相：贝塞尔曲线弧线
	var step_speed: float = 16.0 + body_speed * 0.12
	leg_data.step_progress = minf(1.0, leg_data.step_progress + delta * step_speed)
	var t: float = leg_data.step_progress

	# 二次贝塞尔曲线: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
	var u: float = 1.0 - t
	var pos: Vector2 = leg_data.step_start * (u * u) + leg_data.step_mid * (2 * u * t) + leg_data.step_end * (t * t)
	leg_data.ik_controller.global_position = pos

	if leg_data.step_progress >= 1.0:
		leg_data.stepping = false
		leg_data.ik_controller.global_position = leg_data.step_end
