## 波风水门（漂泊寻者）完整机制测试
## 覆盖：角色属性、飞雷神标记/聚气/拔除、螺旋丸、漂泊九尾三段攻击、AI策略
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 波风水门（漂泊寻者）完整机制测试 ===")

	await get_tree().process_frame

	var minato_char := load("res://resources/characters/波风水门.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData

	if minato_char == null:
		print("FATAL: 波风水门.tres 加载失败")
		get_tree().quit(1)
		return
	if naruto_char == null:
		print("FATAL: 漩涡鸣人.tres 加载失败")
		get_tree().quit(1)
		return

	print("[DEBUG] 角色资源加载成功: minato=%s naruto=%s" % [minato_char.character_name, naruto_char.character_name])

	var minato := PlayerState.new(0, "水门", minato_char, true)
	var naruto := PlayerState.new(1, "鸣人", naruto_char, false)

	# ── 测试1：角色属性 ──────────────────────────────────────────
	_assert(minato.character.max_hp == 8, "1a: 波风水门HP应为8实际=" + str(minato.character.max_hp))
	_assert(minato.character.grade == "S", "1b: 波风水门等级应为S实际=" + minato.character.grade)
	_assert(minato.hp == 8, "1c: 初始HP应为8实际=" + str(minato.hp))
	_assert("刺客" in minato.character.tags, "1d: 波风水门标签应含刺客")

	# ── 测试2：技能列表验证 ──────────────────────────────────────
	var skill_names: Array[String] = []
	for skill in minato.character.skills:
		skill_names.append(skill.skill_name)
	_assert("普攻" in skill_names, "2a: 技能列表包含普攻")
	_assert("飞雷神" in skill_names, "2b: 技能列表包含飞雷神")
	_assert("飞雷神聚" in skill_names, "2c: 技能列表包含飞雷神聚")
	_assert("飞雷神拔除" in skill_names, "2d: 技能列表包含飞雷神拔除")
	_assert("螺旋丸" in skill_names, "2e: 技能列表包含螺旋丸")
	_assert("漂泊九尾" in skill_names, "2f: 技能列表包含漂泊九尾")

	# ── 测试3：飞雷神技能属性 ────────────────────────────────────
	var ftg_skill: SkillData = null
	for skill in minato.character.skills:
		if skill.skill_name == "飞雷神":
			ftg_skill = skill
	_assert(ftg_skill != null, "3a: 飞雷神技能存在")
	_assert(ftg_skill.energy_cost == 0, "3b: 飞雷神耗气为0实际=" + str(ftg_skill.energy_cost))
	_assert(ftg_skill.ftg_cost == 1, "3c: 飞雷神消耗1标记实际=" + str(ftg_skill.ftg_cost))
	_assert(ftg_skill.max_range == 3, "3d: 飞雷神范围为3实际=" + str(ftg_skill.max_range))

	# ── 测试4：螺旋丸技能属性 ────────────────────────────────────
	var rasengan: SkillData = null
	for skill in minato.character.skills:
		if skill.skill_name == "螺旋丸":
			rasengan = skill
	_assert(rasengan != null, "4a: 螺旋丸技能存在")
	_assert(rasengan.energy_cost == 2, "4b: 螺旋丸耗气为2实际=" + str(rasengan.energy_cost))
	_assert(rasengan.max_range >= 999, "4c: 螺旋丸范围无限实际=" + str(rasengan.max_range))

	# ── 测试5：漂泊九尾技能属性 ──────────────────────────────────
	var nine_tails: SkillData = null
	for skill in minato.character.skills:
		if skill.skill_name == "漂泊九尾":
			nine_tails = skill
	_assert(nine_tails != null, "5a: 漂泊九尾技能存在")
	_assert(nine_tails.energy_cost == 5, "5b: 漂泊九尾耗气为5实际=" + str(nine_tails.energy_cost))
	_assert(nine_tails.is_limited, "5c: 漂泊九尾为限定技")

	# ── 测试6：飞雷神聚为非被动（可主动使用）────────────────────
	var ftg_charge: SkillData = null
	for skill in minato.character.skills:
		if skill.skill_name == "飞雷神聚":
			ftg_charge = skill
	_assert(ftg_charge != null, "6a: 飞雷神聚技能存在")
	_assert(not ftg_charge.is_passive, "6b: 飞雷神聚为非被动技（可主动使用）")

	# ── 初始化 GameManager 环境 ──────────────────────────────────
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "水门", "character": minato_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var gm_minato: PlayerState = gm.get_player(0)
	var gm_naruto: PlayerState = gm.get_player(1)
	var dist_sys: DistanceSystem = gm.get("_distance_system")

	# ── 测试7：开局飞雷神标记初始化为3 ────────────────────────────
	_assert(gm_minato.ftg_marks == 3, "7: 开局飞雷神标记为3实际=" + str(gm_minato.ftg_marks))

	# ── 测试8：飞雷神聚增加标记 ──────────────────────────────────
	var marks_before := gm_minato.ftg_marks
	var ftg_charge_effect := SkillEffect.new()
	ftg_charge_effect.effect_type = SkillEffect.EffectType.FTG_CHARGE
	ftg_charge_effect.value = 1
	ftg_charge_effect.target = SkillEffect.EffectTarget.SELF
	var ftg_charge_skill := SkillData.new()
	ftg_charge_skill.skill_name = "飞雷神聚"
	ftg_charge_skill.energy_cost = 0
	ftg_charge_skill.min_range = 0
	ftg_charge_skill.max_range = 0
	ftg_charge_skill.effects = [ftg_charge_effect]
	gm_minato.energy = 5
	var charge_logs := RoundResolver.apply_effects(gm_minato, ftg_charge_skill, [gm_minato], dist_sys)
	_assert(gm_minato.ftg_marks == marks_before + 1, "8: 飞雷神聚后标记+1实际=" + str(gm_minato.ftg_marks))

	# ── 测试9：飞雷神标记造成0.5伤害 ─────────────────────────────
	var naruto_hp_before := gm_naruto.hp
	gm_minato.energy = 5
	# 飞雷神消耗1标记
	var ftg_logs := RoundResolver.apply_effects(gm_minato, ftg_skill, [gm_naruto], dist_sys)
	var ftg_result: Dictionary = {}
	for entry in ftg_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.FTG_MARK:
			ftg_result = entry.get("result", {})
	_assert(ftg_result.get("ftg_marked", false), "9a: 飞雷神标记成功")
	_assert(ftg_result.get("damage_dealt", 0) == 0.5, "9b: 飞雷神造成0.5伤害实际=" + str(ftg_result.get("damage_dealt", -1)))
	_assert(gm_naruto.hp == naruto_hp_before - 0.5, "9c: 鸣人HP从" + str(naruto_hp_before) + "减至" + str(gm_naruto.hp))
	_assert(gm_minato.ftg_marks == marks_before, "9d: 飞雷神消耗后标记数恢复（聚+1后用-1）实际=" + str(gm_minato.ftg_marks))

	# ── 测试10：飞雷神标记添加到ftg_marked_by ────────────────────
	_assert(gm_naruto.ftg_marked_by.has(0), "10: 鸣人被水门标记（ftg_marked_by包含0）")

	# ── 测试10.5：无敌状态下飞雷神只免疫伤害、标记仍生效 ──────────
	# 场景：迈特凯八门全开无敌，被飞雷神标记——伤害应免疫，标记应照常施加
	var gai_char_ftg := load("res://resources/characters/迈特凯.tres") as CharacterData
	var gai_ftg := PlayerState.new(0, "迈特凯", gai_char_ftg, false)
	var minato_ftg := PlayerState.new(1, "水门", minato_char, false)
	var dist_ftg := DistanceSystem.new()
	dist_ftg.setup([0, 1])
	gai_ftg.hp = 15.0
	gai_ftg.clone_count = 1
	gai_ftg.invincible_turns = 2  # 八门全开无敌状态
	minato_ftg.ftg_marks = 3
	minato_ftg.energy = 5
	# 找到飞雷神技能
	var ftg_skill_b: SkillData = null
	for skill in minato_ftg.character.skills:
		if skill.skill_name == "飞雷神":
			ftg_skill_b = skill
	_assert(ftg_skill_b != null, "10.5a: 找到飞雷神技能")
	var ftg_logs_b := RoundResolver.apply_effects(minato_ftg, ftg_skill_b, [gai_ftg], dist_ftg)
	var ftg_result_b: Dictionary = {}
	for entry in ftg_logs_b:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.FTG_MARK:
			ftg_result_b = entry.get("result", {})
	_assert(ftg_result_b.get("damage_dealt", -1) == 0.0, "10.5b: 无敌时飞雷神伤害为0实际=" + str(ftg_result_b.get("damage_dealt", -1)))
	_assert(ftg_result_b.get("ftg_marked", false), "10.5c: 无敌时飞雷神标记仍生效")
	_assert(gai_ftg.hp == 15.0, "10.5d: 无敌时HP不变实际=" + str(gai_ftg.hp))
	_assert(gai_ftg.clone_count == 1, "10.5e: 无敌时分身不被消耗实际=" + str(gai_ftg.clone_count))
	_assert(gai_ftg.ftg_marked_by.has(1), "10.5f: 无敌时目标仍被标记（水门id=1）")

	# ── 测试11：飞雷神拔除清除标记 ────────────────────────────────
	var ftg_remove_effect := SkillEffect.new()
	ftg_remove_effect.effect_type = SkillEffect.EffectType.FTG_REMOVE
	ftg_remove_effect.target = SkillEffect.EffectTarget.SELF
	var ftg_remove_skill := SkillData.new()
	ftg_remove_skill.skill_name = "飞雷神拔除"
	ftg_remove_skill.energy_cost = 0
	ftg_remove_skill.min_range = 0
	ftg_remove_skill.max_range = 0
	ftg_remove_skill.effects = [ftg_remove_effect]
	gm_naruto.energy = 5
	var remove_logs := RoundResolver.apply_effects(gm_naruto, ftg_remove_skill, [gm_naruto], dist_sys)
	_assert(gm_naruto.ftg_marked_by.is_empty(), "11: 拔除后鸣人ftg_marked_by清空")

	# ── 测试12：螺旋丸造成3伤害 ──────────────────────────────────
	gm_minato.energy = 5
	var naruto_hp2 := gm_naruto.hp
	var rasengan_logs := RoundResolver.apply_effects(gm_minato, rasengan, [gm_naruto], dist_sys)
	var rasengan_result: Dictionary = {}
	for entry in rasengan_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
			rasengan_result = entry.get("result", {})
	_assert(rasengan_result.get("damage_dealt", 0) == 3, "12a: 螺旋丸造成3伤害实际=" + str(rasengan_result.get("damage_dealt", -1)))
	_assert(gm_naruto.hp == naruto_hp2 - 3, "12b: 鸣人HP从" + str(naruto_hp2) + "减至" + str(gm_naruto.hp))
	_assert(gm_minato.energy == 3, "12c: 螺旋丸消耗2气后剩余3实际=" + str(gm_minato.energy))

	# ── 测试13：漂泊九尾释放 — 第一段伤害 ────────────────────────
	# 重置状态
	gm_minato.hp = 8
	gm_minato.energy = 5
	gm_naruto.hp = 10
	gm_naruto.ftg_marked_by.clear()

	# 信号收集
	var invincible_started_signals: Array = []
	gm.nine_tails_invincible_started.connect(func(pid: int): invincible_started_signals.append(pid))
	var stage_changed_signals: Array = []
	gm.nine_tails_stage_changed.connect(func(pid: int, s: int): stage_changed_signals.append([pid, s]))
	var attack_signals: Array = []
	gm.nine_tails_attack.connect(func(pid: int, s: int, d: float, tids: Array[int]): attack_signals.append([pid, s, d, tids]))

	gm.call("_process_nine_tails_release", gm_minato)

	_assert(gm_minato.nine_tails_invincible, "13a: 九尾释放后进入无敌状态")
	_assert(gm_minato.nine_tails_stage == 1, "13b: 九尾阶段为1实际=" + str(gm_minato.nine_tails_stage))
	_assert(invincible_started_signals.size() >= 1, "13c: nine_tails_invincible_started信号已发射")
	_assert(stage_changed_signals.size() >= 1, "13d: nine_tails_stage_changed信号已发射")
	# 第一段：0.5x3=1.5伤害
	_assert(gm_naruto.hp == 10 - 1.5, "13e: 九尾咆哮0.5x3=1.5伤害，鸣人HP从10减至" + str(gm_naruto.hp))
	_assert(attack_signals.size() >= 1, "13f: nine_tails_attack信号已发射")

	# ── 测试14：漂泊九尾第二段（下回合结束）──────────────────────
	stage_changed_signals.clear()
	attack_signals.clear()
	# 记录当前鸣人HP
	var naruto_hp3 := gm_naruto.hp
	gm.call("_process_nine_tails_progress")

	_assert(gm_minato.nine_tails_stage == 2, "14a: 九尾阶段推进到2实际=" + str(gm_minato.nine_tails_stage))
	# 第二段：1x2=2伤害（2人游戏，距离必然<=2）
	_assert(gm_naruto.hp == naruto_hp3 - 2, "14b: 九尾大爪1x2=2伤害，鸣人HP从" + str(naruto_hp3) + "减至" + str(gm_naruto.hp))

	# ── 测试15：漂泊九尾第三段（下下回合结束）+ 退出无敌 ──────────
	stage_changed_signals.clear()
	attack_signals.clear()
	var invincible_ended_signals: Array = []
	gm.nine_tails_invincible_ended.connect(func(pid: int): invincible_ended_signals.append(pid))
	var naruto_hp4 := gm_naruto.hp
	gm.call("_process_nine_tails_progress")

	_assert(gm_minato.nine_tails_stage == 0, "15a: 九尾阶段回到0实际=" + str(gm_minato.nine_tails_stage))
	_assert(not gm_minato.nine_tails_invincible, "15b: 九尾无敌结束")
	_assert(invincible_ended_signals.size() >= 1, "15c: nine_tails_invincible_ended信号已发射")
	# 第三段：4伤害
	_assert(gm_naruto.hp == naruto_hp4 - 4, "15d: 九尾尾兽玉4伤害，鸣人HP从" + str(naruto_hp4) + "减至" + str(gm_naruto.hp))

	# ── 测试16：九尾无敌期间水门不受伤 ───────────────────────────
	gm_minato.nine_tails_invincible = true
	gm_minato.nine_tails_stage = 1
	gm_minato.hp = 8
	var minato_hp_before := gm_minato.hp
	var naruto_attack: SkillData = gm_naruto.character.skills[0]  # 普攻
	gm_naruto.energy = 5
	var atk_logs := RoundResolver.apply_effects(gm_naruto, naruto_attack, [gm_minato], dist_sys)
	var atk_result: Dictionary = {}
	for entry in atk_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
			atk_result = entry.get("result", {})
	_assert(atk_result.get("invincible", false), "16a: 九尾无敌状态标记invincible")
	_assert(atk_result.get("damage_dealt", 0) == 0, "16b: 九尾无敌下伤害为0")
	_assert(gm_minato.hp == minato_hp_before, "16c: 九尾无敌HP不变")

	# ── 测试17：九尾总伤害计算 ───────────────────────────────────
	# 第一段0.5x3=1.5 + 第二段1x2=2 + 第三段4 = 7.5总伤害
	gm_minato.hp = 8
	gm_minato.energy = 5
	gm_naruto.hp = 20
	gm_minato.nine_tails_invincible = false
	gm_minato.nine_tails_stage = 0
	gm.call("_process_nine_tails_release", gm_minato)
	var hp_after_stage1 := gm_naruto.hp
	gm.call("_process_nine_tails_progress")
	var hp_after_stage2 := gm_naruto.hp
	gm.call("_process_nine_tails_progress")
	var hp_after_stage3 := gm_naruto.hp
	var total_dmg := 20 - hp_after_stage3
	_assert(total_dmg == 7.5, "17: 九尾三段总伤害7.5实际=" + str(total_dmg) + "（HP 20→" + str(hp_after_stage3) + "）")

	# ── 测试18：飞雷神ftg_cost校验 ────────────────────────────────
	gm_minato.ftg_marks = 0
	gm_minato.energy = 5
	var can_use := RoundResolver.can_use_skill(gm_minato, ftg_skill, gm_naruto, dist_sys)
	_assert(not can_use, "18: 飞雷神标记不足时不能使用")
	# 恢复标记
	gm_minato.ftg_marks = 3
	can_use = RoundResolver.can_use_skill(gm_minato, ftg_skill, gm_naruto, dist_sys)
	_assert(can_use, "18b: 飞雷神标记充足时可以使用")

	# ── 测试19：角色选择页preload ────────────────────────────────
	var cs_preloads: Array = [
		preload("res://resources/characters/漩涡鸣人.tres"),
		preload("res://resources/characters/宇智波佐助.tres"),
		preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
		preload("res://resources/characters/春野樱.tres"),
		preload("res://resources/characters/千手柱间.tres"),
		preload("res://resources/characters/迈特凯.tres"),
		preload("res://resources/characters/波风水门.tres"),
	]
	var minato_in_preloads := false
	for res in cs_preloads:
		if res is CharacterData and res.character_name == "波风水门（漂泊寻者）":
			minato_in_preloads = true
	_assert(minato_in_preloads, "19: 波风水门在character_select preload列表中")

	# ── 测试20：AI策略基础验证 ───────────────────────────────────
	# AI应该在气>=5时优先九尾
	var ai_minato := PlayerState.new(0, "水门", minato_char, false)
	ai_minato.energy = 5
	ai_minato.ftg_marks = 3
	var ai := AIController.new()
	var alive_players: Array[PlayerState] = [ai_minato, gm_naruto]
	var ai_action := ai.decide_action(ai_minato, alive_players, dist_sys)
	_assert(ai_action.action == PlayerState.ActionType.USE_SKILL, "20a: AI选择使用技能")
	var ai_skill := ai_minato.get_all_skills()[ai_action.skill_index]
	_assert(ai_skill.skill_name == "漂泊九尾", "20b: 气>=5时AI优先漂泊九尾实际=" + ai_skill.skill_name)

	# AI在气>=2但<5时优先螺旋丸
	ai_minato.energy = 2
	ai_minato.ftg_marks = 3
	ai_minato.limited_skills_used.clear()
	ai_action = ai.decide_action(ai_minato, alive_players, dist_sys)
	ai_skill = ai_minato.get_all_skills()[ai_action.skill_index]
	_assert(ai_skill.skill_name == "螺旋丸", "20c: 气=2时AI优先螺旋丸实际=" + ai_skill.skill_name)

	print("=== 波风水门测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
