@tool
class_name IKRoot extends Node2D
## IK 反向动力学根节点 — 管理一个 Skeleton2D，协调所有子 IKChain 的求解
##
## 将此节点放在所有 IKChain 的共同祖先位置。
## IKRoot 自动发现所有 IKChain 后代节点，为它们创建 Bone2D 骨骼，
## 使用 Godot 内置的 CCDIK 修改器求解 IK。

var skeleton: Skeleton2D = Skeleton2D.new()
var modification_stack: SkeletonModificationStack2D = SkeletonModificationStack2D.new()

func _init() -> void:
	modification_stack.enabled = true
	skeleton.set_modification_stack(modification_stack)
	add_child(skeleton)

func _ready() -> void:
	# 递归将每个 IKChain 的 bone 按层级挂入 skeleton
	for child: Node in get_children():
		if child is IKChain:
			_mount_chain_recursive(child, skeleton)

func _mount_chain_recursive(chain: IKChain, parent_node: Node2D) -> void:
	var seg_bone: Bone2D = chain.bone
	seg_bone.name = chain.name
	seg_bone.transform = chain.transform
	seg_bone.rest = transform
	# 先添加到父节点，再设置全局变换
	parent_node.add_child(seg_bone)
	# 使用 global_transform 确保位置正确，无论父节点有何变换
	#seg_bone.global_transform = chain.global_transform
	for child: IKChain in chain.get_children():
		if child is IKChain:
			_mount_chain_recursive(child, seg_bone)
