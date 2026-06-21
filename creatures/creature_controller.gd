class_name CreatureController extends Node2D
## 生物控制器抽象基类
##
## 提取所有控制器的共同功能：
## - head_anchor 导出
## - 身体朝向 (body_forward)
## - 速度估算 (基于 head_anchor 位置变化)

@export var head_anchor: ChainJoint

# ===================== 运动状态 =====================
var body_forward: Vector2 = Vector2.RIGHT
var _smoothed_forward: Vector2 = Vector2.RIGHT
var _body_velocity: Vector2 = Vector2.ZERO
var _last_head_anchor_pos: Vector2 = Vector2.ZERO
var _velocity_initialized: bool = false

# 速度平滑速率，子类在 _ready() 中根据需要覆盖
var _velocity_lerp_rate: float = 10.0


# ===================== 速度估算 =====================

func _update_velocity_estimation(delta: float) -> void:
	## 基于 head_anchor 世界坐标变化估算身体速度
	## 子类的 _update_body_direction() 末尾调用此方法
	if _velocity_initialized and delta > 0.0:
		var instant_velocity: Vector2 = (head_anchor.global_position - _last_head_anchor_pos) / delta
		_body_velocity = _body_velocity.lerp(instant_velocity, minf(1.0, delta * _velocity_lerp_rate))
	_last_head_anchor_pos = head_anchor.global_position
	_velocity_initialized = true
