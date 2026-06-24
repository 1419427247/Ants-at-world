class_name GIElement extends Node2D

@export var gi_light_viewport :GILightViewport

var _children: Array[Node2D]

func _ready() -> void:
	_children.assign(get_children())
	for child: Node2D in get_children():
		child.reparent(gi_light_viewport,true)

func _process(delta: float) -> void:
	for child: Node2D in _children:
		child.global_position = global_position
		child.global_rotation = global_rotation
