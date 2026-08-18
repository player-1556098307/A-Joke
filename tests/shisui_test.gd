## 宇智波止水完整机制测试
## 覆盖：角色属性、技能定义、日晕舞中断/衔接九十九、
## 斩（无敌+延迟2伤+解锁螺旋）、螺旋（3段+无敌+封技+解锁九十九）、
## 九十九（4段+无敌）、别天神夺舍（击杀触发/完全替换/半血/继承气/夺舍体死亡回退）
## 说明：完整回合链（submit→APPLYING→ELIMINATION→END_PHASE→ROUND_END→GESTURE_INPUT）
## 同步走完，无敌/封技等回合结束时递减，因此用信号捕获验证中间状态
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 宇智波止水完整机制测试 ===")
	await get_tree().process_frame

	var shisui_char := load("res://resources/characters/宇智波止水（须佐能）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if shisui_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# ══ 测试1：角色属性 ══════════════════════════════════════════
	_assert(shisui_char.max_hp == 6, "1a: 止水HP=6（实际=%d）" % shisui_char.max_hp)
	_assert(shisui_char.grade == "S", "1b: 止水等级S（实际=%s）" % shisui_char.grade)
	_assert("刺客" in shisui_char.tags and "法师" in shisui_char.tags, "1c: 标签=刺客+法师")
	_assert(shisui_char.portrait != null, "1d: 止水立绘已加载")

	var shisui_skills: Array[String] = []
	for s in shisui_char.skills:
		shisui_skills.append(s.skill_name)
	_assert("普攻" in shisui_skills and "宇智波流·日晕舞" in shisui_skills and "须佐能乎·斩" in shisui_skills and "别天神·夺舍" in shisui_skills, "1e: 基础技能含普攻/日晕舞/斩/别天神·夺舍")
	_assert("须佐能乎·螺旋" not in shisui_skills and "须佐能乎·九十九" not in shisui_skills, "1f: 螺旋/九十九为解锁技能不出现在基础列表")

	# ═════════ 测试2：技能属性 ══════════════════════════════════
	var hiano: SkillData = null
	var slash: SkillData = null
	var koto: SkillData = null
	for s in shisui_char.skills:
		match s.skill_name:
			"宇智波流·日晕舞": hiano = s
			"须佐能乎·斩": slash = s
			"别天神·夺舍": koto = s

	_assert(hiano != null and hiano.energy_cost == 2, "2a: 日晕舞耗气2（实际=%s）" % str(hiano.energy_cost if hiano else -1))
	_assert(hiano != null and hiano.effects[0].effect_type == SkillEffect.EffectType.HIANO_KAGEROHI, "2b: 日晕舞效果=HIANO_KAGEROHI(%d)（实际=%d）" % [SkillEffect.EffectType.HIANO_KAGEROHI, hiano.effects[0].effect_type if hiano else -1])

	_assert(slash != null and slash.energy_cost == 2, "2c: 斩耗气2（实际=%s）" % str(slash.energy_cost if slash else -1))
	_assert(slash != null and slash.effects[0].effect_type == SkillEffect.EffectType.SUSANOO_SLASH, "2d: 斩效果=SUSANOO_SLASH(%d)（实际=%d）" % [SkillEffect.EffectType.SUSANOO_SLASH, slash.effects[0].effect_type if slash else -1])
	_assert(slash != null and slash.effects[0].target == SkillEffect.EffectTarget.ENEMY_SINGLE, "2e: 斩目标=ENEMY_SINGLE（实际=%d）" % (slash.effects[0].target if slash else -1))

	_assert(koto != null and koto.is_limited and koto.is_passive, "2f: 别天神为被动限定技")
	_assert(koto != null and koto.effects[0].effect_type == SkillEffect.EffectType.KOTOAMATSUKAMI, "2g: 别天神效果=KOTOAMATSUKAMI(%d)（实际=%d）" % [SkillEffect.EffectType.KOTOAMATSUKAMI, koto.effects[0].effect_type if koto else -1])

	# ═════════ 测试3：基础状态初始化 ═════════════════════════════
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var shisui: PlayerState = gm.get_player(0)
	var naruto: PlayerState = gm.get_player(1)
	var sasuke: PlayerState = gm.get_player(2)
	_assert(shisui != null and shisui.hp == 6, "3a: 止水初始HP=6（实际=%d）" % shisui.hp)
	_assert(not shisui.susanoo_spiral_unlocked and not shisui.has_kotoamatsukami_skill, "3b: 初始未解锁螺旋/九十九")
	_assert(not shisui.kotoamatsukami_used and not shisui.takeover_active, "3c: 初始未使用别天神/非夺舍状态")
	_assert(shisui.last_hit_by_id == -1, "3d: 初始最近伤害来源=-1")

	# ═════════ 测试4：须佐能乎·斩（完整回合流程） ══════════════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	shisui.energy = 2
	var slash_idx := _find_skill_index(shisui, "须佐能乎·斩")
	_assert(slash_idx >= 0, "4a: 斩技能索引找到")
	var inv4: Array = []
	var dl4: Array = []
	gm.player_invincible.connect(func(p: int, t: int): inv4.append([p, t]))
	gm.delayed_damage_triggered.connect(func(p: int, d: float, h: float): dl4.append([p, d, h]))
	# 止水胜出猜拳（ROCK 胜 SCISSORS）
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "4b: 止水赢得本回合（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "4c: 进入行动阶段（实际=%d）" % gm.get("_current_phase"))
	var nar_hp4: float = naruto.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, slash_idx, 1)
	_assert(shisui.energy == 0, "4d: 斩消耗2气（2→0，实际=%d）" % shisui.energy)
	_assert(inv4.size() == 1 and inv4[0][1] == 1, "4e: 斩后本回合无敌（信号已发射，实际=%d）" % (inv4[0][1] if inv4.size() > 0 else -1))
	_assert(shisui.susanoo_spiral_unlocked, "4f: 斩解锁螺旋")
	_assert(dl4.size() == 1 and dl4[0][0] == 1 and dl4[0][1] == 2.0, "4g: 斩延迟2伤挂到目标鸣人并触发（目标=%d 伤害=%s）" % [dl4[0][0] if dl4.size() > 0 else -1, str(dl4[0][1] if dl4.size() > 0 else -1)])
	_assert(naruto.hp == nar_hp4 - 2, "4h: 斩延迟伤害生效（鸣人HP %d→%d）" % [nar_hp4, naruto.hp])

	# ═════════ 测试5：须佐能乎·螺旋（完整回合流程） ═════════════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	var spiral_res := load("res://resources/characters/skills/须佐能乎·螺旋.tres") as SkillData
	_assert(spiral_res != null, "5a: 螺旋技能资源可加载")
	shisui.susanoo_spiral_unlocked = true
	shisui.unlocked_skills.append(spiral_res)
	shisui.energy = 2
	var spiral_idx := _find_skill_index(shisui, "须佐能乎·螺旋")
	_assert(spiral_idx >= 0, "5b: 螺旋技能索引（=%d）" % spiral_idx)
	var inv5: Array = []
	var dis5: Array = []
	gm.player_invincible.connect(func(id: int, t: int): inv5.append([id, t]))
	gm.skill_disabled.connect(func(id: int, t: int): dis5.append([id, t]))
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "5c: 止水赢得本回合")
	var nar_hp5: float = naruto.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, spiral_idx, 1)
	_assert(inv5.size() == 1 and inv5[0][1] == 1, "5d: 螺旋后本回合无敌（信号=%d）" % (inv5[0][1] if inv5.size() > 0 else -1))
	# 封技信号：螺旋施加时 emit 1；回合结束 skill_disabled_turns 归零时会再 emit 0，故至少 1 条即可
	_assert(dis5.size() >= 1 and dis5[0][1] >= 1, "5e: 螺旋封技（信号=%d）" % (dis5[0][1] if dis5.size() > 0 else -1))
	_assert(naruto.hp == nar_hp5 - 3, "5f: 螺旋三段3伤（鸣人HP %d→%d）" % [nar_hp5, naruto.hp])
	_assert(shisui.has_kotoamatsukami_skill, "5g: 螺旋解锁九十九获得别天神条件")
	var has_nn := false
	for sk in shisui.unlocked_skills:
		if sk.skill_name == "须佐能乎·九十九":
			has_nn = true
			break
	_assert(has_nn, "5h: 螺旋解锁九十九技能")

	# ═════════ 测试6：须佐能乎·九十九（完整回合流程） ═══════════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	var nn_res := load("res://resources/characters/skills/须佐能乎·九十九.tres") as SkillData
	_assert(nn_res != null, "6a: 九十九技能资源可加载")
	shisui.unlocked_skills.append(nn_res)
	shisui.has_kotoamatsukami_skill = true
	shisui.energy = 2
	var nn_idx := _find_skill_index(shisui, "须佐能乎·九十九")
	_assert(nn_idx >= 0, "6b: 九十九已解锁（索引=%d）" % nn_idx)
	var inv6: Array = []
	gm.player_invincible.connect(func(i6: int, t6: int): inv6.append([i6, t6]))
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var nar_hp6: float = naruto.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, nn_idx, 1)
	_assert(naruto.hp == nar_hp6 - 4, "6c: 九十九四段4伤（鸣人HP %d→%d）" % [nar_hp6, naruto.hp])
	_assert(inv6.size() == 1 and inv6[0][1] == 1, "6d: 九十九后本回合无敌（信号=%d）" % (inv6[0][1] if inv6.size() > 0 else -1))

	# ═════════ 测试7：日晕舞（完整回合流程，不中断→3段全打） ═════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	shisui.energy = 2
	var hiano_idx := _find_skill_index(shisui, "宇智波流·日晕舞")
	_assert(hiano_idx >= 0, "7a: 日晕舞技能索引")
	var hiano_sig: Array = []
	gm.hiano_interrupt_required.connect(func(p: int, t: int, m: int): hiano_sig.append([p, t, m]))
	var nar_hp7: float = naruto.hp
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, hiano_idx, 1)
	_assert(hiano_sig.size() == 1, "7b: 人类弹窗信号已发射（实际=%d）" % hiano_sig.size())
	_assert(hiano_sig[0][2] == 2, "7c: 弹窗最大中断点=2（实际=%d）" % hiano_sig[0][2])
	gm.call("_on_hiano_interrupt_made", 0, 0)  # 不中断
	_assert(naruto.hp == nar_hp7 - 3, "7d: 日晕舞不中断打满3段（鸣人HP %d→%d）" % [nar_hp7, naruto.hp])
	_assert(shisui.energy == 0, "7e: 日晕舞消耗2气（2→0，实际=%d）" % shisui.energy)

	# ═════════ 测试8：日晕舞中断（1段后）+ 衔接九十九 ════════════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	shisui.energy = 4  # 日晕舞2气 + 九十九2气
	var nn8 := load("res://resources/characters/skills/须佐能乎·九十九.tres") as SkillData
	if nn8 and not shisui.unlocked_skills.has(nn8):
		shisui.unlocked_skills.append(nn8)
	shisui.has_kotoamatsukami_skill = true
	var nar_hp8: float = naruto.hp
	var inv8: Array = []
	gm.player_invincible.connect(func(i8: int, t8: int): inv8.append([i8, t8]))
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(shisui, "宇智波流·日晕舞"), 1)
	gm.call("_on_hiano_interrupt_made", 0, 1)  # 1段后中断
	_assert(naruto.hp == nar_hp8 - 1 - 4, "8a: 日晕舞中断1段+九十九4段=共5伤（鸣人HP %d→%d）" % [nar_hp8, naruto.hp])
	_assert(shisui.energy == 0, "8b: 日晕舞2气+九十九2气=4气消耗（4→0，实际=%d）" % shisui.energy)
	_assert(inv8.size() >= 1 and inv8[0][1] == 1, "8c: 衔接九十九后本回合无敌（信号=%d）" % (inv8[0][1] if inv8.size() > 0 else -1))

	# ═════════ 测试9：AI自动中断选择 ════════════════════════════════
	gm.setup_game({
		"players": [
			{"name": "止水AI", "character": shisui_char, "is_human": false},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	shisui.energy = 4
	naruto.hp = 1.5  # 低血触发AI中断（≤1.5→中断1段）
	var nar_hp9: float = naruto.hp
	var hiano_ai: SkillData = null
	for s in shisui_char.skills:
		if s.skill_name == "宇智波流·日晕舞":
			hiano_ai = s
			break
	shisui.energy -= 2  # 模拟 _apply_actions 已扣日晕舞2气（4→2）
	gm.set("_hiano_pending", { "player_id": 0, "target_id": 1, "skill": hiano_ai })
	gm.set("_current_phase", GameManager.GamePhase.APPLYING)
	gm.call("_request_hiano_interrupt", shisui, naruto)
	_assert(naruto.hp == 0.0, "9a: AI低血自动中断1段+衔接九十九（1.5血→0，实际=%s）" % str(naruto.hp))
	_assert(shisui.energy == 0, "9b: AI衔接后气耗光（4→0，实际=%d）" % shisui.energy)

	# ═════════ 测试10：别天神夺舍（击杀触发完整流程） ══════════
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	shisui = gm.get_player(0)
	naruto = gm.get_player(1)
	sasuke = gm.get_player(2)
	shisui.has_kotoamatsukami_skill = true  # 满足别天神条件
	shisui.energy = 2
	naruto.hp = 1.0
	var koto_sig: Array = []
	gm.kotoamatsukami_required.connect(func(pid: int, tid: int): koto_sig.append([pid, tid]))
	# 完整流程：止水日晕舞击杀鸣人
	shisui.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(shisui, "宇智波流·日晕舞"), 1)
	gm.call("_on_hiano_interrupt_made", 0, 0)  # 不中断
	_assert(naruto.hp == 0.0, "10a: 鸣人被击杀（HP=%d）" % naruto.hp)
	_assert(koto_sig.size() >= 1, "10b: 别天神弹窗信号已发射（实际=%d）" % koto_sig.size())
	_assert(naruto.is_alive, "10c: 弹窗确认前受害者保持存活")
	_assert(shisui.koto_awaiting_confirm, "10d: 止水等待确认标记")

	var takeover_sig: Array = []
	gm.kotoamatsukami_takeover.connect(func(pid: int, tid: int): takeover_sig.append([pid, tid]))
	gm.call("_on_kotoamatsukami_made", 0, true)
	_assert(shisui.character == naruto_char, "10e: 夺舍后角色变为鸣人")
	_assert(shisui.hp == 3.0, "10f: 夺舍后血量=鸣人半血（3，实际=%d）" % shisui.hp)
	_assert(shisui.energy == naruto.energy, "10g: 夺舍后继承鸣人阵亡时气")
	_assert(shisui.kotoamatsukami_used, "10h: 别天神已使用")
	_assert(shisui.takeover_active, "10i: 夺舍状态激活")
	_assert(takeover_sig.size() == 1, "10j: 夺舍信号已发射（实际=%d）" % takeover_sig.size())

	# ═════════ 测试11：夺舍体死亡回退 ═══════════════════════
	var revert_sig: Array = []
	gm.takeover_reverted.connect(func(pid: int): revert_sig.append(pid))
	shisui.hp = 0.0
	var did_revert: bool = gm.call("_revert_takeover_if_needed", shisui)
	_assert(did_revert, "11a: 夺舍体死亡触发回退")
	_assert(shisui.character == shisui_char, "11b: 回退后角色恢复为止水")
	_assert(shisui.hp > 0, "11c: 回退后血量>0（实际=%d）" % shisui.hp)
	_assert(shisui.is_alive, "11d: 回退后仍存活")
	_assert(revert_sig.size() == 1, "11e: 回退信号已发射（实际=%d）" % revert_sig.size())
	_assert(shisui.has_kotoamatsukami_skill, "11f: 回退保留别天神条件状态")

	# ═════════ 测试12：AI决策（止水走通用逻辑，技能可用） ═════════
	var ai := AIController.new()
	var shisui_ai := PlayerState.new(0, "止水AI", shisui_char, false)
	shisui_ai.energy = 4
	var nar_ai := PlayerState.new(1, "鸣人", naruto_char, false)
	var sas_ai := PlayerState.new(2, "佐助", sasuke_char, false)
	var dist := DistanceSystem.new()
	dist.setup([0, 1, 2])
	var dec := ai.decide_action(shisui_ai, [shisui_ai, nar_ai, sas_ai], dist)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "12a: AI止水有技能时使用技能（实际=%d）" % dec["action"])
	if dec["action"] == PlayerState.ActionType.USE_SKILL and dec["skill_index"] >= 0:
		var used_name: String = shisui_ai.get_all_skills()[dec["skill_index"]].skill_name
		_assert(used_name in ["宇智波流·日晕舞", "须佐能乎·斩", "须佐能乎·螺旋", "须佐能乎·九十九", "普攻"], "12b: AI使用止水可用技能（实际=%s）" % used_name)

	print("=== 止水测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 在玩家的全部技能（含解锁）中查找技能索引
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