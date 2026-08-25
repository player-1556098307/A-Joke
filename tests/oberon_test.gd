## 奥伯龙完整机制测试
## 覆盖：角色属性/技能定义、夜之帷幕（准备阶段获气+伤害归零）、
##       梦之终结（结束夜幕+伤害x2）、仲夏夜之梦（3盾不可叠加）、
##       终极技能（3伤+麻痹+免疫下次攻击）、AI策略
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 奥伯龙完整机制测试 ===")
	await get_tree().process_frame

	var ob_char := load("res://resources/characters/奥伯龙.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if ob_char == null or naruto_char == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_stats_and_skills(ob_char, naruto_char)
	await _test_night_curtain(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_dream_end(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_midsummer_dream(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_fairy_tale(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_immune_next_attack(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_damage_zero_with_night(ob_char, naruto_char, sasuke_char, sakura_char)
	await _test_ai(ob_char, naruto_char, sasuke_char, sakura_char)

	print("=== 奥伯龙测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ 测试1：角色属性与技能定义 ═══════════════════════
func _test_stats_and_skills(ob_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试1：角色属性与技能定义 ---")
	_assert(ob_char.max_hp == 8, "1a: 奥伯龙HP=8（实际=%d）" % ob_char.max_hp)
	_assert(ob_char.grade == "S", "1b: 等级S（实际=%s）" % ob_char.grade)
	_assert("法师" in ob_char.tags and ob_char.tags.size() == 1, "1c: 标签=法师（实际=%s）" % str(ob_char.tags))

	var names: Array[String] = []
	for s in ob_char.skills:
		names.append(s.skill_name)
	_assert("普攻" in names and "夜之帷幕" in names and "梦之终结" in names and "仲夏夜之梦" in names and "于彼方点缀的梦之童话" in names, "1d: 技能完整（实际=%s）" % str(names))

	var basic: SkillData = null
	var curtain: SkillData = null
	var dream_end: SkillData = null
	var midsummer: SkillData = null
	var fairy: SkillData = null
	for s in ob_char.skills:
		match s.skill_name:
			"普攻": basic = s
			"夜之帷幕": curtain = s
			"梦之终结": dream_end = s
			"仲夏夜之梦": midsummer = s
			"于彼方点缀的梦之童话": fairy = s
	_assert(basic != null and basic.energy_cost == 1 and basic.max_range == 2, "1e: 普攻耗1气/范围2")
	_assert(curtain != null and curtain.is_passive and curtain.energy_cost == 0, "1f: 夜之帷幕被动/0耗")
	_assert(curtain != null and curtain.effects[0].effect_type == SkillEffect.EffectType.NIGHT_CURTAIN, "1g: 夜之帷幕效果=NIGHT_CURTAIN")
	_assert(dream_end != null and dream_end.energy_cost == 0, "1h: 梦之终结0耗")
	_assert(dream_end != null and dream_end.effects[0].effect_type == SkillEffect.EffectType.DREAM_END, "1i: 梦之终结效果=DREAM_END")
	_assert(midsummer != null and midsummer.energy_cost == 1, "1j: 仲夏夜之梦耗1气")
	_assert(midsummer != null and midsummer.effects[0].effect_type == SkillEffect.EffectType.MIDSUMMER_DREAM, "1k: 仲夏夜之梦效果=MIDSUMMER_DREAM")
	_assert(midsummer != null and int(midsummer.effects[0].value) == 3, "1l: 仲夏夜之梦护盾值=3")
	_assert(fairy != null and fairy.energy_cost == 5 and fairy.is_limited, "1m: 终极技能5气/限定技")
	_assert(fairy != null and fairy.max_range == 999, "1n: 终极技能全屏范围")

	# 被动和结束阶段技能不出现在操作阶段
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "奥伯龙", "character": ob_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ob: PlayerState = gm.get_player(0)
	var vis: Array[String] = []
	for s in ob.get_all_skills():
		vis.append(s.skill_name)
	# 操作阶段可见：普攻、仲夏夜之梦、终极技能（夜之帷幕被passives过滤、梦之终结被end_phase过滤）
	_assert(vis == ["普攻", "仲夏夜之梦", "于彼方点缀的梦之童话"], "1o: 可见技能=普攻/仲夏夜之梦/终极（实际=%s）" % str(vis))

## ═════════ 测试2：夜之帷幕（准备阶段获气+伤害归零） ═══════════
func _test_night_curtain(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试2：夜之帷幕 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# R1：奥伯龙(0)赢 → 准备阶段自动触发夜之帷幕 +1气
	# 注意：准备阶段在_round_resolve后、行动阶段前自动执行
	ob.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var nc_sig: Array = []
	gm.night_curtain_activated.connect(func(pid: int): nc_sig.append(pid))
	gm.call("_resolve_round")
	# 准备阶段自动触发：夜幕激活 +1气
	_assert(ob.night_curtain_active == true, "2a: 夜幕降临状态激活")
	_assert(ob.energy == 1, "2b: 夜之帷幕获1气（实际=%d）" % ob.energy)
	_assert(nc_sig.size() == 1 and nc_sig[0] == 0, "2c: night_curtain_activated信号")

	# 奥伯龙在夜幕下普攻 → 伤害归零
	ob.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ob, "普攻"), 2)
	_assert(p2.hp == 6.0, "2d: 夜幕下普攻伤害归零（6→6，实际=%.1f）" % p2.hp)
	# 气被消耗了（普攻1耗）
	_assert(ob.energy == 0, "2e: 夜幕下普攻仍消耗1气（实际=%d）" % ob.energy)

## ═════════ 测试3：梦之终结（结束夜幕+伤害x2） ═══════════════
func _test_dream_end(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试3：梦之终结 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# R1：奥伯龙赢 → 夜幕激活
	ob.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(ob.night_curtain_active == true, "3a: 夜幕激活")

	# 人类奥伯龙行动：充能（不攻击，本回合保持夜幕）
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	await get_tree().process_frame
	# 结束阶段：梦之终结弹窗（人类玩家），自动选自己
	var de_sig: Array = []
	gm.dream_end_used.connect(func(cid: int, tid: int): de_sig.append([cid, tid]))
	# 手动提交梦之终结（选择自己=0号）
	gm.submit_dream_end(0, 0)
	_assert(ob.night_curtain_active == false, "3b: 梦之终结后夜幕消失")
	_assert(ob.damage_double_next == true, "3c: 自己获得伤害x2标记")
	_assert(de_sig.size() == 1 and de_sig[0][0] == 0 and de_sig[0][1] == 0, "3d: dream_end_used信号")

	# R2：奥伯龙赢 → 准备阶段夜幕自动重新触发 → 手动取消后验证伤害x2
	ob.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# R2准备阶段：夜幕自动重新触发（每次准备阶段都会触发）
	_assert(ob.night_curtain_active == true, "3e: R2夜幕重新激活")
	# 手动取消夜幕以验证伤害x2效果
	ob.night_curtain_active = false
	ob.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ob, "普攻"), 2)
	_assert(p2.hp == 4.0, "3f: 梦之终结后普攻伤害x2（6→4，实际=%.1f）" % p2.hp)
	# x2标记消耗后清除
	_assert(ob.damage_double_next == false, "3g: 伤害x2标记消耗后清除")

## ═════════ 测试4：仲夏夜之梦（3盾不可叠加） ═════════════════
func _test_midsummer_dream(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试4：仲夏夜之梦 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]

	# R1：奥伯龙赢 → 夜幕激活
	ob.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(ob.night_curtain_active == true, "4a: 夜幕激活")

	# 使用仲夏夜之梦：消耗1气获得3盾
	ob.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ob, "仲夏夜之梦"), 0)
	_assert(ob.shield == 3, "4b: 仲夏夜之梦获得3盾（实际=%d）" % ob.shield)
	_assert(ob.energy == 0, "4c: 仲夏夜之梦消耗1气（实际=%d）" % ob.energy)

	# 再次使用仲夏夜之梦：不可叠加（取较大值，已有3盾不增加）
	# 需要先进入下一回合获得气
	ob.energy = 1
	# 直接调用 round_resolver 验证不可叠加
	var e := SkillEffect.new()
	e.effect_type = SkillEffect.EffectType.MIDSUMMER_DREAM
	e.value = 3
	e.target = SkillEffect.EffectTarget.SELF
	RoundResolver._apply_single_effect(e, ob, ob, gm.get("_distance_system"))
	_assert(ob.shield == 3, "4d: 仲夏夜之梦不可叠加（仍=3，实际=%d）" % ob.shield)

	# 非夜幕状态不能使用仲夏夜之梦
	ob.night_curtain_active = false
	ob.shield = 0
	ob.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ob, "仲夏夜之梦"), 0)
	# 非夜幕时技能被拒绝，进入ELIMINATION阶段
	_assert(ob.shield == 0, "4e: 非夜幕时仲夏夜之梦无效（盾仍=0，实际=%d）" % ob.shield)

## ═════════ 测试5：终极技能（3伤+麻痹） ═════════════════════
func _test_fairy_tale(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试5：终极技能 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]
	var p2: PlayerState = arr[3]

	# 奥伯龙赢 → 准备阶段自动触发夜幕 → 手动取消夜幕后使用终极技能
	# （夜幕下伤害归零，需先取消夜幕才能造成伤害）
	ob.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# 手动取消夜幕，使终极技能可以造成伤害
	ob.night_curtain_active = false
	ob.energy = 5  # 手动设5气
	var p2_hp_before: float = p2.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ob, "于彼方点缀的梦之童话"), 2)
	_assert(p2.hp == p2_hp_before - 3.0, "5a: 终极技能3伤（%.1f→%.1f）" % [p2_hp_before, p2.hp])
	_assert(p2.paralyze_turns == 1, "5b: 目标麻痹1回合（实际=%d）" % p2.paralyze_turns)
	_assert(ob.immune_next_attack == true, "5c: 自身获得免疫下次攻击标记")
	_assert(ob.energy == 0, "5d: 终极技能消耗5气（实际=%d）" % ob.energy)
	# 限定技已使用标记
	_assert("于彼方点缀的梦之童话" in ob.limited_skills_used, "5e: 限定技标记已记录")

## ═════════ 测试6：免疫下次攻击 ═════════════════════════════
func _test_immune_next_attack(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试6：免疫下次攻击 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]
	var p1: PlayerState = arr[2]

	# 手动设置免疫标记
	ob.immune_next_attack = true
	var hp_before: float = ob.hp

	# p1(鸣人)赢 → 普攻奥伯龙 → 免疫拦截
	p1.current_gesture = PlayerState.Gesture.ROCK
	ob.current_gesture = PlayerState.Gesture.SCISSORS
	for p in [arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p1.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(p1, "普攻"), 0)
	_assert(ob.hp == hp_before, "6a: 免疫下次攻击完全免伤（%.1f→%.1f）" % [hp_before, ob.hp])
	_assert(ob.immune_next_attack == false, "6b: 免疫标记消耗后清除")

	# 第二次攻击正常受伤
	hp_before = ob.hp
	p1.current_gesture = PlayerState.Gesture.ROCK
	ob.current_gesture = PlayerState.Gesture.SCISSORS
	for p in [arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p1.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(p1, "普攻"), 0)
	_assert(ob.hp == hp_before - 1.0, "6c: 免疫消耗后正常受伤（%.1f→%.1f）" % [hp_before, ob.hp])

## ═════════ 测试7：夜幕下所有伤害类型归零 ═════════════════════
func _test_damage_zero_with_night(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试7：夜幕下伤害归零 ---")
	var arr = await _setup4(ob_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ob: PlayerState = arr[1]
	var p2: PlayerState = arr[3]

	# 直接调用 round_resolver 验证夜幕下伤害归零
	ob.night_curtain_active = true
	var e := SkillEffect.new()
	e.effect_type = SkillEffect.EffectType.DAMAGE
	e.value = 3.0
	e.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var res := RoundResolver._apply_single_effect(e, ob, p2, gm.get("_distance_system"))
	_assert(res.get("damage_dealt", -1) == 0, "7a: 夜幕下DAMAGE伤害归零（实际=%.1f）" % res.get("damage_dealt", -1))
	_assert(p2.hp == 6.0, "7b: 目标未受伤（6.0，实际=%.1f）" % p2.hp)
	# 夜幕状态保留（不因攻击取消）
	_assert(ob.night_curtain_active == true, "7c: 夜幕状态保留")

	# 真实伤害也被夜幕归零
	e.effect_type = SkillEffect.EffectType.TRUE_DAMAGE
	e.value = 2.0
	res = RoundResolver._apply_single_effect(e, ob, p2, gm.get("_distance_system"))
	_assert(res.get("damage_dealt", -1) == 0, "7d: 夜幕下TRUE_DAMAGE归零（实际=%.1f）" % res.get("damage_dealt", -1))

## ═════════ 测试8：AI策略 ═══════════════════════════════════
func _test_ai(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试8：AI策略 ---")
	# AI奥伯龙
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "AI奥伯龙", "character": ob_char, "is_human": false},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ob: PlayerState = gm.get_player(0)
	var ai := AIController.new()
	# 5气时优先终极技能
	ob.energy = 5
	var result := ai.decide_action(ob, gm.get_alive_players(), gm.get("_distance_system"))
	_assert(result.get("action") == PlayerState.ActionType.USE_SKILL, "8a: 5气时选择使用技能")
	var skill_name := ""
	if result.get("skill_index", -1) >= 0:
		var all := ob.get_all_skills()
		if result["skill_index"] < all.size():
			skill_name = all[result["skill_index"]].skill_name
	_assert(skill_name == "于彼方点缀的梦之童话", "8b: 5气选终极技能（实际=%s）" % skill_name)

	# 夜幕下低血时选仲夏夜之梦
	ob.energy = 1
	ob.hp = 3
	ob.night_curtain_active = true
	result = ai.decide_action(ob, gm.get_alive_players(), gm.get("_distance_system"))
	skill_name = ""
	if result.get("action") == PlayerState.ActionType.USE_SKILL and result.get("skill_index", -1) >= 0:
		var all := ob.get_all_skills()
		if result["skill_index"] < all.size():
			skill_name = all[result["skill_index"]].skill_name
	_assert(skill_name == "仲夏夜之梦", "8c: 夜幕低血选仲夏夜之梦（实际=%s）" % skill_name)

	# 梦之终结AI目标选择
	ob.energy = 5
	var target := ai.decide_dream_end_target(ob, gm.get_alive_players())
	_assert(target != null, "8d: AI梦之终结目标非null")
	# 5气时优先标记自己
	_assert(target.player_id == 0, "8e: 5气时梦之终结标记自己（实际=%d）" % (target.player_id if target else -1))

## ═════════ 辅助函数 ═════════════════════════════════════════
func _setup4(ob_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData):
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "奥伯龙", "character": ob_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	return [gm, gm.get_player(0), gm.get_player(1), gm.get_player(2), gm.get_player(3)]

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
		print("FAIL: " + msg)
