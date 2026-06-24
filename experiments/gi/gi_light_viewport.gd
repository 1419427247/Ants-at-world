class_name GILightViewport extends SubViewport

@export var main_camera: Camera2D

var camera: Camera2D = Camera2D.new()
# Called when the node enters the scene tree for the first time.

func _init() -> void:
	add_child(camera)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	camera.global_transform = main_camera.global_transform
