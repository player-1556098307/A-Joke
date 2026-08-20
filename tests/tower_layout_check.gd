## 塔选人布局检查：返回按钮存在性/可见性/遮挡检测
extends Node

var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔选人布局检查 ===")
	await get_tree().process_frame
	var sel = (load("res://scenes/tower/tower_select.tscn") as PackedScene).instantiate()
	add_child(sel)
	sel.size = Vector2(960, 540)
	await get_tree().process_frame

	# 1. 查找返回按钮
	var back: Button = null
	for c in sel.get_children():
		if c is Button and c.text == "← 返回":
			back = c
			break
	print("返回按钮存在: ", back != null)
	if back == null:
		print("FAIL: 未找到返回按钮")
		get_tree().quit(1)
		return

	print("返回按钮 visible=", back.visible, " pos=", back.position, " size=", back.size)
	print("返回按钮 z_index=", back.z_index)
	print("返回按钮 global_rect=", back.get_global_rect())

	# 2. 开始按钮应靠右，不与返回按钮重叠
	var start_btn: Button = null
	for c in sel.get_children():
		if c is Button and c.text == "" and c != back:
			start_btn = c
			break
	if start_btn:
		var s_rect: Rect2 = start_btn.get_global_rect()
		var b_rect: Rect2 = back.get_global_rect()
		print("开始按钮 global_rect=", s_rect)
		print("返回按钮 global_rect=", b_rect)
		if s_rect.intersects(b_rect):
			print("FAIL: 开始按钮与返回按钮重叠")
		else:
			print("PASS: 开始按钮与返回按钮不重叠")
	else:
		print("FAIL: 未找到开始按钮")

	# 3. 滚动区底部应不超出 482（槽位条顶部 488）
	var scroll: ScrollContainer = null
	for c in sel.get_children():
		if c is ScrollContainer:
			scroll = c
			break
	if scroll:
		var s_rect: Rect2 = scroll.get_global_rect()
		print("滚动区 global_rect=", s_rect, " 底部=", s_rect.end.y)
		if s_rect.end.y > 488.0:
			print("FAIL: 滚动区底部与槽位条重叠")
		else:
			print("PASS: 滚动区底部不重叠")
	else:
		print("FAIL: 未找到滚动区")

	# 3. z_index 置顶
	if back.z_index >= 100:
		print("PASS: 返回按钮 z_index 置顶")
	else:
		print("FAIL: 返回按钮未置顶")

	get_tree().quit(0)
