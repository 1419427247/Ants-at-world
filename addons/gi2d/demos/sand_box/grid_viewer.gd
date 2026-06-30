extends TextureRect
@export var state_grid: StateGrid

#func _process(delta: float) -> void:
	#texture = state_grid.get_texture()
