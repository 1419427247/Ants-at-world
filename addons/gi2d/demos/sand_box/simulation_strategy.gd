@abstract
class_name SimulationStrategy extends RefCounted

## 模拟策略抽象基类
##
## 策略模式：CPU 和 GPU 两种策略分别实现此接口。
## StateGrid 通过 set_strategy() 注入策略，update() 时委托处理。

## 生成动作列表，不直接修改 output_cells。
## 返回 Array[Array] — 每个元素为 [type, source, target, material_id]
@abstract func process(chunk: StateGrid.Chunk) -> Array
