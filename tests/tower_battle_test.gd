## 塔战斗冒烟测试（适配新版异步流程：过渡动画+对话后第1层才启动）
## 验证：GameUI 场景实例复用、玩家卡片构建、猜拳揭示动画、层标签
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔战斗冒烟测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	SceneManager.last_tower_config = { "players": [{ "character": naruto_char, "is_human": true }] }
	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	add_child(battle)

	# 等待第1层启动（过渡动画 + 进场对话跳过）
	for i in range(900):
		await get_tree().process_frame
		_skip_all_dialogue(battle)
		if battle._phase == "battle":
			break
	await get_tree().process_frame

	var ui = battle._ui
	_assert(ui != null, "1: GameUI 已从场景实例加载")
	_assert(ui._player_cards.size() >= 2, "2: 玩家卡片至少2张（1真人+1+敌人）（实际=%d）" % ui._player_cards.size())
	_assert(ui._human_player_id == 0, "3: 真人玩家ID=0（实际=%d）" % ui._human_player_id)
	_assert(battle._floor_label.text.contains("第1层"), "4: 层标签=第1层（实际=%s）" % battle._floor_label.text)

	var gm := GameManager
	var human := gm.get_player(0)
	var enemy := gm.get_player(1)
	_assert(enemy != null and not enemy.is_human, "5: 敌人为AI（实际=%s）" % (str(enemy.is_human) if enemy else "null"))

	# 猜拳：真人提交 → AI立即出拳 → RESOLVING → 手势揭示动画触发
	ui._pending_reveals.clear()
	human.current_gesture = PlayerState.Gesture.NONE
	enemy.current_gesture = PlayerState.Gesture.NONE
	gm.submit_gesture(0, PlayerState.Gesture.ROCK)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.RESOLVING, "6: 提交后进入RESOLVING（实际=%d）" % gm.get("_current_phase"))
	_assert(ui._pending_reveals.is_empty(), "7: 揭示已播放（动画触发，队列清空）")
	_assert(ui._player_cards.size() >= 2, "8: 动画后卡片仍在（实际=%d）" % ui._player_cards.size())

	# 等待结算完成
	await get_tree().create_timer(1.5).timeout
	_assert(ui._player_cards.size() >= 2, "9: 结算后卡片仍在（实际=%d）" % ui._player_cards.size())

	# --- buff 查看按钮测试 ---
	# 无祝福时按钮应隐藏
	SceneManager.last_tower_config.erase("tower_buffs")
	battle._update_buff_btn_visibility()
	_assert(not battle._buff_btn.visible, "10: 无祝福时buff按钮隐藏")
	_assert(not battle._buff_panel.visible, "11: 无祝福时buff面板隐藏")

	# 模拟获得一个 buff
	SceneManager.last_tower_config["tower_buffs"] = [
		{ "id": "blade_power", "value": 1.0 },
		{ "id": "shield_wall", "value": 0.5 },
	]
	battle._update_buff_btn_visibility()
	_assert(battle._buff_btn.visible, "12: 有祝福+战斗阶段时buff按钮显示")

	# 点击按钮 → 面板弹出
	battle._toggle_buff_panel()
	_assert(battle._buff_panel_visible and battle._buff_panel.visible, "13: 点击后面板弹出")

	# 等待一帧让 VBox 完成子节点布局
	await get_tree().process_frame
	await get_tree().process_frame

	# 面板内容：标题+分隔线+2行buff+关闭提示 = 5 个子节点（VBox 容器内）
	var child_count: int = battle._buff_panel_box.get_child_count()
	_assert(child_count == 5, "14: 面板有5个子节点（标题+分隔+2行+提示）（实际=%d）" % child_count)

	# 布局验证：VBox 内子节点纵向排列且不重叠（位置递增）
	var prev_bottom: float = -1.0
	var layout_ok: bool = true
	for c in battle._buff_panel_box.get_children():
		if c is Control:
			var ctl: Control = c
			if ctl.position.y < prev_bottom:
				layout_ok = false
			prev_bottom = ctl.position.y + ctl.size.y
	_assert(layout_ok, "14b: 面板子节点纵向排列不重叠（位置递增）")

	# 面板位置避开右侧手势区（game_ui.tscn GesturePanel: 774,88 - 946,532）
	var panel_rect: Rect2 = battle._buff_panel.get_global_rect()
	var gesture_rect := Rect2(774, 88, 172, 444)
	var inter: Rect2 = panel_rect.intersection(gesture_rect)
	_assert(not inter.has_area(), "14c: buff面板不与右侧手势区重叠（面板=%s 手势区=%s 重叠=%s）" % [panel_rect, gesture_rect, inter])

	# 再次点击 → 面板隐藏
	battle._toggle_buff_panel()
	_assert(not battle._buff_panel_visible and not battle._buff_panel.visible, "15: 再次点击面板隐藏")

	# 切换到非战斗阶段 → 按钮应隐藏
	battle._phase = "reward"
	battle._update_buff_btn_visibility()
	_assert(not battle._buff_btn.visible, "16: 非战斗阶段按钮隐藏")

	print("=== 塔战斗冒烟测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _skip_all_dialogue(battle: Node) -> void:
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
