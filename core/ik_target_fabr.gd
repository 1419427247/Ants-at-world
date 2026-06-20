@tool
class_name IKTargetFABR extends IKTarget

## IK 链的末端节点
@export var ik_tip: IKChain

## IK 链的关节列表（按顺序组成 FABRIK 关节链）
@export var ik_chains: Array[IKChain]

## FABRIK 求解前的磁力偏移向量，可影响骨骼链的弯曲方向
@export var magnet: Vector2

var fabrik: SkeletonModification2DFABRIK

func _setup_modification() -> void:
	if ik_chains.size() < 2:
		return

	fabrik = SkeletonModification2DFABRIK.new()
	fabrik.fabrik_data_chain_length = ik_chains.size()
	fabrik.magnet = magnet
	# 将自身（Marker2D）作为 IK 目标点 — 路径相对于 Skeleton2D
	fabrik.target_nodepath = ik_root.skeleton.get_path_to(self)

	for i: int in range(ik_chains.size()):
		var seg: IKChain = ik_chains[i]
		# bone2d_node 必须是相对于 Skeleton2D 的路径
		fabrik.set_fabrik_joint_bone2d_node(i, ik_root.skeleton.get_path_to(seg.bone))
		fabrik.set_fabrik_joint_bone_index(i, seg.bone.get_index_in_skeleton())

	ik_root.modification_stack.add_modification(fabrik)
