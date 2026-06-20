@tool
class_name IKTargetPhysicalBones extends IKTarget

## 是否在 _ready 时自动查找 PhysicalBone2D 子节点
@export var auto_fetch: bool = true

var physical_bones: SkeletonModification2DPhysicalBones

func _setup_modification() -> void:
	physical_bones = SkeletonModification2DPhysicalBones.new()
	if auto_fetch:
		physical_bones.fetch_physical_bones()
	ik_root.modification_stack.add_modification(physical_bones)


## 手动填充物理骨骼列表（查找 Skeleton2D 下所有 PhysicalBone2D 子节点）
func fetch_physical_bones() -> void:
	if physical_bones:
		physical_bones.fetch_physical_bones()


## 开始物理模拟
func start_simulation(bones: Array[StringName] = []) -> void:
	if physical_bones:
		physical_bones.start_simulation(bones)


## 停止物理模拟
func stop_simulation(bones: Array[StringName] = []) -> void:
	if physical_bones:
		physical_bones.stop_simulation(bones)
