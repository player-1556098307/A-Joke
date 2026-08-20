## 慈悲尖塔模式流程测试
## 覆盖：start_tower 启动、逐层推进（层胜→下一层）、3层通关胜利、
##      敌人尖塔祝福/塔模式标志、层间玩家状态重建
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

	await _test_flow(naruto_char)

	print("=== 塔流程测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _test_flow(naruto_char: CharacterData) -> void:
	print("--- 模式流程：1人闯关 ---")
	var gm := GameManager
	var tower := TowerManager.new()
	add_child(tower)

	var floors: Array = []
	var victory: Array = []
	var defeat: Array = []
	tower.floor_changed.connect(func(f: int, name: String): floors.append([f, name]))
	tower.tower_victory.connect(func(): victory.append(true))
	tower.tower_defeat.connect(func(): defeat.append(true))

	tower.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame

	_assert(floors.size() == 1 and floors[0][0] == 1, "1a: 进入第1层（实际=%s）" % str(floors))
	_assert(floors.size() > 0 and floors[0][1] == "破败王者（怒）", "1b: 第1层敌人=破败王者（实际=%s）" % (floors[0][1] if floors.size() > 0 else "?"))
	_assert(gm.get("_is_tower_mode"), "1c: 塔模式标志已设置")
	# 敌人尖塔祝福：2气
	var enemy: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 2:
			enemy = p
			break
	_assert(enemy != null and enemy.energy == 2, "1d: 敌人尖塔祝福2气（实际=%s）" % (str(enemy.energy) if enemy else "?"))
	# 玩家 team=1
	var player: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 1:
			player = p
			break
	_assert(player != null and player.team_id == 1, "1e: 玩家team=1")

	# 模拟第1层玩家胜：敌人HP归零 → 淘汰 → GAME_OVER → 层2
	enemy.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	_assert(floors.size() == 2 and floors[1][0] == 2, "2a: 层胜后进入第2层（实际=%s）" % str(floors))
	_assert(floors.size() > 1 and floors[1][1] == "漩涡鸣人（仙人模式）", "2b: 第2层敌人=仙人鸣人（实际=%s）" % (floors[1][1] if floors.size() > 1 else "?"))
	# 层间恢复：玩家满血
	var player2: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 1:
			player2 = p
			break
	_assert(player2 != null and player2.hp == player2.character.max_hp, "2c: 层间玩家满血（实际=%.1f/%d）" % [player2.hp, player2.character.max_hp])
	_assert(player2.energy == 0, "2d: 层间玩家气重置（实际=%d）" % player2.energy)

	# 第2层敌人（仙人鸣人）也有尖塔祝福
	var enemy2: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 2:
			enemy2 = p
			break
	_assert(enemy2 != null and enemy2.energy == 2, "2e: 第2层敌人祝福2气（实际=%s）" % (str(enemy2.energy) if enemy2 else "?"))

	# 模拟第2层胜 → 第3层（司马懿）
	enemy2.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	_assert(floors.size() == 3 and floors[2][1] == "司马懿（狂）", "3a: 第3层敌人=司马懿（实际=%s）" % (floors[2][1] if floors.size() > 2 else "?"))

	# 模拟第3层胜 → 通关
	var enemy3: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 2:
			enemy3 = p
			break
	enemy3.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	_assert(victory.size() == 1, "4a: 3层通关触发胜利（实际=%d）" % victory.size())
	_assert(defeat.is_empty(), "4b: 未触发失败")
	_assert(floors.size() == 3, "4c: 共3层（实际=%d）" % floors.size())

	# 模拟失败场景：新塔，玩家死 → 失败
	var tower2 := TowerManager.new()
	add_child(tower2)
	var defeat2: Array = []
	tower2.tower_defeat.connect(func(): defeat2.append(true))
	tower2.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame
	# 玩家死亡 → 淘汰 → GAME_OVER（敌人存活）→ 失败
	for p in gm.get_alive_players():
		if p.team_id == 1:
			p.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	_assert(defeat2.size() == 1, "5: 玩家全灭触发失败（实际=%d）" % defeat2.size())

	tower.queue_free()
	tower2.queue_free()

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
