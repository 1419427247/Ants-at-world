extends Node

@onready var texture_rect: TextureRect = %TextureRect

const WIDTH := 4096
const HEIGHT := 4096

var rd: RenderingDevice
var compute_shader_rid: RID
var compute_pipeline_rid: RID

var texture_a: RID
var texture_b: RID
var uniform_set_a: RID  # a -> b
var uniform_set_b: RID  # b -> a

var front_is_a := true


func _ready() -> void:
	_setup_compute()


func _setup_compute() -> void:
	# 创建本地渲染设备
	rd = RenderingServer.create_local_rendering_device()
	assert(rd != null, "无法创建本地渲染设备")

	# 加载并编译计算着色器
	var shader_file := load("res://experiments/game_of_life.glsl") as RDShaderFile
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	compute_shader_rid = rd.shader_create_from_spirv(spirv)
	assert(compute_shader_rid.is_valid(), "计算着色器编译失败")

	# 创建计算管线
	compute_pipeline_rid = rd.compute_pipeline_create(compute_shader_rid)
	assert(compute_pipeline_rid.is_valid(), "计算管线创建失败")

	# 纹理格式配置
	var tex_format := RDTextureFormat.new()
	tex_format.width = WIDTH
	tex_format.height = HEIGHT
	tex_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tex_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	# 生成随机初始数据（约15%存活率）
	var initial_data := PackedByteArray()
	initial_data.resize(WIDTH * HEIGHT * 4)
	for i in range(WIDTH * HEIGHT):
		var val := 255 if randf() > 0.85 else 0
		initial_data[i * 4 + 0] = val
		initial_data[i * 4 + 1] = val
		initial_data[i * 4 + 2] = val
		initial_data[i * 4 + 3] = 255

	var tex_view := RDTextureView.new()

	# 创建两张 ping-pong 纹理
	texture_a = rd.texture_create(tex_format, tex_view, [initial_data])
	texture_b = rd.texture_create(tex_format, tex_view, [initial_data])

	# 创建 uniform set A: texture_a -> texture_b
	var uniform_a_in := RDUniform.new()
	uniform_a_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_a_in.binding = 0
	uniform_a_in.add_id(texture_a)

	var uniform_a_out := RDUniform.new()
	uniform_a_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_a_out.binding = 1
	uniform_a_out.add_id(texture_b)

	uniform_set_a = rd.uniform_set_create([uniform_a_in, uniform_a_out], compute_shader_rid, 0)

	# 创建 uniform set B: texture_b -> texture_a
	var uniform_b_in := RDUniform.new()
	uniform_b_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_b_in.binding = 0
	uniform_b_in.add_id(texture_b)

	var uniform_b_out := RDUniform.new()
	uniform_b_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_b_out.binding = 1
	uniform_b_out.add_id(texture_a)

	uniform_set_b = rd.uniform_set_create([uniform_b_in, uniform_b_out], compute_shader_rid, 0)

	# 显示初始状态
	_update_display(texture_a)


func _process(_delta: float) -> void:
	_compute_step()


func _compute_step() -> void:
	var uniform_set := uniform_set_a if front_is_a else uniform_set_b
	var output_tex := texture_b if front_is_a else texture_a

	# 提交计算任务
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compute_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceili(WIDTH / 16.0), ceili(HEIGHT / 16.0), 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	front_is_a = not front_is_a

	# 更新显示
	_update_display(output_tex)


func _update_display(tex_rid: RID) -> void:
	var bytes: PackedByteArray = rd.texture_get_data(tex_rid, 0)
	if bytes.is_empty():
		return

	var image := Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, bytes)
	if image:
		texture_rect.texture = ImageTexture.create_from_image(image)
