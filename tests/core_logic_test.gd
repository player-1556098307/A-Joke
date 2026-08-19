## 游戏底层逻辑专项测试
## 测试目标：状态机流转、核心状态字段、游戏流程循环（多回合/淘汰/胜负/平局/加赛）
## 所有玩家 is_human=true，避免AI干扰
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

func _find_skill_index(p: PlayerState, sn: String) -> int:
	var all := p.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == sn:
			return i
	return -1

func _ready() -> void:
	print("=== 游戏底层逻辑专项测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	var sasuke_fy_char := load("res://resources/characters/宇智波佐助（疾风传）.tres") as CharacterData
	if naruto_char == null or sasuke_char == null or sakura_char == null or sasuke_fy_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager
	# 钟机制角色参与时自动拒绝招架，避免流程挂起
	gm.end_phase_bell_decision_required.connect(func(pid: int, _cnt: int) -> void:
		gm.submit_bell_decision(pid, false)
	)

	# ════════════════════════════════════════════════════════════════
	# 测试组A：状态机阶段流转
	# ════════════════════════════════════════════════════════════════
	print("--- A组：状态机阶段流转 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var p0: PlayerState = gm.get_player(0)
	var p1: PlayerState = gm.get_player(1)

	# A1: 初始阶段是GESTURE_INPUT
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "A1: 初始阶段=GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))
	# A2: 回合编号从1开始（首次进入GESTURE_INPUT时+1）
	_assert(gm.get("_current_round_number") == 1, "A2: 第1回合（实际=%d）" % gm.get("_current_round_number"))

	# A3: 提交手势后进入RESOLVING
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.submit_gesture(0, PlayerState.Gesture.ROCK)
	gm.submit_gesture(1, PlayerState.Gesture.SCISSORS)
	_assert(gm.get("_current_phase") == GameManager.GamePhase.RESOLVING, "A3: 手势提交后=RESOLVING（实际=%d）" % gm.get("_current_phase"))

	# A4: 结算后进入PREPARATION
	await get_tree().create_timer(0.6).timeout
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION or gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT, "A4: 结算后=PREPARATION或ACTION_INPUT（实际=%d）" % gm.get("_current_phase"))
	_assert(gm.get("_sole_winner_id") == 0, "A5: 唯一胜者=0（实际=%d）" % gm.get("_sole_winner_id"))

	# ════════════════════════════════════════════════════════════════
	# 测试组B：猜拳结算规则（平局/单胜/多人加赛）
	# ════════════════════════════════════════════════════════════════
	print("--- B组：猜拳结算规则 ---")

	# B1: 石头胜剪刀
	var gestures := {0: PlayerState.Gesture.ROCK, 1: PlayerState.Gesture.SCISSORS}
	var result := RoundResolver.resolve_gestures(gestures)
	_assert(not result["is_draw"], "B1: 石头vs剪刀非平局")
	_assert(result["winners"].has(0), "B1: 胜者=0")

	# B2: 剪刀胜布
	gestures = {0: PlayerState.Gesture.SCISSORS, 1: PlayerState.Gesture.PAPER}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(not result["is_draw"], "B2: 剪刀vs布非平局")
	_assert(result["winners"].has(0), "B2: 胜者=0")

	# B3: 布胜石头
	gestures = {0: PlayerState.Gesture.PAPER, 1: PlayerState.Gesture.ROCK}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(not result["is_draw"], "B3: 布vs石头非平局")
	_assert(result["winners"].has(0), "B3: 胜者=0")

	# B4: 同手势平局
	gestures = {0: PlayerState.Gesture.ROCK, 1: PlayerState.Gesture.ROCK}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(result["is_draw"], "B4: 石头vs石头平局")

	# B5: 三种手势同时出现=平局
	gestures = {0: PlayerState.Gesture.ROCK, 1: PlayerState.Gesture.SCISSORS, 2: PlayerState.Gesture.PAPER}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(result["is_draw"], "B5: 三种手势同出=平局")

	# B6: 仅1人有效出拳直接胜出（其余SKIP）
	gestures = {0: PlayerState.Gesture.ROCK, 1: PlayerState.Gesture.SKIP}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(not result["is_draw"], "B6: 1人出拳+1人SKIP非平局")
	_assert(result["winners"].has(0), "B6: 唯一出拳者胜")

	# B7: 全部SKIP=平局(all_skipped)
	gestures = {0: PlayerState.Gesture.SKIP, 1: PlayerState.Gesture.SKIP}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(result["is_draw"], "B7: 全SKIP=平局")
	_assert(result.get("all_skipped", false), "B7: all_skipped=true")

	# B8: 2人同胜（如2人出石头vs1人剪刀）→多胜者加赛
	gestures = {0: PlayerState.Gesture.ROCK, 1: PlayerState.Gesture.ROCK, 2: PlayerState.Gesture.SCISSORS}
	result = RoundResolver.resolve_gestures(gestures)
	_assert(not result["is_draw"], "B8: 2石头vs1剪刀非平局")
	_assert(result["winners"].size() == 2, "B8: 2胜者需加赛（实际=%d）" % result["winners"].size())

	# ════════════════════════════════════════════════════════════════
	# 测试组C：聚气与能量管理
	# ════════════════════════════════════════════════════════════════
	print("--- C组：聚气与能量管理 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# C1: 初始能量=0
	_assert(p0.energy == 0, "C1: 初始能量=0（实际=%d）" % p0.energy)
	# C2: 聚气+1
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "C2: 鸣人胜出")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p0.energy == 1, "C2: 聚气后能量=1（实际=%d）" % p0.energy)
	# C3: 影分身存在时聚气+2
	p0.energy = 1
	p0.clone_count = 1
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p0.energy == 3, "C3: 分身时聚气+2（1+1+1=3，实际=%d）" % p0.energy)

	# C4: 普通角色max_energy=999上限
	p0.energy = 998
	p0.add_energy(10)
	_assert(p0.energy == 999, "C4: 能量上限999（实际=%d）" % p0.energy)

	# ════════════════════════════════════════════════════════════════
	# 测试组D：伤害吸收链（盾/分身/防反）
	# ════════════════════════════════════════════════════════════════
	print("--- D组：伤害吸收链 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# D1: 数值盾吸收
	p1.shield = 2
	var p0_hp := p0.hp
	var p1_hp := p1.hp
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1.hp == p1_hp, "D1: 盾吸收1伤HP不变（%.1f→%.1f）" % [p1_hp, p1.hp])
	_assert(p1.shield == 1, "D1: 盾-1（实际=%d）" % p1.shield)

	# D2: 全挡盾（-1）
	p1.shield = -1
	p1_hp = p1.hp
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1.hp == p1_hp, "D2: 全挡盾吸收后HP不变（%.1f→%.1f）" % [p1_hp, p1.hp])
	_assert(p1.shield == 0, "D2: 全挡盾消失（实际=%d）" % p1.shield)

	# D3: 影分身吸收
	p1.clone_count = 1
	p1_hp = p1.hp
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1.hp == p1_hp, "D3: 分身吸收后HP不变（%.1f→%.1f）" % [p1_hp, p1.hp])
	_assert(p1.clone_count == 0, "D3: 分身消失（实际=%d）" % p1.clone_count)

	# ════════════════════════════════════════════════════════════════
	# 测试组E：麻痹机制
	# ════════════════════════════════════════════════════════════════
	print("--- E组：麻痹机制 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# E1: 麻痹玩家自动SKIP
	p0.paralyze_turns = 1
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.ROCK  # 平局避免冲突
	gm.call("_apply_paralyze")
	_assert(p0.current_gesture == PlayerState.Gesture.SKIP, "E1: 麻痹自动SKIP（实际=%d）" % p0.current_gesture)

	# E2: 麻痹状态下不可使用技能 → 尝试提交技能应被拒绝
	# 先让佐助胜出
	p0.paralyze_turns = 1
	p0.current_gesture = PlayerState.Gesture.SKIP
	p1.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "E2: 佐助胜出（麻痹者SKIP）")
	# 佐助对鸣人用千鸟（麻痹）
	p1.energy = 2
	var p0_hp_e2 := p0.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(p1, "千鸟"), 0)
	_assert(p0.hp == p0_hp_e2 - 2.0, "E2: 千鸟2伤（%.1f→%.1f）" % [p0_hp_e2, p0.hp])
	_assert(p0.paralyze_turns >= 1, "E2: 被千鸟麻痹（实际=%d）" % p0.paralyze_turns)

	# ════════════════════════════════════════════════════════════════
	# 测试组F：击飞机制
	# ════════════════════════════════════════════════════════════════
	print("--- F组：击飞机制 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# F1: 击飞玩家可正常猜拳
	p0.knockdown_turns = 1
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "F1: 击飞玩家可猜拳胜出")

	# F2: 击飞玩家强制聚气（即使提交技能也变聚气）—— submit_action后整轮同步完成
	# pending_action已被reset_round_data重置，通过energy验证聚气生效
	p0.energy = 0
	var energy_before := p0.energy
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p0.energy == energy_before + 1, "F2: 击飞强制聚气+1（实际=%d）" % p0.energy)
	# F3: 击飞回合结束后递减到0（knockdown_consumed已被reset，但knockdown_turns递减可见）
	_assert(p0.knockdown_turns == 0, "F3: 击飞递减到0（实际=%d）" % p0.knockdown_turns)

	# ════════════════════════════════════════════════════════════════
	# 测试组G：无敌机制
	# ════════════════════════════════════════════════════════════════
	print("--- G组：无敌机制 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# G1: 无敌状态免疫伤害
	p1.invincible_turns = 1
	p1_hp = p1.hp
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1.hp == p1_hp, "G1: 无敌免疫伤害（%.1f→%.1f）" % [p1_hp, p1.hp])

	# G2: 无敌状态免疫控制（麻痹）
	p1.invincible_turns = 1
	p1.paralyze_turns = 0
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "千鸟"), 1)
	_assert(p1.paralyze_turns == 0, "G2: 无敌免疫麻痹（实际=%d）" % p1.paralyze_turns)

	# ════════════════════════════════════════════════════════════════
	# 测试组H：距离系统
	# ════════════════════════════════════════════════════════════════
	print("--- H组：距离系统 ---")

	var ds := DistanceSystem.new()
	ds.setup([0, 1, 2, 3])
	# H1: 相邻玩家距离1
	_assert(ds.get_distance(0, 1) == 1, "H1: 相邻距离1（实际=%d）" % ds.get_distance(0, 1))
	# H2: 对面玩家距离2（4人环形）
	_assert(ds.get_distance(0, 2) == 2, "H2: 对面距离2（实际=%d）" % ds.get_distance(0, 2))
	# H3: 三人环形中距离1和1
	ds.setup([0, 1, 2])
	_assert(ds.get_distance(0, 2) == 1, "H3: 3人环形0-2距离1（实际=%d）" % ds.get_distance(0, 2))
	# H4: 距离偏移
	ds.setup([0, 1, 2, 3])
	ds.modify_distance(0, 2, 1)
	_assert(ds.get_distance(0, 2) == 3, "H4: 偏移后距离3（实际=%d）" % ds.get_distance(0, 2))
	# H5: 负偏移最小为1
	ds.modify_distance(0, 2, -5)
	_assert(ds.get_distance(0, 2) == 1, "H5: 负偏移最小1（实际=%d）" % ds.get_distance(0, 2))
	# H6: 同玩家距离0
	_assert(ds.get_distance(0, 0) == 0, "H6: 同玩家距离0")
	# H7: 不在座位表的返回999
	_assert(ds.get_distance(0, 99) == 999, "H7: 不存在玩家距离999")
	# H8: 死亡玩家移除后距离更新
	ds.remove_player(1)
	_assert(ds.get_distance(0, 2) == 1, "H8: 移除1后0-2距离1（实际=%d）" % ds.get_distance(0, 2))
	# H9: 座位交换（0和2互换后座位=[2,1,0,3]，0在pos2，1在pos1，距离1）
	ds.setup([0, 1, 2, 3])
	ds.swap_seats(0, 2)
	_assert(ds.get_distance(0, 1) == 1, "H9: 交换0-2后0-1距离1（实际=%d）" % ds.get_distance(0, 1))

	# ════════════════════════════════════════════════════════════════
	# 测试组I：延迟伤害
	# ════════════════════════════════════════════════════════════════
	print("--- I组：延迟伤害 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# I1: 螺旋丸延迟2回合后3伤
	# 注意：submit_action同步执行整轮（含_end_round），trigger_in已从2减到1
	var p1_hp_i1 := p1.hp
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "螺旋丸"), 1)
	_assert(p1.delayed_damages.size() == 1, "I1: 延迟伤害队列+1（实际=%d）" % p1.delayed_damages.size())
	_assert(p1.delayed_damages[0]["damage"] == 3.0, "I1a: 延迟伤害=3（实际=%.1f）" % p1.delayed_damages[0]["damage"])
	_assert(p1.delayed_damages[0]["trigger_in"] == 1, "I1b: submit_action后trigger_in=1（已减1，实际=%d）" % p1.delayed_damages[0]["trigger_in"])

	# I2: 再过1回合（_end_round再执行一次），trigger_in减到0，延迟伤害触发
	var p1_hp_pre_trigger := p1.hp
	gm.call("_process_end_phase")
	gm.call("_end_round")
	_assert(p1.delayed_damages.size() == 0, "I2: 延迟伤害触发后队列清空（实际=%d）" % p1.delayed_damages.size())
	_assert(p1.hp == p1_hp_pre_trigger - 3.0, "I2: 延迟伤害3伤触发（%.1f→%.1f）" % [p1_hp_pre_trigger, p1.hp])

	# ════════════════════════════════════════════════════════════════
	# 测试组J：淘汰与游戏结束
	# ════════════════════════════════════════════════════════════════
	print("--- J组：淘汰与游戏结束 ---")

	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)

	# J1: HP归零后淘汰
	p1.hp = 1.0
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1.hp <= 0, "J1: 佐助HP<=0（%.1f）" % p1.hp)
	# 进入淘汰检测
	gm.call("_check_elimination")
	_assert(not p1.is_alive, "J2: 佐助被淘汰")
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GAME_OVER, "J3: 游戏结束（实际=%d）" % gm.get("_current_phase"))

	print("=== 游戏底层逻辑专项测试结束：PASS=%d FAIL=%d ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)
