class_name CpuSimulationStrategy extends SimulationStrategy

## CPU 模拟策略 — 生成动作列表，由 StateGrid 统一解算
##
## 动作以数组表示：[ActionType, ...args]
##   SWAP: [SWAP, Vector2i(source), Vector2i(target)]  — source 材质移到 target
##   SPAWN:[SPAWN,Vector2i(target), int(id)]            — 在 target 生成材质

enum ActionType { SWAP, SPAWN }


# ------------------------------------------------------------------
# 处理回调
# ------------------------------------------------------------------
var _process_func: Callable


func bind_process(callable: Callable) -> void:
	## 注册处理回调，签名：
	##     func(chunk: StateGrid.Chunk) -> Array
	_process_func = callable


func process(chunk: StateGrid.Chunk) -> Array:
	## 仅生成动作列表，不修改 chunk.output_cells
	return _process_func.call(chunk)
