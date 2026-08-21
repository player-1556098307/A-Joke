## 慈悲尖塔模式流程测试
## 覆盖：start_tower 启动、逐层推进（层胜→下一层）、层间玩家状态重建、
##      精英层到达、失败触发
## 适配 16 层结构：第1-3层小怪，第4层精英（破败王者），第16层Boss跳过=通关
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 慈悲尖塔模式流程测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	if naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_basic_flow(naruto_char)
	await _test_defeat(naruto_char)

	print("=== 塔流程测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 测试1：基本流程 — 启动→小怪层→层间重建→推进到精英层
func _test_basic_flow(naruto_char: CharacterData) -> void:
	print("--- 模式流程：启动→小怪层→精英层 ---")
	var gm := GameManager
	var tower := TowerManager.new()
	add_child(tower)

	var floors: Array = []
	tower.floor_changed.connect(func(f: int, name: String): floors.append([f, name]))

	tower.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame

	# ── 第1层：小怪层 ──
	_assert(floors.size() == 1 and floors[0][0] == 1, "1a: 进入第1层（实际=%s）" % str(floors))
	_assert(not floors[0][1] == "破败王者（怒）", "1b: 第1层非精英（是=%s）" % floors[0][1])
	_assert(gm.get("_is_tower_mode"), "1c: 塔模式标志已设置")

	# 敌人尖塔祝福：2气
	var enemy: PlayerState = _get_first_enemy(gm)
	_assert(enemy != null and enemy.energy == 2, "1d: 敌人尖塔祝福2气（实际=%s）" % (str(enemy.energy) if enemy else "无敌人"))

	# 玩家 team=1
	var player: PlayerState = _get_player(gm)
	_assert(player != null and player.team_id == 1, "1e: 玩家team=1")

	# 模拟第1层玩家胜：杀全部敌人 → 淘汰 → GAME_OVER → 第2层
	_kill_all_enemies(gm)
	await get_tree().process_frame
	_assert(floors.size() == 2 and floors[1][0] == 2, "2a: 层胜后进入第2层（实际=%s）" % str(floors))

	# 层间恢复：玩家满血、气重置
	var player2: PlayerState = _get_player(gm)
	_assert(player2 != null and player2.hp == player2.character.max_hp, "2b: 层间玩家满血（实际=%.1f/%d）" % [player2.hp if player2 else 0, player2.character.max_hp if player2 else 0])
	_assert(player2 != null and player2.energy == 0, "2c: 层间玩家气重置（实际=%d）" % (player2.energy if player2 else -1))

	# 第2层敌人也有尖塔祝福
	var enemy2: PlayerState = _get_first_enemy(gm)
	_assert(enemy2 != null and enemy2.energy == 2, "2d: 第2层敌人祝福2气")

	# ── 推进穿过第2、3层小怪 → 第4层精英 ──
	_kill_all_enemies(gm)
	await get_tree().process_frame
	# 现在第3层
	_assert(floors.size() >= 3 and floors[floors.size() - 1][0] == 3, "3a: 进入第3层")

	_kill_all_enemies(gm)
	await get_tree().process_frame
	# 现在第4层=精英
	_assert(floors.size() >= 4 and floors[floors.size() - 1][0] == 4, "4a: 进入第4层精英")
	var floor4_name: String = floors[floors.size() - 1][1]
	_assert(floor4_name == "破败王者（怒）", "4b: 第4层精英=破败王者（实际=%s）" % floor4_name)

	# 精英怪也有尖塔祝福
	var elite: PlayerState = _get_first_enemy(gm)
	_assert(elite != null and elite.energy == 2, "4c: 精英怪祝福2气")

	tower.queue_free()

## 测试2：失败场景 — 玩家死亡触发失败
func _test_defeat(naruto_char: CharacterData) -> void:
	print("--- 模式流程：玩家死亡→失败 ---")
	var gm := GameManager
	var tower := TowerManager.new()
	add_child(tower)

	var defeat: Array = []
	tower.tower_defeat.connect(func(): defeat.append(true))

	tower.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame

	# 玩家死亡 → 淘汰 → GAME_OVER（敌人存活）→ 失败
	var player: PlayerState = _get_player(gm)
	_assert(player != null, "5a: 玩家存在")
	if player != null:
		player.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	_assert(defeat.size() == 1, "5b: 玩家全灭触发失败（实际=%d）" % defeat.size())

	tower.queue_free()

# ═════════ 辅助函数 ═══════════════════════════════════════

## 获取第一个敌方 PlayerState
func _get_first_enemy(gm: Variant) -> PlayerState:
	for p in gm.get_alive_players():
		if p.team_id == 2:
			return p
	return null

## 获取玩家 PlayerState
func _get_player(gm: Variant) -> PlayerState:
	for p in gm.get_alive_players():
		if p.team_id == 1:
			return p
	return null

## 杀死所有敌方单位并触发淘汰检查
func _kill_all_enemies(gm: Variant) -> void:
	for p in gm.get_alive_players():
		if p.team_id == 2:
			p.hp = 0.0
	gm.call("_check_elimination")

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
