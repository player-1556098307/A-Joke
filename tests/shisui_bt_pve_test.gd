## 新止水（宇智波止水·天劫）PvE 多场景测试
## 模式：人类玩家 vs AI 对手（PvE 单机对战）
## 覆盖：回溯撤销AI操作、回溯跳过、AI止水自动回溯、
##      幻影瞬身（普攻获影/增伤）、幻影闪避（人类决策）、日影舞
## 说明：手势由测试手动指定（可控胜负），AI 行动走真实 decide_action
extends Node

var _pass_count: int = 0
var _fail_count: int = 0
## 回溯瞬间能量捕获（GDScript 闭包无法写回局部变量，用成员变量）
var _bt_energy_capture: int = -1

func _ready() -> void:
	print("=== 新止水 PvE 多场景测试 ===")
	await get_tree().process_frame

	var shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if shisui_char == null or naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_bt_revert_ai_action(shisui_char, naruto_char)
	await _test_bt_skip(shisui_char, naruto_char)
	await _test_bt_ai_shisui_auto(shisui_char, naruto_char)
	await _test_phantom_and_hiroari(shisui_char, naruto_char)
	await _test_phantom_dodge_vs_ai(shisui_char, naruto_char)

	print("=== 新止水 PvE 测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ PvE场景1：回溯撤销AI操作 ═════════════════════════
## R1 人类赢聚气 → R2 AI赢聚气 → R3 人类赢回溯 → 撤销AI的聚气
func _test_bt_revert_ai_action(shisui_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- PvE场景1：回溯撤销AI操作 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人AI", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var ai: PlayerState = gm.get_player(1)

	# R1：人类 ROCK vs AI SCISSORS → 人类赢 → 聚气
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "P1a: R1止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "P1b: 行动阶段（实际=%d）" % gm.get("_current_phase"))
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(ns.energy == 1, "P1c: R1聚气 e=1（实际=%d）" % ns.energy)

	# R2：人类 SCISSORS vs AI ROCK → AI赢 → AI真实行动（0气→聚气）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "P1d: R2 AI胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(ai.energy == 1, "P1e: AI聚气 e=1（实际=%d）" % ai.energy)
	_assert(ns.energy == 1, "P1f: 人类e保持1（实际=%d）" % ns.energy)

	# R3：人类 ROCK vs AI SCISSORS → 人类赢 → 回溯弹窗 → 回溯
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "P1g: R3止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 1, "P1h: 上回合主=AI（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(bt_req.size() == 1, "P1i: 回溯弹窗触发（实际=%d）" % bt_req.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION, "P1j: 准备阶段（实际=%d）" % gm.get("_current_phase"))
	var snap: Dictionary = gm.get("_prev_round_pre_snapshot")
	_assert(int(snap["states"][1]["energy"]) == 0, "P1k: 快照AI能量=0（实际=%d）" % int(snap["states"][1]["energy"]))
	gm.submit_backtrack_decision(0, true)
	_assert(ai.energy == 0, "P1l: 回溯后AI能量撤销回0（实际=%d）" % ai.energy)
	_assert(ns.energy == 0, "P1m: 回溯消耗1气 e=0（快照1-1，实际=%d）" % ns.energy)
	_assert(gm.get("_prev_round_pre_snapshot").is_empty(), "P1n: 快照已清空")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "P1o: 回溯后进入行动阶段（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvE场景2：回溯跳过（不撤销，不重复弹窗） ═════════════════
func _test_bt_skip(shisui_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- PvE场景2：回溯跳过 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人AI", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var ai: PlayerState = gm.get_player(1)

	# R1 人类赢聚气 → R2 AI赢聚气 → R3 人类赢弹窗 → 跳过
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(ai.energy == 1, "P2a: R2 AI聚气 e=1（实际=%d）" % ai.energy)
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "P2b: 回溯弹窗触发（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, false)
	_assert(ai.energy == 1, "P2c: 跳过不撤销AI聚气（实际=%d）" % ai.energy)
	_assert(ns.energy == 1, "P2d: 跳过不消耗气（实际=%d）" % ns.energy)
	_assert(gm.get("_prev_round_pre_snapshot").is_empty(), "P2e: 快照已清空（不循环弹窗）")
	_assert(bt_req.size() == 1, "P2f: 不重复弹窗（实际=%d）" % bt_req.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "P2g: 进入行动阶段（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvE场景3：AI止水自动回溯（不弹窗） ═════════════════════
## R1 人类赢聚气 → R2 AI赢聚气 → R3 人类赢普攻AI → R4 AI赢自动回溯撤销普攻
func _test_bt_ai_shisui_auto(shisui_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- PvE场景3：AI止水自动回溯 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水AI", "character": shisui_char, "is_human": false},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ai: PlayerState = gm.get_player(0)
	var hum: PlayerState = gm.get_player(1)
	_assert(_is_shisui(ai), "P3a: AI为止水（实际=%s）" % ai.character.character_name)

	# R1：人类 ROCK vs AI SCISSORS → 人类赢 → 聚气
	hum.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "P3b: R1人类胜（实际=%d）" % gm.get("_sole_winner_id"))
	gm.submit_action(1, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(hum.energy == 1, "P3c: 人类聚气 e=1（实际=%d）" % hum.energy)

	# R2：AI ROCK vs 人类 SCISSORS → AI赢 → AI聚气 e=1
	hum.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "P3d: R2 AI胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(ai.energy == 1, "P3e: AI聚气 e=1（实际=%d）" % ai.energy)

	# R3：人类 ROCK vs AI SCISSORS → 人类赢 → 普攻AI止水（6→5）
	hum.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "P3f: R3人类胜（实际=%d）" % gm.get("_sole_winner_id"))
	hum.energy = 1
	var ai_hp3: float = ai.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(hum, "普攻"), 0)
	_assert(ai.hp == ai_hp3 - 1.0, "P3g: 人类普攻止水1伤（%.1f→%.1f）" % [ai_hp3, ai.hp])
	_assert(hum.energy == 0, "P3h: 人类耗1气（实际=%d）" % hum.energy)

	# R4：AI ROCK vs 人类 SCISSORS → AI止水赢 → 自动回溯（无弹窗）
	hum.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	# 回溯信号必须在 _resolve_round 前连接（回溯在调用内同步完成）
	_bt_energy_capture = -1
	var bt_perf := func(pid: int, r: int): _bt_energy_capture = ai.energy
	gm.backtrack_performed.connect(bt_perf)
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "P3i: R4 AI胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 1, "P3j: 上回合主=人类（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(ai.energy >= 1, "P3k: AI止水有气回溯（实际=%d）" % ai.energy)
	_assert(bt_req.is_empty(), "P3l: AI自动回溯不弹窗（实际=%d）" % bt_req.size())
	_assert(ai.hp == 6.0, "P3m: 回溯撤销普攻 AI回6（实际=%.1f）" % ai.hp)
	_assert(hum.energy == 1, "P3n: 回溯撤销人类耗气 e回1（实际=%d）" % hum.energy)
	_assert(gm.get("_prev_round_pre_snapshot").is_empty(), "P3o: 快照已清空")
	_assert(_bt_energy_capture == 0, "P3p: 回溯瞬间AI已扣1气（快照1-1=0，实际=%d）" % _bt_energy_capture)

## ═════════ PvE场景4：幻影获取+增伤+日影舞（连庄） ═════════════════
func _test_phantom_and_hiroari(shisui_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- PvE场景4：幻影获取+增伤+日影舞 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人AI", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var ai: PlayerState = gm.get_player(1)

	var basic_idx := _find_skill_index(ns, "普攻")
	# R1：人类赢 → 普攻（1伤）→ 幻影1
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ns.energy = 1
	var ai_hp1: float = ai.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(ai.hp == ai_hp1 - 1.0, "P4a: R1普攻1伤（%.1f→%.1f）" % [ai_hp1, ai.hp])
	_assert(ns.phantom_count == 1, "P4b: 幻影1（实际=%d）" % ns.phantom_count)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "P4c: 回到出拳")

	# R2：人类赢 → 普攻（1幻影+0.5）→ 幻影2
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ns.energy = 1
	var ai_hp2: float = ai.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(ai.hp == ai_hp2 - 1.5, "P4d: R2普攻1.5伤（%.1f→%.1f，实际差=%.1f）" % [ai_hp2, ai.hp, ai_hp2 - ai.hp])
	_assert(ns.phantom_count == 2, "P4e: 幻影2（实际=%d）" % ns.phantom_count)

	# R3：人类赢 → 普攻（2幻影+1.0）→ 幻影3
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ns.energy = 1
	var ai_hp3: float = ai.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, basic_idx, 1)
	_assert(ai.hp == ai_hp3 - 2.0, "P4f: R3普攻2伤（%.1f→%.1f，实际差=%.1f）" % [ai_hp3, ai.hp, ai_hp3 - ai.hp])
	_assert(ns.phantom_count == 3, "P4g: 幻影3（实际=%d）" % ns.phantom_count)

	# R4：人类赢（连庄上回合自己→不弹回溯）→ 日影舞 → AI死亡
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	gm.call("_resolve_round")
	_assert(bt_req.is_empty(), "P4h: 连庄不弹回溯（实际=%d）" % bt_req.size())
	ns.energy = 3
	var hiro_req: Array = []
	gm.hiroari_targets_required.connect(func(pid: int, tids: Array): hiro_req.append([pid, tids]))
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ns, "日影舞"), 1)
	_assert(hiro_req.size() == 1, "P4i: 日影舞目标弹窗（实际=%d）" % hiro_req.size())
	gm.submit_hiroari_targets(0, [1, 1, 1, 1])
	_assert(ai.hp == 0.0, "P4j: 4段×2伤 AI死亡（实际=%.1f）" % ai.hp)
	_assert(ns.phantom_count == 0, "P4k: 幻影清空（实际=%d）" % ns.phantom_count)
	_assert(ns.energy == 0, "P4l: 日影舞耗3气（实际=%d）" % ns.energy)

## ═════════ PvE场景5：幻影闪避 vs AI（弹窗决策） ═════════════════════
func _test_phantom_dodge_vs_ai(shisui_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- PvE场景5：幻影闪避 vs AI ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人AI", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var ns: PlayerState = gm.get_player(0)
	var ai: PlayerState = gm.get_player(1)

	# R1：人类赢 → 普攻AI（幻影1，AI 6→5）
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "P5a: R1人类胜（实际=%d）" % gm.get("_sole_winner_id"))
	ns.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ns, "普攻"), 1)
	_assert(ns.phantom_count == 1, "P5a2: 幻影1（实际=%d）" % ns.phantom_count)

	# R2：人类赢 → 聚气 e=1（幻影保持1）
	ns.current_gesture = PlayerState.Gesture.ROCK
	ai.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(ns.energy == 1 and ns.phantom_count == 1, "P5b: 聚气后 e=1幻影=1（实际=%d/%d）" % [ns.energy, ns.phantom_count])

	# R3：AI赢（0气自动聚气 e=1）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "P5c: R3 AI胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(ai.energy == 1, "P5c2: AI自动聚气 e=1（实际=%d）" % ai.energy)

	# R4：AI赢（1气）→ 临时托管AI手动普攻人类（AI自动决策会随机选影分身）→ 弹窗闪避
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	ai.is_human = true  # 临时托管，强制走手动行动提交
	var dodge_req: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req.append([pid, aid]))
	var dodge_trig: Array = []
	gm.phantom_dodge_triggered.connect(func(pid: int, aid: int): dodge_trig.append([pid, aid]))
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "P5c3: R4停在行动阶段等待托管（实际=%d）" % gm.get("_current_phase"))
	var ns_hp4: float = ns.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(ai, "普攻"), 0)
	_assert(dodge_req.size() == 1, "P5d: 闪避弹窗触发（实际=%d）" % dodge_req.size())
	_assert(dodge_req.size() > 0 and dodge_req[0][0] == 0 and dodge_req[0][1] == 1, "P5e: 弹窗=止水闪避AI（实际=%s）" % str(dodge_req))
	gm.submit_phantom_dodge(0, true)
	_assert(ns.hp == ns_hp4, "P5f: 闪避无伤（%.1f）" % ns.hp)
	_assert(ns.energy == 0, "P5g: 闪避耗1气（实际=%d）" % ns.energy)
	_assert(ns.phantom_count == 0, "P5h: 闪避耗1幻影（实际=%d）" % ns.phantom_count)
	_assert(dodge_trig.size() == 1, "P5i: 闪避触发信号（实际=%d）" % dodge_trig.size())
	ai.is_human = false
	_assert(ai.energy == 0, "P5i2: AI普攻耗1气（实际=%d）" % ai.energy)

	# R5：AI赢（0气自动聚气 e=1）→ 手动给人类1气1幻影
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(ai.energy == 1, "P5j: AI聚气 e=1（实际=%d）" % ai.energy)
	ns.energy = 1
	ns.phantom_count = 1

	# R6：AI赢（1气）→ 临时托管手动普攻 → 弹窗 → 拒绝 → 受伤不消耗
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	ai.current_gesture = PlayerState.Gesture.ROCK
	ai.is_human = true
	var dodge_req6: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req6.append([pid, aid]))
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "P5j2: R6停在行动阶段（实际=%d）" % gm.get("_current_phase"))
	var ns_hp6: float = ns.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(ai, "普攻"), 0)
	_assert(dodge_req6.size() == 1, "P5k: 再次弹窗（实际=%d）" % dodge_req6.size())
	gm.submit_phantom_dodge(0, false)
	_assert(ns.hp == ns_hp6 - 1.0, "P5l: 拒绝闪避承受1伤（%.1f→%.1f）" % [ns_hp6, ns.hp])
	_assert(ns.energy == 1, "P5m: 拒绝不耗气（实际=%d）" % ns.energy)
	_assert(ns.phantom_count == 1, "P5n: 拒绝不耗幻影（实际=%d）" % ns.phantom_count)
	ai.is_human = false

func _is_shisui(player: PlayerState) -> bool:
	for s in player.character.skills:
		if s.skill_name == "幻影瞬身":
			return true
	return false

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
