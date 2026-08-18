## 迈特凯修复验证测试（针对两个 bug）
## Bug1: 鸣人放影分身导致 shield 被污染为 -1（全挡护盾）→ 受击全被"护盾格挡"
## Bug2: 夕象伤害 = 1 + (consecutive_rounds - 1)，断连后回到 1
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

var gm: GameManager
var gai: PlayerState
var naruto: PlayerState

func _ready() -> void:
	print("=== 迈特凯修复验证测试 ===")
	await get_tree().process_frame

	var gai_char := load("res://resources/characters/迈特凯.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if gai_char == null or naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	gm = GameManager
	gm.setup_game({
		"players": [
			{"name": "迈特凯", "character": gai_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	gai = gm.get_player(0)
	naruto = gm.get_player(1)
	print("[FIX] 初始 gai hp=%d naruto hp=%d" % [gai.hp, naruto.hp])

	# 先解锁八门（直接模拟聚气8次）
	for i in range(8):
		gm.call("_process_gate_open", gai)
	_assert(gai.gate_count == 8, "0a: 八门全开 gate_count=8")
	var unlocked_names: Array[String] = []
	for s in gai.unlocked_skills:
		unlocked_names.append(s.skill_name)
	_assert("夕象" in unlocked_names, "0b: 夕象已解锁")

	# ── 测试1：鸣人放影分身不再产生护盾 ─────────────────────────────
	# 找到鸣人的影分身技能
	var shadow_skill: SkillData = null
	for skill in naruto.character.skills:
		if skill.skill_name == "影分身":
			shadow_skill = skill
	_assert(shadow_skill != null, "1a: 找到鸣人影分身技能")

	naruto.energy = 10
	naruto.shield = 0
	naruto.clone_count = 0
	var dist_sys: DistanceSystem = gm.get("_distance_system")
	var logs := RoundResolver.apply_effects(naruto, shadow_skill, [naruto], dist_sys)
	_assert(naruto.clone_count == 1, "1b: 影分身召唤成功 clone_count=1")
	_assert(naruto.shield == 0, "1c: 影分身后 shield 仍为 0（修复：不再被 -1 全挡护盾污染，实际=%d）" % naruto.shield)

	# 验证 _emit_effect_signals 不再对 CLONE_SHIELD 发射 player_shielded
	var shield_signals: Array = []
	gm.player_shielded.connect(func(pid: int, sv: int): shield_signals.append([pid, sv]))
	for entry in logs:
		gm.call("_emit_effect_signals", entry)
	_assert(shield_signals.is_empty(), "1d: CLONE_SHIELD 不触发 player_shielded 信号（修复）")

	# ── 测试2：夕象伤害 = 连续回合数（连续赢 → 增伤） ──────────────────
	# 连续4回合迈特凯赢：consecutive_rounds 依次 1/2/3/4
	# 前3回合聚气，第4回合放夕象 → 伤害应为 4
	naruto.clone_count = 0
	naruto.shield = 0
	naruto.hp = 6
	gai.energy = 0

	for i in range(3):
		# 迈特凯赢（石头 vs 剪刀）
		gai.current_gesture = PlayerState.Gesture.ROCK
		naruto.current_gesture = PlayerState.Gesture.SCISSORS
		gm.call("_resolve_round")
		_assert(gm.get("_sole_winner_id") == 0, "2a-%d: 第%d回合迈特凯胜" % [i + 1, i + 1])
		_assert(gai.consecutive_rounds == i + 1, "2a-%d: consecutive_rounds=%d（期望%d）" % [i + 1, gai.consecutive_rounds, i + 1])
		gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
		_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "2a-%d: 回合结束回到出拳" % (i + 1))

	# 第4回合：放夕象
	gai.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gai.consecutive_rounds == 4, "2b: 连续4回合 consecutive=4（实际=%d）" % gai.consecutive_rounds)
	var xx_idx: int = -1
	var all_skills := gai.get_all_skills()
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == "夕象":
			xx_idx = i
			break
	_assert(xx_idx >= 0, "2c: 夕象索引找到 idx=%d" % xx_idx)
	var naruto_hp_before: int = naruto.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, xx_idx, 1)
	_assert(naruto.hp == naruto_hp_before - 4, "2d: 夕象连击4回合造成4伤（HP %d→%d，期望%d）" % [naruto_hp_before, naruto.hp, naruto_hp_before - 4])

	# ── 测试3：断连后 consecutive 重置，伤害回到 1 ───────────────────
	# 第5回合：鸣人赢（剪刀 vs 石头）
	gai.current_gesture = PlayerState.Gesture.SCISSORS
	naruto.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "3a: 第5回合鸣人胜（断连）")
	# AI 鸣人自动行动（可能聚气/攻击），保持简单：不管它
	await get_tree().process_frame

	# 第6回合：迈特凯赢 → consecutive 重置为 1，放夕象伤害应回 1
	naruto.clone_count = 0
	naruto.shield = 0
	gai.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gai.consecutive_rounds == 1, "3b: 断连后 consecutive_rounds 重置为 1（实际=%d）" % gai.consecutive_rounds)
	var xx_idx2: int = -1
	all_skills = gai.get_all_skills()
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == "夕象":
			xx_idx2 = i
			break
	var hp_before2: int = naruto.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, xx_idx2, 1)
	_assert(naruto.hp == hp_before2 - 1, "3c: 断连后夕象伤害回到1（HP %d→%d，期望%d）" % [hp_before2, naruto.hp, hp_before2 - 1])

	print("=== 修复验证测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)