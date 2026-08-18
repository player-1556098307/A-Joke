## 新止水（宇智波止水·天劫）完整机制测试
## 覆盖：角色属性、技能定义、幻影瞬身（命中获影/增伤/闪避拦截）、
## 日影舞（4段独立目标/死亡顺延/幻影消耗）、别天神回溯（条件/快照/恢复/重新入座）、
## 旧止水改名（别天神·夺舍）、AI 策略
## 说明：所有玩家设 is_human=true（避免AI自动行动干扰），回合由测试手动推进
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 新止水（天劫）完整机制测试 ===")
	await get_tree().process_frame

	var new_shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	var old_shisui_char := load("res://resources/characters/宇智波止水（须佐能）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if new_shisui_char == null or old_shisui_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# ══ 测试1：角色属性 ══════════════════════════════════════════
	_assert(new_shisui_char.max_hp == 6, "1a: 新止水HP=6（实际=%d）" % new_shisui_char.max_hp)
	_assert(new_shisui_char.grade == "A", "1b: 新止水等级A（实际=%s）" % new_shisui_char.grade)
	_assert("刺客" in new_shisui_char.tags and "法师" not in new_shisui_char.tags, "1c: 标签=刺客（实际=%s）" % str(new_shisui_char.tags))
	_assert(new_shisui_char.portrait != null, "1d: 新止水立绘已加载")

	var ns_skills: Array[String] = []
	for s in new_shisui_char.skills:
		ns_skills.append(s.skill_name)
	_assert("普攻" in ns_skills and "幻影瞬身" in ns_skills and "日影舞" in ns_skills and "别天神" in ns_skills, "1e: 技能列表=普攻/幻影瞬身/日影舞/别天神（实际=%s）" % str(ns_skills))
	_assert("须佐能乎·斩" not in ns_skills and "宇智波流·日晕舞" not in ns_skills, "1f: 新止水不含旧止水技能")

	# ═════════ 测试2：技能属性 ══════════════════════════════════
	var basic: SkillData = null
	var phantom: SkillData = null
	var hiroari: SkillData = null
	var backtrack: SkillData = null
	for s in new_shisui_char.skills:
		match s.skill_name:
			"普攻": basic = s
			"幻影瞬身": phantom = s
			"日影舞": hiroari = s
			"别天神": backtrack = s

	_assert(basic != null and basic.energy_cost == 1 and basic.max_range == 2, "2a: 普攻耗气1/范围2（实际=%s/%s）" % [str(basic.energy_cost if basic else -1), str(basic.max_range if basic else -1)])
	_assert(phantom != null and phantom.is_passive and phantom.energy_cost == 0, "2b: 幻影瞬身为被动/0耗（实际=%s/%s）" % [str(phantom.is_passive if phantom else false), str(phantom.energy_cost if phantom else -1)])
	_assert(phantom != null and phantom.effects[0].effect_type == SkillEffect.EffectType.PHANTOM_BODY, "2c: 幻影瞬身效果=PHANTOM_BODY(%d)（实际=%d）" % [SkillEffect.EffectType.PHANTOM_BODY, phantom.effects[0].effect_type if phantom else -1])
	_assert(hiroari != null and hiroari.energy_cost == 3 and hiroari.max_range == 999, "2d: 日影舞耗3气/全屏（实际=%s/%s）" % [str(hiroari.energy_cost if hiroari else -1), str(hiroari.max_range if hiroari else -1)])
	_assert(hiroari != null and hiroari.effects[0].effect_type == SkillEffect.EffectType.HIROARI and hiroari.effects[0].value == 2, "2e: 日影舞效果=HIROARI(%d)/2伤（实际=%d/%s）" % [SkillEffect.EffectType.HIROARI, hiroari.effects[0].effect_type if hiroari else -1, str(hiroari.effects[0].value if hiroari else -1)])
	_assert(backtrack != null and backtrack.is_passive and backtrack.energy_cost == 1, "2f: 别天神（回溯）为被动/1耗（实际=%s/%s）" % [str(backtrack.is_passive if backtrack else false), str(backtrack.energy_cost if backtrack else -1)])
	_assert(backtrack != null and backtrack.effects[0].effect_type == SkillEffect.EffectType.BACKTRACK, "2g: 回溯效果=BACKTRACK(%d)（实际=%d）" % [SkillEffect.EffectType.BACKTRACK, backtrack.effects[0].effect_type if backtrack else -1])

	# ═════════ 测试 3：幻影递增（普攻命中+1） ══════════════════
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	var sas: PlayerState = gm.get_player(2)
	_assert(ns != null and ns.hp == 6, "3a: 初始HP=6（实际=%d）" % ns.hp)
	_assert(ns.phantom_count == 0, "3b: 初始幻影0（实际=%d）" % ns.phantom_count)

	var basic_idx := _find_skill_index(ns, "普攻")
	_assert(basic_idx >= 0, "3c: 普攻索引找到（=%d）" % basic_idx)
	var ph_sigs: Array = []
	gm.phantom_changed.connect(func(pid: int, cnt: int): ph_sigs.append([pid, cnt]))
	# 第1回合：新止水胜 → 停ACTION_INPUT → 设1气 → 普攻鸣人（无幻影→基础1伤）
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "3d: 新止水胜出（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "3e: 进入行动阶段（实际=%d）" % gm.get("_current_phase"))
	ns.energy = 1
	var nar_hp3: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(nar.hp == nar_hp3 - 1.0, "3f: 普攻1伤（鸣人HP %.1f→%.1f）" % [nar_hp3, nar.hp])
	_assert(ns.phantom_count == 1, "3g: 命中后获得1幻影（实际=%d）" % ns.phantom_count)
	_assert(ph_sigs.size() >= 1 and ph_sigs[0][0] == 0 and ph_sigs[0][1] == 1, "3h: phantom_changed信号已发射（实际=%s）" % str(ph_sigs))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "3i: 回合结束回到出拳（实际=%d）" % gm.get("_current_phase"))

	# ═════════ 测试 4：幻影增伤（1幻影 +0.5） ═════════════════
	# 第2回合：新止水再胜 → 上回合是自己 → 不可回溯 → 直接行动
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "4a: 连续胜出（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "4b: 连续胜利直接行动（实际=%d）" % gm.get("_current_phase"))
	ns.energy = 1
	var nar_hp4: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(nar.hp == nar_hp4 - 1.5, "4c: 1幻影普攻1.5伤（%.1f→%.1f，实际差=%.1f）" % [nar_hp4, nar.hp, nar_hp4 - nar.hp])
	_assert(ns.phantom_count == 2, "4d: 再次命中幻影=2（实际=%d）" % ns.phantom_count)

	# ═════════ 测试 5：幻影闪避（人类弹窗决策） ═══════════════
	# 鸣人回合 → 普攻新止水 → 新止水（人类）有2气2幻影 → 弹窗决策
	ns.energy = 2
	ns.phantom_count = 2
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "5a: 鸣人胜出（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "5b: 鸣人行动阶段（实际=%d）" % gm.get("_current_phase"))
	var dodge_req: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req.append([pid, aid]))
	var dodge_trig: Array = []
	gm.phantom_dodge_triggered.connect(func(pid: int, aid: int): dodge_trig.append([pid, aid]))
	var ns_hp5: float = ns.hp
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	_assert(dodge_req.size() == 1, "5c: 闪避弹窗信号已发射（实际=%d）" % dodge_req.size())
	_assert(dodge_req.size() > 0 and dodge_req[0][0] == 0 and dodge_req[0][1] == 1, "5d: 信号=新止水闪避鸣人（实际=%s）" % str(dodge_req))
	_assert(ns.hp == ns_hp5, "5e: 决策前未结算（HP不变=%d）" % ns.hp)
	# 人类选择闪避
	gm.submit_phantom_dodge(0, true)
	_assert(ns.hp == ns_hp5, "5f: 闪避成功HP不变（%.1f）" % ns.hp)
	_assert(ns.energy == 1, "5g: 闪避消耗1气（2→1，实际=%d）" % ns.energy)
	_assert(ns.phantom_count == 1, "5h: 闪避消耗1幻影（2→1，实际=%d）" % ns.phantom_count)
	_assert(dodge_trig.size() == 1, "5i: 闪避触发信号已发射（实际=%d）" % dodge_trig.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "5j: 回合正常结束回到出拳（实际=%d）" % gm.get("_current_phase"))

	# ═════════ 测试 6：幻影闪避（拒绝闪避 → 承受伤害） ═════════
	ns.energy = 1
	ns.phantom_count = 1
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "6a: 鸣人胜出（实际=%d）" % gm.get("_sole_winner_id"))
	var ns_hp6: float = ns.hp
	var dodge_req6: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req6.append([pid, aid]))
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	_assert(dodge_req6.size() == 1, "6b: 再次请求闪避决策（实际=%d）" % dodge_req6.size())
	gm.submit_phantom_dodge(0, false)  # 拒绝闪避
	_assert(ns.hp == ns_hp6 - 1.0, "6c: 拒绝闪避承受1伤（%.1f→%.1f）" % [ns_hp6, ns.hp])
	_assert(ns.energy == 1, "6d: 拒绝闪避不消耗（仍1气，实际=%d）" % ns.energy)
	_assert(ns.phantom_count == 1, "6e: 拒绝闪避不消耗幻影（仍1，实际=%d）" % ns.phantom_count)

	# ═════════ 测试 7：日影舞（人类4段独立目标） ═══════════════
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	ns = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	ns.energy = 3
	ns.phantom_count = 3
	var hiroari_idx := _find_skill_index(ns, "日影舞")
	_assert(hiroari_idx >= 0, "7a: 日影舞索引找到（=%d）" % hiroari_idx)
	var hiro_req: Array = []
	gm.hiroari_targets_required.connect(func(pid: int, tids: Array): hiro_req.append([pid, tids]))
	var hiro_used: Array = []
	gm.hiroari_used.connect(func(pid: int, tids: Array): hiro_used.append([pid, tids]))
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "7b: 进入行动阶段（实际=%d）" % gm.get("_current_phase"))
	var nar_hp7: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, hiroari_idx, 1)
	_assert(hiro_req.size() == 1, "7c: 日影舞目标请求信号（实际=%d）" % hiro_req.size())
	_assert(hiro_req.size() > 0 and hiro_req[0][0] == 0 and hiro_req[0][1].size() == 2, "7d: 可指定2个目标（实际=%s）" % str(hiro_req))
	# 人类提交4段全打鸣人（可重复）
	gm.submit_hiroari_targets(0, [1, 1, 1, 1])
	# 鸣人HP=6，8伤溢出 → HP下限0
	_assert(nar.hp == 0.0, "7e: 4段×2伤=8（鸣人%.1f→0.0，实际=%.1f）" % [nar_hp7, nar.hp])
	_assert(ns.energy == 0, "7f: 日影舞消耗3气（3→0，实际=%d）" % ns.energy)
	_assert(ns.phantom_count == 0, "7g: 释放消耗全部3幻影（实际=%d）" % ns.phantom_count)
	_assert(hiro_used.size() == 1, "7h: hiroari_used信号已发射（实际=%d）" % hiro_used.size())
	# 全人类局：有人死亡触发 _is_human_dead()（非网络局）→ GAME_OVER
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GAME_OVER, "7i: 人类死亡→GAME_OVER（实际=%d）" % gm.get("_current_phase"))

	# ═════════ 测试 8：日影舞死亡顺延 ═════════════════════════
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	ns = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	ns.energy = 3
	ns.phantom_count = 3
	nar.hp = 2.0  # 鸣人残血（1段就死）
	var sas_hp8: float = sas.hp
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ns, "日影舞"), 1)
	# 人类全选鸣人 → 第1段击杀，第2~4段顺延佐助
	gm.submit_hiroari_targets(0, [1, 1, 1, 1])
	_assert(nar.hp == 0.0, "8a: 鸣人被打死（HP=%.1f）" % nar.hp)
	# 佐助HP=6，3段×2伤=6 → HP下限0
	_assert(sas.hp == 0.0, "8b: 剩余3段顺延到佐助（%.1f→0.0，实际=%.1f）" % [sas_hp8, sas.hp])
	_assert(ns.phantom_count == 0, "8c: 幻影已清空（实际=%d）" % ns.phantom_count)

	# ═════════ 测试 9：别天神回溯（完整回合链） ════════════════
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	ns = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	# 记录第1回合开始前初始HP（回溯应恢复到该值）
	var sas_hp_initial: float = sas.hp
	# 第1回合：鸣人胜 → 普攻佐助（佐助 8→7）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "9a: 第1回合鸣人胜（实际=%d）" % gm.get("_sole_winner_id"))
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 2)
	# 佐助HP=6，鸣人普攻1伤→5
	_assert(sas.hp == 5.0, "9b: 鸣人普攻佐助1伤（6→5，实际=%.1f）" % sas.hp)
	var sas_hp_after_r1: float = sas.hp
	# 第2回合：新止水胜 → 快照已滚动（prev=第1回合开始前状态）→ 准备阶段触发回溯
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1  # 回溯消耗1气
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "9c: 第2回合新止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 1, "9d: 上回合主=鸣人（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(not gm.get("_last_round_pre_snapshot").is_empty(), "9e: 当前回合快照已拍摄")
	_assert(not gm.get("_prev_round_pre_snapshot").is_empty(), "9e2: 上回合快照已滚动")
	_assert(bt_req.size() == 1, "9f: 回溯弹窗信号已发射（实际=%d）" % bt_req.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "9g: 处于准备阶段（实际=%d）" % gm.get("_current_phase"))
	var snap: Dictionary = gm.get("_prev_round_pre_snapshot")
	var snap_sas_hp: float = snap["states"][2]["hp"]
	_assert(snap_sas_hp == sas_hp_initial, "9h: 上回合快照佐助HP=第1回合开始前值（快照=%.1f 初始=%.1f）" % [snap_sas_hp, sas_hp_initial])
	_assert(snap_sas_hp != sas_hp_after_r1, "9h2: 上回合快照非第1回合后值（快照=%.1f 回合后=%.1f）" % [snap_sas_hp, sas_hp_after_r1])
	# 制造差异：佐助 HP 改成 1，回溯应恢复
	sas.hp = 1.0
	var bt_perf: Array = []
	gm.backtrack_performed.connect(func(pid: int, r: int): bt_perf.append([pid, r]))
	gm.submit_backtrack_decision(0, true)
	_assert(sas.hp == snap_sas_hp, "9i: 回溯后佐助恢复上回合开始前HP（%.1f，实际=%.1f）" % [snap_sas_hp, sas.hp])
	_assert(ns.energy == 0, "9j: 回溯消耗1气（1→0，实际=%d）" % ns.energy)
	_assert(gm.get("_prev_round_pre_snapshot").is_empty(), "9k: 上回合快照已清空")
	_assert(bt_perf.size() == 1, "9l: backtrack_performed信号已发射（实际=%d）" % bt_perf.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "9m: 回溯后进入行动阶段（实际=%d）" % gm.get("_current_phase"))

	# ═════════ 测试 10：回溯不可用（上回合是自己） ═════════
	# 第3回合：新止水再胜 → 上回合主=自己 → 不可回溯 → 直接行动
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req10: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req10.append(pid))
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "10a: 第3回合新止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 0, "10b: 上回合主=新止水（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(bt_req10.is_empty(), "10c: 自己连庄不弹回溯（实际=%d）" % bt_req10.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "10d: 直接进入行动（实际=%d）" % gm.get("_current_phase"))

	# ═════════ 测试 11：回溯恢复存活玩家入座 ═════════════════
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	ns = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	# 第1回合：鸣人胜 → 普攻佐助
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 2)
	# 第2回合：新止水胜 → 模拟佐助被移出座位表 → 回溯应恢复
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	ns.energy = 1
	gm.call("_resolve_round")
	var dist: DistanceSystem = gm.get("_distance_system")
	dist._seat_order.erase(2)
	_assert(not gm.call("_distance_system_contains", 2), "11a: 佐助已被移出座位表")
	gm.submit_backtrack_decision(0, true)
	_assert(gm.call("_distance_system_contains", 2), "11b: 回溯后佐助重新入座")

	# ═════════ 测试 12：旧止水改名（别天神·夺舍） ═════════
	var old_skills: Array[String] = []
	for s in old_shisui_char.skills:
		old_skills.append(s.skill_name)
	_assert("须佐能乎·斩" in old_skills and "别天神·夺舍" in old_skills and "别天神" not in old_skills, "12a: 旧止水技能=斩/夺舍且不含'别天神'（实际=%s）" % str(old_skills))
	_assert("别天神·夺舍" not in ns_skills, "12b: 新止水无夺舍技能")

	# ═════════ 测试 13：AI 决策（新止水专用策略） ═════════
	var ai := AIController.new()
	var ns_ai := PlayerState.new(0, "新止水AI", new_shisui_char, false)
	ns_ai.hp = 6.0
	ns_ai.energy = 5
	ns_ai.phantom_count = 3
	var nar_ai := PlayerState.new(1, "鸣人", naruto_char, false)
	var sas_ai := PlayerState.new(2, "佐助", sasuke_char, false)
	var dist_ai := DistanceSystem.new()
	dist_ai.setup([0, 1, 2])
	dist_ai.modify_distance(0, 1, 0)
	var dec := ai.decide_action(ns_ai, [ns_ai, nar_ai, sas_ai], dist_ai)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "13a: 3幻影+5气AI用技能（实际=%d）" % dec["action"])
	if dec["action"] == PlayerState.ActionType.USE_SKILL and dec["skill_index"] >= 0:
		var used_name: String = ns_ai.get_all_skills()[dec["skill_index"]].skill_name
		_assert(used_name == "日影舞", "13b: 3幻影3气以上优先日影舞（实际=%s）" % used_name)

	var ns_ai2 := PlayerState.new(0, "新止水AI2", new_shisui_char, false)
	ns_ai2.hp = 6.0
	ns_ai2.energy = 2
	ns_ai2.phantom_count = 0
	var dec2 := ai.decide_action(ns_ai2, [ns_ai2, nar_ai, sas_ai], dist_ai)
	_assert(dec2["action"] == PlayerState.ActionType.USE_SKILL, "13c: 无幻影有气时普攻（实际=%d）" % dec2["action"])
	if dec2["action"] == PlayerState.ActionType.USE_SKILL and dec2["skill_index"] >= 0:
		var s2_name: String = ns_ai2.get_all_skills()[dec2["skill_index"]].skill_name
		_assert(s2_name == "普攻", "13d: 普攻攒幻影（实际=%s）" % s2_name)

	print("=== 新止水测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 在玩家全部技能（含解锁）中查找技能索引
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