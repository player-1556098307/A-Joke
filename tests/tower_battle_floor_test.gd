## 塔战斗层推进测试：打赢第1层不崩溃（复现 game_over 冲突 bug）
## 验证：真实对局打穿第1层 → TowerManager 推进第2层 → GameUI 正常刷新
## 使用 fast_mode 跳过过渡动画和对话，避免时序依赖
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔战斗层推进测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	SceneManager.last_tower_config = { "players": [{ "character": naruto_char, "is_human": true }] }
	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	# 启用快速模式：跳过过渡动画和对话
	battle.fast_mode = true
	add_child(battle)
	await get_tree().process_frame

	var gm := GameManager
	var floors: Array = []
	# fast_mode 下 start_tower 立即触发第1层 floor_changed（在 add_child 时同步调用）
	# 因此需在 add_child 后立即连接信号，捕捉第2层变化
	battle.tower_mgr.floor_changed.connect(func(f: int, n: String): floors.append([f, n]))

	# 循环打赢第1层（玩家每回合赢 → 普攻敌人）
	for i in range(80):
		if floors.size() >= 1:
			break
		var human: PlayerState = gm.get_player(0)
		var enemy: PlayerState = gm.get_player(1)
		if enemy == null or not enemy.is_alive or not human.is_alive:
			break
		human.current_gesture = PlayerState.Gesture.ROCK
		enemy.current_gesture = PlayerState.Gesture.SCISSORS
		gm.call("_resolve_round")
		human.energy = 1
		if gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT:
			gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(human, "普攻"), enemy.player_id)
		await get_tree().process_frame

	_assert(floors.size() >= 1 and floors[0][0] == 2, "1: 打赢第1层进入第2层（实际=%s）" % str(floors))
	_assert(battle._ui != null, "2: GameUI 未崩溃（仍存在）")
	if battle._ui != null:
		_assert(battle._ui._player_cards.size() >= 2, "3: 第2层玩家卡片已刷新（实际=%d）" % battle._ui._player_cards.size())
	_assert(battle._floor_label.text.contains("第2层"), "4: 层标签=第2层（实际=%s）" % battle._floor_label.text)
	# 注：打穿3层的通关流程由 tower_mode_test 验证

	print("=== 层推进测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _find_skill_index(player: PlayerState, skill_name: String) -> int:
	var all := player.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == skill_name:
			return i
	return -1

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
