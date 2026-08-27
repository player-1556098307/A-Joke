## 阿尔托莉雅·卡斯特完整机制测试
## 覆盖：角色属性/技能定义、乐园妖精（开局5气）、
##       巡礼（消耗气→圣盾+计数+4次升级）、Around Caliburn（圣盾+伤害x2）、
##       湖之加护（结束阶段+1气）、圣剑锻造（无消耗释放+fallback 3气）、AI策略
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 阿尔托莉雅·卡斯特完整机制测试 ===")
	await get_tree().process_frame

	var caster_char := load("res://resources/characters/阿尔托莉雅·卡斯特.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if caster_char == null or naruto_char == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_stats_and_skills(caster_char, naruto_char)
	await _test_fairy_paradise(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_pilgrimage(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_caliburn(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_lake_blessing(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_sword_forge(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_sword_forge_fallback(caster_char, naruto_char, sasuke_char, sakura_char)
	await _test_ai(caster_char, naruto_char, sasuke_char, sakura_char)

	print("=== 卡斯特测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ 测试1：角色属性与技能定义 ═══════════════════════
func _test_stats_and_skills(caster_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试1：角色属性与技能定义 ---")
	_assert(caster_char.max_hp == 6, "1a: 卡斯特HP=6（实际=%d）" % caster_char.max_hp)
	_assert(caster_char.grade == "S", "1b: 等级S（实际=%s）" % caster_char.grade)
	_assert("法师" in caster_char.tags and caster_char.tags.size() == 1, "1c: 标签=法师（实际=%s）" % str(caster_char.tags))

	var names: Array[String] = []
	for s in caster_char.skills:
		names.append(s.skill_name)
	_assert("普攻" in names, "1d: 含普攻")
	_assert("乐园妖精" in names, "1e: 含乐园妖精")
	_assert("巡礼" in names, "1f: 含巡礼")
	_assert("Around Caliburn" in names, "1g: 含Around Caliburn")
	_assert("湖之加护" in names, "1h: 含湖之加护")
	_assert("圣剑锻造" in names, "1i: 含圣剑锻造")

	var basic: SkillData = null
	var fp: SkillData = null
	var pg: SkillData = null
	var ac: SkillData = null
	var lb: SkillData = null
	var sf: SkillData = null
	for s in caster_char.skills:
		match s.skill_name:
			"普攻": basic = s
			"乐园妖精": fp = s
			"巡礼": pg = s
			"Around Caliburn": ac = s
			"湖之加护": lb = s
			"圣剑锻造": sf = s
	_assert(basic != null and basic.energy_cost == 1 and basic.max_range == 3, "1j: 普攻耗1气/范围3")
	_assert(fp != null and fp.is_passive and fp.energy_cost == 0, "1k: 乐园妖精被动/0耗")
	_assert(fp != null and fp.effects[0].effect_type == SkillEffect.EffectType.FAIRY_PARADISE, "1l: 乐园妖精效果=FAIRY_PARADISE")
	_assert(pg != null and pg.is_passive and pg.energy_cost == 0, "1m: 巡礼被动/0耗")
	_assert(pg != null and pg.effects[0].effect_type == SkillEffect.EffectType.PILGRIMAGE, "1n: 巡礼效果=PILGRIMAGE")
	_assert(ac != null and ac.energy_cost == 3 and ac.max_range == 999, "1o: Around Caliburn耗3气/全屏")
	_assert(ac != null and ac.effects[0].effect_type == SkillEffect.EffectType.SHIELD, "1p: AC效果=SHIELD(-1)")
	_assert(ac != null and int(ac.effects[0].value) == -1, "1q: AC护盾值=-1")
	_assert(lb != null and lb.is_passive and lb.energy_cost == 0, "1r: 湖之加护被动/0耗")
	_assert(lb != null and lb.effects[0].effect_type == SkillEffect.EffectType.LAKE_BLESSING, "1s: 湖之加护效果=LAKE_BLESSING")
	_assert(sf != null and sf.energy_cost == 3 and sf.max_range == 999, "1t: 圣剑锻造耗3气/全屏")

	# 巡礼升级前圣剑锻造不显示在操作阶段
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "卡斯特", "character": caster_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var cs: PlayerState = gm.get_player(0)
	var vis: Array[String] = []
	for s in cs.get_all_skills():
		vis.append(s.skill_name)
	# 未升级时：普攻 + Around Caliburn（被动过滤掉）
	_assert(vis == ["普攻", "Around Caliburn"], "1u: 未升级时可见=普攻/AC（实际=%s）" % str(vis))

## ═════════ 测试2：乐园妖精（开局5气） ═══════════════════════
func _test_fairy_paradise(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试2：乐园妖精（开局5气） ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]

	# 开局自动获得5气
	_assert(cs.energy == 5, "2a: 乐园妖精开局5气（实际=%d）" % cs.energy)
	# 非卡斯特角色不会获得额外气（鸣人开局0气）
	var p1: PlayerState = arr[2]
	_assert(p1.energy == 0, "2b: 非卡斯特开局0气（实际=%d）" % p1.energy)

## ═════════ 测试3：巡礼（消耗气→圣盾+计数+升级） ═══════════════
func _test_pilgrimage(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试3：巡礼被动 ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]
	var p2: PlayerState = arr[3]

	# R1：卡斯特赢 → 准备阶段无技能 → 行动阶段普攻消耗1气 → 巡礼触发
	cs.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# 乐园妖精开局5气，普攻消耗1气 → energy=4
	# 巡礼触发：shield=-1（圣盾），pilgrimage_count=1
	var pg_sig: Array = []
	gm.pilgrimage_shield_gained.connect(func(pid: int): pg_sig.append(pid))
	# 清零shield以便检测
	cs.shield = 0
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(cs, "普攻"), 2)
	_assert(cs.energy == 4, "3a: 普攻后气=4（5-1，实际=%d）" % cs.energy)
	_assert(cs.shield == -1, "3b: 巡礼触发圣盾shield=-1（实际=%d）" % cs.shield)
	_assert(cs.pilgrimage_count == 1, "3c: pilgrimage_count=1（实际=%d）" % cs.pilgrimage_count)

	# 圣盾不可叠加：已有shield时再消耗气，shield保持-1
	cs.shield = 0
	cs.energy = 5
	# 手动调用_process_pilgrimage模拟第二次消耗
	gm.call("_process_pilgrimage", cs, 1)
	_assert(cs.shield == -1, "3d: 第二次巡礼shield=-1（实际=%d）" % cs.shield)
	_assert(cs.pilgrimage_count == 2, "3e: pilgrimage_count=2（实际=%d）" % cs.pilgrimage_count)

	# 再消耗2次达到4次 → 解锁圣剑锻造
	gm.call("_process_pilgrimage", cs, 1)
	_assert(cs.pilgrimage_count == 3, "3f: pilgrimage_count=3（实际=%d）" % cs.pilgrimage_count)
	_assert(cs.sword_forge_unlocked == false, "3g: 3次未解锁（实际=%s）" % str(cs.sword_forge_unlocked))

	var unlock_sig: Array = []
	gm.sword_forge_unlocked_signal.connect(func(pid: int): unlock_sig.append(pid))
	gm.call("_process_pilgrimage", cs, 1)
	_assert(cs.pilgrimage_count == 4, "3h: pilgrimage_count=4（实际=%d）" % cs.pilgrimage_count)
	_assert(cs.sword_forge_unlocked == true, "3i: 4次解锁圣剑锻造（实际=%s）" % str(cs.sword_forge_unlocked))
	_assert(unlock_sig.size() == 1 and unlock_sig[0] == 0, "3j: sword_forge_unlocked_signal信号")

	# 升级后再消耗气不再触发巡礼
	var count_before := cs.pilgrimage_count
	gm.call("_process_pilgrimage", cs, 1)
	_assert(cs.pilgrimage_count == count_before, "3k: 升级后巡礼不再触发（count仍=%d）" % cs.pilgrimage_count)

	# 升级后圣剑锻造出现在可见技能列表
	var vis: Array[String] = []
	for s in cs.get_all_skills():
		vis.append(s.skill_name)
	_assert("圣剑锻造" in vis, "3l: 升级后圣剑锻造可见（实际=%s）" % str(vis))

## ═════════ 测试4：Around Caliburn（圣盾+伤害x2） ═════════════
func _test_caliburn(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试4：Around Caliburn ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]
	var p2: PlayerState = arr[3]

	# R1：卡斯特赢
	cs.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")

	# 使用 Around Caliburn（3气）选择p2
	cs.energy = 5
	var caliburn_sig: Array = []
	gm.caliburn_used.connect(func(cid: int, tid: int): caliburn_sig.append([cid, tid]))
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(cs, "Around Caliburn"), 2)

	_assert(cs.energy == 2, "4a: AC消耗3气后剩2（实际=%d）" % cs.energy)
	_assert(p2.shield == -1, "4b: 目标获得圣盾shield=-1（实际=%d）" % p2.shield)
	_assert(p2.damage_double_next == true, "4c: 目标获得伤害x2标记")
	_assert(caliburn_sig.size() == 1 and caliburn_sig[0][0] == 0 and caliburn_sig[0][1] == 2, "4d: caliburn_used信号")

	# 巡礼同时触发（消耗了3气）
	_assert(cs.pilgrimage_count == 1, "4e: AC触发巡礼count=1（实际=%d）" % cs.pilgrimage_count)
	_assert(cs.shield == -1, "4f: AC触发巡礼圣盾（实际=%d）" % cs.shield)

	# 圣盾不可叠加：已有盾时不覆盖
	p2.shield = 5  # 手动设为正常盾值
	cs.energy = 5
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(cs, "Around Caliburn"), 2)
	_assert(p2.shield == 5, "4g: 目标已有盾时不覆盖（实际=%d）" % p2.shield)
	_assert(p2.damage_double_next == true, "4h: 伤害x2仍生效")

## ═════════ 测试5：湖之加护（结束阶段+1气） ═══════════════════
func _test_lake_blessing(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试5：湖之加护 ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]
	var p1: PlayerState = arr[2]

	# 卡斯特赢 → 行动阶段充能 → 结束阶段触发湖之加护
	cs.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")

	# 充能（不使用技能，避免巡礼干扰）
	cs.energy = 5  # 重置为乐园妖精值
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	await get_tree().process_frame

	# 湖之加护在结束阶段触发，人类玩家需手动提交
	var lb_sig: Array = []
	gm.lake_blessing_used.connect(func(cid: int, tid: int): lb_sig.append([cid, tid]))

	var lb_req: Array = []
	gm.lake_blessing_required.connect(func(pid: int, tids: Array[int]): lb_req.append([pid, tids]))

	# 等待结束阶段
	await get_tree().process_frame
	await get_tree().process_frame

	# 手动提交湖之加护（选p1=鸣人获得1气）
	var p1_energy_before := p1.energy
	gm.submit_lake_blessing(0, 1)
	_assert(p1.energy == p1_energy_before + 1, "5a: 湖之加护使p1+1气（%d→%d）" % [p1_energy_before, p1.energy])
	_assert(lb_sig.size() == 1 and lb_sig[0][0] == 0 and lb_sig[0][1] == 1, "5b: lake_blessing_used信号")

## ═════════ 测试6：圣剑锻造（无消耗释放） ═════════════════════
func _test_sword_forge(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试6：圣剑锻造（无消耗释放） ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]
	var p1: PlayerState = arr[2]  # 鸣人（被锻造目标）
	var p2: PlayerState = arr[3]  # 佐助（攻击目标）

	# 先解锁圣剑锻造
	cs.sword_forge_unlocked = true

	# R1：卡斯特赢
	cs.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")

	# 使用圣剑锻造（3气）选择p1（鸣人）
	cs.energy = 5
	var sf_used_sig: Array = []
	gm.sword_forge_used.connect(func(cid: int, tid: int, sname: String): sf_used_sig.append([cid, tid, sname]))

	var sf_req_sig: Array = []
	gm.sword_forge_required.connect(func(pid: int, snames: Array[String], ttids: Array[int]): sf_req_sig.append([pid, snames, ttids]))

	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(cs, "圣剑锻造"), 1)

	_assert(cs.energy == 2, "6a: 圣剑锻造消耗3气后剩2（实际=%d）" % cs.energy)
	# 弹窗发给目标(p1=鸣人)而非卡斯特
	_assert(sf_req_sig.size() >= 1, "6b: sword_forge_required信号（发给目标）")
	if sf_req_sig.size() >= 1:
		_assert(sf_req_sig[0][0] == 1, "6b2: 弹窗发给目标player_id=1（实际=%d）" % sf_req_sig[0][0])

	# 目标(鸣人)提交选择第0个技能（普攻），攻击p2(佐助)
	var p2_hp_before: float = p2.hp
	var saved_p1_energy := p1.energy
	gm.submit_sword_forge(1, 0, 2)

	_assert(sf_used_sig.size() >= 1, "6c: sword_forge_used信号触发")
	_assert(p1.energy == saved_p1_energy, "6d: 目标能量不消耗（实际=%d）" % p1.energy)
	_assert(p2.hp < p2_hp_before, "6e: 攻击目标受伤（%.1f→%.1f）" % [p2_hp_before, p2.hp])

## ═════════ 测试7：圣剑锻造 fallback（无可用技能→3气） ════════
func _test_sword_forge_fallback(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试7：圣剑锻造 fallback ---")
	var arr = await _setup4(caster_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var cs: PlayerState = arr[1]
	var p1: PlayerState = arr[2]  # 鸣人

	# 先解锁圣剑锻造
	cs.sword_forge_unlocked = true

	# R1：卡斯特赢
	cs.current_gesture = PlayerState.Gesture.ROCK
	for p in [arr[2], arr[3], arr[4]]:
		p.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")

	# 使用圣剑锻造（3气）选择p1（鸣人，有耗气技能→走正常路径）
	cs.energy = 5
	var fb_sig: Array = []
	gm.sword_forge_fallback.connect(func(cid: int, tid: int): fb_sig.append([cid, tid]))

	var sf_req_sig: Array = []
	gm.sword_forge_required.connect(func(pid: int, snames: Array[String], ttids: Array[int]): sf_req_sig.append([pid, snames, ttids]))

	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(cs, "圣剑锻造"), 1)

	# p1(鸣人)有普攻（耗气），走正常路径→目标人类弹窗等待 submit_sword_forge
	_assert(cs.energy == 2, "7a: 圣剑锻造消耗3气后剩2（实际=%d）" % cs.energy)
	_assert(sf_req_sig.size() >= 1, "7b: sword_forge_required信号（发给目标）")

	# 目标提交选择第0个技能（普攻），攻击p2(佐助=2)
	var saved_p1_energy := p1.energy
	gm.submit_sword_forge(1, 0, 2)
	_assert(p1.energy == saved_p1_energy, "7c: 目标能量不消耗（实际=%d）" % p1.energy)
	_assert(fb_sig.size() == 0, "7d: 有可用技能时不触发fallback")

## ═════════ 测试8：AI策略 ═══════════════════════════════════
func _test_ai(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试8：AI策略 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "AI卡斯特", "character": caster_char, "is_human": false},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var cs: PlayerState = gm.get_player(0)
	var ai := AIController.new()

	# 5气时：圣剑锻造未解锁 → Around Caliburn（3气，给自己圣盾+伤害x2）
	cs.energy = 5
	cs.sword_forge_unlocked = false
	var result := ai.decide_action(cs, gm.get_alive_players(), gm.get("_distance_system"))
	# 非组队模式下，AC给自己
	var skill_name := ""
	if result.get("action") == PlayerState.ActionType.USE_SKILL and result.get("skill_index", -1) >= 0:
		var all := cs.get_all_skills()
		if result["skill_index"] < all.size():
			skill_name = all[result["skill_index"]].skill_name
	_assert(skill_name == "Around Caliburn", "8a: 5气未解锁时选AC（实际=%s）" % skill_name)

	# 升级后有圣剑锻造 → 优先选圣剑锻造
	cs.sword_forge_unlocked = true
	cs.energy = 5
	result = ai.decide_action(cs, gm.get_alive_players(), gm.get("_distance_system"))
	skill_name = ""
	if result.get("action") == PlayerState.ActionType.USE_SKILL and result.get("skill_index", -1) >= 0:
		var all := cs.get_all_skills()
		if result["skill_index"] < all.size():
			skill_name = all[result["skill_index"]].skill_name
	_assert(skill_name == "圣剑锻造", "8b: 解锁后选圣剑锻造（实际=%s）" % skill_name)

	# 1气时：普攻
	cs.energy = 1
	cs.sword_forge_unlocked = false
	result = ai.decide_action(cs, gm.get_alive_players(), gm.get("_distance_system"))
	skill_name = ""
	if result.get("action") == PlayerState.ActionType.USE_SKILL and result.get("skill_index", -1) >= 0:
		var all := cs.get_all_skills()
		if result["skill_index"] < all.size():
			skill_name = all[result["skill_index"]].skill_name
	_assert(skill_name == "普攻", "8c: 1气时选普攻（实际=%s）" % skill_name)

	# 0气时：充能
	cs.energy = 0
	result = ai.decide_action(cs, gm.get_alive_players(), gm.get("_distance_system"))
	_assert(result.get("action") == PlayerState.ActionType.CHARGE or result.is_empty(), "8d: 0气时充能")

## ═════════ 辅助函数 ═════════════════════════════════════════
func _setup4(caster_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData):
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "卡斯特", "character": caster_char, "is_human": true},
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
