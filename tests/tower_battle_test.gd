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
	_assert(ui._player_cards.size() == 2, "2: 玩家卡片2张（1真人+1敌人）（实际=%d）" % ui._player_cards.size())
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
	_assert(ui._player_cards.size() == 2, "8: 动画后卡片仍在")

	# 等待结算完成
	await get_tree().create_timer(1.5).timeout
	_assert(ui._player_cards.size() == 2, "9: 结算后卡片仍在（实际=%d）" % ui._player_cards.size())

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
