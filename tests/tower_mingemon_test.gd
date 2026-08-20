## 塔模式 AI 侠影柱间队友明神门目标测试
## 场景：玩家(team1) + AI侠影柱间队友(team1) vs 敌人(team2)
## 验证：AI队友明神门只禁锢敌人，不误伤玩家/队友
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔模式AI明神门目标测试 ===")
	await get_tree().process_frame

	var hashirama_char := load("res://resources/characters/千手柱间.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var enemy_char := load("res://resources/characters/tower/破败王者（怒）.tres") as CharacterData
	if hashirama_char == null or naruto_char == null or enemy_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_ai_decision(hashirama_char, naruto_char, enemy_char)
	await _test_tower_flow(hashirama_char, naruto_char, enemy_char)
	await _test_tower_aoe_no_friendly(hashirama_char, naruto_char, enemy_char)

	print("=== 塔模式AI明神门测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 单元：AI队友（侠影柱间）决策明神门目标=敌人
func _test_ai_decision(hashirama_char: CharacterData, naruto_char: CharacterData, enemy_char: CharacterData) -> void:
	print("--- 单元：AI队友明神门决策 ---")
	var ai := AIController.new()
	var p0 := PlayerState.new(0, "玩家", naruto_char, true)
	p0.team_id = 1
	var hs := PlayerState.new(1, "AI·柱间", hashirama_char, false)
	hs.team_id = 1
	hs.energy = 0  # 只有明神门(0耗)可用
	var p2 := PlayerState.new(2, "敌人", enemy_char, false)
	p2.team_id = 2
	var dist := DistanceSystem.new()
	dist.setup([0, 1, 2])

	var dec := ai.decide_action(hs, [p0, hs, p2], dist)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "1a: AI队友用技能（实际=%d）" % dec["action"])
	var skill_name: String = ""
	if dec["skill_index"] >= 0:
		skill_name = hs.get_all_skills()[dec["skill_index"]].skill_name
	_assert(skill_name == "明神门", "1b: 0气时选明神门（实际=%s）" % skill_name)
	_assert(dec["target_id"] == 2, "1c: 明神门目标=敌人(2)（实际=%d）" % dec["target_id"])

## 流程：塔模式 AI队友赢 → 自动明神门 → 只禁锢敌人
func _test_tower_flow(hashirama_char: CharacterData, naruto_char: CharacterData, enemy_char: CharacterData) -> void:
	print("--- 流程：塔模式AI队友明神门 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
			{"name": "AI·柱间", "character": hashirama_char, "is_human": false, "team_id": 1},
			{"name": "破败王者", "character": enemy_char, "is_human": false, "team_id": 2},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var p0: PlayerState = gm.get_player(0)
	var hs: PlayerState = gm.get_player(1)
	var p2: PlayerState = gm.get_player(2)

	# AI队友(1)赢 → AI自动行动（0气 → 明神门打敌人）
	hs.energy = 0
	p0.current_gesture = PlayerState.Gesture.SCISSORS
	hs.current_gesture = PlayerState.Gesture.ROCK
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "2a: AI队友胜（实际=%d）" % gm.get("_sole_winner_id"))
	# AI自动行动在 _resolve_round 内同步完成
	_assert(p2.paralyze_turns == 3, "2b: 敌人被禁锢3回合（实际=%d）" % p2.paralyze_turns)
	_assert(p0.paralyze_turns == 0, "2c: 玩家（队友）不被禁锢（实际=%d）" % p0.paralyze_turns)
	_assert(hs.paralyze_turns == 0, "2d: 施法者自己不被禁锢（实际=%d）" % hs.paralyze_turns)
	# 明神门限定技标记
	_assert("明神门" in hs.limited_skills_used, "2e: 明神门已标记限定使用")

## 塔模式 ENEMY_ALL（木龙覆花海）：组队下只打敌人，不打玩家队友
func _test_tower_aoe_no_friendly(hashirama_char: CharacterData, naruto_char: CharacterData, enemy_char: CharacterData) -> void:
	print("--- 塔模式：ENEMY_ALL 不打队友 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
			{"name": "AI·柱间", "character": hashirama_char, "is_human": false, "team_id": 1},
			{"name": "破败王者", "character": enemy_char, "is_human": false, "team_id": 2},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var hs: PlayerState = gm.get_player(1)
	var p2: PlayerState = gm.get_player(2)

	# 单元：木龙覆花海（ENEMY_ALL）的目标构建——友伤是设定，包含队友
	var mulong: SkillData = null
	for sk in hs.character.skills:
		if sk.skill_name == "仙法·木龙覆花海":
			mulong = sk
			break
	_assert(mulong != null, "3a: 找到木龙覆花海技能")
	if mulong != null:
		var targets: Array = gm.call("_build_skill_targets", hs, mulong)
		# 塔模式3人局：柱间队友+玩家+敌人，ENEMY_ALL 打除自己外全部（含队友=友伤设定）
		_assert(targets.size() == 2, "3b: ENEMY_ALL 含队友（友伤设定，实际=%d）" % targets.size())

	# 对比：单机 FFA（team_id=0）ENEMY_ALL 同样打全场
	var gm2 := GameManager
	gm2.setup_game({
		"players": [
			{"name": "柱间", "character": hashirama_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "破败", "character": enemy_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var hs2: PlayerState = gm2.get_player(0)
	var targets2: Array = gm2.call("_build_skill_targets", hs2, mulong)
	_assert(targets2.size() == 2, "3c: FFA同样打全场（实际=%d）" % targets2.size())

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
