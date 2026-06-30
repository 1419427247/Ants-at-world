extends Node2D
## 三足步态（tripod gait）演示
##
## A组（红）：左前(FL) + 右中(MR) + 左后(BL)
## B组（蓝）：右前(FR) + 左中(ML) + 右后(BR)
## 两组交替支撑/摆动，始终至少3腿着地

@onready var body: Node2D = $ChainJoint

@onready var foot_fl: Sprite2D = $IKTargets/FootFL
@onready var foot_fr: Sprite2D = $IKTargets/FootFR
@onready var foot_ml: Sprite2D = $IKTargets/FootML
@onready var foot_mr: Sprite2D = $IKTargets/FootMR
@onready var foot_bl: Sprite2D = $IKTargets/FootBL
@onready var foot_br: Sprite2D = $IKTargets/FootBR

# 腿数据：[sprite, 静止偏移, 组(0=A,1=B), 世界坐标, 是否摆动, 摆动进度]
var _legs: Array = []

var _stride: float = 36.0
var _acc: float = 0.0
var _phase: float = 0.0  # 0=A摆B撑, 0.5=B摆A撑
var _speed: float = 60.0


func _ready() -> void:
	_legs = [
		[foot_fl, Vector2(14, -18), 0, Vector2.ZERO, false, 0.0],
		[foot_fr, Vector2(14,  18), 1, Vector2.ZERO, false, 0.0],
		[foot_ml, Vector2( 0, -20), 1, Vector2.ZERO, false, 0.0],
		[foot_mr, Vector2( 0,  20), 0, Vector2.ZERO, false, 0.0],
		[foot_bl, Vector2(-14,-18), 0, Vector2.ZERO, false, 0.0],
		[foot_br, Vector2(-14, 18), 1, Vector2.ZERO, false, 0.0],
	]
	for l in _legs:
		l[3] = _rest(l[1])
		l[0].global_position = l[3]
		l[0].texture = _dot(12, Color.RED if l[2] == 0 else Color(0.2, 0.4, 1.0))


func _process(delta: float) -> void:
	body.position += Vector2.RIGHT * _speed * delta

	_acc += _speed * delta
	if _acc >= _stride:
		_acc -= _stride
		_phase = fmod(_phase + 0.5, 1.0)

	var a_swing: bool = _phase < 0.5
	for l in _legs:
		var is_a: bool = l[2] == 0
		var should_swing: bool = is_a == a_swing

		if should_swing and not l[4]:
			l[4] = true
			l[5] = 0.0
			# swing_start = 当前位置, swing_end = 静止位置前方一跨步
			l.append(l[3])  # index 6: swing_start
			l.append(_rest(l[1]) + Vector2.RIGHT * _stride)  # index 7: swing_end

		if l[4]:
			l[5] += delta * 2.5
			if l[5] >= 1.0:
				l[4] = false
				l[3] = l[7]
				l.resize(6)  # 清理临时数据
			else:
				var t: float = 0.5 - 0.5 * cos(l[5] * PI)
				l[3] = l[6].lerp(l[7], t)

		l[0].global_position = l[3]


func _rest(off: Vector2) -> Vector2:
	return body.global_position + Vector2.RIGHT * off.x + Vector2.UP * off.y


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r2: float = (size * 0.5) * (size * 0.5)
	var c: float = (size - 1) * 0.5
	for y in size:
		for x in size:
			img.set_pixel(x, y, color if (x-c)*(x-c)+(y-c)*(y-c) < r2 else Color.TRANSPARENT)
	return ImageTexture.create_from_image(img)
