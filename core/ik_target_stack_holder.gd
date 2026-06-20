@tool
class_name IKTargetStackHolder extends IKTarget

## 持有的子修改栈
@export var held_modification_stack: SkeletonModificationStack2D

var stack_holder: SkeletonModification2DStackHolder

func _setup_modification() -> void:
	if not held_modification_stack:
		push_warning("IKTargetStackHolder: held_modification_stack 为空")
		return

	stack_holder = SkeletonModification2DStackHolder.new()
	stack_holder.held_modification_stack = held_modification_stack
	ik_root.modification_stack.add_modification(stack_holder)
