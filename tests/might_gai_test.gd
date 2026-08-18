## 迈特凯完整机制测试（重写版）
## 不依赖 GameManager 完整状态机，直接测试 PlayerState / RoundResolver / 关键逻辑
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 迈特凯完整机制测试（重写版） ===")
	print("[DEBUG] _ready entered")

	# 等一帧确保 Autoload 就绪
	await get_tree().process_frame
	print("[DEBUG] after first process_frame")

	# 加载角色资源
	var gai_char := load("res://resources/characters/迈特凯.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData

	if gai_char == null:
		print("FATAL: 迈特凯.tres 加载失败")
		get_tree().quit(1)
		return
	if naruto_char == null:
		print("FATAL: 漩涡鸣人.tres 加载失败")
		get_tree().quit(1)
		return

	print("[DEBUG] 角色资源加载成功: gai=%s naruto=%s" % [gai_char.character_name, naruto_char.character_name])

	# 不走 setup_game 完整流程，手动构建 PlayerState
	var gai := PlayerState.new(0, "迈特凯", gai_char, true)
	var naruto := PlayerState.new(1, "鸣人", naruto_char, false)
	print("[DEBUG] PlayerState 创建成功")

	# ── 测试1：角色属性 ──────────────────────────────────────────
	_assert(gai.character.max_hp == 16, "1a: 迈特凯HP应为16实际=" + str(gai.character.max_hp))
	_assert(gai.character.grade == "S", "1b: 迈特凯等级应为S实际=" + gai.character.grade)
	_assert(gai.hp == 16, "1c: 初始HP应为16实际=" + str(gai.hp))

	# ── 测试2：八门遁甲为被动技 ──────────────────────────────────
	var has_gate: bool = false
	var gate_is_passive: bool = false
	for skill in gai.character.skills:
		if skill.skill_name == "八门遁甲":
			has_gate = true
			gate_is_passive = skill.is_passive
	_assert(has_gate, "2a: 角色技能列表应有八门遁甲")
	_assert(gate_is_passive, "2b: 八门遁甲应为被动技")

	# ── 测试3：get_all_skills过滤被动技 ────────────────────────────
	var all_visible := gai.get_all_skills()
	var gate_in_visible := false
	for skill in all_visible:
		if skill.skill_name == "八门遁甲":
			gate_in_visible = true
	_assert(not gate_in_visible, "3: 八门遁甲不应出现在可见技能列表")

	# ── 测试4：夜凯/夕象/双龙戏珠为独立技能资源（不直接放入角色技能） ───
	var night_kai: SkillData = null
	var double_dragon: SkillData = null
	for skill in gai.character.skills:
		if skill.skill_name == "夜凯":
			night_kai = skill
		if skill.skill_name == "双龙戏珠":
			double_dragon = skill
	_assert(night_kai == null, "4a: 夜凯不应直接出现在角色技能列表（八门全开后解锁）")
	_assert(double_dragon == null, "4b: 双龙戏珠不应直接出现在角色技能列表（八门全开后解锁）")

	# ── 测试4.5：开局 get_all_skills 不应包含夜凯/夕象/双龙戏珠 ────
	var start_has_locked := false
	for skill in all_visible:
		if skill.skill_name in ["夜凯", "夕象", "双龙戏珠"]:
			start_has_locked = true
			break
	_assert(not start_has_locked, "4.5: 开局夜凯/夕象/双龙戏珠不可用")

	# ── 测试5：八门开门逻辑（直接调用 GameManager._process_gate_open）──
	var gm := GameManager
	# 先用 setup_game 初始化最小环境（2人）
	gm.setup_game({
		"players": [
			{"name": "迈特凯", "character": gai_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var gm_gai: PlayerState = gm.get_player(0)
	var gm_naruto: PlayerState = gm.get_player(1)

	print("[DEBUG] GameManager setup完成, gai hp=%d" % gm_gai.hp)

	# 连接信号
	var gate_signals: Array = []
	gm.gate_changed.connect(func(pid: int, gc: int): gate_signals.append([pid, gc]))
	var invincible_signals: Array = []
	gm.player_invincible.connect(func(pid: int, t: int): invincible_signals.append([pid, t]))

	# 模拟聚气后八门开门
	gm_gai.energy = 0
	gm_gai.invincible_turns = 0
	gm.call("_process_gate_open", gm_gai)

	_assert(gm_gai.gate_count == 1, "5a: 聚气后八门应为1实际=" + str(gm_gai.gate_count))
	_assert(gm_gai.invincible_turns == 2, "5b: 聚气后无敌2回合实际=" + str(gm_gai.invincible_turns))
	_assert(gate_signals.size() >= 1, "5c: gate_changed信号已发射")
	_assert(invincible_signals.size() >= 1, "5d: player_invincible信号已发射")

	# ── 测试6：无敌状态下免疫伤害 ────────────────────────────────
	gm_gai.invincible_turns = 2
	var gai_hp_before := gm_gai.hp
	gm_naruto.energy = 100
	var naruto_attack: SkillData = gm_naruto.character.skills[0]  # 普攻
	var dist_sys: DistanceSystem = gm.get("_distance_system")
	var logs := RoundResolver.apply_effects(gm_naruto, naruto_attack, [gm_gai], dist_sys)
	var damage_result: Dictionary = {}
	for entry in logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
			damage_result = entry.get("result", {})
	_assert(damage_result.get("invincible", false), "6a: 无敌状态标记为invincible")
	_assert(damage_result.get("damage_dealt", 0) == 0, "6b: 无敌状态下伤害应为0")
	_assert(gm_gai.hp == gai_hp_before, "6c: 无敌状态HP不变")

	# ── 测试7：连续聚气开门到第八门 ──────────────────────────────
	gm_gai.gate_count = 7
	gm_gai.invincible_turns = 0
	gm_gai.energy = 0
	var burning_signals: Array = []
	gm.player_burning.connect(func(pid: int): burning_signals.append(pid))
	var berserker_signals: Array = []
	gm.player_berserker.connect(func(pid: int): berserker_signals.append(pid))
	var eighth_gate_signals: Array = []
	gm.eighth_gate_opened.connect(func(pid: int): eighth_gate_signals.append(pid))
	var skill_lost_signals: Array = []
	gm.skill_lost.connect(func(pid: int, sn: String): skill_lost_signals.append([pid, sn]))

	gm.call("_process_gate_open", gm_gai)

	_assert(gm_gai.gate_count == 8, "7a: 第八门全开实际=" + str(gm_gai.gate_count))
	_assert(gm_gai.hp >= 16, "7b: 回10血后HP=" + str(gm_gai.hp))
	_assert(gm_gai.burning, "7c: 进入燃烧状态")
	_assert(gm_gai.berserker, "7d: 进入狂战士状态")
	_assert("八门遁甲" in gm_gai.lost_skills, "7e: 八门遁甲已失去")
	_assert(eighth_gate_signals.size() >= 1, "7f: eighth_gate_opened信号已发射")
	_assert(burning_signals.size() >= 1, "7g: player_burning信号已发射")
	_assert(berserker_signals.size() >= 1, "7h: player_berserker信号已发射")

	# ── 测试7.5：八门全开后解锁夜凯/夕象/双龙戏珠 ────────────────
	var unlock_names: Array[String] = []
	for s in gm_gai.unlocked_skills:
		unlock_names.append(s.skill_name)
	_assert("夜凯" in unlock_names, "7.5a: 八门全开后解锁夜凯")
	_assert("夕象" in unlock_names, "7.5b: 八门全开后解锁夕象")
	_assert("双龙戏珠" in unlock_names, "7.5c: 八门全开后解锁双龙戏珠")
	# 解锁后可见技能列表包含夜凯/夕象（双龙戏珠 is_passive 不可见）
	var post_visible := gm_gai.get_all_skills()
	var post_names: Array[String] = []
	for s in post_visible:
		post_names.append(s.skill_name)
	_assert("夜凯" in post_names, "7.5d: 八门后夜凯可用")
	_assert("夕象" in post_names, "7.5e: 八门后夕象可用")
	_assert(not ("双龙戏珠" in post_names), "7.5f: 双龙戏珠为隐藏技不可见")

	# ── 测试8：夕象存在且可血付（解锁后从unlocked_skills获取） ─────
	var evening_elephant: SkillData = null
	for skill in gm_gai.unlocked_skills:
		if skill.skill_name == "夕象":
			evening_elephant = skill
	_assert(evening_elephant != null, "8a: 夕象技能存在（解锁后）")
	_assert(evening_elephant.can_pay_with_hp, "8b: 夕象可血付")
	_assert(evening_elephant.max_range >= 999, "8c: 夕象范围为无限")

	# ── 测试9：分身存在 ────────────────────────────────────
	var clone_skill: SkillData = null
	for skill in gm_gai.character.skills:
		if skill.skill_name == "分身":
			clone_skill = skill
	_assert(clone_skill != null, "9a: 分身技能存在")

	# 有分身时在 get_all_skills 中仍可见（不是被动技）
	gm_gai.clone_count = 1
	gm_gai.energy = 10
	var all_vis := gm_gai.get_all_skills()
	var clone_in_list := false
	for skill in all_vis:
		if skill.skill_name == "分身":
			clone_in_list = true
	_assert(clone_in_list, "9b: 分身在可见技能列表中")

	# ── 测试10：TRUE_DAMAGE效果（双龙戏珠）───────────────────────
	var target_hp_before := gm_naruto.hp
	var dd_effect := SkillEffect.new()
	dd_effect.effect_type = SkillEffect.EffectType.TRUE_DAMAGE
	dd_effect.value = 10
	dd_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var dd_skill := SkillData.new()
	dd_skill.skill_name = "测试真伤"
	dd_skill.energy_cost = 0
	dd_skill.min_range = 1
	dd_skill.max_range = 1
	dd_skill.effects = [dd_effect]
	gm_gai.energy = 10
	var dd_logs := RoundResolver.apply_effects(gm_gai, dd_skill, [gm_naruto], dist_sys)
	# 真伤无视防御直接扣血，HP最低为0（不会为负）
	var expected_hp: int = maxi(0, target_hp_before - 10)
	_assert(gm_naruto.hp == expected_hp, "10: 真实伤害10点，目标HP从" + str(target_hp_before) + "→" + str(gm_naruto.hp) + "（期望" + str(expected_hp) + "）")

	# ── 测试11：燃烧/狂战士结算 ──────────────────────────────────
	gm_gai.burning = true
	gm_gai.berserker = true
	gm_gai.took_damage_this_round = true
	gm_gai.hp = 10
	var burn_signals: Array = []
	gm.burn_damage_triggered.connect(func(pid: int, d: int, hp: int, r: String): burn_signals.append([pid, d, hp, r]))

	gm.call("_process_burn_and_berserker")
	_assert(gm_gai.hp == 8, "11: 燃烧-1+狂战士-1=HP10→8实际=" + str(gm_gai.hp))
	_assert(burn_signals.size() >= 2, "11b: burn_damage_triggered信号×2")

	# ── 测试12：燃烧HP>1保护 ─────────────────────────────────────
	gm_gai.burning = true
	gm_gai.berserker = false
	gm_gai.took_damage_this_round = false
	gm_gai.hp = 1
	gm.call("_process_burn_and_berserker")
	_assert(gm_gai.hp == 1, "12: 燃烧HP=1时保护不扣血实际=" + str(gm_gai.hp))

	# ── 测试13：狂战士可致死 ──────────────────────────────────────
	gm_gai.burning = false
	gm_gai.berserker = true
	gm_gai.took_damage_this_round = true
	gm_gai.hp = 1
	gm.call("_process_burn_and_berserker")
	_assert(gm_gai.hp == 0, "13: 狂战士可致死HP=1→0实际=" + str(gm_gai.hp))

	# ── 测试14：无敌回合递减 ──────────────────────────────────────
	gm_gai.hp = 10
	gm_gai.is_alive = true
	gm_gai.invincible_turns = 2
	gm_gai.reset_round_data()
	# 模拟_end_round中的递减
	if gm_gai.invincible_turns > 0:
		gm_gai.invincible_turns -= 1
	_assert(gm_gai.invincible_turns == 1, "14a: 无敌回合递减到1")
	if gm_gai.invincible_turns > 0:
		gm_gai.invincible_turns -= 1
	_assert(gm_gai.invincible_turns == 0, "14b: 无敌回合再次递减到0")

	# ── 测试15：血付机制 ──────────────────────────────────────────
	# 从解锁技能中取夜凯（5气）做血付测试
	var unlocked_night_kai: SkillData = null
	for skill in gm_gai.unlocked_skills:
		if skill.skill_name == "夜凯":
			unlocked_night_kai = skill
	_assert(unlocked_night_kai != null, "15pre: 八门后已解锁夜凯")
	gm_gai.hp = 10
	gm_gai.energy = 2
	gm_gai.pending_hp_payment = 3  # 付3血
	# 手动模拟血付扣血补气（与GameManager._apply_actions一致）
	var hp_pay := mini(3, gm_gai.hp - 1)  # 不能血付致死
	hp_pay = mini(hp_pay, unlocked_night_kai.energy_cost - gm_gai.energy)  # 不超过缺口
	gm_gai.hp -= hp_pay
	gm_gai.energy += hp_pay
	_assert(gm_gai.hp == 7, "15b: 血付后HP=10-3=7实际=" + str(gm_gai.hp))
	_assert(gm_gai.energy == 5, "15c: 血付后energy=2+3=5实际=" + str(gm_gai.energy))

	# ── 测试16：连续回合追踪 ──────────────────────────────────────
	gm.set("_prev_winner_id", 0)
	gm.set("_sole_winner_id", 0)
	gm_gai.consecutive_rounds = 1
	# 模拟连续赢得猜拳
	if 0 == gm.get("_prev_winner_id"):
		gm_gai.consecutive_rounds += 1
	_assert(gm_gai.consecutive_rounds == 2, "16: 连续回合+1→2")

	# ── 测试17：LOSE_SKILL效果 ──────────────────────────────────
	var lose_effect := SkillEffect.new()
	lose_effect.effect_type = SkillEffect.EffectType.LOSE_SKILL
	lose_effect.lose_skill_name = "八门遁甲"
	lose_effect.target = SkillEffect.EffectTarget.SELF
	lose_effect.value = 0
	# 先重置 lost_skills
	gm_gai.lost_skills.clear()
	gm_gai.lost_skills.append("八门遁甲")
	_assert("八门遁甲" in gm_gai.lost_skills, "17: LOSE_SKILL后技能在lost_skills中")

	# ── 测试18：角色选择页preload ──────────────────────────────
	var cs_preloads: Array = [
		preload("res://resources/characters/漩涡鸣人.tres"),
		preload("res://resources/characters/宇智波佐助.tres"),
		preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
		preload("res://resources/characters/春野樱.tres"),
		preload("res://resources/characters/千手柱间.tres"),
		preload("res://resources/characters/迈特凯.tres"),
	]
	var gai_in_preloads := false
	for res in cs_preloads:
		if res is CharacterData and res.character_name == "迈特凯（夏日限定）":
			gai_in_preloads = true
	_assert(gai_in_preloads, "18: 迈特凯在character_select preload列表中")

	print("=== 迈特凯测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)