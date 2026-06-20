@tool
class_name IKTargetJiggle extends IKTarget

## 抖动链的关节列表（按顺序排列）
@export var ik_chains: Array[IKChain]

## 是否使用重力
@export var use_gravity: bool = false

## 重力向量
@export var gravity: Vector2 = Vector2.DOWN * 98.0

## 阻尼系数（越高越倾向于保持当前速度）
@export var damping: float = 0.8

## 质量（越高运动越快、过冲越大）
@export var mass: float = 1.0

## 刚度（越高越像弹簧，快速回正）
@export var stiffness: float = 0.5

var jiggle: SkeletonModification2DJiggle

func _setup_modification() -> void:
	if ik_chains.size() < 1:
		return

	jiggle = SkeletonModification2DJiggle.new()
	jiggle.jiggle_data_chain_length = ik_chains.size()
	jiggle.use_gravity = use_gravity
	jiggle.gravity = gravity
	jiggle.damping = damping
	jiggle.mass = mass
	jiggle.stiffness = stiffness
	# 将自身（Marker2D）作为目标点
	jiggle.target_nodepath = ik_root.skeleton.get_path_to(self)

	for i: int in range(ik_chains.size()):
		var seg: IKChain = ik_chains[i]
		jiggle.set_jiggle_joint_bone2d_node(i, ik_root.skeleton.get_path_to(seg.bone))
		jiggle.set_jiggle_joint_bone_index(i, seg.bone.get_index_in_skeleton())

	ik_root.modification_stack.add_modification(jiggle)
