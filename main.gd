extends Node

@onready var emitters_and_occluders: SubViewport = $EmittersAndOccluders

func _ready() -> void:
	await RenderingServer.frame_post_draw
	print(emitters_and_occluders.get_texture().get_rid())
	
	RenderingServer.texture_2d_get()
