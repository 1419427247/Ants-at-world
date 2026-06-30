extends Node

## 2D 像素沙盒 — 基于分块 StateGrid + CPU 策略模式

@onready var state_grid: StateGrid = $StateGrid

func _ready() -> void:
	var cpu_strategy = CpuSimulationStrategy.new()
	cpu_strategy.bind_process(_sand_process)
	state_grid.strategy = cpu_strategy

	for x: int in range(32):
		state_grid.set_cell(Vector2i(x, 128), Color.from_rgba8(0,0,0,1))
		for y: int in 32:
			if randf() < 0.5:
				state_grid.set_cell(Vector2i(x, y), Color.from_rgba8(0,0,0,2))

func _physics_process(delta: float) -> void:
	state_grid.update()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		_place_at_cursor(event.button_index)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_place_at_cursor(MOUSE_BUTTON_LEFT)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_place_at_cursor(MOUSE_BUTTON_RIGHT)


func _place_at_cursor(button_index: int) -> void:
	var world_pos: Vector2i = Vector2i(state_grid.get_global_mouse_position())
	match button_index:
		MOUSE_BUTTON_LEFT:
			state_grid.set_cell(world_pos, Color.from_rgba8(0, 0, 0, 2))  # 放沙
		MOUSE_BUTTON_RIGHT:
			state_grid.set_cell(world_pos, Color.from_rgba8(0, 0, 0, 0))  # 清除


## 沙粒模拟：遍历 chunk 内部区域，沙粒下方为空时生成 MOVE 动作
func _sand_process(chunk: StateGrid.Chunk) -> Array:
	var actions: Array = []
	var state_grid: StateGrid = chunk.state_grid
	var chunk_coord: Vector2i = chunk.coord
	var chunk_size: int = state_grid.chunk_size
	var gs: int = chunk.ghost_size

	for loop_y: int in chunk_size:
		for loop_x: int in chunk_size:
			var idx: int = (loop_y + 1) * gs + (loop_x + 1)
			var material_id: int = chunk.cells[idx].x
			if material_id == 0:
				continue

			var world_x: int = chunk_coord.x * chunk_size + loop_x
			var world_y: int = chunk_coord.y * chunk_size + loop_y

			# 沙（material_id == 2）：垂直下落
			if material_id == 2 and state_grid.get_cell(world_x, world_y + 1).a8 == 0:
				actions.append([
					CpuSimulationStrategy.ActionType.SWAP,
					Vector2i(world_x, world_y),        # source
					Vector2i(world_x, world_y + 1),    # target
				])

	return actions
