## FTG intercept mechanism test
## Covers: _check_ftg_intercept / _ai_decide_ftg_intercept / _apply_ftg_choice / submit_ftg_intercept / _resume_ftg_action
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== FTG Intercept Test ===")

	await get_tree().process_frame

	var minato_char := load("res://resources/characters/波风水门.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	print("[DEBUG] char loaded: minato=%s naruto=%s sakura=%s" % [minato_char != null, naruto_char != null, sakura_char != null])

	if minato_char == null or naruto_char == null or sakura_char == null:
		print("FATAL: char resource load failed")
		get_tree().quit(1)
		return

	# ── Scene 1: 3-player game, AI Minato attacked, mark on attacker -> dodge+counter ──
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": false},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
			{"name": "Sakura", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	var minato: PlayerState = gm.get_player(0)
	var naruto: PlayerState = gm.get_player(1)
	var sakura: PlayerState = gm.get_player(2)
	var dist_sys: DistanceSystem = gm.get("_distance_system")

	# ── Test 1: AI dodge + rasengan counter ──────────────────
	naruto.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	minato.hp = 8
	naruto.hp = 10

	var naruto_attack: SkillData = naruto.character.skills[0]
	var targets: Array[PlayerState] = [minato]

	var dodge_signals: Array = []
	gm.ftg_dodge_triggered.connect(func(pid: int, aid: int): dodge_signals.append([pid, aid]))
	var mark_removed_signals: Array = []
	gm.ftg_mark_removed.connect(func(pid: int): mark_removed_signals.append(pid))
	var skill_applied_signals: Array = []
	gm.skill_applied.connect(func(logs: Array[Dictionary]): skill_applied_signals.append(logs))

	var intercept_result: Dictionary = gm.call("_check_ftg_intercept", naruto, naruto_attack, targets)

	_assert(not intercept_result.has("pending"), "1a: AI Minato intercept not pending (auto-decide)")
	_assert(dodge_signals.size() >= 1, "1b: ftg_dodge_triggered signal emitted")
	_assert(dodge_signals[0][0] == minato.player_id, "1c: dodge signal Minato ID correct")
	_assert(mark_removed_signals.has(naruto.player_id), "1d: mark on Naruto removed")
	_assert(not naruto.ftg_marked_by.has(minato.player_id), "1e: Naruto ftg_marked_by no longer has Minato")
	_assert(minato.energy == 3, "1f: dodge counter costs 2 energy, remaining 3, actual=" + str(minato.energy))
	_assert(naruto.hp == 10 - 3, "1g: rasengan counter deals 3 dmg, Naruto HP=7, actual=" + str(naruto.hp))
	_assert(skill_applied_signals.size() >= 1, "1h: skill_applied signal emitted (rasengan counter)")

	# ── Test 2: AI swap ───────────────────────────────────────
	minato.hp = 8
	minato.energy = 5
	naruto.hp = 10
	sakura.hp = 10
	naruto.ftg_marked_by.clear()
	sakura.ftg_marked_by.clear()
	sakura.ftg_marked_by.append(minato.player_id)

	targets = [minato]

	var swap_signals: Array = []
	gm.ftg_swap_triggered.connect(func(swapper: int, swapped: int, orig: int): swap_signals.append([swapper, swapped, orig]))
	mark_removed_signals.clear()
	gm.ftg_mark_removed.connect(func(pid: int): mark_removed_signals.append(pid))

	intercept_result = gm.call("_check_ftg_intercept", naruto, naruto_attack, targets)

	_assert(not intercept_result.has("pending"), "2a: AI Minato swap not pending")
	_assert(swap_signals.size() >= 1, "2b: ftg_swap_triggered signal emitted")
	_assert(swap_signals[0][0] == minato.player_id, "2c: swap signal Minato ID correct")
	_assert(swap_signals[0][1] == sakura.player_id, "2d: swap target is Sakura")
	_assert(mark_removed_signals.has(sakura.player_id), "2e: mark on Sakura removed")
	_assert(not sakura.ftg_marked_by.has(minato.player_id), "2f: Sakura ftg_marked_by no longer has Minato")

	# ── Test 3: AI no options -> skip ─────────────────────────
	minato.hp = 8
	minato.energy = 5
	naruto.hp = 10
	sakura.hp = 10
	naruto.ftg_marked_by.clear()
	sakura.ftg_marked_by.clear()

	targets = [minato]
	intercept_result = gm.call("_check_ftg_intercept", naruto, naruto_attack, targets)

	_assert(not intercept_result.has("pending"), "3a: no options -> no intercept")
	_assert(intercept_result.is_empty(), "3b: no options -> empty dict returned")

	# ── Test 4: Human Minato -> signal + pending ─────────────
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": true},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
			{"name": "Sakura", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)
	sakura = gm.get_player(2)

	naruto.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	minato.hp = 8
	naruto.hp = 10

	var required_signals: Array = []
	gm.ftg_intercept_required.connect(func(target_id: int, attacker_id: int, marked_ids: Array[int], attacker_marked: bool):
		required_signals.append({"target_id": target_id, "attacker_id": attacker_id, "marked_ids": marked_ids, "attacker_marked": attacker_marked})
	)

	targets = [minato]
	intercept_result = gm.call("_check_ftg_intercept", naruto, naruto_attack, targets)

	_assert(intercept_result.has("pending"), "4a: human Minato intercept returns pending")
	_assert(required_signals.size() >= 1, "4b: ftg_intercept_required signal emitted")
	_assert(required_signals[0]["target_id"] == minato.player_id, "4c: signal target_id is Minato")
	_assert(required_signals[0]["attacker_id"] == naruto.player_id, "4d: signal attacker_id is Naruto")
	_assert(required_signals[0]["attacker_marked"] == true, "4e: attacker_marked = true")

	# ── Test 5: submit_ftg_intercept -> dodge -> counter confirm -> resume ──
	naruto.ftg_marked_by.clear()
	naruto.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	minato.hp = 8
	naruto.hp = 10

	var pending_dict: Dictionary = {
		"winner": naruto,
		"skill": naruto_attack,
		"targets": targets,
		"splash_targets": [] as Array[PlayerState],
	}
	gm.set("_ftg_pending", pending_dict)

	var dodge_signals2: Array = []
	gm.ftg_dodge_triggered.connect(func(pid: int, aid: int): dodge_signals2.append([pid, aid]))
	var counter_required_signals: Array = []
	gm.rasengan_counter_required.connect(func(target_id: int, attacker_id: int, energy: int):
		counter_required_signals.append({"target_id": target_id, "attacker_id": attacker_id, "energy": energy})
	)

	# Human Minato chooses dodge
	gm.submit_ftg_intercept(minato.player_id, GameManager.FTGChoice.DODGE, -1)

	await get_tree().process_frame
	await get_tree().process_frame

	_assert(dodge_signals2.size() >= 1, "5a: dodge signal emitted")
	_assert(not naruto.ftg_marked_by.has(minato.player_id), "5b: mark on Naruto removed")
	# 闪避后不自动反击，等待二次确认
	_assert(counter_required_signals.size() >= 1, "5c: rasengan_counter_required signal emitted")
	_assert(counter_required_signals[0]["target_id"] == minato.player_id, "5d: counter signal target_id is Minato")
	_assert(counter_required_signals[0]["attacker_id"] == naruto.player_id, "5e: counter signal attacker_id is Naruto")
	_assert(minato.energy == 5, "5f: no auto counter before confirm, energy stays 5, actual=" + str(minato.energy))
	_assert(naruto.hp == 10, "5g: no auto counter before confirm, Naruto HP stays 10, actual=" + str(naruto.hp))
	var ftg_pending_after_dodge: Dictionary = gm.get("_ftg_pending")
	_assert(not ftg_pending_after_dodge.is_empty(), "5h: _ftg_pending kept while awaiting counter confirm")
	_assert(ftg_pending_after_dodge.get("awaiting_counter", false), "5i: awaiting_counter flag set")

	# 玩家选择反击
	gm.submit_rasengan_counter(minato.player_id, true)

	await get_tree().process_frame
	await get_tree().process_frame

	_assert(minato.energy == 3, "5j: rasengan counter costs 2 energy, remaining 3, actual=" + str(minato.energy))
	_assert(naruto.hp == 10 - 3, "5k: rasengan counter deals 3 dmg, Naruto HP=7, actual=" + str(naruto.hp))
	var ftg_pending: Dictionary = gm.get("_ftg_pending")
	_assert(ftg_pending.is_empty(), "5l: _ftg_pending cleared after counter resume")

	# ── Test 6: submit_ftg_intercept -> swap -> resume ───────
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": true},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
			{"name": "Sakura", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)
	sakura = gm.get_player(2)

	sakura.ftg_marked_by.append(minato.player_id)
	minato.hp = 8
	minato.energy = 5
	naruto.hp = 10
	sakura.hp = 10

	targets = [minato]
	var pending_dict2: Dictionary = {
		"winner": naruto,
		"skill": naruto_attack,
		"targets": targets,
		"splash_targets": [] as Array[PlayerState],
	}
	gm.set("_ftg_pending", pending_dict2)

	var swap_signals2: Array = []
	gm.ftg_swap_triggered.connect(func(swapper: int, swapped: int, orig: int): swap_signals2.append([swapper, swapped, orig]))

	# Human Minato chooses swap (target = Sakura)
	gm.submit_ftg_intercept(minato.player_id, GameManager.FTGChoice.SWAP, sakura.player_id)

	await get_tree().process_frame
	await get_tree().process_frame

	_assert(swap_signals2.size() >= 1, "6a: swap signal emitted")
	_assert(swap_signals2[0][1] == sakura.player_id, "6b: swap target is Sakura")
	_assert(not sakura.ftg_marked_by.has(minato.player_id), "6c: mark on Sakura removed")
	var ftg_pending2: Dictionary = gm.get("_ftg_pending")
	_assert(ftg_pending2.is_empty(), "6d: _ftg_pending cleared after resume")
	_assert(sakura.hp < 10, "6e: Sakura takes damage instead of Minato, HP=" + str(sakura.hp))
	_assert(minato.hp == 8, "6f: Minato unharmed (swap success), HP=" + str(minato.hp))

	# ── Test 7: submit_ftg_intercept -> skip ──────────────────
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": true},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)

	naruto.ftg_marked_by.append(minato.player_id)
	minato.hp = 8
	minato.energy = 5
	naruto.hp = 10

	targets = [minato]
	var pending_dict3: Dictionary = {
		"winner": naruto,
		"skill": naruto_attack,
		"targets": targets,
		"splash_targets": [] as Array[PlayerState],
	}
	gm.set("_ftg_pending", pending_dict3)

	# Human Minato chooses skip
	gm.submit_ftg_intercept(minato.player_id, GameManager.FTGChoice.SKIP, -1)

	await get_tree().process_frame
	await get_tree().process_frame

	_assert(minato.hp < 8, "7a: Minato takes damage after skip, HP=" + str(minato.hp))
	_assert(naruto.ftg_marked_by.has(minato.player_id), "7b: mark not removed after skip")

	# ── Test 8: FTGChoice enum values ─────────────────────────
	_assert(GameManager.FTGChoice.NONE == 0, "8a: FTGChoice.NONE=0")
	_assert(GameManager.FTGChoice.SWAP == 1, "8b: FTGChoice.SWAP=1")
	_assert(GameManager.FTGChoice.DODGE == 2, "8c: FTGChoice.DODGE=2")
	_assert(GameManager.FTGChoice.SKIP == 3, "8d: FTGChoice.SKIP=3")

	# ── Test 9: AI intercept priority (dodge > swap > skip) ──
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": false},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
			{"name": "Sakura", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)
	sakura = gm.get_player(2)

	# Scenario A: attacker marked + has 2 energy -> dodge
	naruto.ftg_marked_by.append(minato.player_id)
	sakura.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	var marked_sakura: Array[int] = [sakura.player_id]
	var choice_a: int = gm.call("_ai_decide_ftg_intercept", minato, naruto, marked_sakura, true)
	_assert(choice_a == GameManager.FTGChoice.DODGE, "9a: attacker marked + has energy -> dodge, actual=" + str(choice_a))

	# Scenario B: attacker marked but low energy -> swap
	minato.energy = 1
	var choice_b: int = gm.call("_ai_decide_ftg_intercept", minato, naruto, marked_sakura, true)
	_assert(choice_b == GameManager.FTGChoice.SWAP, "9b: attacker marked but low energy -> swap, actual=" + str(choice_b))

	# Scenario C: attacker not marked, has marked players -> swap
	naruto.ftg_marked_by.clear()
	minato.energy = 5
	var choice_c: int = gm.call("_ai_decide_ftg_intercept", minato, naruto, marked_sakura, false)
	_assert(choice_c == GameManager.FTGChoice.SWAP, "9c: attacker not marked + has marked -> swap, actual=" + str(choice_c))

	# Scenario D: no options -> skip
	sakura.ftg_marked_by.clear()
	minato.energy = 5
	var empty_marked: Array[int] = []
	var choice_d: int = gm.call("_ai_decide_ftg_intercept", minato, naruto, empty_marked, false)
	_assert(choice_d == GameManager.FTGChoice.SKIP, "9d: no options -> skip, actual=" + str(choice_d))

	# ── Test 10: non-damage skill does not trigger intercept ──
	minato.energy = 5
	naruto.ftg_marked_by.clear()
	sakura.ftg_marked_by.clear()
	sakura.ftg_marked_by.append(minato.player_id)

	var ftg_charge_skill: SkillData = null
	for s in minato.character.skills:
		if s.skill_name == "飞雷神聚":
			ftg_charge_skill = s
	if ftg_charge_skill == null:
		_assert(false, "10a: FTG charge skill not found")
	else:
		var ftg_targets: Array[PlayerState] = [minato]
		var no_intercept: Dictionary = gm.call("_check_ftg_intercept", naruto, ftg_charge_skill, ftg_targets)
		_assert(not no_intercept.has("pending"), "10a: non-damage skill does not trigger intercept")

	# ── Test 11: dodge + decline counter ─────────────────────
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": true},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)

	naruto.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	minato.hp = 8
	naruto.hp = 10

	targets = [minato]
	var pending_dict4: Dictionary = {
		"winner": naruto,
		"skill": naruto_attack,
		"targets": targets,
		"splash_targets": [] as Array[PlayerState],
	}
	gm.set("_ftg_pending", pending_dict4)

	# dodge
	gm.submit_ftg_intercept(minato.player_id, GameManager.FTGChoice.DODGE, -1)
	await get_tree().process_frame

	# 放弃反击
	gm.submit_rasengan_counter(minato.player_id, false)
	await get_tree().process_frame
	await get_tree().process_frame

	_assert(minato.energy == 5, "11a: decline counter keeps energy 5, actual=" + str(minato.energy))
	_assert(naruto.hp == 10, "11b: decline counter no damage to Naruto, actual=" + str(naruto.hp))
	_assert(not naruto.ftg_marked_by.has(minato.player_id), "11c: mark still removed after dodge")
	var ftg_pending4: Dictionary = gm.get("_ftg_pending")
	_assert(ftg_pending4.is_empty(), "11d: _ftg_pending cleared after decline")

	# ── Test 12: AI dodge modifies targets array (removes Minato) ──
	# 直接调用 _check_ftg_intercept 时 targets 是传入数组，AI 闪避应移除水门
	gm.setup_game({
		"players": [
			{"name": "Minato", "character": minato_char, "is_human": false},
			{"name": "Naruto", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	await get_tree().process_frame

	minato = gm.get_player(0)
	naruto = gm.get_player(1)

	naruto.ftg_marked_by.clear()
	naruto.ftg_marked_by.append(minato.player_id)
	minato.energy = 5
	minato.hp = 8
	naruto.hp = 10

	var ai_targets: Array[PlayerState] = [minato]
	var ai_result: Dictionary = gm.call("_check_ftg_intercept", naruto, naruto_attack, ai_targets)
	_assert(not ai_result.has("pending"), "12a: AI dodge not pending")
	_assert(ai_targets.size() == 0, "12b: AI dodge removes Minato from targets, size=0, actual=" + str(ai_targets.size()))
	_assert(minato.hp == 8, "12c: Minato unharmed after AI dodge, HP=" + str(minato.hp))

	print("=== FTG Intercept Test: PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(condition: bool, msg: String) -> void:
	if condition:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)