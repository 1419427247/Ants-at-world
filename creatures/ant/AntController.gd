class_name AntController extends Node2D
## 蚂蚁控制器 — 引用场景中的 ChainJoint 节点，处理移动和步态

# ===================== 脊柱关节 =====================
@export_node_path("ChainJoint") var head_anchor_path: NodePath
@export_node_path("ChainJoint") var head_path: NodePath
@export_node_path("ChainJoint") var thorax_path: NodePath
@export_node_path("ChainJoint") var petiole_path: NodePath
@export_node_path("ChainJoint") var abdomen_first_path: NodePath

var head_anchor: ChainJoint
var head: ChainJoint
var thorax: ChainJoint
var petiole: ChainJoint
var abdomen_first: ChainJoint

# ===================== 腿部数据 =====================
class LegData extends RefCounted:
	var hip: IKChain
	var knee: IKChain
	var foot: IKChain
	var foot_target: Node2D
	var ik_chain: IKChain
	var body_attachment: ChainJoint
	var attach_offset: Vector2
	var rest_forward: float
	var rest_side: float
	var gait_group: int
	var stepping: bool
	var step_progress: float
	var step_start: Vector2
	var step_end: Vector2
	var error_distance: float

var legs: Array[LegData] = []

# ===================== 触角数据 =====================
class AntennaData extends RefCounted:
	var base: IKChain
	var segments: Array[IKChain] = []
	var tip: IKChain
	var tip_target: Node2D
	var ik_chain: IKChain
	var side: float

var antennae: Array[AntennaData] = []

# ===================== 运动状态 =====================
var move_speed: float = 100.0
var body_forward: Vector2 = Vector2.RIGHT
var _smoothed_forward: Vector2 = Vector2.RIGHT
var group_a_stepping: bool = false
var group_b_stepping: bool = false
var _body_velocity: Vector2 = Vector2.ZERO
var _last_head_anchor_pos: Vector2 = Vector2.ZERO
var _velocity_initialized: bool = false
var _stride_accumulator: float = 0.0
var _stride_length: float = 16.0
var _next_gait_group: int = 0


func _ready() -> void:
	_resolve_spine_references()
	_init_legs()
	_init_antennae()


func _resolve_spine_references() -> void:
	if head_anchor_path:
		head_anchor = get_node(head_anchor_path) as ChainJoint
	if head_path:
		head = get_node(head_path) as ChainJoint
	if thorax_path:
		thorax = get_node(thorax_path) as ChainJoint
	if petiole_path:
		petiole = get_node(petiole_path) as ChainJoint
	if abdomen_first_path:
		abdomen_first = get_node(abdomen_first_path) as ChainJoint


func _process(delta: float) -> void:
	_update_head_movement(delta)
	_update_hip_positions()
	_update_gait(delta)
	_update_antenna_targets(delta)


# ===================== 初始化腿部 =====================

func _init_legs() -> void:
	# 腿部配置: [路径, 附着关节, 附着偏移, 静止前向, 静止侧向, 步态组]
	var leg_configs: Array = [
		# [路径, 附着关节, 髋部偏移, 静止前向, 静止侧向, 步态组]
		# 三角步态：A组=FL+MR+BL，B组=FR+ML+BR
		["IKRoot/LegFL", thorax, Vector2(5, -8), 10.0, -18.0, 0],
		["IKRoot/LegFR", thorax, Vector2(5, 8), 10.0, 18.0, 1],
		["IKRoot/LegML", thorax, Vector2(-2, -10), 0.0, -20.0, 1],
		["IKRoot/LegMR", thorax, Vector2(-2, 10), 0.0, 20.0, 0],
		["IKRoot/LegBL", petiole, Vector2(-8, -8), -10.0, -18.0, 0],
		["IKRoot/LegBR", petiole, Vector2(-8, 8), -10.0, 18.0, 1],
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

		var leg_root: Node = get_node(config[0] as String)
		leg_data.hip = leg_root.get_node("Hip") as IKChain
		leg_data.knee = leg_root.get_node("Hip/Knee") as IKChain
		leg_data.foot = leg_root.get_node("Hip/Knee/Foot") as IKChain
		var leg_name: String = leg_root.name
		leg_data.foot_target = get_node("IKTargets/" + leg_name + "Target") as Node2D
		leg_data.ik_chain = leg_root as IKChain

		# 初始化脚部目标到静止位置
		var init_right: Vector2 = body_forward.rotated(PI * 0.5)
		var init_rest: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + init_right * leg_data.rest_side
		leg_data.foot_target.global_position = init_rest

		legs.append(leg_data)


# ===================== 初始化触角 =====================

func _init_antennae() -> void:
	var antenna_configs: Array = [
		["AntennaIKRoot/AntennaL", -1.0],
		["AntennaIKRoot/AntennaR", 1.0],
	]

	for config: Array in antenna_configs:
		var antenna_data: AntennaData = AntennaData.new()
		antenna_data.side = config[1] as float

		var antenna_root: Node = get_node(config[0] as String)
		antenna_data.base = antenna_root.get_node("Base") as IKChain
		antenna_data.segments.append(antenna_root.get_node("Base/Seg1") as IKChain)
		antenna_data.segments.append(antenna_root.get_node("Base/Seg1/Seg2") as IKChain)
		antenna_data.segments.append(antenna_root.get_node("Base/Seg1/Seg2/Seg3") as IKChain)
		antenna_data.tip = antenna_root.get_node("Base/Seg1/Seg2/Seg3/Tip") as IKChain
		var antenna_name: String = antenna_root.name
		antenna_data.tip_target = get_node("IKTargets/" + antenna_name + "Target") as Node2D
		antenna_data.ik_chain = antenna_root as IKChain

		antennae.append(antenna_data)


# ===================== 头部移动 =====================

func _update_head_movement(delta: float) -> void:
	var mouse_position: Vector2 = get_global_mouse_position()
	var direction: Vector2 = mouse_position - head_anchor.global_position
	var distance: float = direction.length()

	if distance > 1.0:
		var move_distance: float = minf(distance, move_speed * delta)
		head_anchor.global_position += direction.normalized() * move_distance

	# 估算身体速度（平滑后供步态预测使用）
	if _velocity_initialized and delta > 0.0:
		var instant_velocity: Vector2 = (head_anchor.global_position - _last_head_anchor_pos) / delta
		_body_velocity = _body_velocity.lerp(instant_velocity, minf(1.0, delta * 10.0))
	_last_head_anchor_pos = head_anchor.global_position
	_velocity_initialized = true

	# 更新身体朝向：用整条脊柱的平均方向，并平滑过渡
	var spine_dir: Vector2 = Vector2.ZERO
	var spine_count: int = 0
	if head and thorax:
		spine_dir += head.global_position - thorax.global_position
		spine_count += 1
	if thorax and petiole:
		spine_dir += thorax.global_position - petiole.global_position
		spine_count += 1
	if spine_count > 0:
		spine_dir /= spine_count
		if spine_dir.length() > 0.1:
			var target_forward: Vector2 = spine_dir.normalized()
			# 平滑插值，避免方向突变
			_smoothed_forward = _smoothed_forward.lerp(target_forward, delta * 8.0).normalized()
			body_forward = _smoothed_forward


# ===================== 髋部定位 =====================

func _update_hip_positions() -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)
	for leg_data: LegData in legs:
		var attachment: ChainJoint = leg_data.body_attachment
		# 髋部偏移使用身体局部坐标（x=前向, y=侧向），随身体朝向旋转
		var hip_forward: float = leg_data.attach_offset.x
		var hip_side: float = leg_data.attach_offset.y
		leg_data.hip.global_position = attachment.global_position + body_forward * hip_forward + body_right * hip_side


# ===================== 步态算法（蚂蚁三角步态） =====================
# 蚂蚁使用三角步态：FL+MR+BL 一组，FR+ML+BR 另一组，交替迈步
# 支撑腿固定在地面推动身体前进，摆动腿抬起向前迈步

func _update_gait(delta: float) -> void:
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)

	# 用身体整体移动距离驱动步态节奏，保证所有腿（含后腿）规律迈步
	# 后腿挂在 petiole 上，脊柱链式跟随会衰减位移，单靠髋部误差后腿几乎不触发
	_stride_accumulator += _body_velocity.length() * delta

	# 更新各组迈步状态
	group_a_stepping = false
	group_b_stepping = false
	for leg_data: LegData in legs:
		if leg_data.stepping:
			if leg_data.gait_group == 0:
				group_a_stepping = true
			else:
				group_b_stepping = true

	# 两组都空闲且身体已移动一个步幅，强制触发下一组迈步（A/B 交替）
	var force_group: int = -1
	if not group_a_stepping and not group_b_stepping and _stride_accumulator >= _stride_length:
		_stride_accumulator -= _stride_length
		force_group = _next_gait_group
		_next_gait_group = 1 if _next_gait_group == 0 else 0

	for leg_data: LegData in legs:
		_update_single_leg(leg_data, delta, body_right, force_group)


func _update_single_leg(leg_data: LegData, delta: float, body_right: Vector2, force_group: int) -> void:
	# 目标落脚位置（相对当前身体朝向）
	var rest_position: Vector2 = leg_data.hip.global_position + body_forward * leg_data.rest_forward + body_right * leg_data.rest_side

	if leg_data.stepping:
		# 摆动相：抬起腿，沿弧线向前迈步
		# 步速随该腿自身误差距离调整，误差越大步越快
		var step_speed: float = 14.0 + minf(leg_data.error_distance, 30.0) * 0.5
		leg_data.step_progress = minf(1.0, leg_data.step_progress + delta * step_speed)
		var progress: float = leg_data.step_progress

		# 弧线：中间向外侧凸起，模拟抬腿（俯视图）
		var arc_height: float = sin(progress * PI) * 8.0
		var side_sign: float = 1.0 if leg_data.rest_side > 0 else -1.0

		# 落点在迈步开始时已锁定，不再每帧跟随身体，避免"腿追着身体走"
		var step_pos: Vector2 = lerp(leg_data.step_start, leg_data.step_end, progress)
		leg_data.foot_target.global_position = step_pos + body_right * side_sign * arc_height

		if leg_data.step_progress >= 1.0:
			leg_data.stepping = false
			leg_data.foot_target.global_position = leg_data.step_end
	else:
		# 支撑相：脚完全固定在地面，绝对不移动
		# 计算脚相对髋部的实际偏移与理想偏移的误差
		var desired_offset: Vector2 = body_forward * leg_data.rest_forward + body_right * leg_data.rest_side
		var actual_offset: Vector2 = leg_data.foot_target.global_position - leg_data.hip.global_position
		var offset_error: Vector2 = actual_offset - desired_offset
		leg_data.error_distance = offset_error.length()

		# 误差过大时触发迈步（无论方向——前进、后退、转向都能触发）
		var step_threshold: float = 10.0
		var other_group_stepping: bool = group_b_stepping if leg_data.gait_group == 0 else group_a_stepping

		# 触发条件：误差过大，或被步态节奏强制触发（保证后腿也规律迈步）
		var error_trigger: bool = leg_data.error_distance > step_threshold
		var rhythm_trigger: bool = force_group == leg_data.gait_group
		if (error_trigger or rhythm_trigger) and not other_group_stepping:
			leg_data.stepping = true
			leg_data.step_progress = 0.0
			leg_data.step_start = leg_data.foot_target.global_position
			# 预测落点：沿身体速度方向前移一段，让脚迈到身体"将要到达"的位置
			# 这样身体是追上脚，而不是脚追身体
			var step_speed: float = 14.0 + minf(leg_data.error_distance, 30.0) * 0.5
			var step_duration: float = 1.0 / maxf(step_speed, 1.0)
			var predicted_move: Vector2 = _body_velocity * step_duration
			leg_data.step_end = rest_position + predicted_move
			if leg_data.gait_group == 0:
				group_a_stepping = true
			else:
				group_b_stepping = true


# ===================== 触角目标 =====================

func _update_antenna_targets(delta: float) -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)

	for antenna_data: AntennaData in antennae:
		var side: float = antenna_data.side
		# 触角基部：头部前方两侧
		var base_offset: Vector2 = body_forward * head.radius * 0.5 + body_right * side * head.radius * 0.6
		antenna_data.base.global_position = head.global_position + base_offset

		# 触角尖端目标：向前外方伸展，带自然摆动
		var base_position: Vector2 = antenna_data.base.global_position
		# 主摆动（慢速大幅）
		var sway_primary: float = sin(time * 2.0 + side * PI * 0.5) * 5.0
		# 次摆动（快速小幅，模拟触觉探测）
		var sway_secondary: float = sin(time * 5.0 + side * PI) * 2.0
		# 垂直微抖动
		var bob: float = sin(time * 4.0 + side * 0.7) * 1.5

		var forward_dist: float = 22.0
		var side_dist: float = side * 6.0 + sway_primary + sway_secondary

		var target_position: Vector2 = base_position + body_forward * forward_dist + body_right * side_dist + body_forward.rotated(PI * 0.5).rotated(PI * 0.5) * bob
		antenna_data.tip_target.global_position = target_position
