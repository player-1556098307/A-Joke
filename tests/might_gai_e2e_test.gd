## 迈特凯端到端全流程测试
## 模拟完整游戏回合循环：出拳→结算→行动（聚气/夜凯）→执行→回合结束
## 验证"聚气×8→八门全开→夜凯解锁→释放夜凯"的完整游戏链路
## 注意：submit_gesture(0, ROCK) 会触发 _flush_pending_ai_gestures 覆盖 AI 手势，
## 因此用手动赋值 current_gesture + 直接调用 _resolve_round() 保持确定性。
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 迈特凯端到端测试（完整回合流程） ===")
	await get_tree().process_frame

	var gai_char := load("res://resources/characters/迈特凯.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if gai_char == null or naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "迈特凯", "character": gai_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var gai: PlayerState = gm.get_player(0)
	var naruto: PlayerState = gm.get_player(1)
	print("[E2E] 初始状态 gai hp=%d naruto hp=%d" % [gai.hp, naruto.hp])

	# 连接关键信号
	var gate_signals: Array = []
	gm.gate_changed.connect(func(pid: int, gc: int): gate_signals.append([pid, gc]))
	var unlocked_signals: Array = []
	gm.skill_unlocked.connect(func(pid: int, sn: String): unlocked_signals.append([pid, sn]))
	var eighth_signals: Array = []
	gm.eighth_gate_opened.connect(func(pid: int): eighth_signals.append(pid))

	# ── 第1-8回合：迈特凯每回合猜拳获胜 → 聚气（开门） ──────────────
	var rounds_to_open := 8
	for i in range(rounds_to_open):
		var round_no := i + 1
		_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "回合%d开始处于GESTURE_INPUT" % round_no)

		# 手动设定手势（石头 vs 剪刀 → 迈特凯必胜），跳过 RESOLVING 的 2 秒动画延时
		gai.current_gesture = PlayerState.Gesture.ROCK
		naruto.current_gesture = PlayerState.Gesture.SCISSORS
		gm.call("_resolve_round")

		# 迈特凯是 human → 结算后停在 ACTION_INPUT 等待行动
		_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "回合%d猜拳后进入ACTION_INPUT（实际=%d）" % [round_no, gm.get("_current_phase")])
		_assert(gm.get("_sole_winner_id") == 0, "回合%d胜者为迈特凯" % round_no)

		# 聚气（submit_action 同步走完 行动→结算→回合结束→回到出拳阶段）
		gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
		_assert(gai.gate_count == i + 1, "回合%d聚气后八门=%d（期望%d）" % [round_no, gai.gate_count, i + 1])
		_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "回合%d后回到GESTURE_INPUT（实际=%d）" % [round_no, gm.get("_current_phase")])

	_assert(gai.gate_count == 8, "八门全开 gate_count=8（实际=%d）" % gai.gate_count)
	_assert(gai.burning, "八门全开后进入燃烧状态")
	_assert(gai.berserker, "八门全开后进入狂战士状态")
	_assert(gai.hp >= 14, "八门全开回10血后HP>=14（实际=%d，燃烧结算后）" % gai.hp)
	_assert("八门遁甲" in gai.lost_skills, "八门遁甲已永久移除")
	_assert(gate_signals.size() >= 8, "gate_changed信号至少8次（实际=%d）" % gate_signals.size())
	_assert(eighth_signals.size() >= 1, "eighth_gate_opened信号已发射")

	# ── 解锁技能检查 ──────────────────────────────────────────────
	var unlocked_names: Array[String] = []
	for s in gai.unlocked_skills:
		unlocked_names.append(s.skill_name)
	_assert("夜凯" in unlocked_names, "夜凯已解锁")
	_assert("夕象" in unlocked_names, "夕象已解锁")
	_assert("双龙戏珠" in unlocked_names, "双龙戏珠已解锁")
	_assert(unlocked_signals.size() >= 3, "skill_unlocked信号≥3次（实际=%d）" % unlocked_signals.size())

	var visible_names: Array[String] = []
	for s in gai.get_all_skills():
		visible_names.append(s.skill_name)
	_assert("夜凯" in visible_names, "夜凯在可见技能列表中")
	_assert(not ("双龙戏珠" in visible_names), "双龙戏珠为隐藏技不可见")

	# ── 第9回合：迈特凯获胜 → 释放夜凯 ────────────────────────────
	print("[E2E] 释放夜凯前 gai.energy=%d" % gai.energy)
	_assert(gai.energy >= 5, "释放夜凯前能量≥5（实际=%d）" % gai.energy)

	gai.current_gesture = PlayerState.Gesture.ROCK
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "第9回合进入ACTION_INPUT（实际=%d）" % gm.get("_current_phase"))
	_assert(gm.get("_sole_winner_id") == 0, "第9回合胜者为迈特凯")

	# 找到夜凯索引（get_all_skills 中）
	var night_kai_idx: int = -1
	var all_skills := gai.get_all_skills()
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == "夜凯":
			night_kai_idx = i
			break
	_assert(night_kai_idx >= 0, "夜凯索引找到（idx=%d）" % night_kai_idx)

	var naruto_hp_before: int = naruto.hp
	print("[E2E] 释放夜凯前 naruto hp=%d" % naruto_hp_before)
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, night_kai_idx, 1)
	_assert(naruto.hp == naruto_hp_before - 5, "夜凯造成5伤：HP从%d→%d（期望%d）" % [naruto_hp_before, naruto.hp, naruto_hp_before - 5])
	_assert(gai.energy == 3, "夜凯消耗5气后energy=3（实际=%d）" % gai.energy)

	print("=== 端到端测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)