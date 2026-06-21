class_name CreatureRoot extends Node2D
## 通用生物根节点 — 所有生物场景的根节点
##
## 自动添加 VisibleOnScreenNotifier2D，离屏时禁用 IK 解算和渲染
## 若场景中已有 VisibleOnScreenNotifier2D 节点则复用

func _init() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "ScreenNotifier"
	notifier.rect = Rect2(-150, -150, 300, 300)
	add_child(notifier)
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)

func _on_screen_entered() -> void:
	_set_ik_enabled(true)
	_set_render_process(true)

func _on_screen_exited() -> void:
	_set_ik_enabled(false)
	_set_render_process(false)

func _set_ik_enabled(enabled: bool) -> void:
	var ik_targets: Node = get_node_or_null("IKTargets")
	if not ik_targets:
		return
	for child in ik_targets.get_children():
		var ik: IKController = child as IKController
		if ik:
			ik.enabled = enabled


func _set_render_process(enabled: bool) -> void:
	for child in get_children():
		var s: Script = child.get_script()
		if s and "Renderer" in s.resource_path:
			child.process_mode = PROCESS_MODE_INHERIT if enabled else PROCESS_MODE_DISABLED
			return
