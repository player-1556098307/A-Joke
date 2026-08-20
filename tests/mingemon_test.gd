## 明神门目标测试：只禁锢一名范围1玩家，而非全体
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 明神门目标测试 ===")
	await get_tree().process_frame

	var hashirama_char := load("res://resources/characters/千手柱间.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if hashirama_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_mingemon(hashirama_char, naruto_char, sasuke_char)
	await _test_mingemon_effect_target(hashirama_char)
	await _test_ai_mingemon(hashirama_char, naruto_char, sasuke_char)
	await _test_mulong_fuhaihua(hashirama_char, naruto_char, sasuke_char)

	print("=== 明神门测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _test_mingemon(hashirama_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- 对局：明神门只禁锢目标 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "柱间", "character": hashirama_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var hs: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	var sas: PlayerState = gm.get_player(2)

	# 柱间赢 → 释放明神门打鸣人（范围1）
	hs.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "1a: 柱间胜（实际=%d）" % gm.get("_sole_winner_id"))
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(hs, "明神门"), 1)
	_assert(nar.paralyze_turns == 3, "1b: 鸣人被禁锢3回合（实际=%d）" % nar.paralyze_turns)
	# 封技按回合末递减：释放当回合末-1 → 剩2（设计如此，下一回合仍封技）
	_assert(nar.skill_disabled_turns >= 2, "1c: 鸣人封技生效中（实际=%d）" % nar.skill_disabled_turns)
	_assert(sas.paralyze_turns == 0, "1d: 佐助不被禁锢（实际=%d）" % sas.paralyze_turns)
	_assert(sas.skill_disabled_turns == 0, "1e: 佐助不被封技（实际=%d）" % sas.skill_disabled_turns)

func _test_mingemon_effect_target(hashirama_char: CharacterData) -> void:
	print("--- 效果定义：明神门 target=ENEMY_SINGLE ---")
	var ms: SkillData = null
	for sk in hashirama_char.skills:
		if sk.skill_name == "明神门":
			ms = sk
			break
	_assert(ms != null, "2a: 找到明神门技能")
	if ms != null:
		for eff in ms.effects:
			_assert(eff.target == SkillEffect.EffectTarget.ENEMY_SINGLE, "2b: 效果target=ENEMY_SINGLE(%d)（实际=%d）" % [SkillEffect.EffectTarget.ENEMY_SINGLE, eff.target])
		_assert(ms.min_range == 1 and ms.max_range == 1, "2c: 范围1（%d~%d）" % [ms.min_range, ms.max_range])

## AI 柱间释放明神门：只禁锢一个目标（非全体）
func _test_ai_mingemon(hashirama_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- AI：明神门只禁锢目标 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "柱间AI", "character": hashirama_char, "is_human": false},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var hs: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	var sas: PlayerState = gm.get_player(2)

	# AI柱间赢 → AI自动行动（明神门）
	hs.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "3a: AI柱间胜（实际=%d）" % gm.get("_sole_winner_id"))
	# AI自动行动在 _resolve_round 内同步完成
	var paralyzed_count := 0
	if nar.paralyze_turns > 0:
		paralyzed_count += 1
	if sas.paralyze_turns > 0:
		paralyzed_count += 1
	_assert(paralyzed_count <= 1, "3b: 明神门最多禁锢1人（实际=%d，鸣人=%d 佐助=%d）" % [paralyzed_count, nar.paralyze_turns, sas.paralyze_turns])

## 木龙覆花海（ENEMY_ALL）：禁锢所有敌人（符合描述，与明神门对比）
func _test_mulong_fuhaihua(hashirama_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- 对比：木龙覆花海禁锢所有 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "柱间", "character": hashirama_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var hs: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	var sas: PlayerState = gm.get_player(2)
	hs.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	hs.energy = 4
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(hs, "仙法·木龙覆花海"), 1)
	_assert(nar.paralyze_turns == 3 and sas.paralyze_turns == 3, "4a: 木龙覆花海禁锢所有敌人（鸣人=%d 佐助=%d）" % [nar.paralyze_turns, sas.paralyze_turns])

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
