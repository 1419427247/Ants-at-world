@tool
@abstract
class_name IKTarget extends Marker2D

## 目标要驱动的 IKRoot
@export var ik_root: IKRoot

func _ready() -> void:
	await get_tree().process_frame
	_setup_modification()

@abstract func _setup_modification() -> void
