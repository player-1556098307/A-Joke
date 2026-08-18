## Bug 修复专项测试
## bug1：侠影柱砸钟不能获得钟（bell_cost>0 技能伤害不计入 dealt_damage_this_round）
## bug2：麻痹状态下新止水不可使用幻影闪避（paralyze_turns>0 时拦截）
## 说明：所有玩家 is_human=true（避免AI自动行动干扰），回合由测试手动推进
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		print("FAIL: " + msg)

func _find_skill_index(p: PlayerState, name: String) -> int:
	var all := p.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == name:
			return i
	return -1

func _ready() -> void:
	print("=== Bug 修复专项测试 ===")
	await get_tree().process_frame

	var hashi_char := load("res://resources/characters/千手柱间.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var new_shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	if hashi_char == null or naruto_char == null or sasuke_char == null or new_shisui_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager

	# 柱间有人类身份且有钟机制，行动结算后进入 END_PHASE 会询问招架决策
	# 测试中自动拒绝，避免流程挂起（钟结算仍在 _process_end_phase 内完成）
	gm.end_phase_bell_decision_required.connect(func(player_id: int, _cnt: int) -> void:
		gm.submit_bell_decision(player_id, false)
	)

	# ═════════ 测试1：砸钟伤害不计入钟获取（bug1） ═════════
	gm.setup_game({
		"players": [
			{"name": "柱间", "character": hashi_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var hashi: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	_assert(hashi.bell_count == 0, "1a: 初始钟=0（实际=%d）" % hashi.bell_count)
	var zhong_idx := _find_skill_index(hashi, "砸钟")
	_assert(zhong_idx >= 0, "1b: 砸钟技能存在（idx=%d）" % zhong_idx)
	# 第1回合：柱间胜 → 普攻鸣人
	hashi.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "1c: 柱间胜出（实际=%d）" % gm.get("_sole_winner_id"))
	hashi.energy = 1
	var nar_hp1: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(hashi, "普攻"), 1)
	_assert(nar.hp == nar_hp1 - 1.0, "1d: 普攻1伤（%.1f→%.1f）" % [nar_hp1, nar.hp])
	gm.call("_process_end_phase")
	_assert(hashi.bell_count == 1, "1e: 普攻命中后获得1钟（实际=%d）" % hashi.bell_count)

	# 第2回合：柱间再胜 → 砸钟
	hashi.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "1f: 柱间再胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(hashi.bell_count == 1, "1g: 砸钟前有1钟（实际=%d）" % hashi.bell_count)
	hashi.energy = 0
	var nar_hp2: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, zhong_idx, 1)
	_assert(nar.hp == nar_hp2 - 1.0, "1h: 砸钟1伤（%.1f→%.1f）" % [nar_hp2, nar.hp])
	_assert(hashi.bell_count == 0, "1i: 砸钟消耗1钟（1→0，实际=%d）" % hashi.bell_count)
	gm.call("_process_end_phase")
	_assert(hashi.bell_count == 0, "1j: 砸钟伤害不计入钟获取（仍=0，实际=%d）" % hashi.bell_count)

	# 第3回合：柱间再胜 → 普攻 → 仍能获得钟（回归：非砸钟技能正常）
	hashi.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "1k: 柱间三胜（实际=%d）" % gm.get("_sole_winner_id"))
	hashi.energy = 1
	var nar_hp3: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(hashi, "普攻"), 1)
	_assert(nar.hp == nar_hp3 - 1.0, "1l: 普攻1伤（%.1f→%.1f）" % [nar_hp3, nar.hp])
	gm.call("_process_end_phase")
	_assert(hashi.bell_count == 1, "1m: 普攻仍可获钟（实际=%d）" % hashi.bell_count)

	# ═════════ 测试2：麻痹状态下幻影闪避不可用（bug2） ═════════
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var nar2: PlayerState = gm.get_player(1)
	ns.phantom_count = 2
	ns.energy = 2
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar2.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "2a: 鸣人胜出（实际=%d）" % gm.get("_sole_winner_id"))
	ns.paralyze_turns = 1
	var dodge_req: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req.append([pid, aid]))
	var ns_hp: float = ns.hp
	nar2.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar2, "普攻"), 0)
	_assert(dodge_req.is_empty(), "2b: 麻痹状态不弹闪避（实际=%d）" % dodge_req.size())
	_assert(ns.hp == ns_hp - 1.0, "2c: 攻击直接命中（%.1f→%.1f）" % [ns_hp, ns.hp])
	_assert(ns.phantom_count == 2 and ns.energy == 2, "2d: 闪避资源未消耗（幻影=%d 气=%d）" % [ns.phantom_count, ns.energy])

	# 麻痹解除后闪避恢复
	ns.paralyze_turns = 0
	ns.hp = 6.0
	ns.phantom_count = 2
	ns.energy = 2
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar2.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "2e: 鸣人再胜（实际=%d）" % gm.get("_sole_winner_id"))
	var dodge_req2: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req2.append([pid, aid]))
	var ns_hp2: float = ns.hp
	nar2.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar2, "普攻"), 0)
	_assert(dodge_req2.size() == 1, "2f: 麻痹解除后闪避弹窗恢复（实际=%d）" % dodge_req2.size())
	_assert(ns.hp == ns_hp2, "2g: 决策前未结算（HP=%.1f）" % ns.hp)
	gm.submit_phantom_dodge(0, true)
	_assert(ns.phantom_count == 1 and ns.energy == 1, "2h: 闪避消耗1幻影1气（幻=%d 气=%d）" % [ns.phantom_count, ns.energy])
	_assert(ns.hp == ns_hp2, "2i: 闪避后未受伤（HP=%.1f）" % ns.hp)

	print("=== Bug修复测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)