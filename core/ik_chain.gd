@tool
class_name IKChain extends Node2D
## IK 反向动力学链 — 递归容器
##
## IKChain 既可以作为链的容器（包含子 IKChain），
## 也可以作为链中的一个关节段（leaf 节点，拥有 radius 等属性）。
## 由 IKRoot 统一管理骨骼和求解。

@export var minimum_angle_degrees: float = -180.0
@export var maximum_angle_degrees: float = 180.0

var root: IKRoot
var parent_chain: IKChain

var bone: Bone2D = Bone2D.new()

func _init() -> void:
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(1)

func _ready() -> void:
	parent_chain = get_parent() as IKChain
	set_notify_transform(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	global_transform = bone.global_transform

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()

func _draw() -> void:
	var bone_color: Color = Color(0.4, 0.7, 1.0, 0.7)
	var joint_color: Color = Color(0.3, 0.9, 0.5, 0.8)
	if parent_chain:
		draw_line(Vector2.ZERO, to_local(parent_chain.global_position), bone_color, 1.0)
	draw_circle(Vector2.ZERO, 2.0, joint_color)
