## 慈悲尖塔敌人机制测试
## 覆盖：尖塔祝福、破败王者之刃3阶段+悲痛刷新、反馈怒标记、鬼才连赢回合、
##      仙人之力聚气+1、蛙组手必中真伤、谋略控制免疫
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 慈悲尖塔敌人机制测试 ===")
	await get_tree().process_frame

	var broken_char := load("res://resources/characters/tower/破败王者（怒）.tres") as CharacterData
	var sage_char := load("res://resources/characters/tower/漩涡鸣人（仙人模式）.tres") as CharacterData
	var sima_char := load("res://resources/characters/tower/司马懿（狂）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var new_shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	var might_gai_char := load("res://resources/characters/迈特凯.tres") as CharacterData
	if broken_char == null or sage_char == null or sima_char == null or naruto_char == null or sasuke_char == null or new_shisui_char == null or might_gai_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_blessing(broken_char, naruto_char)
	await _test_blade(broken_char, might_gai_char)
	await _test_fury(sima_char, naruto_char)
	await _test_genius(sima_char, naruto_char)
	await _test_sage(sage_char, naruto_char)
	await _test_frog_kata(sage_char, new_shisui_char)
	await _test_strategy(sima_char, sasuke_char)

	print("=== 塔敌人测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ 测试1：尖塔祝福（开局2气） ═══════════════════════
func _test_blessing(broken_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试1：尖塔祝福 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "破败", "character": broken_char, "is_human": true},
			{"name": "玩家", "character": naruto_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var enemy: PlayerState = gm.get_player(0)
	var player: PlayerState = gm.get_player(1)
	_assert(enemy.energy == 2, "1a: 破败开局2气（实际=%d）" % enemy.energy)
	_assert(player.energy == 0, "1b: 玩家无祝福0气（实际=%d）" % player.energy)

## ═════════ 测试2：破败王者之刃（3阶段+悲痛刷新） ═══════════
## 靶子用迈特凯（16血）防止阶段1的50%伤害打死目标
func _test_blade(broken_char: CharacterData, might_gai_char: CharacterData) -> void:
	print("--- 测试2：破败王者之刃 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "破败", "character": broken_char, "is_human": true},
			{"name": "靶子", "character": might_gai_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var enemy: PlayerState = gm.get_player(0)
	var player: PlayerState = gm.get_player(1)

	# R1：破败胜 → 普攻（阶段1：1伤 + 目标现有HP 50%）
	enemy.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	enemy.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(enemy, "普攻"), 1)
	# 靶子16血：普攻1 + 50%*16=8 → 7
	_assert(player.hp == 7.0, "2a: 阶段1普攻1+50%%伤害=9（16→7，实际=%.1f）" % player.hp)
	_assert(enemy.blade_stage == 1, "2b: 阶段计数=1（实际=%d）" % enemy.blade_stage)

	# R2：破败胜 → 破败掉血后普攻（阶段2：恢复自身一半生命值）
	enemy.hp = 6.0
	enemy.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	enemy.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(enemy, "普攻"), 1)
	_assert(enemy.hp == 12.0, "2c: 阶段2恢复半血（6→12，实际=%.1f）" % enemy.hp)
	_assert(enemy.blade_stage == 2, "2d: 阶段计数=2（实际=%d）" % enemy.blade_stage)

	# R3：破败胜 → 普攻（阶段3：获得2气）
	var e_before: int = enemy.energy
	enemy.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	enemy.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(enemy, "普攻"), 1)
	_assert(enemy.energy == e_before + 2, "2e: 阶段3得2气（%d→%d）" % [e_before, enemy.energy])
	_assert(enemy.blade_stage == 3, "2f: 阶段计数=3（实际=%d）" % enemy.blade_stage)

	# R4：破败胜 → 普攻（阶段耗尽无附加效果，只有基础1伤）
	enemy.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	var p_hp4: float = player.hp
	gm.call("_resolve_round")
	enemy.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(enemy, "普攻"), 1)
	_assert(player.hp == p_hp4 - 1.0, "2g: 阶段耗尽仅普攻1伤（%.1f→%.1f）" % [p_hp4, player.hp])

	# R5：悲痛刷新——破败半血以下普攻 → 阶段重置为1（50%伤害）
	enemy.hp = 5.0
	enemy.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	var p_hp5: float = player.hp
	gm.call("_resolve_round")
	enemy.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(enemy, "普攻"), 1)
	# 靶子4血：普攻1 + 50%%*4=2 → 1
	_assert(player.hp == p_hp5 - 1.0 - p_hp5 * 0.5, "2h: 悲痛刷新后阶段1（普攻1+50%%伤害，%.1f→%.1f）" % [p_hp5, player.hp])

## ═════════ 测试3：反馈（怒标记） ═══════════════════════════
func _test_fury(sima_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试3：反馈怒标记 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "司马懿", "character": sima_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var sm: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)

	# R1：鸣人赢（司马懿输）→ 怒+1
	sm.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "3a: 鸣人胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(sm.fury_marks == 1, "3b: 猜拳输怒+1（实际=%d）" % sm.fury_marks)
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	# R2：鸣人再赢 → 怒+1（=2）
	sm.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(sm.fury_marks == 2, "3c: 再输怒+1（实际=%d）" % sm.fury_marks)
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	# R3：司马懿赢 → 普攻鸣人（0.5伤 + 怒2真伤）
	sm.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "3d: 司马懿胜（实际=%d）" % gm.get("_sole_winner_id"))
	sm.energy = 1
	var nar_hp3: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sm, "普攻"), 1)
	_assert(nar.hp == nar_hp3 - 0.5 - 2.0, "3e: 普攻0.5+怒2真伤=2.5（%.1f→%.1f）" % [nar_hp3, nar.hp])
	_assert(sm.fury_marks == 0, "3f: 普攻后怒清空（实际=%d）" % sm.fury_marks)

## ═════════ 测试4：鬼才（连赢2回合额外回合） ════════════════
func _test_genius(sima_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试4：鬼才 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "司马懿", "character": sima_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var sm: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)

	# R1：司马懿胜 → 聚气
	sm.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	# R2：司马懿连赢 → 鬼才触发（force_win_next_round）
	sm.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(sm.consecutive_rounds == 2, "4a: 连赢2回合（实际=%d）" % sm.consecutive_rounds)
	_assert(sm.force_win_next_round, "4b: 鬼才设置强制判胜")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	# R3：即使司马懿出剪刀（输给石头）也强制判胜（额外回合）
	sm.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "4c: 鬼才额外回合强制判胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(not sm.force_win_next_round, "4d: 强制判胜已消耗")

## ═════════ 测试5：仙人之力（聚气+1） ═══════════════════════
func _test_sage(sage_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试5：仙人之力 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "仙人鸣人", "character": sage_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var sage: PlayerState = gm.get_player(0)
	sage.current_gesture = PlayerState.Gesture.ROCK
	gm.get_player(1).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(sage.energy == 4, "5: 尖塔祝福2气+仙人之力聚气2=4（实际=%d）" % sage.energy)

## ═════════ 测试6：蛙组手（必中真伤） ═══════════════════════
func _test_frog_kata(sage_char: CharacterData, shisui_char: CharacterData) -> void:
	print("--- 测试6：蛙组手必中 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "仙人鸣人", "character": sage_char, "is_human": true},
			{"name": "止水", "character": shisui_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var sage: PlayerState = gm.get_player(0)
	var shs: PlayerState = gm.get_player(1)
	# 止水有幻影+气（可闪避），蛙组手必中 → 不触发闪避弹窗
	shs.phantom_count = 2
	shs.energy = 2
	sage.current_gesture = PlayerState.Gesture.ROCK
	shs.current_gesture = PlayerState.Gesture.SCISSORS
	var dodge_req: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req.append([pid, aid]))
	gm.call("_resolve_round")
	sage.energy = 2
	var shs_hp: float = shs.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sage, "蛙组手"), 1)
	_assert(shs.hp == shs_hp - 2.0, "6a: 蛙组手2真伤（%.1f→%.1f）" % [shs_hp, shs.hp])
	_assert(dodge_req.is_empty(), "6b: 必中不触发幻影闪避弹窗（实际=%d）" % dodge_req.size())
	_assert(shs.phantom_count == 2 and shs.energy == 2, "6c: 闪避资源未消耗（%d/%d）" % [shs.phantom_count, shs.energy])

## ═════════ 测试7：谋略（控制免疫） ═════════════════════════
func _test_strategy(sima_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- 测试7：谋略控制免疫 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "司马懿", "character": sima_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var sm: PlayerState = gm.get_player(0)
	var sas: PlayerState = gm.get_player(1)
	# 佐助胜 → 千鸟（2伤+麻痹1）打司马懿 → 谋略免疫麻痹
	sm.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	sas.energy = 2
	var sm_hp: float = sm.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "千鸟"), 0)
	_assert(sm.hp == sm_hp - 2.0, "7a: 千鸟2伤（%.1f→%.1f）" % [sm_hp, sm.hp])
	_assert(sm.paralyze_turns == 0, "7b: 谋略免疫麻痹（实际=%d）" % sm.paralyze_turns)

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
