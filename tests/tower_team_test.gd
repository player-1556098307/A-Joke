## 塔模式 AI 队友不打自己人测试
## 覆盖：AI 决策目标排除队友（单元）、塔模式真实对局 AI 队友只打敌人（流程）
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔模式 AI 不打自己人测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var enemy_char := load("res://resources/characters/tower/破败王者（怒）.tres") as CharacterData
	if naruto_char == null or sasuke_char == null or enemy_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_ai_target(naruto_char, sasuke_char, enemy_char)
	await _test_tower_flow(naruto_char, sasuke_char, enemy_char)

	print("=== AI队友测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 单元：AI 决策在 team 模式下排除队友
func _test_ai_target(naruto_char: CharacterData, sasuke_char: CharacterData, enemy_char: CharacterData) -> void:
	print("--- 单元：AI 决策目标排除队友 ---")
	var ai := AIController.new()
	var p0 := PlayerState.new(0, "玩家", naruto_char, true)
	p0.team_id = 1
	var p1 := PlayerState.new(1, "AI队友", sasuke_char, false)
	p1.team_id = 1
	p1.energy = 1
	var p2 := PlayerState.new(2, "敌人", enemy_char, false)
	p2.team_id = 2
	var dist := DistanceSystem.new()
	dist.setup([0, 1, 2])

	var dec := ai.decide_action(p1, [p0, p1, p2], dist)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "1a: AI队友用技能（实际=%d）" % dec["action"])
	_assert(dec["target_id"] == 2, "1b: 目标=敌人(2)（实际=%d）" % dec["target_id"])

	# 无敌人时（纯队友局）：无可选目标 → 聚气
	var dec2 := ai.decide_action(p1, [p0, p1], dist)
	_assert(dec2["action"] == PlayerState.ActionType.CHARGE, "1c: 无敌人时聚气（实际=%d）" % dec2["action"])

## 流程：塔模式 AI 队友真实对局只打敌人
func _test_tower_flow(naruto_char: CharacterData, sasuke_char: CharacterData, enemy_char: CharacterData) -> void:
	print("--- 流程：塔模式 AI 队友只打敌人 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
			{"name": "AI·佐助", "character": sasuke_char, "is_human": false, "team_id": 1},
			{"name": "破败王者", "character": enemy_char, "is_human": false, "team_id": 2},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var p0: PlayerState = gm.get_player(0)
	var p1: PlayerState = gm.get_player(1)
	var p2: PlayerState = gm.get_player(2)
	_assert(p1.team_id == 1 and p2.team_id == 2, "2a: 队伍分配正确（队友=%d 敌人=%d）" % [p1.team_id, p2.team_id])

	# AI队友(1)赢 → AI 自动行动 → 应打敌人(2)，真人(0)不掉血
	p1.energy = 1
	p0.current_gesture = PlayerState.Gesture.SCISSORS
	p1.current_gesture = PlayerState.Gesture.ROCK
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	var p0_hp: float = p0.hp
	var p2_hp: float = p2.hp
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "2b: AI队友胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(p2.hp == p2_hp - 1.0, "2c: 敌人被打1伤（%.1f→%.1f）" % [p2_hp, p2.hp])
	_assert(p0.hp == p0_hp, "2d: 真人队友不掉血（实际=%.1f）" % p0.hp)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
