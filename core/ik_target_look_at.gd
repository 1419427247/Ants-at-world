@tool
class_name IKTargetLookAt extends IKTarget

## 要旋转的 Bone2D 对应的 IKChain 节点
@export var bone_chain: IKChain

## 约束设置
@export var enable_constraint: bool = false
@export var constraint_angle_invert: bool = false
@export var constraint_angle_min_degrees: float = -180.0
@export var constraint_angle_max_degrees: float = 180.0

## 额外旋转偏移（度）
@export var additional_rotation_degrees: float = 0.0

var lookat: SkeletonModification2DLookAt

func _setup_modification() -> void:
	if not bone_chain:
		return

	lookat = SkeletonModification2DLookAt.new()
	# 将自身（Marker2D）作为目标点
	lookat.target_nodepath = ik_root.skeleton.get_path_to(self)
	lookat.bone2d_node = ik_root.skeleton.get_path_to(bone_chain.bone)
	lookat.bone_index = bone_chain.bone.get_index_in_skeleton()
	lookat.set_enable_constraint(enable_constraint)
	lookat.set_constraint_angle_invert(constraint_angle_invert)
	lookat.set_constraint_angle_min(deg_to_rad(constraint_angle_min_degrees))
	lookat.set_constraint_angle_max(deg_to_rad(constraint_angle_max_degrees))
	lookat.set_additional_rotation(deg_to_rad(additional_rotation_degrees))

	ik_root.modification_stack.add_modification(lookat)
