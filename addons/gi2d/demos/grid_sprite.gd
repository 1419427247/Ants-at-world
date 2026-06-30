extends Sprite2D

## 网格渲染器 — 从 StateGrid 获取纹理并显示

var _sg: StateGrid

func _ready() -> void:
	scale = Vector2(8, 8)

func set_state_grid(sg: StateGrid) -> void:
	_sg = sg
	texture = sg.get_texture()
	queue_redraw()

func _process(_delta: float) -> void:
	if _sg:
		texture = _sg.get_texture()
