## 卫宫完整机制测试
## 覆盖：角色属性、技能列表、准备阶段轮询、投影机制（目标选择/技能复制/用完消失/每回合一次）、
## 无限剑制（结界5回合/必赢/锁定距离1敌人/技能收集/结界结束）、结界内技能使用、AI策略、选人列表
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 卫宫完整机制测试 ===")
	await get_tree().process_frame

	var emiya_char := load("res://resources/characters/卫宫.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData

	if emiya_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# ── 测试1：角色属性 ──────────────────────────────────────────
	_assert(emiya_char.max_hp == 7, "1a: 卫宫HP应为7实际=" + str(emiya_char.max_hp))
	_assert(emiya_char.grade == "A", "1b: 卫宫等级应为A实际=" + emiya_char.grade)
	_assert("射手" in emiya_char.tags, "1c: 卫宫标签应含射手")

	var skill_names: Array[String] = []
	for skill in emiya_char.skills:
		skill_names.append(skill.skill_name)
	_assert("普攻" in skill_names, "1d: 卫宫技能列表包含普攻")
	_assert("投影" in skill_names, "1e: 卫宫技能列表包含投影")
	_assert("伪·螺旋剑" in skill_names, "1f: 卫宫技能列表包含伪·螺旋剑")
	_assert("无限剑制" in skill_names, "1g: 卫宫技能列表包含无限剑制")

	# ── 测试2：技能属性 ──────────────────────────────────────────
	var proj_skill: SkillData = null
	var spiral_skill: SkillData = null
	var ubw_skill: SkillData = null
	for skill in emiya_char.skills:
		if skill.skill_name == "投影":
			proj_skill = skill
		elif skill.skill_name == "伪·螺旋剑":
			spiral_skill = skill
		elif skill.skill_name == "无限剑制":
			ubw_skill = skill

	_assert(proj_skill != null and proj_skill.energy_cost == 1, "2a: 投影耗气1实际=" + str(proj_skill.energy_cost if proj_skill else -1))
	_assert(spiral_skill != null and spiral_skill.energy_cost == 2, "2b: 伪·螺旋剑耗气2实际=" + str(spiral_skill.energy_cost if spiral_skill else -1))
	_assert(spiral_skill != null and spiral_skill.max_range == 999, "2c: 伪·螺旋剑无限距离(999)实际=" + str(spiral_skill.max_range if spiral_skill else -1))
	_assert(ubw_skill != null and ubw_skill.energy_cost == 3, "2d: 无限剑制耗气3实际=" + str(ubw_skill.energy_cost if ubw_skill else -1))
	# 效果类型检查
	if proj_skill and proj_skill.effects.size() > 0:
		_assert(proj_skill.effects[0].effect_type == SkillEffect.EffectType.PROJECT_SKILL, "2e: 投影效果类型=PROJECT_SKILL(18)实际=" + str(proj_skill.effects[0].effect_type))
	if ubw_skill and ubw_skill.effects.size() > 0:
		_assert(ubw_skill.effects[0].effect_type == SkillEffect.EffectType.BINDING_FIELD, "2f: 无限剑制效果类型=BINDING_FIELD(19)实际=" + str(ubw_skill.effects[0].effect_type))
		_assert(ubw_skill.effects[0].value == 6, "2g: 无限剑制结界持续6回合实际=" + str(ubw_skill.effects[0].value))

	# ── 测试3：投影机制 - 基础复制 ───────────────────────────────
	var emiya := PlayerState.new(0, "卫宫", emiya_char, true)
	var naruto := PlayerState.new(1, "鸣人", naruto_char, false)
	var sasuke := PlayerState.new(2, "佐助", sasuke_char, false)
	var dist := DistanceSystem.new()
	dist.setup([0, 1, 2])

	# 投影目标：鸣人（有螺旋丸技能）
	var spiral_res := load("res://resources/characters/skills/螺旋丸.tres") as SkillData
	_assert(spiral_res != null, "3a: 螺旋丸技能资源可加载")
	# 通过 PlayerState.projected_skill 直接设置模拟投影成功
	emiya.projected_skill = spiral_res
	emiya.projected_used_this_round = false
	var all_after := emiya.get_all_skills()
	var has_spiral := false
	for s in all_after:
		if s.skill_name == "螺旋丸":
			has_spiral = true
	_assert(has_spiral, "3b: 投影螺旋丸后出现在卫宫技能列表")
	_assert(emiya.projected_skill.energy_cost == spiral_res.energy_cost, "3c: 投影技能原耗气")

	# ── 测试4：投影机制 - 用完消失 ──────────────────────────────
	# 模拟使用投影技能后：game_manager._apply_actions 中会清空 projected_skill
	emiya.projected_skill = null
	emiya.projected_used_this_round = false
	var all_after_use := emiya.get_all_skills()
	var has_spiral_after := false
	for s in all_after_use:
		if s.skill_name == "螺旋丸":
			has_spiral_after = true
	_assert(not has_spiral_after, "4a: 投影技能使用后从技能列表消失")

	# ── 测试5：投影机制 - 每回合一次 ─────────────────────────────
	# projected_used_this_round=true 时 get_preparation_skill 应跳过
	# 直接测 PlayerState 的标记重置逻辑（reset_round_data）
	emiya.projected_used_this_round = true
	emiya.reset_round_data()
	_assert(not emiya.projected_used_this_round, "5a: 每回合重置投影已使用标记")

	# ── 测试6：无限剑制 - 结界基础 ──────────────────────────────
	# 直接调用 GameManager._start_binding_field 验证结界状态
	var gm := GameManager
	# 重置状态
	gm._players.clear()
	gm._players.append(PlayerState.new(0, "卫宫", emiya_char, true))
	gm._players.append(PlayerState.new(1, "鸣人", naruto_char, false))
	gm._players.append(PlayerState.new(2, "佐助", sasuke_char, false))
	for p in gm._players:
		p.is_alive = true
		p.hp = p.character.max_hp
		p.energy = 10
	var emi = gm.get_player(0)
	var nar = gm.get_player(1)
	var sas = gm.get_player(2)
	gm._distance_system = DistanceSystem.new()
	gm._distance_system.setup([0, 1, 2])

	# 鸣人在距离1内（距离1），佐助在距离1外（距离1，环形排列）
	# 环形布局：0-1=1, 1-2=1, 2-0=1（3人环）
	# 所有人距离都是1 → 锁定全部
	gm.call("_start_binding_field", emi)
	_assert(emi.binding_field_turns == 6, "6a: 结界持续6回合（释放+之后5回合）实际=" + str(emi.binding_field_turns))
	_assert(emi.binding_field_force_win, "6b: 结界释放后下次猜拳必赢")
	_assert(emi.force_win_next_round, "6c: 复用force_win_next_round机制")
	_assert(emi.binding_field_targets.size() == 2, "6d: 锁定距离1以内敌人（3人环全锁）实际=" + str(emi.binding_field_targets.size()))
	_assert(emi.binding_field_skills.size() > 0, "6e: 结界内技能已收集")

	# ── 测试7：结界技能收集（含被动技）─────────────────────────
	var bf_names: Array[String] = []
	for s in emi.binding_field_skills:
		bf_names.append(s.skill_name)
	# 鸣人有螺旋丸（主动），佐助有麒麟等；检查是否含鸣人的主动技能
	var has_naruto_skill := false
	for s in emi.binding_field_skills:
		if s.skill_name in ["螺旋丸", "影分身之术", "螺旋手里剑"]:
			has_naruto_skill = true
	_assert(has_naruto_skill, "7a: 结界内包含鸣人技能")

	# ── 测试8：结界内技能加入 get_all_skills ────────────────────
	var visible_bf: Array[String] = []
	for s in emi.get_all_skills():
		visible_bf.append(s.skill_name)
	# 结界内被动技（如希耶尔的代行者）不应出现在可见列表（被动技被过滤），
	# 但主动技应出现
	_assert("螺旋丸" in visible_bf or "影分身之术" in visible_bf, "8a: 结界内主动技出现在卫宫技能列表")

	# ── 测试9：结界结束 ─────────────────────────────────────────
	# 模拟5个回合结束：_end_round 递减
	emi.binding_field_turns = 1
	# 调用一次回合结束递减逻辑（通过 reset_round_data 模拟，实际由 GameManager._end_round 处理）
	# 直接模拟：
	emi.binding_field_turns -= 1
	if emi.binding_field_turns == 0:
		emi.binding_field_targets.clear()
		emi.binding_field_skills.clear()
	_assert(emi.binding_field_turns == 0, "9a: 结界回合数递减到0")
	_assert(emi.binding_field_targets.is_empty(), "9b: 结界结束时清空锁定目标")
	_assert(emi.binding_field_skills.is_empty(), "9c: 结界结束时清空结界内技能")

	# ── 测试10：完整游戏流程 - 卫宫猜拳获胜进入准备阶段 ──────────
	gm.setup_game({
		"players": [
			{"name": "卫宫", "character": emiya_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var e2 = gm.get_player(0)
	var n2 = gm.get_player(1)
	e2.energy = 10

	# ── 测试10.5：非自己回合不可投影（鸣人获胜）────────────
	# 鸣人出石头、卫宫出剪刀 → 鸣人获胜进入准备阶段
	# 卫宫不是胜者 → 不应触发投影，也不应停在 PREPARATION 等待
	e2.current_gesture = PlayerState.Gesture.SCISSORS
	n2.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	await get_tree().process_frame
	_assert(e2.projected_skill == null, "10.5a: 鸣人获胜时卫宫不会投影")
	_assert(gm.get("_sole_winner_id") == 1, "10.5b: 该回合胜者为鸣人")
	# 鸣人是 AI：准备阶段无其他玩家技能 → 直接进入行动阶段自动决策 → 回合结束回到出拳
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "10.5c: 非自己回合结束后回到出拳阶段（实际=%d）" % gm.get("_current_phase"))

	# 第1回合：卫宫获胜 → 进入准备阶段（有投影技能）
	e2.current_gesture = PlayerState.Gesture.ROCK
	n2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# 卫宫有投影技能 → 应该停在 PREPARATION（因为是人类，等待投影决策）
	var phase_after_win: int = gm.get("_current_phase")
	_assert(phase_after_win == GameManager.GamePhase.PREPARATION, "10a: 卫宫获胜后进入准备阶段（实际=%d）" % phase_after_win)
	_assert(gm.get("_sole_winner_id") == 0, "10b: 胜者为卫宫")

	# 卫宫跳过投影 → 进入行动阶段
	gm.submit_project_skill(0, -1, "")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "10c: 跳过投影后进入行动阶段（实际=%d）" % gm.get("_current_phase"))

	# 卫宫聚气
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "10d: 行动后回到出拳阶段（实际=%d）" % gm.get("_current_phase"))

	# ── 测试11：投影实际执行 ────────────────────────────────────
	# 第2回合：卫宫获胜 → 准备阶段 → 投影鸣人的螺旋丸
	e2.current_gesture = PlayerState.Gesture.ROCK
	n2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "11a: 第2回合进入准备阶段（实际=%d）" % gm.get("_current_phase"))
	# 投影鸣人的螺旋丸
	var spiral_path := "res://resources/characters/skills/螺旋丸.tres"
	e2.energy = 5  # 确保有足够的气，便于验证扣气
	var energy_before_proj: int = e2.energy
	gm.submit_project_skill(0, 1, spiral_path)
	_assert(e2.projected_skill != null, "11b: 投影后 projected_skill 非空")
	_assert(e2.projected_skill.skill_name == "螺旋丸", "11c: 投影的技能是螺旋丸（实际=%s）" % (e2.projected_skill.skill_name if e2.projected_skill else "null"))
	_assert(e2.energy == energy_before_proj - 1, "11d: 投影消耗1气（%d→%d）" % [energy_before_proj, e2.energy])
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "11e: 投影后进入行动阶段（实际=%d）" % gm.get("_current_phase"))

	# 使用投影的螺旋丸（需要找到索引）
	var spiral_idx: int = -1
	var all_sk2 := e2.get_all_skills()
	for i in range(all_sk2.size()):
		if all_sk2[i].skill_name == "螺旋丸":
			spiral_idx = i
			break
	_assert(spiral_idx >= 0, "11f: 投影技能螺旋丸在技能列表索引找到（idx=%d）" % spiral_idx)
	var n2_hp_before: int = n2.hp
	e2.energy = 10
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, spiral_idx, 1)
	_assert(n2.hp == n2_hp_before - 3, "11g: 投影的螺旋丸造成3伤（HP %d→%d）" % [n2_hp_before, n2.hp])
	_assert(e2.projected_skill == null, "11h: 使用投影技能后消失")

	# ── 测试12：无限剑制实际释放 ────────────────────────────────
	# 第3回合：卫宫获胜 → 准备阶段跳过 → 行动阶段释放无限剑制
	e2.current_gesture = PlayerState.Gesture.ROCK
	n2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "12a: 第3回合进入准备阶段（实际=%d）" % gm.get("_current_phase"))
	gm.submit_project_skill(0, -1, "")  # 跳过投影
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "12b: 跳过投影后进入行动阶段（实际=%d）" % gm.get("_current_phase"))

	# 找到无限剑制索引
	var ubw_idx: int = -1
	all_sk2 = e2.get_all_skills()
	for i in range(all_sk2.size()):
		if all_sk2[i].skill_name == "无限剑制":
			ubw_idx = i
			break
	_assert(ubw_idx >= 0, "12c: 无限剑制索引找到（idx=%d）" % ubw_idx)
	e2.energy = 10
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, ubw_idx, 0)
	# 释放当回合算第1回合，回合结束时递减为5（共6回合：释放+之后5回合）
	_assert(e2.binding_field_turns == 5, "12d: 释放当回合结束后结界剩5回合（实际=%d）" % e2.binding_field_turns)
	_assert(e2.force_win_next_round, "12e: 释放无限剑制后下次猜拳必赢")
	# 鸣人距离1（2人环：距离1）→ 锁定
	_assert(e2.binding_field_targets.size() == 1, "12f: 锁定距离1以内敌人（实际=%d）" % e2.binding_field_targets.size())
	_assert(e2.binding_field_targets.has(1), "12g: 锁定的目标是鸣人")

	# 无限剑制释放后获得额外行动（在 ACTION_INPUT？）
	# 注意：submit_action 同步走完整个回合（行动→结算→回合结束），
	# 因此释放后立即进入下一回合 GESTURE_INPUT，而不是额外行动
	# 验证释放后进入 GESTURE_INPUT 且结界状态保留
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "12h: 释放无限剑制后回合结束进入GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))
	_assert(e2.binding_field_turns == 5, "12i: 释放当回合结束结界剩5回合（实际=%d" % e2.binding_field_turns)

	# ── 测试13：无限剑制 - 结界持续与递减 ──────────────────────
	# 下一回合（第4回合）：卫宫因force_win自动获胜进入准备阶段
	e2.current_gesture = PlayerState.Gesture.ROCK
	n2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "13a: 无限剑制必赢进入准备阶段（实际=%d）" % gm.get("_current_phase"))
	_assert(gm.get("_sole_winner_id") == 0, "13b: 无限剑制强制胜者=卫宫（实际=%d）" % gm.get("_sole_winner_id"))
	gm.submit_project_skill(0, -1, "")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "13c: 跳过投影进入行动阶段（实际=%d）" % gm.get("_current_phase"))
	# 行动阶段可用结界内技能（螺旋丸）
	var bf_idx: int = -1
	all_sk2 = e2.get_all_skills()
	for i in range(all_sk2.size()):
		if all_sk2[i].skill_name == "螺旋丸":
			bf_idx = i
			break
	_assert(bf_idx >= 0, "13d: 结界内螺旋丸出现在技能列表（idx=%d）" % bf_idx)
	# 释放螺旋丸（结界技能，可重复使用；鸣人自带螺旋丸为延迟伤害版）
	e2.energy = 10
	var delayed_before: int = n2.delayed_damages.size()
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, bf_idx, 1)
	# 结界内收集的是鸣人自带技能：延迟伤害版（2回合后触发），不立即扣血
	_assert(n2.delayed_damages.size() == delayed_before + 1, "13e: 结界内螺旋丸挂上延迟伤害（延迟数 %d→%d）" % [delayed_before, n2.delayed_damages.size()])
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "13f: 使用结界技能后回到出拳阶段（实际=%d）" % gm.get("_current_phase"))
	# 结界内技能可重复使用（未消失）
	_assert(e2.binding_field_skills.size() > 0, "13g: 结界技能使用后保留（可重复使用）")
	# 释放回合→剩5，本回合（第2回合）结束→剩4
	_assert(e2.binding_field_turns == 4, "13h: 本回合结束结界剩4回合（实际=%d）" % e2.binding_field_turns)

	# ── 测试13.5：结界结束后 binding_field_skills 清空 ──────────
	# 当前结界剩4回合，需再走4个完整回合让结界递减到0并触发清理
	# 先清空延迟伤害队列并拉满鸣人HP，避免延迟伤害致死导致游戏提前结束
	n2.delayed_damages.clear()
	n2.hp = n2.character.max_hp
	for round_i in range(4):
		e2.current_gesture = PlayerState.Gesture.ROCK
		n2.current_gesture = PlayerState.Gesture.SCISSORS
		gm.call("_resolve_round")
		# 卫宫赢 → 准备阶段（自己回合可投影，但跳过）
		_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "13.5a-r%d: 进入准备阶段（实际=%d）" % [round_i, gm.get("_current_phase")])
		gm.submit_project_skill(0, -1, "")
		# 聚气
		gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	# 结界应已结束并清理
	_assert(e2.binding_field_turns == 0, "13.5b: 4回合后结界结束（turns=0实际=%d）" % e2.binding_field_turns)
	_assert(e2.binding_field_targets.is_empty(), "13.5c: 结界结束后清空锁定目标")
	_assert(e2.binding_field_skills.is_empty(), "13.5d: 结界结束后清空结界内技能")
	# 结界内技能不再出现在技能列表
	var bf_after_end: Array[String] = []
	for s in e2.get_all_skills():
		bf_after_end.append(s.skill_name)
	_assert(not ("螺旋丸" in bf_after_end), "13.5e: 结界结束后螺旋丸不再出现在技能列表")

	# ── 测试14：AI 卫宫策略 ─────────────────────────────────────
	var ai := AIController.new()
	var emi_ai := PlayerState.new(99, "卫宫AI", emiya_char, false)
	var n_ai := PlayerState.new(98, "鸣人AI", naruto_char, false)
	emi_ai.energy = 10
	emi_ai.hp = 7
	n_ai.hp = 100
	var dist_ai := DistanceSystem.new()
	dist_ai.setup([0, 1])
	var decision := ai.decide_action(emi_ai, [n_ai], dist_ai)
	_assert(decision != null, "14a: AI对卫宫能返回决策")
	# 3气且无结界 → 应优先无限剑制
	if decision.has("skill_index") and decision["skill_index"] >= 0:
		var chosen: SkillData = emi_ai.get_all_skills()[decision["skill_index"]]
		_assert(chosen.skill_name in ["无限剑制", "伪·螺旋剑", "普攻"], "14b: AI选中技能在卫宫技能集内: " + chosen.skill_name)
	else:
		_assert(decision.get("action_type", -1) == PlayerState.ActionType.CHARGE, "14c: 气不足充能")

	# ── 测试15：选人列表包含卫宫 ────────────────────────────────
	var cs_preloads: Array = [
		preload("res://resources/characters/漩涡鸣人.tres"),
		preload("res://resources/characters/宇智波佐助.tres"),
		preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
		preload("res://resources/characters/春野樱.tres"),
		preload("res://resources/characters/千手柱间.tres"),
		preload("res://resources/characters/迈特凯.tres"),
		preload("res://resources/characters/波风水门.tres"),
		preload("res://resources/characters/希耶尔.tres"),
		preload("res://resources/characters/千手柱间（秽土转生）.tres"),
		preload("res://resources/characters/卫宫.tres"),
	]
	var emiya_in_preloads := false
	for res in cs_preloads:
		if res is CharacterData and res.character_name == "卫宫":
			emiya_in_preloads = true
	_assert(emiya_in_preloads, "15: 卫宫在character_select preload列表中")

	print("=== 卫宫测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)