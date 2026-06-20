@tool
class_name IKController extends Node2D
## IK 控制器 — 手动 CCDIK 求解器
##
## 以自身 global_position 作为 IK 目标点，驱动 JointBone 链进行 CCDIK 求解。
## JointBone 模型：tip = 自身 global_position，关节 = 父骨骼 global_position。

## 骨骼链（从根部到末端，按顺序排列）
@export var joint_bones: Array[JointBone]

## 每帧最大迭代次数
@export var iterations: int = 10:
	set(v):
		iterations = maxi(1, v)

## 收敛阈值（像素）
@export var tolerance: float = 1.0:
	set(v):
		tolerance = maxf(0.0, v)

## 单次旋转上限（度），0 = 无限制
@export var max_rotation_per_step: float = 0.0:
	set(v):
		max_rotation_per_step = maxf(0.0, v)

## 是否启用
@export var enabled: bool = true

## 是否在编辑器中运行
@export var is_running_in_editor: bool

## 平滑插值速率（0 = 无平滑，值越大贴近求解结果越快/平滑感越弱，推荐 5~15）
@export var lerp_speed: float = 0.0:
	set(v):
		lerp_speed = maxf(0.0, v)

## 缓存的 CCDIK 求解目标位置（用于平滑插值）
var _target_positions: Array[Vector2] = []


func _process(delta: float) -> void:
	if not enabled:
		return
	if joint_bones.is_empty():
		return
	if not is_running_in_editor and Engine.is_editor_hint():
		return

	if lerp_speed <= 0.0:
		_solve_ccdik()
	else:
		_solve_and_smooth(delta)

	queue_redraw()


## 执行 CCDIK 求解后平滑插值到目标位置
func _solve_and_smooth(delta: float) -> void:
	# 1. 保存当前骨骼位置
	var saved: Array[Vector2] = []
	saved.resize(joint_bones.size())
	for i in range(joint_bones.size()):
		saved[i] = joint_bones[i].position

	# 2. 运行 CCDIK 求解（修改真实 bone.position 以确保迭代正确）
	_solve_ccdik()

	# 3. 保存求解后的目标位置
	_target_positions.resize(joint_bones.size())
	for i in range(joint_bones.size()):
		_target_positions[i] = joint_bones[i].position

	# 4. 恢复求解前的位置
	for i in range(joint_bones.size()):
		joint_bones[i].position = saved[i]

	# 5. 指数平滑插值到目标位置
	var weight := 1.0 - exp(-lerp_speed * delta)
	for i in range(joint_bones.size()):
		joint_bones[i].position = joint_bones[i].position.lerp(_target_positions[i], weight)

## 执行 CCDIK 求解
func _solve_ccdik() -> void:
	var target := global_position
	var tip_bone: JointBone = joint_bones[-1]
	for _i in range(iterations):
		if tip_bone.global_position.distance_to(target) <= tolerance:
			break
		# 从末端到根部逐关节求解
		for j in range(joint_bones.size() - 1, -1, -1):
			var bone: JointBone = joint_bones[j]
			_rotate_bone_toward(bone, tip_bone, target)
			_apply_constraint(bone)


## 将骨骼旋转使末端效应器朝向目标
func _rotate_bone_toward(bone: JointBone, tip_bone: JointBone, target: Vector2) -> void:
	var joint_pos := _get_joint_pos(bone)
	var end_effector := tip_bone.global_position

	# 末端效应器或目标与关节重合时无法计算有效角度
	if end_effector.is_equal_approx(joint_pos) or target.is_equal_approx(joint_pos):
		return

	var angle_to_effector := (end_effector - joint_pos).angle()
	var angle_to_target := (target - joint_pos).angle()
	var delta := angle_to_target - angle_to_effector

	# 规范化到 [-PI, PI]
	delta = wrapf(delta, -PI, PI)

	# 单步旋转限制
	if max_rotation_per_step > 0.0:
		var max_rad := deg_to_rad(max_rotation_per_step)
		delta = clampf(delta, -max_rad, max_rad)

	# 骨骼位置长度为零时无法旋转
	var bone_length := bone.position.length()
	if bone_length < 0.001:
		return

	# 应用旋转：旋转 position 方向
	var new_pos_angle := bone.position.angle() + delta
	bone.position = Vector2.from_angle(new_pos_angle) * bone_length


## 应用关节角度约束
func _apply_constraint(bone: JointBone) -> void:
	var parent_bone := bone.get_parent_bone()
	if not parent_bone:
		return

	var bone_joint_pos := _get_joint_pos(bone)
	var parent_joint_pos := _get_joint_pos(parent_bone)

	var bone_dir := (bone.global_position - bone_joint_pos).angle()
	# 父骨骼长度为零时，回退使用 global_rotation 作为参考方向
	var parent_dir: float
	if parent_bone.global_position.is_equal_approx(parent_joint_pos):
		parent_dir = parent_bone.global_rotation
	else:
		parent_dir = (parent_bone.global_position - parent_joint_pos).angle()
	var relative_angle_deg := rad_to_deg(bone_dir - parent_dir)

	# 规范化到 [-180, 180]
	relative_angle_deg = wrapf(relative_angle_deg, -180.0, 180.0)

	# 已在约束范围内则无需修正
	if relative_angle_deg >= bone.minimum_angle_degrees \
			and relative_angle_deg <= bone.maximum_angle_degrees:
		return

	# 计算到两个边界的旋转量，选择最短旋转（考虑角度环绕）
	var to_min := wrapf(bone.minimum_angle_degrees - relative_angle_deg, -180.0, 180.0)
	var to_max := wrapf(bone.maximum_angle_degrees - relative_angle_deg, -180.0, 180.0)
	var correction_deg := to_min if absf(to_min) <= absf(to_max) else to_max

	if absf(correction_deg) < 0.001:
		return

	var correction_rad := deg_to_rad(correction_deg)
	var bone_length := bone.position.length()
	if bone_length < 0.001:
		return
	var new_pos_angle := bone.position.angle() + correction_rad
	bone.position = Vector2.from_angle(new_pos_angle) * bone_length


## 获取骨骼的关节位置（旋转中心）
func _get_joint_pos(bone: JointBone) -> Vector2:
	var parent_bone := bone.get_parent_bone()
	if parent_bone:
		return parent_bone.global_position
	# 根骨骼：使用父节点的全局位置作为关节
	var parent := bone.get_parent() as Node2D
	if parent:
		return parent.global_position
	return bone.global_position


func _draw() -> void:
	if not enabled:
		return
	if not Engine.is_editor_hint():
		return
	# 绘制目标点指示器
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 0.0, 0.8))
