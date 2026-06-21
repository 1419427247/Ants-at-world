extends Node

@onready var texture_rect: TextureRect = $TextureRect
@onready var source_viewport: SubViewport = $SourceViewport

var rd: RenderingDevice
var compute_shader_rid: RID
var compute_pipeline_rid: RID
var input_texture: RID   # 接收 GPU copy 的输入
var output_texture: RID  # 计算着色器写入 + 显示
var uniform_set: RID
var current_width := 0
var current_height := 0
var current_format: RenderingDevice.DataFormat

func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	assert(rd != null, "无法获取主渲染设备")

	var shader_file := load("res://experiments/viewport_grayscale.glsl") as RDShaderFile
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	compute_shader_rid = rd.shader_create_from_spirv(spirv)
	assert(compute_shader_rid.is_valid(), "计算着色器编译失败")

	compute_pipeline_rid = rd.compute_pipeline_create(compute_shader_rid)
	assert(compute_pipeline_rid.is_valid(), "计算管线创建失败")



func _process(_delta: float) -> void:
	var vp_tex = source_viewport.get_texture()
	if not vp_tex:
		return

	var vp_rid = vp_tex.get_rid()
	if not vp_rid.is_valid():
		return

	# 获取 Viewport 的底层 RD 纹理（GPU 侧，不经过 CPU）
	var rd_tex = RenderingServer.texture_get_rd_texture(vp_rid, false)
	if not rd_tex.is_valid():
		return

	# 获取纹理格式信息（自动适应 HDR 或普通格式）
	var fmt = rd.texture_get_format(rd_tex)
	var w = fmt.width
	var h = fmt.height
	if w <= 0 or h <= 0:
		return

	# 尺寸或格式变化时重建输入/输出纹理
	if w != current_width or h != current_height or fmt.format != current_format:
		_resize_textures(w, h, fmt.format)

	# GPU copy: Viewport RD 纹理 → input_texture（纯 GPU，无 CPU 传输）
	var src_layer := 0
	var dst_layer := 0
	var src_mipmap := 0
	var dst_mipmap := 0
	rd.texture_copy(rd_tex, input_texture, Vector3.ZERO, Vector3.ZERO, Vector3(w, h, 1), src_layer, dst_layer, src_mipmap, dst_mipmap)

	# 调度计算着色器
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compute_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceili(w / 16.0), ceili(h / 16.0), 1)
	rd.compute_list_end()

	# 用 Texture2DRD 直接显示 output_texture，无需 CPU 回读
	var display_texture = Texture2DRD.new()
	display_texture.texture_rd_rid = output_texture
	texture_rect.texture = display_texture


func _resize_textures(w: int, h: int, data_format: RenderingDevice.DataFormat) -> void:
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if input_texture.is_valid():
		rd.free_rid(input_texture)
	if output_texture.is_valid():
		rd.free_rid(output_texture)

	current_width = w
	current_height = h
	current_format = data_format

	var tex_format := RDTextureFormat.new()
	tex_format.width = w
	tex_format.height = h
	tex_format.format = data_format

	var tex_view := RDTextureView.new()

	# 输入纹理：接收 GPU copy + 计算着色器读取
	tex_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	input_texture = rd.texture_create(tex_format, tex_view)

	# 输出纹理：计算着色器写入 + 可采样显示
	tex_format.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	output_texture = rd.texture_create(tex_format, tex_view)

	var uniform_in := RDUniform.new()
	uniform_in.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_in.binding = 0
	uniform_in.add_id(input_texture)

	var uniform_out := RDUniform.new()
	uniform_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform_out.binding = 1
	uniform_out.add_id(output_texture)

	uniform_set = rd.uniform_set_create([uniform_in, uniform_out], compute_shader_rid, 0)


func _exit_tree() -> void:
	if not rd:
		return
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if input_texture.is_valid():
		rd.free_rid(input_texture)
	if output_texture.is_valid():
		rd.free_rid(output_texture)
	if compute_pipeline_rid.is_valid():
		rd.free_rid(compute_pipeline_rid)
	if compute_shader_rid.is_valid():
		rd.free_rid(compute_shader_rid)
