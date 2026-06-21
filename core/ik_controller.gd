@tool
class_name IKController extends Node2D
## IK 控制器 — 手动 CCDIK 求解器
##
## 以自身 global_position 作为 IK 目标点，驱动 JointBone 链进行 CCDIK 求解。
## JointBone 模型：tip = 自身 global_position，关节 = 父骨骼 global_position。

## 骨骼链（从根部到末端，按顺序排列）
@export var joint_bones: Array[JointBone]

## 每帧最大迭代次数
@export var iterations: int = 1:
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

			# 旋转骨骼使末端朝向目标（原 _rotate_bone_toward 内联）
			var joint_pos := bone.parent.global_position if bone.parent else bone.global_position
			var end_effector := tip_bone.global_position
			if not end_effector.is_equal_approx(joint_pos) and not target.is_equal_approx(joint_pos):
				var angle_to_effector := (end_effector - joint_pos).angle()
				var angle_to_target := (target - joint_pos).angle()
				var delta := angle_to_target - angle_to_effector
				delta = wrapf(delta, -PI, PI)
				if max_rotation_per_step > 0.0:
					var max_rad := deg_to_rad(max_rotation_per_step)
					delta = clampf(delta, -max_rad, max_rad)
				var bone_length := bone.position.length()
				if bone_length >= 0.001:
					var new_pos_angle := bone.position.angle() + delta
					bone.position = Vector2.from_angle(new_pos_angle) * bone_length

			# 应用关节角度约束（原 _apply_constraint 内联）
			var parent_bone := bone.parent_bone
			if parent_bone:
				var bone_joint_pos := bone.parent.global_position if bone.parent else bone.global_position
				var parent_joint_pos := parent_bone.parent.global_position if parent_bone.parent else parent_bone.global_position
				var bone_dir := (bone.global_position - bone_joint_pos).angle()
				var parent_dir: float
				if parent_bone.global_position.is_equal_approx(parent_joint_pos):
					parent_dir = parent_bone.global_rotation
				else:
					parent_dir = (parent_bone.global_position - parent_joint_pos).angle()
				var relative_angle_deg := rad_to_deg(bone_dir - parent_dir)
				relative_angle_deg = wrapf(relative_angle_deg, -180.0, 180.0)
				if not (relative_angle_deg >= bone.minimum_angle_degrees and relative_angle_deg <= bone.maximum_angle_degrees):
					var to_min := wrapf(bone.minimum_angle_degrees - relative_angle_deg, -180.0, 180.0)
					var to_max := wrapf(bone.maximum_angle_degrees - relative_angle_deg, -180.0, 180.0)
					var correction_deg := to_min if absf(to_min) <= absf(to_max) else to_max
					if absf(correction_deg) >= 0.001:
						var correction_rad := deg_to_rad(correction_deg)
						var bone_len := bone.position.length()
						if bone_len >= 0.001:
							var new_angle := bone.position.angle() + correction_rad
							bone.position = Vector2.from_angle(new_angle) * bone_len


func _draw() -> void:
	if not enabled:
		return
	#if not Engine.is_editor_hint():
		#return
	# 绘制目标点指示器
	draw_circle(Vector2.ZERO, 5.0, Color(1.0, 1.0, 0.0, 0.8))
