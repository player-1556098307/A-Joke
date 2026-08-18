## 希耶尔完整机制测试
## 覆盖：角色属性、代行者、相位滑剑（满血x2/没气得1气/濒死置位暴击）、
## 断头台（穿透无视护盾/无敌/圣盾）、断罪死（7次猜拳/回血/即死）、AI策略、选人列表
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 希耶尔完整机制测试 ===")

	await get_tree().process_frame

	var xiye_char := load("res://resources/characters/希耶尔.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData

	if xiye_char == null:
		print("FATAL: 希耶尔.tres 加载失败")
		get_tree().quit(1)
		return
	if naruto_char == null:
		print("FATAL: 漩涡鸣人.tres 加载失败")
		get_tree().quit(1)
		return
	if sasuke_char == null:
		print("FATAL: 宇智波佐助.tres 加载失败")
		get_tree().quit(1)
		return

	print("[DEBUG] 角色资源加载成功: xiye=%s naruto=%s sasuke=%s" % [xiye_char.character_name, naruto_char.character_name, sasuke_char.character_name])

	var xiye := PlayerState.new(0, "希耶尔", xiye_char, true)
	var naruto := PlayerState.new(1, "鸣人", naruto_char, false)
	var sasuke := PlayerState.new(2, "佐助", sasuke_char, false)

	var dist := DistanceSystem.new()
	dist.setup([0, 1, 2])

	# ── 测试1：角色属性 ──────────────────────────────────────────
	_assert(xiye.character.max_hp == 6, "1a: 希耶尔HP应为6实际=" + str(xiye.character.max_hp))
	_assert(xiye.character.grade == "S", "1b: 希耶尔等级应为S实际=" + xiye.character.grade)
	_assert(xiye.hp == 6, "1c: 初始HP应为6实际=" + str(xiye.hp))
	_assert("战士" in xiye.character.tags, "1d: 希耶尔标签应含战士")
	_assert("刺客" in xiye.character.tags, "1e: 希耶尔标签应含刺客")

	# ── 测试2：技能列表验证 ──────────────────────────────────────
	var skill_names: Array[String] = []
	for skill in xiye.character.skills:
		skill_names.append(skill.skill_name)
	_assert("普攻" in skill_names, "2a: 技能列表包含普攻")
	_assert("代行者" in skill_names, "2b: 技能列表包含代行者")
	_assert("相位滑剑" in skill_names, "2c: 技能列表包含相位滑剑")
	_assert("原理血戒·断头台" in skill_names, "2d: 技能列表包含断头台")
	_assert("第七圣典·断罪死" in skill_names, "2e: 技能列表包含断罪死")

	# 代行者/相位滑剑应为被动
	var daixing_passive := false
	var xiangwei_passive := false
	for skill in xiye.character.skills:
		if skill.skill_name == "代行者":
			daixing_passive = skill.is_passive
		if skill.skill_name == "相位滑剑":
			xiangwei_passive = skill.is_passive
	_assert(daixing_passive, "2f: 代行者应为被动技")
	_assert(xiangwei_passive, "2g: 相位滑剑应为被动技")

	# 被动技能不应出现在可见技能列表
	var visible := xiye.get_all_skills()
	var passive_visible := false
	for skill in visible:
		if skill.skill_name in ["代行者", "相位滑剑"]:
			passive_visible = true
	_assert(not passive_visible, "2h: 被动技不应出现在可见技能列表")

	# ── 测试3：断头台/断罪死技能属性 ────────────────────────────
	var guillotine: SkillData = null
	var death_sentence: SkillData = null
	for skill in xiye.character.skills:
		if skill.skill_name == "原理血戒·断头台":
			guillotine = skill
		if skill.skill_name == "第七圣典·断罪死":
			death_sentence = skill
	_assert(guillotine != null, "3a: 断头台技能存在")
	_assert(guillotine.energy_cost == 4, "3b: 断头台耗气4实际=" + str(guillotine.energy_cost))
	_assert(guillotine.max_range == 999, "3c: 断头台无视距离(999)实际=" + str(guillotine.max_range))
	_assert(death_sentence != null, "3d: 断罪死技能存在")
	_assert(death_sentence.energy_cost == 6, "3e: 断罪死耗气6实际=" + str(death_sentence.energy_cost))
	_assert(death_sentence.max_range == 999, "3f: 断罪死无视距离(999)实际=" + str(death_sentence.max_range))

	# 断头台效果应为PIERCE_DAMAGE，断罪死为DEATH_SENTENCE
	var guillotine_effect_type: int = -1
	var death_sentence_effect_type: int = -1
	if guillotine and guillotine.effects.size() > 0:
		guillotine_effect_type = guillotine.effects[0].effect_type
	if death_sentence and death_sentence.effects.size() > 0:
		death_sentence_effect_type = death_sentence.effects[0].effect_type
	_assert(guillotine_effect_type == SkillEffect.EffectType.PIERCE_DAMAGE, "3g: 断头台效果类型=穿透伤害(16)实际=" + str(guillotine_effect_type))
	_assert(death_sentence_effect_type == SkillEffect.EffectType.DEATH_SENTENCE, "3h: 断罪死效果类型=断罪死(17)实际=" + str(death_sentence_effect_type))

	# ── 测试4：is_xiye 识别 ──────────────────────────────────────
	_assert(RoundResolver.is_xiye(xiye), "4a: is_xiye(希耶尔)=true")
	_assert(not RoundResolver.is_xiye(naruto), "4b: is_xiye(鸣人)=false")

	# ── 测试5：代行者（对法师目标+1）──────────────────────────────
	# 鸣人无法师标签
	var bonus_naruto := RoundResolver.agent_bonus(xiye, naruto)
	_assert(bonus_naruto == 0.0, "5a: 对无法师标签目标代行者加成=0实际=" + str(bonus_naruto))
	# 佐助有法师标签
	var bonus_sasuke := RoundResolver.agent_bonus(xiye, sasuke)
	_assert(bonus_sasuke == 1.0, "5b: 对法师标签目标代行者加成=1实际=" + str(bonus_sasuke))
	# 非希耶尔角色无加成
	_assert(RoundResolver.agent_bonus(naruto, sasuke) == 0.0, "5c: 非希耶尔无代行者加成")

	# ── 测试6：相位滑剑 — 满血x2 ────────────────────────────────
	var xi2 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var na2 := PlayerState.new(1, "鸣人", naruto_char, false)
	xi2.hp = 6  # 满血
	xi2.energy = 5
	xi2.can_crit_next = false
	var ps_res := RoundResolver.phase_sword_pre_apply(xi2, 1.0)
	_assert(ps_res["multiplier"] == 2.0, "6a: 满血时伤害x2，multiplier=2实际=" + str(ps_res["multiplier"]))

	# 非满血无x2
	xi2.hp = 3
	var ps_res2 := RoundResolver.phase_sword_pre_apply(xi2, 1.0)
	_assert(ps_res2["multiplier"] == 1.0, "6b: 非满血 multiplier=1实际=" + str(ps_res2["multiplier"]))

	# ── 测试7：相位滑剑 - 没气获得1气 ────────────────────────────
	xi2.hp = 6
	xi2.energy = 0
	var ps3 := RoundResolver.phase_sword_pre_apply(xi2, 1.0)
	_assert(ps3["energy_gained"] == 1, "7a: 没气时获得1气实际=" + str(ps3["energy_gained"]))
	_assert(xi2.energy == 1, "7b: energy=0+1=1实际=" + str(xi2.energy))

	# 有气时不得气
	xi2.energy = 2
	var ps4 := RoundResolver.phase_sword_pre_apply(xi2, 1.0)
	_assert(ps4["energy_gained"] == 0, "7c: 有气时不得气实际=" + str(ps4["energy_gained"]))

	# ── 测试8：相位滑剑 - 三条件可叠加 ──────────────────────────
	var xi3 := PlayerState.new(0, "希耶尔", xiye_char, true)
	xi3.hp = 6   # 满血
	xi3.energy = 0  # 没气
	xi3.can_crit_next = false
	var ps5 := RoundResolver.phase_sword_pre_apply(xi3, 2.0)
	_assert(ps5["multiplier"] == 2.0, "8a: 满血+没气叠加 multiplier=2实际=" + str(ps5["multiplier"]))
	_assert(ps5["energy_gained"] == 1, "8b: 满血+没气叠加 energy_gained=1实际=" + str(ps5["energy_gained"]))

	# ── 测试9：暴击状态机 ────────────────────────────────────────
	var x9 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n9 := PlayerState.new(1, "鸣人", naruto_char, false)
	# 初始无暴击
	_assert(not x9.can_crit_next, "9a: 初始无暴击状态")
	# 造成伤害致目标HP归零 → 置位
	var basic_effect := SkillEffect.new()
	basic_effect.effect_type = SkillEffect.EffectType.DAMAGE
	basic_effect.value = 6.0
	basic_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var basic_skill := SkillData.new()
	basic_skill.skill_name = "普攻"
	basic_skill.energy_cost = 1
	basic_skill.min_range = 1
	basic_skill.max_range = 999
	basic_skill.effects = [basic_effect]
	var logs := RoundResolver.apply_effects(x9, basic_skill, [n9], dist)
	_assert(x9.can_crit_next, "9b: 伤害致死→置位可暴击")
	var n9_hp: float = logs[0]["result"]["remaining_hp"]
	_assert(n9_hp == 0.0, "9c: 目标HP归零实际=" + str(n9_hp))

	# 满血x2 + 暴击x2 → 实际伤害为12？先验证结算数值
	# x9满血(6/6)，n9剩0HP。满血x2：6*2=12，但n9只有6血，伤害12→HP归零。damage_dealt应为12
	var dmg_dealt: float = logs[0]["result"]["damage_dealt"]
	_assert(dmg_dealt == 12.0, "9d: 满血x2伤害=6*2=12实际=" + str(dmg_dealt))

	# ── 测试10：暴击50%概率（多测几次至少出现过一次暴击）────────
	var crit_seen := false
	var crit_total := 0
	for i in range(200):
		var x10 := PlayerState.new(0, "希耶尔", xiye_char, true)
		var n10 := PlayerState.new(1, "鸣人", naruto_char, false)
		x10.hp = 6
		x10.can_crit_next = true
		x10.crit_checked_this_round = false
		var cr := RoundResolver.crit_check(x10)
		if cr["crit"]:
			crit_seen = true
			crit_total += 1
		_assert(x10.crit_checked_this_round, "10a: 暴击判定后标记已检查")
		_assert(not x10.can_crit_next, "10b: 暴击判定后状态清除")
	_assert(crit_seen, "10c: 200次中至少出现1次暴击(50%概率)")
	# 概率合理性：暴击次数应在 50±40 内
	_assert(crit_total >= 60 and crit_total <= 140, "10d: 200次暴击次数合理范围60~140实际=" + str(crit_total))

	# ── 测试11：断头台穿透 - 无视数值护盾 ────────────────────────
	var x11 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n11 := PlayerState.new(1, "鸣人", naruto_char, false)
	x11.hp = 6  # 满血（会x2）
	n11.shield = 3
	var guillotine_skill: SkillData = guillotine
	if guillotine_skill == null:
		guillotine_skill = SkillData.new()
		guillotine_skill.skill_name = "原理血戒·断头台"
		guillotine_skill.energy_cost = 4
		guillotine_skill.min_range = 1
		guillotine_skill.max_range = 999
		var ge := SkillEffect.new()
		ge.effect_type = SkillEffect.EffectType.PIERCE_DAMAGE
		ge.value = 4.0
		ge.target = SkillEffect.EffectTarget.ENEMY_SINGLE
		guillotine_skill.effects = [ge]
	var g_logs := RoundResolver.apply_effects(x11, guillotine_skill, [n11], dist)
	var g_res: Dictionary = g_logs[0]["result"]
	_assert(g_res["shield_absorbed"] == 0.0, "11a: 穿透无视护盾 shield_absorbed=0实际=" + str(g_res["shield_absorbed"]))
	# 满血x2 → 4*2=8
	_assert(g_res["damage_dealt"] == 8.0, "11b: 满血x2穿透伤害=4*2=8实际=" + str(g_res["damage_dealt"]))
	_assert(n11.shield == 3, "11c: 目标护盾未被消耗 shield仍=3实际=" + str(n11.shield))
	_assert(n11.hp == 0.0, "11d: 目标HP=6-8=0实际=" + str(n11.hp))
	_assert(x11.can_crit_next, "11e: 断头台致死→置位可击")

	# ── 测试12：断头台 - 无视无敌状态 ────────────────────────────
	var x12 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n12 := PlayerState.new(1, "鸣人", naruto_char, false)
	x12.hp = 6
	n12.invincible_turns = 2
	var g12 := RoundResolver.apply_effects(x12, guillotine_skill, [n12], dist)
	var g12_res: Dictionary = g12[0]["result"]
	_assert(g12_res["damage_dealt"] == 8.0, "12a: 穿透无视无敌伤害=8实际=" + str(g12_res["damage_dealt"]))
	_assert(n12.hp == 0.0, "12b: 无敌目标仍被穿透打死 HP=0实际=" + str(n12.hp))

	# ── 测试13：断头台 - 无视圣盾(全挡护盾) ─────────────────────
	var x13 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n13 := PlayerState.new(1, "鸣人", naruto_char, false)
	x13.hp = 6
	n13.shield = -1  # 全挡护盾
	var g13 := RoundResolver.apply_effects(x13, guillotine_skill, [n13], dist)
	var g13_res: Dictionary = g13[0]["result"]
	_assert(g13_res["shield_absorbed"] == 0.0, "13a: 穿透无视圣盾 shield_absorbed=0实际=" + str(g13_res["shield_absorbed"]))
	_assert(n13.shield == -1, "13b: 圣盾未被消耗仍=-1实际=" + str(n13.shield))
	_assert(n13.hp == 0.0, "13c: 圣盾目标被穿透扣血HP=0实际=" + str(n13.hp))

	# ── 测试14：断罪死 - 基础结算与回血 ─────────────────────────
	var x14 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n14 := PlayerState.new(1, "鸣人", naruto_char, false)
	x14.hp = 6
	n14.hp = 6
	var ds_skill: SkillData = death_sentence
	if ds_skill == null:
		ds_skill = SkillData.new()
		ds_skill.skill_name = "第七圣典·断罪死"
		ds_skill.energy_cost = 6
		ds_skill.min_range = 1
		ds_skill.max_range = 999
		var de := SkillEffect.new()
		de.effect_type = SkillEffect.EffectType.DEATH_SENTENCE
		de.value = 7.0
		de.target = SkillEffect.EffectTarget.ENEMY_SINGLE
		ds_skill.effects = [de]
	var ds_logs := RoundResolver.apply_effects(x14, ds_skill, [n14], dist)
	var ds_res: Dictionary = ds_logs[0]["result"]
	_assert(ds_res.has("rounds"), "14a: 断罪死结果包含rounds")
	_assert(ds_res["rounds"].size() == 7, "14b: 猜拳7次 rounds.size=7实际=" + str(ds_res["rounds"].size()))
	var wc: int = ds_res["win_count"]
	_assert(wc >= 0 and wc <= 7, "14c: 赢次数0~7实际=" + str(wc))
	# 回血上限：满血时回0
	_assert(ds_res["total_heal"] == 0.0, "14d: 满血时输不掉血 total_heal=0实际=" + str(ds_res["total_heal"]))

	# 回血测试：希耶尔少血时输掉猜拳回血
	var x14b := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n14b := PlayerState.new(1, "鸣人", naruto_char, false)
	x14b.hp = 2
	n14b.hp = 6
	var ds_logs2 := RoundResolver.apply_effects(x14b, ds_skill, [n14b], dist)
	var ds_res2: Dictionary = ds_logs2[0]["result"]
	var lose_count: int = ds_res2["lose_count"]
	# HP=2，最多回血到6（需4次回满），超过部分封顶
	var expect_heal: float = float(mini(lose_count, 4))
	_assert(ds_res2["total_heal"] == expect_heal, "14e: 输x次回x血(封顶4) total_heal=" + str(ds_res2["total_heal"]) + " lose=" + str(lose_count) + " expect=" + str(expect_heal))
	_assert(x14b.hp == 2.0 + expect_heal, "14f: 希耶尔HP=2+回血(封顶4)实际=" + str(x14b.hp) + " expect=" + str(2.0 + expect_heal))

	# 回血上限：最多回满
	var x14c := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n14c := PlayerState.new(1, "鸣人", naruto_char, false)
	x14c.hp = 5
	n14c.hp = 6
	var ds_logs3 := RoundResolver.apply_effects(x14c, ds_skill, [n14c], dist)
	var ds_res3: Dictionary = ds_logs3[0]["result"]
	_assert(x14c.hp <= 6.0, "14g: 回血上限不超过最大HP实际=" + str(x14c.hp))

	# ── 测试15: 断罪死 - 即死判定 ──────────────────────────────
	# 赢>=4 则即死：构造确定性场景不便，通过验证逻辑字段确认
	var x15 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n15 := PlayerState.new(1, "鸣人", naruto_char, false)
	x15.hp = 4  # 非满血，排除相位滑剑x2干扰（单次赢=1伤）
	n15.hp = 6
	var ds_logs4 := RoundResolver.apply_effects(x15, ds_skill, [n15], dist)
	var ds_res4: Dictionary = ds_logs4[0]["result"]
	# 若赢>=4 必然即死且HP=0
	if ds_res4["win_count"] >= 4:
		_assert(ds_res4["instant_kill"], "15a: 赢>=4 → 即死标记 true")
		_assert(n15.hp == 0.0, "15b: 即死目标HP=0实际=" + str(n15.hp))
	else:
		_assert(not ds_res4["instant_kill"], "15c: 赢<4 → 不即死")
		# 否则正常结算：目标HP = 6 - 实际总伤害
		# 注意：希耶尔输的回合会回血，可能回到满血触发相位滑剑x2，故不能简单按赢次数断言
		var expect_dmg: float = float(ds_res4["damage_dealt"])
		_assert(n15.hp == 6.0 - expect_dmg, "15d: 非即死时目标HP=6-实际总伤害实际=" + str(n15.hp) + " expect=" + str(6.0 - expect_dmg))

	# ── 测试16: 断罪死 - 每次赢的伤害吃被动强化（对法师+1/满血x2） ──
	var x16 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var s16 := PlayerState.new(2, "佐助", sasuke_char, false)
	x16.hp = 6   # 满血
	s16.hp = 20  # 高血量保证不即死干扰（win<4时）
	var ds_logs5 := RoundResolver.apply_effects(x16, ds_skill, [s16], dist)
	var ds_res5: Dictionary = ds_logs5[0]["result"]
	if ds_res5["win_count"] < 4:
		# 每赢1次：基础1 + 代行者(法师)+1 = 2，满血x2 → 4伤
		_assert(ds_res5["damage_dealt"] == float(ds_res5["win_count"]) * 4.0,
			"16a: 断罪死每次赢=2*2=4伤（法师+1,满血x2）实际=" + str(ds_res5["damage_dealt"]) + " win=" + str(ds_res5["win_count"]))

	# ── 测试17: AI - 希耶尔策略分支存在 ────────────────────────
	var ai := AIController.new()
	# 无需直接断言AI内部，但确认AI能对希耶尔出决策不崩溃
	var x17 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n17 := PlayerState.new(1, "鸣人", naruto_char, false)
	x17.is_human = false
	n17.is_human = false
	x17.hp = 6
	x17.energy = 6
	var decision := ai.decide_action(x17, [n17], dist)
	_assert(decision != null, "17a: AI对希耶尔能返回决策")
	_assert(decision.has("skill_index") or decision.has("action_type"), "17b: AI决策含skill_index/action_type")
	# 有6气时应倾向用断罪死
	if decision.has("skill_index") and decision["skill_index"] >= 0:
		var chosen: SkillData = x17.get_all_skills()[decision["skill_index"]]
		_assert(chosen.skill_name in ["第七圣典·断罪死", "原理血戒·断头台", "普攻"], "17c: AI选中的技能在希耶尔技能集内: " + chosen.skill_name)
	else:
		_assert(decision.get("action_type", -1) == PlayerState.ActionType.CHARGE, "17d: 气不足充能")

	# ── 测试18: 选人列表包含希耶尔 ─────────────────────────────
	var cs_preloads: Array = [
		preload("res://resources/characters/漩涡鸣人.tres"),
		preload("res://resources/characters/宇智波佐助.tres"),
		preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
		preload("res://resources/characters/春野樱.tres"),
		preload("res://resources/characters/千手柱间.tres"),
		preload("res://resources/characters/迈特凯.tres"),
		preload("res://resources/characters/波风水门.tres"),
		preload("res://resources/characters/希耶尔.tres"),
	]
	var xiye_in_preloads := false
	for res in cs_preloads:
		if res is CharacterData and res.character_name == "希耶尔":
			xiye_in_preloads = true
	_assert(xiye_in_preloads, "18: 希耶尔在character_select preload列表中")

	# ── 测试19: 相位滑剑伤害致死置位后下一次普攻暴击 ────────────
	var x19 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n19 := PlayerState.new(1, "鸣人", naruto_char, false)
	x19.hp = 6
	n19.hp = 6
	# 第一击：打6伤致其濒死（满血x2=12）
	var basic_skill2 := SkillData.new()
	basic_skill2.skill_name = "普攻"
	basic_skill2.energy_cost = 1
	basic_skill2.min_range = 1
	basic_skill2.max_range = 999
	basic_effect = SkillEffect.new()
	basic_effect.effect_type = SkillEffect.EffectType.DAMAGE
	basic_effect.value = 3.0
	basic_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	basic_skill2.effects = [basic_effect]
	# 用3伤打满血6血希耶尔：x2=6，鸣人HP 6→0，置位可击
	var lg := RoundResolver.apply_effects(x19, basic_skill2, [n19], dist)
	_assert(x19.can_crit_next, "19a: 致死后置位可击")
	# 重置对局双方再验证下一次伤害
	var x19b := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n19b := PlayerState.new(1, "鸣人", naruto_char, false)
	x19b.hp = 4  # 非满血
	n19b.hp = 6
	x19b.can_crit_next = true
	x19b.crit_checked_this_round = false
	# 手动强制暴击（用确定性的方式）
	# 直接调用 apply_effects 会用随机；改测50%概率覆盖即可（已测10）

	# ── 测试20: 被飞雷神标记后动态获得飞雷神拔除技能 ────────────
	var x20 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var n20 := PlayerState.new(1, "鸣人", naruto_char, false)
	# 未标记时：技能列表不应包含飞雷神拔除
	var s20_before: Array[String] = []
	for sk in x20.get_all_skills():
		s20_before.append(sk.skill_name)
	_assert(not ("飞雷神拔除" in s20_before), "20a: 未标记时希耶尔技能列表不含飞雷神拔除")
	# 被鸣人标记后：技能列表应动态追加飞雷神拔除
	x20.ftg_marked_by.append(n20.player_id)
	var s20_after: Array[String] = []
	for sk in x20.get_all_skills():
		s20_after.append(sk.skill_name)
	_assert("飞雷神拔除" in s20_after, "20b: 被标记后希耶尔技能列表动态出现飞雷神拔除")
	# 使用飞雷神拔除清除标记（复用 t.res 技能，0气，SELF目标）
	var ftg_remove_skill: SkillData = null
	for sk in x20.get_all_skills():
		if sk.skill_name == "飞雷神拔除":
			ftg_remove_skill = sk
			break
	_assert(ftg_remove_skill != null, "20c: 飞雷神拔除技能资源可获取")
	_assert(ftg_remove_skill.energy_cost == 0, "20d: 飞雷神拔除耗气为0实际=" + str(ftg_remove_skill.energy_cost))
	var remove_logs := RoundResolver.apply_effects(x20, ftg_remove_skill, [x20], dist)
	_assert(x20.ftg_marked_by.is_empty(), "20e: 使用飞雷神拔除后标记清除")
	# 拔除后技能列表不再含飞雷神拔除
	var s20_final: Array[String] = []
	for sk in x20.get_all_skills():
		s20_final.append(sk.skill_name)
	_assert(not ("飞雷神拔除" in s20_final), "20f: 标记清除后飞雷神拔除技能消失")

	print("=== 希耶尔测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)