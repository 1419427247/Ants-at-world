@tool
class_name IKTargetTwoBone extends IKTarget

## 第一节骨骼对应的 IKChain 节点（对应 joint_one）
@export var joint_one_chain: IKChain

## 第二节骨骼对应的 IKChain 节点（对应 joint_two）
@export var joint_two_chain: IKChain

## 目标最小距离（0 表示无限制）
@export var target_minimum_distance: float = 0.0

## 目标最大距离（0 表示无限制）
@export var target_maximum_distance: float = 0.0

## 是否翻转弯曲方向
@export var flip_bend_direction: bool = false

var twoboneik: SkeletonModification2DTwoBoneIK

func _setup_modification() -> void:
	if not joint_one_chain or not joint_two_chain:
		return
	twoboneik = SkeletonModification2DTwoBoneIK.new()
	# 将自身（Marker2D）作为 IK 目标点
	twoboneik.target_nodepath = ik_root.skeleton.get_path_to(self)
	twoboneik.set_joint_one_bone2d_node(ik_root.skeleton.get_path_to(joint_one_chain.bone))
	twoboneik.set_joint_one_bone_idx(joint_one_chain.bone.get_index_in_skeleton())
	twoboneik.set_joint_two_bone2d_node(ik_root.skeleton.get_path_to(joint_two_chain.bone))
	twoboneik.set_joint_two_bone_idx(joint_two_chain.bone.get_index_in_skeleton())
	twoboneik.target_minimum_distance = target_minimum_distance
	twoboneik.target_maximum_distance = target_maximum_distance
	twoboneik.flip_bend_direction = flip_bend_direction
	ik_root.modification_stack.add_modification(twoboneik)
