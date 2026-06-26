class_name GIComposite extends ColorRect

@export var pass_diffuse: Viewport
@export var pass_gi: ComputePass
@export var pass_directional: ComputePass
@export var pass_ao: ComputePass

var _gi_tex = Texture2DRD.new()
var _dir_tex = Texture2DRD.new()
var _ao_tex = Texture2DRD.new()

func _process(delta: float) -> void:
	material.set_shader_parameter("diffuse_texture", pass_diffuse.get_texture())

	_gi_tex.texture_rd_rid = pass_gi.get_output_resource_id()
	material.set_shader_parameter("gi_texture", _gi_tex)

	_dir_tex.texture_rd_rid = pass_directional.get_output_resource_id()
	material.set_shader_parameter("directional_texture", _dir_tex)

	var ao_rid = pass_ao.get_output_resource_id()
	_ao_tex.texture_rd_rid = ao_rid
	material.set_shader_parameter("ao_texture", _ao_tex)

	if pass_diffuse.has_method("get_uv_region"):
		var region: Vector4 = pass_diffuse.get_uv_region()
		material.set_shader_parameter("gi_uv_offset", Vector2(region.x, region.y))
		material.set_shader_parameter("gi_uv_scale", Vector2(region.z, region.w))
	else:
		material.set_shader_parameter("gi_uv_offset", Vector2.ZERO)
		material.set_shader_parameter("gi_uv_scale", Vector2.ONE)
