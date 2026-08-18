## 秽土柱间完整机制测试
## 覆盖：角色属性、气上限6、技能升级(树界→花树界/木人→木龙)、跺脚(受击得气+判胜)、
## 真数千手(全屏+无敌)、明神门(限定技+2气+禁锢3)、希耶尔代行者克制交互
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 秽土柱间完整机制测试 ===")

	await get_tree().process_frame

	var edo_char := load("res://resources/characters/千手柱间（秽土转生）.tres") as CharacterData
	var xiye_char := load("res://resources/characters/希耶尔.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData

	if edo_char == null:
		print("FATAL: 千手柱间（秽土转生）.tres 加载失败")
		get_tree().quit(1)
		return
	if xiye_char == null:
		print("FATAL: 希耶尔.tres 加载失败")
		get_tree().quit(1)
		return
	if naruto_char == null:
		print("FATAL: 漩涡鸣人.tres 加载失败")
		get_tree().quit(1)
		return

	print("[DEBUG] 角色资源加载成功: edo=%s xiye=%s naruto=%s" % [edo_char.character_name, xiye_char.character_name, naruto_char.character_name])

	# ── 测试1：角色属性 ──────────────────────────────────────────
	_assert(edo_char.max_hp == 8, "1a: 秽土柱间HP应为8实际=" + str(edo_char.max_hp))
	_assert(edo_char.grade == "S", "1b: 秽土柱间等级应为S实际=" + edo_char.grade)
	_assert("战士" in edo_char.tags, "1c: 标签应含战士")
	_assert("法师" in edo_char.tags, "1d: 标签应含法师")
	_assert("秽土转生" in edo_char.tags, "1e: 标签应含秽土转生")

	# ── 测试2：技能列表验证 ──────────────────────────────────────
	var skill_names: Array[String] = []
	for skill in edo_char.skills:
		skill_names.append(skill.skill_name)
	_assert("普攻" in skill_names, "2a: 技能列表包含普攻")
	_assert("仙人之力" in skill_names, "2b: 技能列表包含仙人之力")
	_assert("仙法·树界降诞" in skill_names, "2c: 技能列表包含树界降诞")
	_assert("木人之术" in skill_names, "2d: 技能列表包含木人之术")
	_assert("仙法·真数千手" in skill_names, "2e: 技能列表包含真数千手")
	_assert("明神门" in skill_names, "2f: 技能列表包含明神门")

	# 仙人之力应为被动
	var sage_passive := false
	for skill in edo_char.skills:
		if skill.skill_name == "仙人之力":
			sage_passive = skill.is_passive
	_assert(sage_passive, "2g: 仙人之力应为被动技")

	# 被动技不出现在可见技能列表
	var edo := PlayerState.new(0, "秽土柱间", edo_char, true)
	var visible_names: Array[String] = []
	for skill in edo.get_all_skills():
		visible_names.append(skill.skill_name)
	_assert(not ("仙人之力" in visible_names), "2h: 仙人之力不应出现在可见技能列表")
	_assert("普攻" in visible_names, "2i: 普攻应出现在可见技能列表")
	_assert("仙法·树界降诞" in visible_names, "2j: 树界降诞应出现在可见技能列表")

	# ── 测试3：气上限6（仙人之力）────────────────────────────────
	_assert(edo.max_energy == 6, "3a: 秽土柱间max_energy应为6实际=" + str(edo.max_energy))
	# 加气超过上限应clamp
	edo.energy = 5
	edo.add_energy(3)
	_assert(edo.energy == 6, "3b: 加气超过上限应clamp到6实际=" + str(edo.energy))
	# 普通角色max_energy应为999
	var naruto := PlayerState.new(1, "鸣人", naruto_char, false)
	_assert(naruto.max_energy == 999, "3c: 鸣人max_energy应为999实际=" + str(naruto.max_energy))
	naruto.energy = 100
	naruto.add_energy(50)
	_assert(naruto.energy == 150, "3d: 普通角色加气不受限实际=" + str(naruto.energy))

	# ── 测试4：树界降诞技能属性 ──────────────────────────────────
	var sjj: SkillData = null
	var mrz: SkillData = null
	var qss: SkillData = null
	var msg: SkillData = null
	for skill in edo_char.skills:
		if skill.skill_name == "仙法·树界降诞":
			sjj = skill
		elif skill.skill_name == "木人之术":
			mrz = skill
		elif skill.skill_name == "仙法·真数千手":
			qss = skill
		elif skill.skill_name == "明神门":
			msg = skill
	_assert(sjj != null, "4a: 树界降诞技能存在")
	_assert(sjj.energy_cost == 2, "4b: 树界降诞耗气2实际=" + str(sjj.energy_cost))
	_assert(mrz != null, "4c: 木人之术技能存在")
	_assert(mrz.energy_cost == 2, "4d: 木人之术耗气2实际=" + str(mrz.energy_cost))
	_assert(qss != null, "4e: 真数千手技能存在")
	_assert(qss.energy_cost == 4, "4f: 真数千手耗气4实际=" + str(qss.energy_cost))
	_assert(msg != null, "4g: 明神门技能存在")
	_assert(msg.is_limited, "4h: 明神门应为限定技")

	# 树界降诞效果：1伤+麻痹2+封技2
	_assert(sjj.effects.size() == 3, "4i: 树界降诞应有3个效果实际=" + str(sjj.effects.size()))
	_assert(sjj.effects[0].effect_type == SkillEffect.EffectType.DAMAGE, "4j: 第1效果=DAMAGE")
	_assert(sjj.effects[0].value == 1, "4k: 伤害值=1实际=" + str(sjj.effects[0].value))
	_assert(sjj.effects[1].effect_type == SkillEffect.EffectType.PARALYZE, "4l: 第2效果=PARALYZE")
	_assert(sjj.effects[1].value == 2, "4m: 麻痹回合=2实际=" + str(sjj.effects[1].value))
	_assert(sjj.effects[2].effect_type == SkillEffect.EffectType.DISABLE_SKILL, "4n: 第3效果=DISABLE_SKILL")
	_assert(sjj.effects[2].value == 2, "4o: 封技回合=2实际=" + str(sjj.effects[2].value))

	# 木人之术效果：3伤+禁锢增伤1
	_assert(mrz.effects[0].effect_type == SkillEffect.EffectType.DAMAGE, "4p: 木人第1效果=DAMAGE")
	_assert(mrz.effects[0].value == 3, "4q: 木人伤害=3实际=" + str(mrz.effects[0].value))
	_assert(mrz.effects[0].bonus_if_paralyzed == 1, "4r: 木人禁锢增伤=1实际=" + str(mrz.effects[0].bonus_if_paralyzed))

	# 真数千手效果：6伤 ENEMY_ALL
	_assert(qss.effects[0].effect_type == SkillEffect.EffectType.DAMAGE, "4s: 真数千手效果=DAMAGE")
	_assert(qss.effects[0].value == 6, "4t: 真数千手伤害=6实际=" + str(qss.effects[0].value))
	_assert(qss.effects[0].target == SkillEffect.EffectTarget.ENEMY_ALL, "4u: 真数千手目标=ENEMY_ALL")

	# 明神门效果：麻痹3+封技3
	_assert(msg.effects[0].effect_type == SkillEffect.EffectType.PARALYZE, "4v: 明神门第1效果=PARALYZE")
	_assert(msg.effects[0].value == 3, "4w: 明神门麻痹回合=3实际=" + str(msg.effects[0].value))
	_assert(msg.effects[1].effect_type == SkillEffect.EffectType.DISABLE_SKILL, "4x: 明神门第2效果=DISABLE_SKILL")
	_assert(msg.effects[1].value == 3, "4y: 明神门封技回合=3实际=" + str(msg.effects[1].value))

	# ── 测试5：木龙之术/花树界降临升级版技能属性 ────────────────────
	var hsjj := load("res://resources/characters/skills/花树界降临.tres") as SkillData
	var mlz := load("res://resources/characters/skills/木龙之术.tres") as SkillData
	_assert(hsjj != null, "5a: 花树界降临技能资源可加载")
	_assert(mlz != null, "5b: 木龙之术技能资源可加载")
	if hsjj:
		_assert(hsjj.energy_cost == 2, "5c: 花树界降临耗气2实际=" + str(hsjj.energy_cost))
		_assert(hsjj.max_range == 1, "5d: 花树界降临射程1实际=" + str(hsjj.max_range))
		# 花树界有溅射效果
		var has_splash := false
		for e in hsjj.effects:
			if e.target == SkillEffect.EffectTarget.ENEMY_SPLASH:
				has_splash = true
		_assert(has_splash, "5e: 花树界降临包含ENEMY_SPLASH溅射效果")
		# 主目标2伤
		_assert(hsjj.effects[0].value == 2, "5f: 花树界主目标伤害=2实际=" + str(hsjj.effects[0].value))
	if mlz:
		_assert(mlz.energy_cost == 2, "5g: 木龙之术耗气2实际=" + str(mlz.energy_cost))
		_assert(mlz.max_range == 2, "5h: 木龙之术射程2实际=" + str(mlz.max_range))
		_assert(mlz.effects[0].value == 3, "5i: 木龙之术伤害=3实际=" + str(mlz.effects[0].value))
		_assert(mlz.effects[0].target == SkillEffect.EffectTarget.ENEMY_ALL, "5j: 木龙之术目标=ENEMY_ALL")
		_assert(mlz.effects[0].bonus_if_paralyzed == 2, "5k: 木龙禁锢增伤=2实际=" + str(mlz.effects[0].bonus_if_paralyzed))

	# ── 测试6：树界降诞伤害+禁锢执行 ──────────────────────────────
	var e6 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n6 := PlayerState.new(1, "鸣人", naruto_char, false)
	e6.energy = 2
	e6.skill_target_id = 1
	var dist6 := DistanceSystem.new()
	dist6.setup([0, 1])
	var logs6 := RoundResolver.apply_effects(e6, sjj, [n6], dist6)
	_assert(n6.hp == 5, "6a: 树界降诞造成1伤HP=5实际=" + str(n6.hp))
	_assert(n6.paralyze_turns == 2, "6b: 树界降诞麻痹2回合实际=" + str(n6.paralyze_turns))
	_assert(n6.skill_disabled_turns == 2, "6c: 树界降诞封技2回合实际=" + str(n6.skill_disabled_turns))
	_assert(e6.energy == 0, "6d: 树界降诞消耗2气后energy=0实际=" + str(e6.energy))

	# ── 测试7：木人之术对禁锢目标增伤 ──────────────────────────────
	var e7 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n7 := PlayerState.new(1, "鸣人", naruto_char, false)
	e7.energy = 2
	n7.paralyze_turns = 1  # 预设禁锢
	var dist7 := DistanceSystem.new()
	dist7.setup([0, 1])
	var logs7 := RoundResolver.apply_effects(e7, mrz, [n7], dist7)
	# 3伤+1禁锢增伤=4伤
	_assert(n7.hp == 2, "7a: 木人之术对禁锢目标3+1=4伤HP=2实际=" + str(n7.hp))
	_assert(e7.energy == 0, "7b: 木人之术消耗2气后energy=0实际=" + str(e7.energy))

	# ── 测试8：真数千手全屏伤害 ──────────────────────────────────
	var e8 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n8a := PlayerState.new(1, "鸣人", naruto_char, false)
	var n8b := PlayerState.new(2, "佐助", load("res://resources/characters/宇智波佐助.tres") as CharacterData, false)
	e8.energy = 4
	var dist8 := DistanceSystem.new()
	dist8.setup([0, 1, 2])
	# 真数千手target=ENEMY_ALL，targets传所有其他玩家
	var targets8: Array[PlayerState] = [n8a, n8b]
	var logs8 := RoundResolver.apply_effects(e8, qss, targets8, dist8)
	_assert(n8a.hp == 0, "8a: 真数千手对鸣人6伤HP=0实际=" + str(n8a.hp))
	_assert(n8b.hp == 0, "8b: 真数千手对佐助6伤HP=0实际=" + str(n8b.hp))
	_assert(e8.energy == 0, "8c: 真数千手消耗4气后energy=0实际=" + str(e8.energy))

	# ── 测试9：明神门禁锢3回合 ──────────────────────────────────
	var e9 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n9 := PlayerState.new(1, "鸣人", naruto_char, false)
	e9.energy = 0
	var dist9 := DistanceSystem.new()
	dist9.setup([0, 1])
	var logs9 := RoundResolver.apply_effects(e9, msg, [n9], dist9)
	_assert(n9.paralyze_turns == 3, "9a: 明神门麻痹3回合实际=" + str(n9.paralyze_turns))
	_assert(n9.skill_disabled_turns == 3, "9b: 明神门封技3回合实际=" + str(n9.skill_disabled_turns))
	_assert("明神门" in e9.limited_skills_used, "9c: 明神门标记为已使用限定技")

	# ── 测试10：跺脚字段初始化与递减 ──────────────────────────────
	var e10 := PlayerState.new(0, "秽土柱间", edo_char, true)
	_assert(e10.stomp_active == 0, "10a: 初始stomp_active=0实际=" + str(e10.stomp_active))
	_assert(e10.force_win_next_round == false, "10b: 初始force_win_next_round=false")
	# 模拟普攻后激活跺脚
	e10.stomp_active = 2
	_assert(e10.stomp_active == 2, "10c: 跺脚激活后stomp_active=2")
	# 模拟回合结束递减
	e10.stomp_active -= 1
	_assert(e10.stomp_active == 1, "10d: 递减1后stomp_active=1")
	e10.stomp_active -= 1
	_assert(e10.stomp_active == 0, "10e: 递减2后stomp_active=0")

	# ── 测试11：希耶尔代行者对秽土转生标签+1 ────────────────────────
	var x11 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var e11 := PlayerState.new(1, "秽土柱间", edo_char, false)
	# 秽土转生标签
	var bonus := RoundResolver.agent_bonus(x11, e11)
	_assert(bonus == 1.0, "11a: 代行者对秽土转生标签+1实际=" + str(bonus))
	# 反向：秽土柱间对希耶尔无代行者加成
	_assert(RoundResolver.agent_bonus(e11, x11) == 0.0, "11b: 非希耶尔无代行者加成")

	# ── 测试12：希耶尔对秽土柱间伤害+1（代行者实战）──────────────────
	var x12 := PlayerState.new(0, "希耶尔", xiye_char, true)
	var e12 := PlayerState.new(1, "秽土柱间", edo_char, false)
	x12.energy = 1
	x12.hp = 6  # 满血，触发相位滑剑x2
	var ba := load("res://resources/characters/希耶尔.tres") as CharacterData
	var basic_skill: SkillData = null
	for sk in ba.skills:
		if sk.skill_name == "普攻":
			basic_skill = sk
			break
	_assert(basic_skill != null, "12a: 希耶尔普攻技能存在")
	var dist12 := DistanceSystem.new()
	dist12.setup([0, 1])
	# 希耶尔满血普攻：1伤(基础)+1(代行者)=2, x2(相位滑剑满血)=4伤
	var logs12 := RoundResolver.apply_effects(x12, basic_skill, [e12], dist12)
	_assert(e12.hp == 4, "12b: 希耶尔满血普攻对秽土柱间4伤(1+1)x2 HP=4实际=" + str(e12.hp))

	# ── 测试13：气上限clamp在加气方法中 ─────────────────────────────
	var e13 := PlayerState.new(0, "秽土柱间", edo_char, true)
	e13.energy = 6
	e13.add_energy(1)
	_assert(e13.energy == 6, "13a: 气满时add_energy不变实际=" + str(e13.energy))
	e13.energy = 4
	e13.add_energy(3)
	_assert(e13.energy == 6, "13b: 加气clamp到6实际=" + str(e13.energy))
	e13.set_energy(100)
	_assert(e13.energy == 6, "13c: set_energy clamp到6实际=" + str(e13.energy))
	e13.set_energy(3)
	_assert(e13.energy == 3, "13d: set_energy未超限正常设置实际=" + str(e13.energy))

	# ── 测试14：选人列表接入 ──────────────────────────────────────
	var edo_in_list := false
	for entry in Characters.LIST:
		if entry.get("id") == "edohashirama":
			edo_in_list = true
			_assert(entry.get("name") == "千手柱间（秽土转生）", "14a: 选人列表name正确")
			_assert(entry.get("hp") == 8, "14b: 选人列表hp=8实际=" + str(entry.get("hp")))
	_assert(edo_in_list, "14c: 选人列表包含edohashirama")

	# ── 测试15：木龙之术 ENEMY_ALL 全体伤害+禁锢增伤 ────────────────
	var e15 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n15a := PlayerState.new(1, "鸣人", naruto_char, false)
	var n15b := PlayerState.new(2, "佐助", load("res://resources/characters/宇智波佐助.tres") as CharacterData, false)
	e15.energy = 2
	n15a.paralyze_turns = 1  # 鸣人禁锢中
	var dist15 := DistanceSystem.new()
	dist15.setup([0, 1, 2])
	var logs15 := RoundResolver.apply_effects(e15, mlz, [n15a, n15b], dist15)
	# 鸣人3伤+2禁锢增伤=5伤
	_assert(n15a.hp == 1, "15a: 木龙对禁锢目标3+2=5伤HP=1实际=" + str(n15a.hp))
	# 佐助3伤无增伤
	_assert(n15b.hp == 3, "15b: 木龙对非禁锢目标3伤HP=3实际=" + str(n15b.hp))
	_assert(e15.energy == 0, "15c: 木龙消耗2气后energy=0实际=" + str(e15.energy))

	# ── 测试16：花树界降临溅射伤害 ────────────────────────────────
	var e16 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n16a := PlayerState.new(1, "鸣人", naruto_char, false)  # 主目标
	var n16b := PlayerState.new(2, "佐助", load("res://resources/characters/宇智波佐助.tres") as CharacterData, false)  # 溅射
	e16.energy = 2
	e16.skill_target_id = 1
	var dist16 := DistanceSystem.new()
	dist16.setup([0, 1, 2])
	# 花树界的主目标效果 + 溅射目标列表
	var main_targets16: Array[PlayerState] = [n16a]
	var splash_targets16: Array[PlayerState] = [n16b]  # 距离1内溅射
	var logs16 := RoundResolver.apply_effects(e16, hsjj, main_targets16, dist16, splash_targets16)
	# 主目标2伤+麻痹2+封技2
	_assert(n16a.hp == 4, "16a: 花树界主目标2伤HP=4实际=" + str(n16a.hp))
	_assert(n16a.paralyze_turns == 2, "16b: 花树界主目标麻痹2回合实际=" + str(n16a.paralyze_turns))
	_assert(n16a.skill_disabled_turns == 2, "16c: 花树界主目标封技2回合实际=" + str(n16a.skill_disabled_turns))
	# 溅射1伤+麻痹2+封技2
	_assert(n16b.hp == 5, "16d: 花树界溅射目标1伤HP=5实际=" + str(n16b.hp))
	_assert(n16b.paralyze_turns == 2, "16e: 花树界溅射目标麻痹2回合实际=" + str(n16b.paralyze_turns))
	_assert(n16b.skill_disabled_turns == 2, "16f: 花树界溅射目标封技2回合实际=" + str(n16b.skill_disabled_turns))

	# ── 测试17：角色头像emoji ──────────────────────────────────────
	_assert(edo_char.avatar_emoji == "秽", "17a: 秽土柱间emoji=秽实际=" + edo_char.avatar_emoji)

	# ── 测试18：跺脚受击触发（模拟）──────────────────────────────
	var e18 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n18 := PlayerState.new(1, "鸣人", naruto_char, false)
	# 跺脚激活
	e18.stomp_active = 2
	e18.energy = 2
	# 模拟受到伤害（直接扣血模拟）
	e18.hp = 6
	# 跺脚触发：获得1气+force_win_next_round
	# 模拟 _process_stomp_trigger 的逻辑
	if e18.stomp_active > 0:
		e18.add_energy(1)
		e18.force_win_next_round = true
	_assert(e18.energy == 3, "18a: 跺脚触发获得1气energy=3实际=" + str(e18.energy))
	_assert(e18.force_win_next_round == true, "18b: 跺脚触发force_win_next_round=true")

	# ── 测试19：气上限不限制消耗后的加气（充能场景）────────────────
	var e19 := PlayerState.new(0, "秽土柱间", edo_char, true)
	e19.energy = 5
	# 充能+1 -> clamp到6
	e19.add_energy(1)
	_assert(e19.energy == 6, "19a: 充能clamp到6实际=" + str(e19.energy))
	# 影分身加成充能+2 -> clamp到6
	e19.energy = 4
	e19.add_energy(2)
	_assert(e19.energy == 6, "19b: 分身加成充能clamp到6实际=" + str(e19.energy))

	# ── 测试20：明神门不加气（限定技energy_cost=0但+2气在game_manager中处理）─────
	_assert(msg.energy_cost == 0, "20a: 明神门energy_cost=0实际=" + str(msg.energy_cost))
	# 明神门在 _apply_actions 中通过 winner.add_energy(2) 加气，不在技能效果中

	# ── 测试21：普攻属性 ──────────────────────────────────────────
	var basic_edo: SkillData = null
	for sk in edo_char.skills:
		if sk.skill_name == "普攻":
			basic_edo = sk
			break
	_assert(basic_edo != null, "21a: 秽土柱间普攻技能存在")
	_assert(basic_edo.energy_cost == 0, "21b: 普攻耗气0（无气也可普攻）实际=" + str(basic_edo.energy_cost))
	_assert(basic_edo.effects[0].value == 1, "21c: 普攻伤害1实际=" + str(basic_edo.effects[0].value))

	# ── 测试22：禁锢组合（麻痹+封技）──────────────────────────────
	# 树界降诞同时施加麻痹和封技
	var e22 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n22 := PlayerState.new(1, "鸣人", naruto_char, false)
	e22.energy = 2
	var dist22 := DistanceSystem.new()
	dist22.setup([0, 1])
	RoundResolver.apply_effects(e22, sjj, [n22], dist22)
	# 禁锢=麻痹+封技，get_all_skills应仅返回普攻
	var n22_skills := n22.get_all_skills()
	_assert(n22_skills.size() == 1, "22a: 禁锢后技能列表仅含普攻实际size=" + str(n22_skills.size()))
	_assert(n22_skills[0].skill_name == "普攻", "22b: 禁锢后仅有普攻")

	# ── 测试23：木龙之术射程2 ──────────────────────────────────────
	_assert(mlz.min_range == 1, "23a: 木龙之术min_range=1实际=" + str(mlz.min_range))
	_assert(mlz.max_range == 2, "23b: 木龙之术max_range=2实际=" + str(mlz.max_range))

	# ── 测试24：_is_edo_hashirama 识别（通过GameManager需要实例化，这里测skill名）──
	var has_sage := false
	for sk in edo_char.skills:
		if sk.skill_name == "仙人之力":
			has_sage = true
	_assert(has_sage, "24a: 秽土柱间含仙人之力技能")
	# 原柱间不含仙人之力
	var orig_hashirama := load("res://resources/characters/千手柱间.tres") as CharacterData
	var orig_has_sage := false
	for sk in orig_hashirama.skills:
		if sk.skill_name == "仙人之力":
			orig_has_sage = true
	_assert(not orig_has_sage, "24b: 原柱间不含仙人之力")

	# ── 测试25：真数千手对自身无敌时不受伤（模拟）──────────────────
	# 真数千手的 ENEMY_ALL 不含施法者自己，施法者通过后效 invincible_turns=1 免疫
	# 这里验证真数千手目标是所有其他玩家（不含施法者）
	var e25 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var n25 := PlayerState.new(1, "鸣人", naruto_char, false)
	e25.energy = 4
	var dist25 := DistanceSystem.new()
	dist25.setup([0, 1])
	# targets应不含施法者
	var targets25: Array[PlayerState] = [n25]
	var logs25 := RoundResolver.apply_effects(e25, qss, targets25, dist25)
	_assert(e25.hp == 8, "25a: 施法者不受伤HP=8实际=" + str(e25.hp))
	_assert(n25.hp == 0, "25b: 目标6伤HP=0实际=" + str(n25.hp))

	# ── 测试26：招架（防反）状态下的明神门控制 ─────────────────────
	# 用户规则：招架只在受到伤害时触发（减半+免疫伴随控制），纯控制技能（明神门无伤害）应正常生效且防反状态不消失
	var e26 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var h26 := PlayerState.new(1, "侠影柱间", orig_hashirama, false)
	h26.counter_stance = true  # 侠影柱间处于招架状态
	var dist26 := DistanceSystem.new()
	dist26.setup([0, 1])
	var msg26: SkillData = null
	for sk in edo_char.skills:
		if sk.skill_name == "明神门":
			msg26 = sk
			break
	_assert(msg26 != null, "26a: 明神门技能存在")
	# 明神门无伤害效果
	var msg_has_damage := false
	for eff in msg26.effects:
		if eff.effect_type == SkillEffect.EffectType.DAMAGE:
			msg_has_damage = true
	_assert(not msg_has_damage, "26b: 明神门为纯控制技能（不含伤害）")
	var logs26 := RoundResolver.apply_effects(e26, msg26, [h26], dist26)
	_assert(h26.counter_stance, "26c: 招架状态未消失（明神门无伤害不触发防反）")
	_assert(h26.paralyze_turns == 3, "26d: 明神门麻痹3回合实际=" + str(h26.paralyze_turns))
	_assert(h26.skill_disabled_turns == 3, "26e: 明神门封技3回合实际=" + str(h26.skill_disabled_turns))
	# 禁锢后 get_all_skills 仅保留普攻（招架不可用）
	var h26_skills := h26.get_all_skills()
	_assert(h26_skills.size() == 1 and h26_skills[0].skill_name == "普攻", "26f: 禁锢后仅保留普攻（招架不可用）")

	# ── 测试27：带伤害技能的控制效果仍被招架免疫 ──────────────────
	# 树界降诞（1伤+禁锢2）打在招架目标上：伤害减半、控制免疫、防反触发
	var e27 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var h27 := PlayerState.new(1, "侠影柱间", orig_hashirama, false)
	h27.counter_stance = true
	var dist27 := DistanceSystem.new()
	dist27.setup([0, 1])
	e27.energy = 2
	var logs27 := RoundResolver.apply_effects(e27, sjj, [h27], dist27)
	_assert(h27.hp == 9.0, "27a: 侠影柱间HP10-树界1伤(减半取整1)=9 实际=" + str(h27.hp))
	_assert(h27.paralyze_turns == 0, "27b: 招架免疫麻痹实际=" + str(h27.paralyze_turns))
	_assert(h27.skill_disabled_turns == 0, "27c: 招架免疫封技实际=" + str(h27.skill_disabled_turns))
	_assert(h27.counter_stance, "27d: 招架状态持续（防反为持续状态）")

	# ── 测试28：招架状态被控制（麻痹/封技）后，受击不触发防反 ─────
	# 用户规则：招架状态保留但不触发——被麻痹/封技期间受击不减伤、不得气、不反击
	# 场景A：招架中被明神门（纯控制）麻痹+封技，随后受普攻伤害
	var e28 := PlayerState.new(0, "秽土柱间", edo_char, true)
	var h28 := PlayerState.new(1, "侠影柱间", orig_hashirama, false)
	h28.counter_stance = true
	h28.energy = 0
	var dist28 := DistanceSystem.new()
	dist28.setup([0, 1])
	# 先用明神门控制（纯控制，招架不免疫，状态保留）
	var logs28a := RoundResolver.apply_effects(e28, msg26, [h28], dist28)
	_assert(h28.counter_stance, "28a: 被控制后招架状态保留")
	_assert(h28.paralyze_turns == 3, "28b: 被麻痹3回合")
	_assert(h28.skill_disabled_turns == 3, "28c: 被封技3回合")
	# 被控制期间受普攻1伤：不应触发防反（不减半、不得气、不反击）
	var e28_hp_before: float = h28.hp
	var e28_energy_before: int = h28.energy
	var basic28: SkillData = null
	for sk in edo_char.skills:
		if sk.skill_name == "普攻":
			basic28 = sk
			break
	var logs28b := RoundResolver.apply_effects(e28, basic28, [h28], dist28)
	_assert(h28.hp == e28_hp_before - 1.0, "28d: 被控制期间受击不减半伤，HP=" + str(h28.hp))
	_assert(h28.energy == e28_energy_before, "28e: 被控制期间不得气 energy=" + str(h28.energy))
	_assert(e28.hp == 8.0, "28f: 被控制期间不反击攻击者 HP=" + str(e28.hp))
	var logs28b_counter := false
	for entry in logs28b:
		if entry.get("result", {}).get("counter_stance_triggered", false):
			logs28b_counter = true
	_assert(not logs28b_counter, "28g: 普攻日志无防反触发标记")

	print("=== 秽土柱间测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
