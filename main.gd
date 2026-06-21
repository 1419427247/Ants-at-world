extends Node2D
## 主场景 — 随机生成12个生物，在屏幕范围内自由游走

const SCREEN_PADDING: float = 80.0
const WANDER_MARGIN: float = 20.0      # 到达目标距离阈值
const TARGET_TIMEOUT_MIN: float = 5  # 目标超时范围（秒）
const TARGET_TIMEOUT_MAX: float = 15
const REST_MIN: float = 1.0            # 到达后休息时间范围
const REST_MAX: float = 4.0

# 生物类型配置: [场景路径, 速度范围, 显示名称]
var creature_types: Array = [
	{ "scene": preload("res://creatures/ant/ant.tscn"), "speed_min": 25, "speed_max": 45, "rest_min": 0.4, "rest_max": 1.2, "name": "Ant" },
	#{ "scene": preload("res://creatures/spider/spider.tscn"), "speed_min": 25, "speed_max": 45, "rest_min": 0.4, "rest_max": 1.2, "name": "Spider" },
	#{ "scene": preload("res://creatures/millipede/millipede.tscn"), "speed_min": 18, "speed_max": 30, "rest_min": 0.8, "rest_max": 2.0, "name": "Millipede" },
	#{ "scene": preload("res://creatures/beetle/beetle.tscn"), "speed_min": 20, "speed_max": 35, "rest_min": 0.5, "rest_max": 1.5, "name": "Beetle" },
	#{ "scene": preload("res://creatures/snail/snail.tscn"), "speed_min": 10, "speed_max": 18, "rest_min": 1.0, "rest_max": 2.5, "name": "Snail" },
]

class CreatureData:
	var node: Node2D
	var type_index: int
	var head_anchor: ChainJoint
	var wander_target: Vector2
	var wander_speed: float
	var target_timer: float
	var resting: bool
	var rest_timer: float

var creatures: Array[CreatureData] = []


func _ready() -> void:
	_spawn_creatures()

func _process(delta: float) -> void:
	_update_wander(delta)

func _spawn_creatures() -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	for type_idx: int in range(creature_types.size()):
		var type_config: Dictionary = creature_types[type_idx]
		for _i: int in range(30):
			var instance: Node2D = type_config["scene"].instantiate()
			add_child(instance)

			# 配置生物数据
			var data: CreatureData = CreatureData.new()
			data.node = instance
			data.type_index = type_idx
			data.head_anchor = instance.get_node("Spine/HeadAnchor") as ChainJoint
			data.wander_speed = randf_range(type_config["speed_min"], type_config["speed_max"])
			# 初始目标在当前位置附近
			data.wander_target = _random_wander_target(screen_size)
			data.target_timer = randf_range(TARGET_TIMEOUT_MIN, TARGET_TIMEOUT_MAX)
			data.resting = false
			data.rest_timer = 0.0

			# 初始化 head_anchor 位置（与 creature position 对齐）
			data.head_anchor.global_position = instance.position

			creatures.append(data)


func _update_wander(delta: float) -> void:
	var screen_size: Vector2 = get_viewport_rect().size

	for data: CreatureData in creatures:
		if not is_instance_valid(data.node):
			continue

		if data.resting:
			# 休息中：不移动，倒计时结束后出发去下一目标
			data.rest_timer -= delta
			if data.rest_timer <= 0.0:
				data.resting = false
				data.wander_target = _random_wander_target(screen_size)
				data.target_timer = randf_range(TARGET_TIMEOUT_MIN, TARGET_TIMEOUT_MAX)
		else:
			# 移动中
			var direction: Vector2 = data.wander_target - data.node.position
			var dist: float = direction.length()

			if dist > WANDER_MARGIN:
				# 朝目标移动
				var step: float = data.wander_speed * delta
				var move: Vector2 = direction.normalized() * minf(step, dist)
				data.node.position += move
				data.head_anchor.global_position = data.node.position

				# 超时未到达也换目标（防止死锁）
				data.target_timer -= delta
				if data.target_timer <= 0.0:
					var type_config: Dictionary = creature_types[data.type_index]
					data.resting = true
					data.rest_timer = randf_range(type_config["rest_min"], type_config["rest_max"])
			else:
				# 到达目标，开始休息
				var type_config: Dictionary = creature_types[data.type_index]
				data.resting = true
				data.rest_timer = randf_range(type_config["rest_min"], type_config["rest_max"])

func _random_wander_target(screen_size: Vector2) -> Vector2:
	# 在摄像机 position 周围 1024px 范围内随机选一个位置
	var cam: Camera2D = get_viewport().get_camera_2d()
	var center: Vector2 = cam.global_position if cam else screen_size * 0.5
	return Vector2(
		randf_range(center.x - 1024, center.x + 1024),
		randf_range(center.y - 1024, center.y + 1024)
	)
