@tool
extends EditorScript

@export var run_on_ready := true

# 着色器路径和调度参数
@export var shader_path := "res://compute_example.glsl"
@export var workgroup_count := Vector3i(5, 1, 1)
@export var input_data := PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0])


func _run() -> void:
	if run_on_ready:
		run_compute_demo()


func run_compute_demo():
	print("=== 计算着色器演示开始 ===")

	# 1. 创建计算着色器实例并加载
	var cs := ComputeShader.new()
	if not cs.load_from_file(shader_path):
		push_error("计算着色器初始化失败")
		return

	# 2. 准备输入数据 → 创建存储缓冲区
	var input_bytes := input_data.to_byte_array()
	var buffer := cs.create_storage_buffer(input_bytes)
	print("输入数据: ", input_data)

	# 3. 创建 UniformSet（缓冲区的 binding = 0，set = 0）
	var uniform_set := cs.create_uniform_set([buffer], 0)

	# 4. 调度计算：(5,1,1) 工作组 × (2,1,1) 本地调用 = 10 次调用
	cs.dispatch(workgroup_count, [uniform_set])

	# 5. 提交 GPU 并等待完成
	cs.submit_and_sync()

	# 6. 读取结果
	var output_bytes := cs.get_buffer_data(buffer)
	var output := output_bytes.to_float32_array()
	print("输出数据: ", output)
	print("=== 计算着色器演示结束 ===")

	# 7. 验证
	var correct := true
	for i in range(input_data.size()):
		if abs(output[i] - input_data[i] * 2.0) > 0.001:
			correct = false
			break
	if correct:
		print("验证通过：每个元素都已乘以 2 ✓")
	else:
		push_error("验证失败：结果与预期不符")
