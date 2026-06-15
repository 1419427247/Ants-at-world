@tool
class_name ComputeShader
## 计算着色器封装类
##
## 封装 Godot RenderingDevice 计算着色器的完整生命周期：
## 加载编译 → 创建缓冲区 → 执行调度 → 读取结果 → 资源清理

var _tracked_rids: Array[RID]
var _device: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _is_ready: bool

## 从 .glsl 文件加载并编译计算着色器
func load_from_file(path: String) -> bool:
	if _is_ready:
		push_warning("ComputeShader: 已初始化，将重新加载")
		cleanup()

	_device = RenderingServer.create_local_rendering_device()
	if _device == null:
		push_error("ComputeShader: 无法创建 RenderingDevice，请使用 Forward+ 或 Mobile 渲染器")
		return false

	var shader_file: RDShaderFile = load(path) as RDShaderFile
	if shader_file == null:
		push_error("ComputeShader: 无法加载着色器文件: ", path)
		return false

	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	if shader_spirv == null:
		push_error("ComputeShader: 无法编译 SPIR-V: ", path)
		return false

	_shader_rid = _device.shader_create_from_spirv(shader_spirv)
	if not _shader_rid.is_valid():
		push_error("ComputeShader: 无法创建着色器 RID")
		return false
	_tracked_rids.append(_shader_rid)

	_pipeline_rid = _device.compute_pipeline_create(_shader_rid)
	if not _pipeline_rid.is_valid():
		push_error("ComputeShader: 无法创建计算管线")
		return false
	_tracked_rids.append(_pipeline_rid)

	_is_ready = true
	return true


## 创建存储缓冲区
func create_storage_buffer(data: PackedByteArray) -> RID:
	assert(_is_ready, "ComputeShader: 未初始化，请先调用 load_from_file()")
	var buffer_rid: RID = _device.storage_buffer_create(data.size(), data)
	_tracked_rids.append(buffer_rid)
	return buffer_rid


## 创建 UniformSet，将 buffers 绑定到指定的 set_index
## 每个 buffer 的 binding 从 0 开始递增
func create_uniform_set(buffers: Array[RID], set_index: int = 0) -> RID:
	assert(_is_ready, "ComputeShader: 未初始化，请先调用 load_from_file()")
	var uniforms: Array[RDUniform] = []
	for binding_index: int in range(buffers.size()):
		var rd_uniform: RDUniform = RDUniform.new()
		rd_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		rd_uniform.binding = binding_index
		rd_uniform.add_id(buffers[binding_index])
		uniforms.append(rd_uniform)
	var uniform_set_rid: RID = _device.uniform_set_create(uniforms, _shader_rid, set_index)
	_tracked_rids.append(uniform_set_rid)
	return uniform_set_rid


## 调度计算着色器
##   workgroup_count - 工作组数量 (x, y, z)
##   uniform_sets    - 要绑定的 UniformSet RID 数组
func dispatch(workgroup_count: Vector3i, uniform_sets: Array[RID]) -> void:
	assert(_is_ready, "ComputeShader: 未初始化，请先调用 load_from_file()")
	var compute_list: int = _device.compute_list_begin()
	_device.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)
	for set_index: int in range(uniform_sets.size()):
		_device.compute_list_bind_uniform_set(compute_list, uniform_sets[set_index], set_index)
	_device.compute_list_dispatch(compute_list, workgroup_count.x, workgroup_count.y, workgroup_count.z)
	_device.compute_list_end()


## 提交到 GPU 并等待执行完成
func submit_and_sync() -> void:
	assert(_is_ready, "ComputeShader: 未初始化，请先调用 load_from_file()")
	_device.submit()
	_device.sync()


## 从缓冲区读取数据
func get_buffer_data(buffer_rid: RID) -> PackedByteArray:
	assert(_is_ready, "ComputeShader: 未初始化，请先调用 load_from_file()")
	return _device.buffer_get_data(buffer_rid)


func _notification(notification_type: int) -> void:
	if notification_type == NOTIFICATION_PREDELETE:
		if _device == null:
			return
		# 逆序释放：先销毁依赖者，再销毁被依赖者
		for rid_index: int in range(_tracked_rids.size() - 1, -1, -1):
			var rid: RID = _tracked_rids[rid_index]
			if rid.is_valid():
				_device.free_rid(rid)


## 释放所有已创建的 RID 资源
## 调用后若要重新执行需再次调用 load_from_file()
func cleanup() -> void:
	# 逆序释放：先销毁依赖者，再销毁被依赖者
	# uniform_set → buffer → pipeline → shader
	for rid_index: int in range(_tracked_rids.size() - 1, -1, -1):
		var rid: RID = _tracked_rids[rid_index]
		if rid.is_valid():
			_device.free_rid(rid)
	_tracked_rids.clear()
	_shader_rid = RID()
	_pipeline_rid = RID()
	_device = null
	_is_ready = false
