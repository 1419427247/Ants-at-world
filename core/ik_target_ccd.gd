@tool
class_name IKTargetCCD extends IKTarget

## IK 链的末端节点
@export var ik_tip: IKChain

## IK 链的关节列表（按顺序组成 CCDIK 关节链）
@export var ik_chains: Array[IKChain]

var ccdik: SkeletonModification2DCCDIK = SkeletonModification2DCCDIK.new()

func _setup_modification() -> void:
	if ik_chains.size() < 2:
		return
	ccdik.ccdik_data_chain_length = ik_chains.size()
	# 将自身（Marker2D）作为 IK 目标点 — 路径相对于 Skeleton2D
	ccdik.target_nodepath = ik_root.skeleton.get_path_to(self)

	for i: int in range(ik_chains.size()):
		var seg: IKChain = ik_chains[i]
		# bone2d_node 必须是相对于 Skeleton2D 的路径
		ccdik.set_ccdik_joint_bone2d_node(i, ik_root.skeleton.get_path_to(seg.bone))
		ccdik.set_ccdik_joint_bone_index(i, seg.bone.get_index_in_skeleton())
		ccdik.set_ccdik_joint_enable_constraint(i, seg.enable_constraint)
		ccdik.set_ccdik_joint_constraint_angle_invert(i, seg.constraint_angle_invert)
		ccdik.set_ccdik_joint_constraint_angle_min(i, deg_to_rad(seg.minimum_angle_degrees))
		ccdik.set_ccdik_joint_constraint_angle_max(i, deg_to_rad(seg.maximum_angle_degrees))
		ccdik.set_ccdik_joint_rotate_from_joint(i, seg.rotate_from_joint)

	# tip_nodepath 也必须是相对于 Skeleton2D 的路径
	ccdik.tip_nodepath = ik_root.skeleton.get_path_to(ik_tip.bone)
	ik_root.modification_stack.add_modification(ccdik)
