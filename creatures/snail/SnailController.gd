class_name SnailController extends CreatureController
## 蜗牛控制器 — 无腿滑行 + 4触角 + 螺旋壳
## 特点：极慢移动、身体柔软跟随、触角探测摆动

# ===================== 脊柱关节 =====================
@export var head: ChainJoint
@export var body: ChainJoint
@export var shell: ChainJoint

# ===================== 触角数据 =====================
class TentacleData extends RefCounted:
	var base: JointBone
	var segments: Array[JointBone] = []
	var tip: JointBone
	var ik_controller: IKController
	var side: float
	var is_long: bool  # 长触角（有眼）还是短触角

var tentacles: Array[TentacleData] = []
var _reference_size: float = 0.0


func _ready() -> void:
	_velocity_lerp_rate = 6.0
	_init_tentacles()


func _process(delta: float) -> void:
	_update_body_direction(delta)
	_update_tentacle_targets(delta)


# ===================== 初始化触角 =====================

func _init_tentacles() -> void:
	# 4条触角：2长（有眼）+ 2短
	# 长触角3段，短触角2段
	var tentacle_configs: Array = [
		[$"../Spine/Head/TentacleLL", -1.0, true],   # 左长触角
		[$"../Spine/Head/TentacleLR", -1.0, false],  # 左短触角
		[$"../Spine/Head/TentacleRL", 1.0, false],   # 右短触角
		[$"../Spine/Head/TentacleRR", 1.0, true],    # 右长触角
	]

	for config: Array in tentacle_configs:
		var tentacle_data: TentacleData = TentacleData.new()
		tentacle_data.side = config[1] as float
		tentacle_data.is_long = config[2] as bool

		var tentacle_root: Node = config[0]
		tentacle_data.base = tentacle_root.get_node("Base") as JointBone
		tentacle_data.segments.append(tentacle_root.get_node("Base/Seg1") as JointBone)
		if tentacle_data.is_long:
			tentacle_data.segments.append(tentacle_root.get_node("Base/Seg1/Seg2") as JointBone)
			tentacle_data.tip = tentacle_root.get_node("Base/Seg1/Seg2/Tip") as JointBone
		else:
			tentacle_data.tip = tentacle_root.get_node("Base/Seg1/Tip") as JointBone
		var tentacle_name: String = tentacle_root.name
		tentacle_data.ik_controller = get_node("../IKTargets/" + tentacle_name + "Target") as IKController

		tentacles.append(tentacle_data)

	# 以头部半径为参考尺寸
	_reference_size = head.radius if head else 8.0

# ===================== 身体朝向 =====================

func _update_body_direction(delta: float) -> void:
	# 更新身体朝向
	var spine_dir: Vector2 = Vector2.ZERO
	if head and body:
		spine_dir = head.global_position - body.global_position
	if spine_dir.length() > 0.1:
		var target_forward: Vector2 = spine_dir.normalized()
		_smoothed_forward = _smoothed_forward.lerp(target_forward, delta * 5.0).normalized()
		body_forward = _smoothed_forward

	_update_velocity_estimation(delta)


# ===================== 触角目标 =====================

func _update_tentacle_targets(delta: float) -> void:
	var time: float = Time.get_ticks_msec() * 0.001
	var body_right: Vector2 = body_forward.rotated(PI * 0.5)

	for tentacle_data: TentacleData in tentacles:
		var side: float = tentacle_data.side
		var is_long: bool = tentacle_data.is_long

		# 触角基部：头部前方两侧
		# 长触角更靠中间上方，短触角更靠两侧下方
		var base_forward: float = head.radius * (0.4 if is_long else 0.2)
		var base_side: float = side * head.radius * (0.4 if is_long else 0.7)
		tentacle_data.base.global_position = head.global_position + body_forward * base_forward + body_right * base_side

		# 触角尖端目标：向前伸展，带自然摆动
		var base_position: Vector2 = tentacle_data.base.global_position

		# 长触角：向前上方伸展，摆动幅度大
		# 短触角：向前下方伸展，摆动幅度小
		var forward_dist: float = _reference_size * 2.5 if is_long else _reference_size * 0.75
		var side_dist: float = side * (_reference_size * 0.38 if is_long else _reference_size * 0.63)

		# 摆动
		var sway_primary: float = sin(time * 1.5 + side * PI * 0.5) * (_reference_size * 0.5 if is_long else _reference_size * 0.25)
		var sway_secondary: float = sin(time * 3.5 + side * PI) * (_reference_size * 0.19 if is_long else _reference_size * 0.1)
		side_dist += sway_primary + sway_secondary

		# 移动时触角向前探测
		var speed_factor: float = minf(_body_velocity.length() / 30.0, 1.0)
		forward_dist += speed_factor * _reference_size * 0.38

		var target_position: Vector2 = base_position + body_forward * forward_dist + body_right * side_dist
		tentacle_data.ik_controller.global_position = target_position
