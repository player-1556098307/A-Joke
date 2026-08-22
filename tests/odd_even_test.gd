## 黑白配（手心手背）机制专项测试
## 测试目标：≥5人触发黑白配、少方胜出、≤4人进入RPS、auto_rps开关
## 所有玩家 is_human=true（同步提交，无AI延时干扰）
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

func _ready() -> void:
	print("=== 黑白配（手心手背）机制测试 ===")
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

	# ════════════════════════════════════════════════════════════════
	# 测试组A：≥5人触发黑白配
	# ════════════════════════════════════════════════════════════════
	print("--- A组：≥5人触发黑白配 ---")

	# 5人全部 is_human=true，同步提交
	var players_a := []
	var chars_a := [naruto_char, sasuke_char, sakura_char, sasuke_fy_char, naruto_char]
	var names_a := ["P0", "P1", "P2", "P3", "P4"]
	for i in range(5):
		players_a.append({"name": names_a[i], "character": chars_a[i], "is_human": true})

	gm.setup_game({"players": players_a})
	await get_tree().process_frame

	# A1: 初始阶段应为 ODD_EVEN_INPUT（5人≥5）
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ODD_EVEN_INPUT,
		"A1: 5人初始阶段=ODD_EVEN_INPUT（实际=%d）" % gm.get("_current_phase"))

	# A2: _odd_even_participants 应有5人
	var oe_parts: Array = gm.get("_odd_even_participants")
	_assert(oe_parts.size() == 5, "A2: 黑白配参与方=5（实际=%d）" % oe_parts.size())

	# A3: _odd_even_active = true
	_assert(gm.get("_odd_even_active") == true, "A3: _odd_even_active=true")

	# A4: 提交3人手心、2人手背 → 手背方(2人)是少方，应胜出
	for pid in [0, 1, 2]:
		gm.submit_odd_even(pid, true)   # 手心
	for pid in [3, 4]:
		gm.submit_odd_even(pid, false)  # 手背
	await get_tree().create_timer(0.7).timeout  # 等 resolve_timer

	# A5: 应进入 GESTURE_INPUT（胜出2人≤4）
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"A5: 黑白配后进入GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	# A6: _rps_participants = [3, 4]（手背方胜出）
	var rps_parts: Array = gm.get("_rps_participants")
	rps_parts.sort()
	_assert(rps_parts.size() == 2, "A6: RPS参与方=2（实际=%d）" % rps_parts.size())
	_assert(rps_parts == [3, 4], "A6b: RPS参与方=[3,4]（实际=%s）" % str(rps_parts))

	# A7: 非参与方的手势为SKIP
	var p0 := gm.get_player(0)
	_assert(p0.current_gesture == PlayerState.Gesture.SKIP, "A7: 非参与方P0手势=SKIP（实际=%d）" % p0.current_gesture)

	# A8: 参与方手势为NONE（可出拳）
	var p3 := gm.get_player(3)
	_assert(p3.current_gesture == PlayerState.Gesture.NONE, "A8: 参与方P3手势=NONE（实际=%d）" % p3.current_gesture)

	# ════════════════════════════════════════════════════════════════
	# 测试组B：黑白配平局 → 重新配
	# ════════════════════════════════════════════════════════════════
	print("--- B组：黑白配平局 ---")

	gm.setup_game({"players": players_a})
	await get_tree().process_frame

	# B1: 全部选手心 → 平局
	for pid in [0, 1, 2, 3, 4]:
		gm.submit_odd_even(pid, true)
	await get_tree().create_timer(0.7).timeout

	# B2: 应仍在 ODD_EVEN_INPUT（平局重新配）
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ODD_EVEN_INPUT,
		"B2: 全部相同→重新配，阶段=ODD_EVEN_INPUT（实际=%d）" % gm.get("_current_phase"))

	# B3: _odd_even_choices 应已清空
	_assert(gm.get("_odd_even_choices").is_empty(), "B3: 平局后_choices清空")

	# ════════════════════════════════════════════════════════════════
	# 测试组C：<5人不触发黑白配
	# ════════════════════════════════════════════════════════════════
	print("--- C组：<5人不触发黑白配 ---")

	var players_c := []
	for i in range(4):
		players_c.append({"name": "C%d" % i, "character": chars_a[i], "is_human": true})

	gm.setup_game({"players": players_c})
	await get_tree().process_frame

	# C1: 4人应直接进入 GESTURE_INPUT
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"C1: 4人直接进入GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	# C2: _odd_even_participants 为空
	_assert(gm.get("_odd_even_participants").is_empty(), "C2: 4人不触发黑白配")

	# ════════════════════════════════════════════════════════════════
	# 测试组D：auto_rps_enabled 开关
	# ════════════════════════════════════════════════════════════════
	print("--- D组：auto_rps_enabled ---")

	# D1: 默认 false
	gm.setup_game({"players": players_c})
	await get_tree().process_frame
	_assert(gm.auto_rps_enabled == false, "D1: 默认auto_rps=false")

	# D2: 通过config设置 auto_rps=true
	gm.setup_game({"players": players_c, "auto_rps": true})
	await get_tree().process_frame
	_assert(gm.auto_rps_enabled == true, "D2: config auto_rps=true生效")

	# D3: 运行时切换
	gm.auto_rps_enabled = false
	_assert(gm.auto_rps_enabled == false, "D3: 运行时关闭auto_rps")
	gm.auto_rps_enabled = true
	_assert(gm.auto_rps_enabled == true, "D4: 运行时开启auto_rps")

	# ════════════════════════════════════════════════════════════════
	# 测试组E：6人黑白配 → 胜出仍>4 → 继续黑白配
	# ════════════════════════════════════════════════════════════════
	print("--- E组：6人黑白配连续配 ---")

	var players_e := []
	for i in range(6):
		players_e.append({"name": "E%d" % i, "character": chars_a[i % 4], "is_human": true})

	gm.setup_game({"players": players_e})
	await get_tree().process_frame

	# E1: 6人初始=ODD_EVEN_INPUT
	_assert(gm.get("_current_phase") == GameManager.GamePhase.ODD_EVEN_INPUT,
		"E1: 6人初始=ODD_EVEN_INPUT（实际=%d）" % gm.get("_current_phase"))

	# E2: 1人手心、5人手背 → 手心方(1人)是少方，1≤4 → 进入RPS
	gm.submit_odd_even(0, true)    # 手心
	for pid in [1, 2, 3, 4, 5]:
		gm.submit_odd_even(pid, false)  # 手背
	await get_tree().create_timer(0.7).timeout

	# E3: 1人胜出 ≤4 → 直接进入 GESTURE_INPUT
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"E3: 1人胜出≤4→GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	# E4: RPS参与方=[0]
	var rps_e: Array = gm.get("_rps_participants")
	rps_e.sort()
	_assert(rps_e == [0], "E4: RPS参与方=[0]（实际=%s）" % str(rps_e))

	# ════════════════════════════════════════════════════════════════
	# 测试组F：6人 → 4vs2 → 2人≤4 → RPS
	# ════════════════════════════════════════════════════════════════
	print("--- F组：6人 4vs2 → 少方2人直接进RPS ---")

	gm.setup_game({"players": players_e})
	await get_tree().process_frame

	# F1: 4人手心、2人手背 → 手背方(2人)少方，2≤4 → RPS
	for pid in [0, 1, 2, 3]:
		gm.submit_odd_even(pid, true)   # 手心
	for pid in [4, 5]:
		gm.submit_odd_even(pid, false)  # 手背
	await get_tree().create_timer(0.7).timeout

	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"F1: 2人胜出≤4→GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	var rps_f: Array = gm.get("_rps_participants")
	rps_f.sort()
	_assert(rps_f == [4, 5], "F2: RPS参与方=[4,5]（实际=%s）" % str(rps_f))

	# ════════════════════════════════════════════════════════════════
	# 测试组G：8人 → 5vs3 → 3人≤4 → RPS
	# ════════════════════════════════════════════════════════════════
	print("--- G组：8人 5vs3 → 少方3人进RPS ---")

	var players_g := []
	for i in range(8):
		players_g.append({"name": "G%d" % i, "character": chars_a[i % 4], "is_human": true})

	gm.setup_game({"players": players_g})
	await get_tree().process_frame

	# 5人手心、3人手背 → 手背方(3人)少方，3≤4 → RPS
	for pid in [0, 1, 2, 3, 4]:
		gm.submit_odd_even(pid, true)
	for pid in [5, 6, 7]:
		gm.submit_odd_even(pid, false)
	await get_tree().create_timer(0.7).timeout

	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"G1: 3人胜出≤4→GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	var rps_g: Array = gm.get("_rps_participants")
	rps_g.sort()
	_assert(rps_g == [5, 6, 7], "G2: RPS参与方=[5,6,7]（实际=%s）" % str(rps_g))

	# ════════════════════════════════════════════════════════════════
	# 测试组H：8人 → 4vs4 → 4≤4 → RPS
	# ════════════════════════════════════════════════════════════════
	print("--- H组：8人 4vs4 → 少方4人(≤4)进RPS ---")

	gm.setup_game({"players": players_g})
	await get_tree().process_frame

	for pid in [0, 1, 2, 3]:
		gm.submit_odd_even(pid, true)
	for pid in [4, 5, 6, 7]:
		gm.submit_odd_even(pid, false)
	await get_tree().create_timer(0.7).timeout

	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"H1: 4人胜出≤4→GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	# ════════════════════════════════════════════════════════════════
	# 测试组I：8人 → 6vs2 → 少方2人≤4 → RPS，但不能触发继续
	# ════════════════════════════════════════════════════════════════
	print("--- I组：8人 6vs2 → 少方2人直接进RPS ---")

	gm.setup_game({"players": players_g})
	await get_tree().process_frame

	for pid in [0, 1, 2, 3, 4, 5]:
		gm.submit_odd_even(pid, true)
	for pid in [6, 7]:
		gm.submit_odd_even(pid, false)
	await get_tree().create_timer(0.7).timeout

	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"I1: 2人胜出≤4→GESTURE_INPUT（实际=%d）" % gm.get("_current_phase"))

	# ════════════════════════════════════════════════════════════════
	# 测试组J：RPS平局不重新触发黑白配
	# ════════════════════════════════════════════════════════════════
	print("--- J组：RPS平局不重新触发黑白配 ---")

	# 5人 → 黑白配后2人RPS → 2人平局 → 应继续RPS不回到黑白配
	gm.setup_game({"players": players_a})
	await get_tree().process_frame

	# 黑白配：3手心 2手背 → 手背方2人胜出
	for pid in [0, 1, 2]:
		gm.submit_odd_even(pid, true)
	for pid in [3, 4]:
		gm.submit_odd_even(pid, false)
	await get_tree().create_timer(0.7).timeout

	# 现在在 GESTURE_INPUT，2个参与者 [3, 4]
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT, "J1: 黑白配后=GESTURE_INPUT")

	# 两人出相同手势（石头） → 平局
	gm.submit_gesture(3, PlayerState.Gesture.ROCK)
	gm.submit_gesture(4, PlayerState.Gesture.ROCK)
	await get_tree().create_timer(0.7).timeout  # 等 resolve_timer

	# J2: 平局后应回到 GESTURE_INPUT（非 ODD_EVEN_INPUT）
	_assert(gm.get("_current_phase") == GameManager.GamePhase.GESTURE_INPUT,
		"J2: RPS平局后=GESTURE_INPUT不触发黑白配（实际=%d）" % gm.get("_current_phase"))

	# J3: _odd_even_done_this_round 仍为true
	_assert(gm.get("_odd_even_done_this_round") == true, "J3: _odd_even_done_this_round=true")

	# ════════════════════════════════════════════════════════════════
	# 测试组K：RPS 1人出拳 → 直接胜出
	# ════════════════════════════════════════════════════════════════
	print("--- K组：黑白配后1人RPS直接胜出 ---")

	gm.setup_game({"players": players_e})  # 6人
	await get_tree().process_frame

	# 1手心 5手背 → 手心方1人胜出
	gm.submit_odd_even(0, true)
	for pid in [1, 2, 3, 4, 5]:
		gm.submit_odd_even(pid, false)
	await get_tree().create_timer(0.7).timeout

	# 1人RPS → 直接胜（RoundResolver: 1人有效直接胜）
	gm.submit_gesture(0, PlayerState.Gesture.ROCK)
	await get_tree().create_timer(0.7).timeout

	_assert(gm.get("_sole_winner_id") == 0, "K1: 1人RPS胜者=0（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(gm.get("_current_phase") == GameManager.GamePhase.PREPARATION or gm.get("_current_phase") == GameManager.GamePhase.ACTION_INPUT,
		"K2: 1人RPS后进入PREPARATION/ACTION_INPUT（实际=%d）" % gm.get("_current_phase"))

	print("=== 黑白配机制测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)
