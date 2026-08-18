## 宇智波泉奈完整机制测试
## 覆盖：角色属性、技能定义、荣耀解锁/触发/行动权转移/重新解锁、
## 无法选择状态、宇智波流招架（半伤+无法选择+反击封技）、豪火球延迟伤害、
## 目标过滤、AI 策略
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 宇智波泉奈完整机制测试 ===")
	await get_tree().process_frame

	var izuna_char := load("res://resources/characters/宇智波泉奈.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if izuna_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# ══ 测试1：角色属性 ══════════════════════════════════════════
	_assert(izuna_char.max_hp == 6, "1a: 泉奈HP=6（实际=%d）" % izuna_char.max_hp)
	_assert(izuna_char.grade == "A", "1b: 泉奈等级A（实际=%s）" % izuna_char.grade)
	_assert("刺客" in izuna_char.tags and "法师" in izuna_char.tags, "1c: 标签=刺客+法师")

	var izuna_skills: Array[String] = []
	for s in izuna_char.skills:
		izuna_skills.append(s.skill_name)
	_assert("普攻" in izuna_skills and "火遁·豪火球" in izuna_skills and "宇智波流" in izuna_skills and "宇智波的荣耀" in izuna_skills, "1d: 技能列表含普攻/豪火球/宇智波流/荣耀")

	# ═════════ 测试2：技能属性 ══════════════════════════════════
	var fireball: SkillData = null
	var stance: SkillData = null
	var glory: SkillData = null
	for s in izuna_char.skills:
		match s.skill_name:
			"火遁·豪火球": fireball = s
			"宇智波流": stance = s
			"宇智波的荣耀": glory = s

	_assert(fireball != null and fireball.energy_cost == 2, "2a: 豪火球耗气2（实际=%s）" % str(fireball.energy_cost if fireball else -1))
	_assert(fireball != null and fireball.max_range == 2, "2b: 豪火球射程2（实际=%s）" % str(fireball.max_range if fireball else -1))
	_assert(fireball != null and fireball.effects.size() == 2 and fireball.effects[0].effect_type == SkillEffect.EffectType.DAMAGE and fireball.effects[0].value == 2, "2c: 豪火球直接2伤")
	_assert(fireball != null and fireball.effects[1].effect_type == SkillEffect.EffectType.DELAYED_DAMAGE and fireball.effects[1].value == 1 and fireball.effects[1].duration == 2, "2d: 豪火球延迟1伤（下回合末触发，duration=2）")

	_assert(stance != null and stance.energy_cost == 2, "2e: 宇智波流耗气2（实际=%s）" % str(stance.energy_cost if stance else -1))
	_assert(stance != null and stance.effects[0].value == 1.5, "2f: 宇智波流突进1.5伤")
	_assert(stance != null and stance.effects[1].effect_type == SkillEffect.EffectType.UCHIHA_STANCE, "2g: 宇智波流含UCHIHA_STANCE(%d)效果（实际=%d）" % [SkillEffect.EffectType.UCHIHA_STANCE, stance.effects[1].effect_type if stance else -1])

	_assert(glory != null and glory.energy_cost == 4, "2h: 荣耀耗气4（实际=%s）" % str(glory.energy_cost if glory else -1))
	_assert(glory != null and glory.is_passive, "2i: 荣耀为被动技")
	_assert(glory != null and glory.effects[0].effect_type == SkillEffect.EffectType.GLORY_TAKEOVER, "2j: 荣耀效果=GLORY_TAKEOVER")

	# ═════════ 测试3：荣耀解锁机制（直接调用） ══════════════════
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "泉奈", "character": izuna_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var izuna: PlayerState = gm.get_player(0)

	izuna.energy = 3
	gm.call("_process_glory_unlock", izuna)
	_assert(not izuna.glory_unlocked, "3a: 3气不解锁荣耀")
	izuna.energy = 4
	gm.call("_process_glory_unlock", izuna)
	_assert(izuna.glory_unlocked, "3b: 4气自动解锁荣耀")
	_assert(izuna.energy == 4, "3c: 解锁不消耗气（仍4气）")

	# ═════════ 测试4：荣耀触发（他人回合）+ 行动权转移 ═══════════
	# 重新 setup，避免上一场 HP 残留
	gm.setup_game({
		"players": [
			{"name": "泉奈", "character": izuna_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var iz := gm.get_player(0)
	var nar := gm.get_player(1)
	var sas := gm.get_player(2)
	iz.energy = 4
	gm.call("_process_glory_unlock", iz)

	var glory_sigs: Array = []
	gm.glory_takeover.connect(func(c, t, d, a, cb): glory_sigs.append([c, t, d]))
	# 人类泉奈荣耀不再自动释放：监听 glory_required 信号，在回调中模拟"释放"
	gm.glory_required.connect(func(pid: int, tid: int):
		gm.submit_glory_decision(pid, true)
	)

	# 鸣人必胜：泉=SCISSORS, 鸣=ROCK, 佐=SCISSORS → ROCK 唯一胜（winners=[1]）
	iz.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var nar_hp_before: float = nar.hp
	gm.call("_resolve_round")

	# 荣耀在准备阶段自动触发：行动权转移给泉奈
	_assert(gm.get("_sole_winner_id") == 0, "4a: 荣耀夺取后回合主=泉奈（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(nar.hp == nar_hp_before - 2, "4b: 荣耀对鸣人造成2伤（HP %d→%d）" % [nar_hp_before, nar.hp])
	_assert(nar.skill_disabled_turns >= 1, "4c: 鸣人本回合失去技能（skill_disabled=%d）" % nar.skill_disabled_turns)
	_assert(iz.energy == 0, "4d: 荣耀消耗4气（4→0，实际=%d）" % iz.energy)
	_assert(not iz.glory_unlocked, "4e: 使用后解锁状态清空")
	_assert(iz.glory_used_this_round, "4f: 本回合荣耀已使用标记")
	_assert(glory_sigs.size() >= 1, "4g: glory_takeover信号已发射（实际=%d）" % glory_sigs.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "4h: 荣耀后进入行动阶段（行动权=泉奈，实际=%d）" % gm.get("_current_phase"))

	# 行动权在泉奈：聚气结束回合
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "4i: 回合结束回到出拳阶段")

	# 荣耀伤害入账结算统计
	var iz_stats = gm.get("_match_record").player_stats.get(0)
	var nar_stats = gm.get("_match_record").player_stats.get(1)
	_assert(iz_stats != null and iz_stats.total_damage_dealt >= 2.0, "4j: 荣耀伤害计入泉奈造成伤害统计（实际=%.1f）" % (iz_stats.total_damage_dealt if iz_stats else -1))
	_assert(nar_stats != null and nar_stats.total_damage_taken >= 2.0, "4k: 荣耀伤害计入鸣人承受伤害统计（实际=%.1f）" % (nar_stats.total_damage_taken if nar_stats else -1))

	# ═════════ 测试5：荣耀重新解锁 + 二次触发 ═══════════════════
	# 泉奈 1 气（上回合聚+1）。每轮泉胜聚气，3 轮后到 4 气 → 重新解锁
	for i in range(3):
		# 泉必胜：泉=ROCK, 鸣=SCISSORS, 佐=SCISSORS → ROCK 胜（泉）
		iz.current_gesture = PlayerState.Gesture.ROCK
		nar.current_gesture = PlayerState.Gesture.SCISSORS
		sas.current_gesture = PlayerState.Gesture.SCISSORS
		gm.call("_resolve_round")
		_assert(gm.get("_sole_winner_id") == 0, "5-%d: 泉奈回合主（实际=%d）" % [i + 1, gm.get("_sole_winner_id")])
		gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(iz.energy == 4, "5a: 聚气后4气（实际=%d）" % iz.energy)
	_assert(iz.glory_unlocked, "5b: 再次达到4气重新解锁荣耀")

	# 再次触发：鸣人回合 → 泉奈荣耀夺取
	iz.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "5c: 二次荣耀夺取回合权（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(iz.energy == 0, "5d: 二次荣耀消耗4气（实际=%d）" % iz.energy)
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)

	# ═════════ 测试6：荣耀不会在自己回合触发 ═══════════════════
	# 泉奈聚到4气解锁 → 自己回合获胜 → 不应触发荣耀（直接进入行动阶段）
	iz.energy = 4
	gm.call("_process_glory_unlock", iz)
	iz.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "6a: 泉奈获胜（回合主=泉奈）")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "6b: 自己回合直接行动（无荣耀拦截，实际=%d）" % gm.get("_current_phase"))
	_assert(iz.energy == 4, "6c: 自己回合荣耀未触发消耗（仍4气，实际=%d）" % iz.energy)
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)

	# ═════════ 测试7：无法选择状态（目标过滤） ══════════════════
	gm.setup_game({
		"players": [
			{"name": "泉奈", "character": izuna_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	iz = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	iz.energy = 10
	# 鸣人进入无法选择
	nar.untargetable_turns = 1

	# 泉奈普攻鸣人 → 目标被过滤 → 不造成伤害
	iz.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "7a: 泉奈回合（实际=%d）" % gm.get("_sole_winner_id"))
	var all_skills := iz.get_all_skills()
	var basic_idx: int = -1
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == "普攻":
			basic_idx = i
			break
	var nar_hp7: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(nar.hp == nar_hp7, "7b: 无法选择目标被过滤（鸣人不受伤，HP=%d）" % nar.hp)
	# 无目标仍消耗能量（apply_effects 先扣气）？验证目标过滤后技能不生效
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "7c: 回合正常结束回到出拳")

	# ═════════ 测试8：宇智波流招架（纯单元测试，避免AI自动行动干扰） ═══
	# 直接构造场景：泉奈处于招架状态，鸣人普攻 → 触发招架
	var iz8 := PlayerState.new(0, "泉奈", izuna_char, true)
	var nar8 := PlayerState.new(1, "鸣人", naruto_char, true)
	var dist8 := DistanceSystem.new()
	dist8.setup([0, 1])
	iz8.uchiha_stance = true
	iz8.energy = 0
	nar8.energy = 5

	# 鸣人普攻泉奈
	var basic_skill: SkillData = null
	for s in naruto_char.skills:
		if s.skill_name == "普攻":
			basic_skill = s
			break
	_assert(basic_skill != null, "8a: 鸣人普攻技能可获取")
	var iz_hp8: float = iz8.hp
	var nar_hp8: float = nar8.hp
	var logs8 := RoundResolver.apply_effects(nar8, basic_skill, [iz8], dist8)
	# 招架：普攻1伤 → 减半（ceil(0.5)=1）泉掉1血；鸣受反击1伤+封技；泉进入无法选择
	_assert(iz8.hp == iz_hp8 - 1, "8b: 招架减半普攻（泉HP %d→%d）" % [iz_hp8, iz8.hp])
	_assert(nar8.hp == nar_hp8 - 1, "8c: 招架反击鸣人1伤（HP %d→%d）" % [nar_hp8, nar8.hp])
	_assert(nar8.skill_disabled_turns >= 1, "8d: 鸣人本回合失去所有技能（skill_disabled=%d）" % nar8.skill_disabled_turns)
	_assert(iz8.untargetable_turns >= 1, "8e: 泉奈进入无法选择1回合")
	_assert(not iz8.uchiha_stance, "8f: 招架触发后解除")
	_assert(logs8.size() >= 1, "8g: 效果结算日志已生成")

	# ═══ 测试8.5：宇智波流技能使用（1.5伤 + 进入招架状态） ═══
	var iz85 := PlayerState.new(0, "泉奈", izuna_char, true)
	var nar85 := PlayerState.new(1, "鸣人", naruto_char, true)
	var dist85 := DistanceSystem.new()
	dist85.setup([0, 1])
	iz85.energy = 5
	var stance_skill: SkillData = null
	for s in izuna_char.skills:
		if s.skill_name == "宇智波流":
			stance_skill = s
			break
	_assert(stance_skill != null, "8.5a: 宇智波流技能可获取")
	var nar_hp85: float = nar85.hp
	var logs85 := RoundResolver.apply_effects(iz85, stance_skill, [nar85], dist85)
	_assert(nar85.hp == nar_hp85 - 1.5, "8.5b: 宇智波流造成1.5伤（HP %d→%d）" % [nar_hp85, nar85.hp])
	_assert(iz85.uchiha_stance, "8.5c: 使用宇智波流后进入招架状态")
	_assert(iz85.energy == 3, "8.5d: 宇智波流消耗2气（5→3，实际=%d）" % iz85.energy)

	# ═════════ 测试9：豪火球延迟伤害 ═══════════════════════════
	gm.setup_game({
		"players": [
			{"name": "泉奈", "character": izuna_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	iz = gm.get_player(0)
	nar = gm.get_player(1)
	iz.energy = 10

	# 第1回合：泉奈使用豪火球（2伤+延迟1伤）
	iz.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	all_skills = iz.get_all_skills()
	var fb_idx: int = -1
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == "火遁·豪火球":
			fb_idx = i
			break
	_assert(fb_idx >= 0, "9a: 豪火球索引找到")
	var nar_hp9: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, fb_idx, 1)
	_assert(nar.hp == nar_hp9 - 2, "9b: 豪火球立即2伤（HP %d→%d）" % [nar_hp9, nar.hp])
	_assert(nar.delayed_damages.size() == 1, "9c: 延迟伤害队列1条")
	_assert(nar.delayed_damages[0]["damage"] == 1 and nar.delayed_damages[0]["trigger_in"] == 1, "9d: 延迟1伤（使用当回合末 trigger_in 2→1，实际=%d）" % nar.delayed_damages[0]["trigger_in"])

	# 下一回合（第2回合）：延迟伤害触发
	var hp_before_burn: float = nar.hp
	gm.call("_process_delayed_damages")
	_assert(nar.hp == hp_before_burn - 1, "9e: 延迟1伤已触发（HP %d→%d）" % [hp_before_burn, nar.hp])
	_assert(nar.delayed_damages.is_empty(), "9f: 延迟队列已清空")

	# ═════════ 测试10：AI 决策 ═════════════════════════════════
	var ai := AIController.new()
	var iz2 := PlayerState.new(0, "泉奈", izuna_char, false)
	iz2.hp = 2.0
	iz2.energy = 4
	var nar2 := PlayerState.new(1, "鸣人", naruto_char, false)
	var sas2 := PlayerState.new(2, "佐助", sasuke_char, false)
	var dist2 := DistanceSystem.new()
	dist2.setup([0, 1, 2])
	var dec := ai.decide_action(iz2, [iz2, nar2, sas2], dist2)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "10a: 残血时AI使用技能（实际=%d）" % dec["action"])
	if dec["action"] == PlayerState.ActionType.USE_SKILL and dec["skill_index"] >= 0:
		var used_name: String = iz2.get_all_skills()[dec["skill_index"]].skill_name
		_assert(used_name == "宇智波流", "10b: 残血优先宇智波流（实际=%s）" % used_name)

	var iz3 := PlayerState.new(0, "泉奈", izuna_char, false)
	iz3.hp = 6.0
	iz3.energy = 6
	var dec2 := ai.decide_action(iz3, [iz3, nar2, sas2], dist2)
	_assert(dec2["action"] == PlayerState.ActionType.USE_SKILL, "10c: 满血多气使用技能（实际=%d）" % dec2["action"])
	if dec2["action"] == PlayerState.ActionType.USE_SKILL and dec2["skill_index"] >= 0:
		var s2_name: String = iz3.get_all_skills()[dec2["skill_index"]].skill_name
		_assert(s2_name == "火遁·豪火球" or s2_name == "宇智波流", "10d: 满血优先豪火球/宇智波流（实际=%s）" % s2_name)

	print("=== 泉奈测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)