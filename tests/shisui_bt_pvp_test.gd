## 新止水（宇智波止水·天劫）PvP 多场景测试
## 模式：全人类玩家（模拟 PvP 对战），手动推进回合
## 覆盖：回溯撤销伤害/聚气/麻痹/延迟伤害/护盾/距离偏移、回溯可用性边界、
##      回溯后连庄不可回溯、日影舞多目标、幻影闪避三态
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 新止水 PvP 多场景测试 ===")
	await get_tree().process_frame

	var shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if shisui_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_bt_revert_damage_energy(shisui_char, naruto_char, sasuke_char)
	await _test_bt_revert_charge(shisui_char, naruto_char, sasuke_char)
	await _test_bt_revert_paralyze(shisui_char, naruto_char, sasuke_char)
	await _test_bt_revert_delayed_damage(shisui_char, naruto_char, sasuke_char)
	await _test_bt_revert_shield_distance(shisui_char, naruto_char, sasuke_char)
	await _test_bt_unavailable(shisui_char, naruto_char, sasuke_char)
	await _test_bt_no_double(shisui_char, naruto_char, sasuke_char)
	await _test_hiroari_multi_target(shisui_char, naruto_char, sasuke_char)
	await _test_phantom_dodge_three_states(shisui_char, naruto_char, sasuke_char)

	print("=== 新止水 PvP 测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 通用：搭建3人全人类局（止水0 鸣人1 佐助2）
func _setup3(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData):
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	return [gm, gm.get_player(0), gm.get_player(1), gm.get_player(2)]

## ═════════ PvP场景A：回溯撤销普攻伤害+气 ═════════════════════
func _test_bt_revert_damage_energy(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景A：回溯撤销普攻伤害+气 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# R1：鸣人胜 → 普攻佐助（佐助6→5，鸣人1→0）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "A1: R1鸣人胜（实际=%d）" % gm.get("_sole_winner_id"))
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 2)
	_assert(sas.hp == 5.0, "A2: 佐助被打1伤（6→5，实际=%.1f）" % sas.hp)
	_assert(nar.energy == 0, "A3: 鸣人耗1气（实际=%d）" % nar.energy)

	# R2：止水胜 → 回溯弹窗 → 回溯 → 佐助回6、鸣人回快照气
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "A4: R2止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 1, "A5: 上回合主=鸣人（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(bt_req.size() == 1, "A6: 回溯弹窗（实际=%d）" % bt_req.size())
	var snap: Dictionary = gm.get("_prev_round_pre_snapshot")
	_assert(float(snap["states"][2]["hp"]) == 6.0, "A7: 快照佐助HP=6（实际=%.1f）" % float(snap["states"][2]["hp"]))
	_assert(int(snap["states"][1]["energy"]) == 0, "A8: 快照鸣人气=0（实际=%d）" % int(snap["states"][1]["energy"]))
	gm.submit_backtrack_decision(0, true)
	_assert(sas.hp == 6.0, "A9: 回溯后佐助回6（实际=%.1f）" % sas.hp)
	_assert(nar.energy == 0, "A10: 回溯后鸣人回快照气0（实际=%d）" % nar.energy)
	_assert(ns.energy == 0, "A11: 回溯扣1气（快照0-1，实际=%d）" % ns.energy)
	_assert(gm.get("_prev_round_pre_snapshot").is_empty(), "A12: 快照已清空")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "A13: 行动阶段（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvP场景B：回溯撤销聚气 ═════════════════════════
func _test_bt_revert_charge(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景B：回溯撤销聚气 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# R1：佐助胜 → 聚气（佐助0→1）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 2, "B1: R1佐助胜（实际=%d）" % gm.get("_sole_winner_id"))
	gm.submit_action(2, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(sas.energy == 1, "B2: 佐助聚气 e=1（实际=%d）" % sas.energy)

	# R2：止水胜 → 回溯 → 佐助回0气
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "B3: 回溯弹窗（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, true)
	_assert(sas.energy == 0, "B4: 回溯撤销佐助聚气（e=0，实际=%d）" % sas.energy)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "B5: 行动阶段（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvP场景C：回溯撤销麻痹 ═════════════════════════
func _test_bt_revert_paralyze(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景C：回溯撤销麻痹 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# R1：佐助胜 → 千鸟打鸣人（2伤+麻痹1）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	sas.energy = 2
	gm.submit_action(2, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "千鸟"), 1)
	_assert(nar.hp == 4.0, "C1: 千鸟2伤（6→4，实际=%.1f）" % nar.hp)
	_assert(nar.paralyze_turns == 1, "C2: 麻痹1回合（实际=%d）" % nar.paralyze_turns)

	# R2：止水胜 → 回溯 → 鸣人回6、麻痹清除
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "C3: 回溯弹窗（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, true)
	_assert(nar.hp == 6.0, "C4: 回溯后鸣人回6（实际=%.1f）" % nar.hp)
	_assert(nar.paralyze_turns == 0, "C5: 回溯撤销麻痹（实际=%d）" % nar.paralyze_turns)
	_assert(sas.energy == 0, "C6: 佐助回快照气0（实际=%d）" % sas.energy)

## ═════════ PvP场景D：回溯撤销延迟伤害（潜在BUG验证点） ═════════════
func _test_bt_revert_delayed_damage(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景D：回溯撤销延迟伤害 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# R1：佐助胜 → 豪火球打鸣人（2伤 + 延迟1伤 duration2）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	sas.energy = 3
	gm.submit_action(2, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "豪火球之术"), 1)
	_assert(nar.hp == 4.0, "D1: 豪火球2伤（6→4，实际=%.1f）" % nar.hp)
	_assert(nar.delayed_damages.size() == 1, "D2: 延迟伤害已挂（%d条）" % nar.delayed_damages.size())

	# R2：止水胜 → 回溯 → 鸣人回6，且延迟伤害应被撤销（"所有操作及其影响"）
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "D3: 回溯弹窗（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, true)
	_assert(nar.hp == 6.0, "D4: 回溯后鸣人回6（实际=%.1f）" % nar.hp)
	_assert(nar.delayed_damages.is_empty(), "D5: 回溯后延迟伤害应清除（实际=%d条）" % nar.delayed_damages.size())

## ═════════ PvP场景E：回溯恢复护盾+距离偏移 ═════════════════════
func _test_bt_revert_shield_distance(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景E：回溯恢复护盾+距离偏移 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]
	var dist: DistanceSystem = gm.get("_distance_system")

	# R1：鸣人胜 → 聚气；同时模拟上回合获得的护盾/距离偏移
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	nar.shield = 2
	dist.modify_distance(1, 2, 1)
	var dist_before: int = dist.get_distance(1, 2)
	_assert(dist_before == 2, "E1: 距离偏移后=2（实际=%d）" % dist_before)
	gm.submit_action(1, PlayerState.ActionType.CHARGE, -1, -1)

	# R2：止水胜 → 回溯 → 护盾清除、距离偏移撤销
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "E2: 回溯弹窗（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, true)
	_assert(nar.shield == 0, "E3: 回溯撤销护盾（实际=%d）" % nar.shield)
	var dist_after: int = dist.get_distance(1, 2)
	_assert(dist_after == 1, "E4: 回溯撤销距离偏移（=1，实际=%d）" % dist_after)

## ═════════ PvP场景F：回溯不可用（上回合自己 / 气不足） ═════════════
func _test_bt_unavailable(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景F：回溯不可用 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# F1：止水连庄（上回合是自己）→ 不弹回溯
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "F1: R1止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(bt_req.is_empty(), "F2: 首回合无回溯机会（实际=%d）" % bt_req.size())

	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "F3: R2止水连庄（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 0, "F4: 上回合=自己（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(bt_req.is_empty(), "F5: 连庄不弹回溯（实际=%d）" % bt_req.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "F6: 直接行动（实际=%d）" % gm.get("_current_phase"))

	# F2：气不足（0气）→ 不弹回溯
	# 重新开局：鸣人R1赢 → R2止水赢（0气）→ 无弹窗
	gm.setup_game({
		"players": [
			{"name": "止水", "character": shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	ns = gm.get_player(0)
	nar = gm.get_player(1)
	sas = gm.get_player(2)
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 2)
	# 止水0气 → 回溯不可用
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req2: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req2.append(pid))
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "F7: R2止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_prev_round_winner_id") == 1, "F8: 上回合=鸣人（实际=%d）" % gm.get("_prev_round_winner_id"))
	_assert(bt_req2.is_empty(), "F9: 0气不弹回溯（实际=%d）" % bt_req2.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "F10: 直接行动（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvP场景G：回溯后连庄不可再次回溯 ═════════════════════
func _test_bt_no_double(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景G：回溯后连庄不可再次回溯 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# R1：鸣人胜 → 普攻佐助
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	nar.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 2)
	var sas_hp1: float = sas.hp
	_assert(sas_hp1 == 5.0, "G1: 佐助5（实际=%.1f）" % sas_hp1)
	# R2：止水胜 → 回溯（佐助回6）
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req.append(pid))
	ns.energy = 1
	gm.call("_resolve_round")
	_assert(bt_req.size() == 1, "G2: R2回溯弹窗（实际=%d）" % bt_req.size())
	gm.submit_backtrack_decision(0, true)
	_assert(sas.hp == 6.0, "G3: 回溯撤销（实际=%.1f）" % sas.hp)
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	# R3：止水连庄 → 不可再次回溯
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	var bt_req3: Array = []
	gm.backtrack_required.connect(func(pid: int): bt_req3.append(pid))
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "G4: R3止水连庄（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(bt_req3.is_empty(), "G5: 回溯后连庄不再弹窗（实际=%d）" % bt_req3.size())
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "G6: 直接行动（实际=%d）" % gm.get("_current_phase"))

## ═════════ PvP场景H：日影舞多目标分配（4段2目标） ═════════════════
func _test_hiroari_multi_target(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景H：日影舞多目标分配 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	ns.energy = 3
	ns.phantom_count = 3
	ns.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "H1: 止水胜（实际=%d）" % gm.get("_sole_winner_id"))
	var hiro_req: Array = []
	gm.hiroari_targets_required.connect(func(pid: int, tids: Array): hiro_req.append([pid, tids]))
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ns, "日影舞"), 1)
	_assert(hiro_req.size() == 1, "H2: 目标弹窗（实际=%d）" % hiro_req.size())
	_assert(hiro_req.size() > 0 and hiro_req[0][1].size() == 2, "H3: 可选2目标（实际=%s）" % str(hiro_req))
	gm.submit_hiroari_targets(0, [1, 1, 2, 2])
	_assert(nar.hp == 2.0, "H4: 鸣人2段×2=4伤（6→2，实际=%.1f）" % nar.hp)
	_assert(sas.hp == 2.0, "H5: 佐助2段×2=4伤（6→2，实际=%.1f）" % sas.hp)
	_assert(ns.phantom_count == 0, "H6: 幻影清空（实际=%d）" % ns.phantom_count)
	_assert(ns.energy == 0, "H7: 耗3气（实际=%d）" % ns.energy)

## ═════════ PvP场景I：幻影闪避三态 ═════════════════════════
func _test_phantom_dodge_three_states(shisui_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- PvP场景I：幻影闪避三态 ---")
	var arr = await _setup3(shisui_char, naruto_char, sasuke_char)
	var gm: GameManager = arr[0]
	var ns: PlayerState = arr[1]
	var nar: PlayerState = arr[2]
	var sas: PlayerState = arr[3]

	# I1：闪避成功（1气1幻影 → 弹窗 → 闪避 → 无伤消耗）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ns.energy = 1
	ns.phantom_count = 1
	nar.energy = 1
	var dodge_req: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req.append([pid, aid]))
	var ns_hp1: float = ns.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	_assert(dodge_req.size() == 1, "I1a: 弹窗（实际=%d）" % dodge_req.size())
	gm.submit_phantom_dodge(0, true)
	_assert(ns.hp == ns_hp1, "I1b: 闪避无伤（实际=%.1f）" % ns.hp)
	_assert(ns.energy == 0 and ns.phantom_count == 0, "I1c: 消耗1气1幻影（%d/%d）" % [ns.energy, ns.phantom_count])

	# I2：无资源（0气0幻影）→ 不弹窗直接受伤
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	nar.energy = 1
	var dodge_req2: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req2.append([pid, aid]))
	var ns_hp2: float = ns.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	_assert(dodge_req2.is_empty(), "I2a: 无资源不弹窗（实际=%d）" % dodge_req2.size())
	_assert(ns.hp == ns_hp2 - 1.0, "I2b: 直接受伤（%.1f→%.1f）" % [ns_hp2, ns.hp])

	# I3：拒绝闪避（1气1幻影 → 弹窗 → 拒绝 → 受伤不消耗）
	ns.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	sas.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ns.energy = 1
	ns.phantom_count = 1
	nar.energy = 1
	var dodge_req3: Array = []
	gm.phantom_dodge_required.connect(func(pid: int, aid: int): dodge_req3.append([pid, aid]))
	var ns_hp3: float = ns.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	_assert(dodge_req3.size() == 1, "I3a: 弹窗（实际=%d）" % dodge_req3.size())
	gm.submit_phantom_dodge(0, false)
	_assert(ns.hp == ns_hp3 - 1.0, "I3b: 拒绝受伤（%.1f→%.1f）" % [ns_hp3, ns.hp])
	_assert(ns.energy == 1 and ns.phantom_count == 1, "I3c: 拒绝不消耗（%d/%d）" % [ns.energy, ns.phantom_count])

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
