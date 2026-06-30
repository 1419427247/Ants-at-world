class_name GILightViewport extends SubViewport

@export var main_camera: Camera2D

## GI 相机 zoom 偏移量（直接加到 main_camera.zoom 上）。
## 负值使 GI 相机 zoom 更小，渲染更广的世界范围，让屏幕外的发光体参与 GI 计算。
## 例如 main_camera.zoom=1.0, margin=-0.2 → gi_camera.zoom=0.8（四周扩展约 12.5%）
## 0.0 = 无偏移（向后兼容）
@export var margin: float = 0.0

var camera: Camera2D = Camera2D.new()
# Called when the node enters the scene tree for the first time.

func _init() -> void:
	add_child(camera)

func _ready() -> void:
	transparent_bg = true
	use_hdr_2d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	camera.global_transform = main_camera.global_transform

	var main_viewport := main_camera.get_viewport()
	if main_viewport == null:
		return
	var main_size: Vector2i = main_viewport.size
	# 保持 size 与主视口一致
	if size != main_size:
		size = main_size
	# zoom 偏移：margin 直接加到 main_camera.zoom 上，clamp 防零
	var gi_zoom := maxf((main_camera.zoom.x + margin), 0.001)
	camera.zoom = Vector2(gi_zoom, gi_zoom)

## 返回主相机视野在 GI 纹理中的 UV 映射区域（xy=offset, zw=scale）。
## 合成器用此值将 SCREEN_UV 映射到 GI 纹理中主相机视野对应的中心区域，实现边缘裁剪。
## margin=0 时返回 vec4(0,0,1,1)，gi_uv == SCREEN_UV。
func get_uv_region() -> Vector4:
	if margin == 0.0:
		return Vector4(0.0, 0.0, 1.0, 1.0)
	# 主相机视野占 GI 纹理的比例 = gi_zoom / main_zoom
	var main_zoom_x := main_camera.zoom.x
	var main_zoom_y := main_camera.zoom.y
	var gi_zoom_x := main_zoom_x + margin
	var gi_zoom_y := main_zoom_y + margin
	# 防止除零或负 zoom
	if main_zoom_x <= 0.0 or main_zoom_y <= 0.0 or gi_zoom_x <= 0.0 or gi_zoom_y <= 0.0:
		return Vector4(0.0, 0.0, 1.0, 1.0)
	var scale_x := gi_zoom_x / main_zoom_x
	var scale_y := gi_zoom_y / main_zoom_y
	var offset_x := (1.0 - scale_x) * 0.5
	var offset_y := (1.0 - scale_y) * 0.5
	return Vector4(offset_x, offset_y, scale_x, scale_y)
