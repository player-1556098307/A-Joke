## 塔战斗 Control 布局验证测试
## 验证：tower_battle 改为 Control 后，子 Control 节点（overlay/transition/dialogue_box）
##       能正确获得非零 size，正常模式下过渡动画和对话流程不会因 size=0 卡死。
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔战斗 Control 布局验证测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	SceneManager.last_tower_config = { "players": [{ "character": naruto_char, "is_human": true }] }
	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	# 正常模式（非 fast_mode）
	battle.fast_mode = false
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 根节点为 Control 且有正确 size
	_assert(battle is Control, "1: 根节点为 Control（实际=%s）" % battle.get_class())
	var root_size: Vector2 = (battle as Control).size
	_assert(root_size.x > 0 and root_size.y > 0, "2: 根节点 size 非零（实际=%s）" % str(root_size))

	# 2. overlay（顶层提示层）有正确 size
	# overlay 是第一个子节点（在 _transition 和 _dialogue_box 之前 add_child）
	var overlay: Control = null
	for child in battle.get_children():
		if child is Control and child.get_child_count() > 0:
			var first_gc = child.get_child(0)
			if first_gc is Label and (first_gc as Label).text == "慈悲尖塔":
				overlay = child as Control
				break
	_assert(overlay != null, "3: 找到 overlay Control")
	if overlay != null:
		_assert(overlay.size.x > 0 and overlay.size.y > 0, "4: overlay size 非零（实际=%s）" % str(overlay.size))
		# floor_label 是 overlay 的子节点
		var fl: Label = battle._floor_label
		_assert(fl != null, "5: floor_label 存在")
		if fl != null:
			_assert(fl.text == "慈悲尖塔", "6: floor_label 初始文本（实际=%s）" % fl.text)

	# 3. TowerFloorTransition 有正确 size
	var transition: TowerFloorTransition = battle._transition
	_assert(transition != null, "7: _transition 存在")
	if transition != null:
		_assert(transition.size.x > 0 and transition.size.y > 0, "8: _transition size 非零（实际=%s）" % str(transition.size))
		# transition 内部有 _overlay ColorRect 和 _dialogue_box
		var t_overlay: ColorRect = transition._overlay
		_assert(t_overlay != null, "9: transition._overlay 存在")
		if t_overlay != null:
			_assert(t_overlay.size.x > 0 and t_overlay.size.y > 0, "10: transition._overlay size 非零（实际=%s）" % str(t_overlay.size))
		var t_dlg: DialogueBox = transition._dialogue_box
		_assert(t_dlg != null, "11: transition._dialogue_box 存在")
		if t_dlg != null:
			_assert(t_dlg.size.x > 0 and t_dlg.size.y > 0, "12: transition._dialogue_box size 非零（实际=%s）" % str(t_dlg.size))

	# 4. DialogueBox（退场/战斗叙事用）有正确 size
	var dlg: DialogueBox = battle._dialogue_box
	_assert(dlg != null, "13: _dialogue_box 存在")
	if dlg != null:
		_assert(dlg.size.x > 0 and dlg.size.y > 0, "14: _dialogue_box size 非零（实际=%s）" % str(dlg.size))

	# 5. 正常模式下 phase 应为 "transition"（过渡动画进行中）
	_assert(battle._phase == "transition", "15: 正常模式初始 phase=transition（实际=%s）" % battle._phase)

	# 6. 过渡动画应已启动（_transition._phase 不为空）
	if transition != null:
		_assert(transition._phase != "" and transition._phase != "done", "16: transition 已启动（phase=%s）" % transition._phase)

	# 7. 验证过渡动画不会卡死：等待几帧后强制完成对话，检查能否进入 battle phase
	var entered_battle: bool = false
	for i in range(600):
		await get_tree().process_frame
		_skip_dialogue(battle)
		if battle._phase == "battle":
			entered_battle = true
			break
	_assert(entered_battle, "17: 正常模式过渡动画完成后进入 battle（未卡死）")

	# 8. 进入 battle 后 GameUI 应有玩家卡片
	if entered_battle:
		var ui = battle._ui
		_assert(ui != null and ui._player_cards.size() >= 2, "18: battle 阶段玩家卡片>=2（实际=%s）" % str(ui._player_cards.size() if ui else "null"))

	print("=== 布局验证测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _skip_dialogue(battle: Node) -> void:
	if battle._transition and battle._transition._dialogue_box and battle._transition._dialogue_box.is_active():
		battle._transition._dialogue_box.force_finish()
	if battle._dialogue_box and battle._dialogue_box.is_active():
		battle._dialogue_box.force_finish()

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
