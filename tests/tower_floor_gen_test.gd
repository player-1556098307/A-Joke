## 慈悲尖塔关卡生成测试
## 覆盖：16层结构、小怪随机生成（同层不重复）、精英怪固定顺序不重复、
##      小怪层数量范围、大Boss层跳过=通关、小怪技能数据完整性
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 慈悲尖塔关卡生成测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	_test_floor_structure()
	_test_small_enemy_generation()
	await _test_elite_order()
	await _test_boss_floor_skip()
	_test_small_enemy_data()
	await _test_multi_enemy_battle(naruto_char)

	print("=== 关卡生成测试结束：PASS=%d FAIL=%d ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)

# ═════════ 测试1：层结构判定 ═══════════════════════════════
func _test_floor_structure() -> void:
	print("--- 测试1：层结构判定 ---")
	var tower := TowerManager.new()
	add_child(tower)

	_assert(TowerManager.MAX_FLOORS == 16, "1a: MAX_FLOORS=16（实际=%d）" % TowerManager.MAX_FLOORS)
	_assert(tower._is_elite_floor(4), "1b: 第4层=精英层")
	_assert(tower._is_elite_floor(8), "1c: 第8层=精英层")
	_assert(tower._is_elite_floor(12), "1d: 第12层=精英层")
	_assert(not tower._is_elite_floor(16), "1e: 第16层≠精英层（是Boss层）")
	_assert(tower._is_boss_floor(16), "1f: 第16层=Boss层")
	_assert(not tower._is_elite_floor(1), "1g: 第1层≠精英层")
	_assert(not tower._is_elite_floor(5), "1h: 第5层≠精英层")

	# 循环轮次
	_assert(tower._get_cycle(1) == 1, "1i: 第1层=第1轮")
	_assert(tower._get_cycle(4) == 1, "1j: 第4层=第1轮")
	_assert(tower._get_cycle(5) == 2, "1k: 第5层=第2轮")
	_assert(tower._get_cycle(12) == 3, "1l: 第12层=第3轮")
	_assert(tower._get_cycle(13) == 4, "1m: 第13层=第4轮")

	# 小怪数量范围
	var r1 := tower._get_small_enemy_count_range(1)
	_assert(r1[0] == 1 and r1[1] == 2, "1n: 第1轮小怪1-2只（实际=%s）" % str(r1))
	var r3 := tower._get_small_enemy_count_range(3)
	_assert(r3[0] == 3 and r3[1] == 4, "1o: 第3轮小怪3-4只（实际=%s）" % str(r3))

	# 小怪 HP 加成（按轮次递增）
	_assert(tower.get_cycle_hp_bonus(1) == 0, "1p: 第1轮HP加成0（实际=%d）" % tower.get_cycle_hp_bonus(1))
	_assert(tower.get_cycle_hp_bonus(2) == 2, "1q: 第2轮HP加成2（实际=%d）" % tower.get_cycle_hp_bonus(2))
	_assert(tower.get_cycle_hp_bonus(3) == 4, "1r: 第3轮HP加成4（实际=%d）" % tower.get_cycle_hp_bonus(3))
	_assert(tower.get_cycle_hp_bonus(4) == 6, "1s: 第4轮HP加成6（实际=%d）" % tower.get_cycle_hp_bonus(4))

	tower.queue_free()

# ═════════ 测试2：小怪随机生成（同层不重复） ═══════════════
func _test_small_enemy_generation() -> void:
	print("--- 测试2：小怪随机生成 ---")
	var tower := TowerManager.new()
	add_child(tower)

	# 多次随机生成，验证同层不重复
	for cycle in range(1, 5):
		var floor_num := cycle * 4 - 2  # 各轮的小怪层
		# 用固定种子重复测试
		for seed_val in range(100, 110):
			tower.set_seed(seed_val)
			var enemies := tower._generate_small_enemies(floor_num)
			var names: Array[String] = []
			for e in enemies:
				names.append(e.character_name)
			# 检查同层不重复
			var unique := true
			for i in range(names.size()):
				for j in range(i + 1, names.size()):
					if names[i] == names[j]:
						unique = false
			_assert(unique, "2a: 第%d层种子%d同层不重复（%s）" % [floor_num, seed_val, str(names)])

	# 验证第1-2轮只用前5种小怪
	tower.set_seed(42)
	var early_enemies := tower._generate_small_enemies(2)
	var early_ok := true
	var early_names: Array = []
	for e in early_enemies:
		early_names.append(e.character_name)
		if not ["训练兵", "铁盾兵", "爆破手", "术师", "医疗兵"].has(e.character_name):
			early_ok = false
	_assert(early_ok, "2b: 第1-2轮只有M1-M5（实际=%s）" % str(early_names))

	# 验证第3-4轮可能出现M6-M8
	var found_late := false
	for seed_val in range(200, 300):
		tower.set_seed(seed_val)
		var late_enemies := tower._generate_small_enemies(10)
		for e in late_enemies:
			if ["狂战士", "影刃", "石像鬼"].has(e.character_name):
				found_late = true
				break
		if found_late:
			break
	_assert(found_late, "2c: 第3-4轮可出现M6-M8")

	# 后期小怪 HP 递增：第3轮（floor=10）生成的训练兵 HP 应为 4+4=8
	var has_boosted_hp := false
	for seed_val in range(300, 320):
		tower.set_seed(seed_val)
		var late_enemies2 := tower._generate_small_enemies(10)
		for e in late_enemies2:
			var base := 0.0
			match e.character_name:
				"训练兵": base = 4.0
				"铁盾兵": base = 6.0
				"爆破手": base = 3.0
				"术师": base = 5.0
				"医疗兵": base = 5.0
				"狂战士": base = 6.0
				"影刃": base = 4.0
				"石像鬼": base = 8.0
			if base > 0.0 and e.max_hp > base:
				has_boosted_hp = true
				break
		if has_boosted_hp:
			break
	_assert(has_boosted_hp, "2d: 第3轮小怪HP高于基础值（实际存在HP加成）")

	tower.queue_free()

# ═════════ 测试3：精英怪固定顺序不重复 ═════════════════════
func _test_elite_order() -> void:
	print("--- 测试3：精英怪顺序 ---")
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	var floors: Array = []
	tower.floor_changed.connect(func(f: int, name: String): floors.append([f, name]))

	tower.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame

	# 推进到第4层（精英层）：连续通过3层小怪
	for _i in range(3):
		var enemies: Array = GameManager.get_alive_players().filter(func(p): return p.team_id == 2)
		for e in enemies:
			e.hp = 0.0
		GameManager.call("_check_elimination")
		await get_tree().process_frame

	# 现在应该在精英层（第4层）
	_assert(tower.get_current_floor() == 4, "3a: 第4层=精英层（实际=%d）" % tower.get_current_floor())
	var elite1_name := tower.get_current_enemy_name()
	_assert(elite1_name == "破败王者（怒）", "3b: 第4层精英=破败王者（实际=%s）" % elite1_name)

	tower.queue_free()

# ═════════ 测试4：大Boss层跳过=通关 ═══════════════════════
func _test_boss_floor_skip() -> void:
	print("--- 测试4：大Boss层跳过 ---")
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	var victory: Array = []
	tower.tower_victory.connect(func(): victory.append(true))

	tower.start_tower([{ "character": naruto_char, "is_human": true }])
	await get_tree().process_frame

	# 快速推进前12层（小怪+精英）
	for _i in range(12):
		var enemies: Array = GameManager.get_alive_players().filter(func(p): return p.team_id == 2)
		for e in enemies:
			e.hp = 0.0
		GameManager.call("_check_elimination")
		await get_tree().process_frame
		if not tower.is_running():
			break

	# 推进到第13-15层小怪
	for _i in range(3):
		if not tower.is_running():
			break
		var enemies: Array = GameManager.get_alive_players().filter(func(p): return p.team_id == 2)
		for e in enemies:
			e.hp = 0.0
		GameManager.call("_check_elimination")
		await get_tree().process_frame

	# 第16层=大Boss → 应该跳过=通关
	_assert(victory.size() == 1, "4a: 第16层跳过触发通关（实际=%d）" % victory.size())

	tower.queue_free()

# ═════════ 测试5：小怪数据完整性 ═══════════════════════════
func _test_small_enemy_data() -> void:
	print("--- 测试5：小怪数据完整性 ---")
	var paths := {
		"训练兵": "res://resources/characters/tower/训练兵.tres",
		"铁盾兵": "res://resources/characters/tower/铁盾兵.tres",
		"爆破手": "res://resources/characters/tower/爆破手.tres",
		"术师": "res://resources/characters/tower/术师.tres",
		"医疗兵": "res://resources/characters/tower/医疗兵.tres",
		"狂战士": "res://resources/characters/tower/狂战士.tres",
		"影刃": "res://resources/characters/tower/影刃.tres",
		"石像鬼": "res://resources/characters/tower/石像鬼.tres",
	}
	var expected_hp := {
		"训练兵": 4.0, "铁盾兵": 6.0, "爆破手": 3.0, "术师": 5.0,
		"医疗兵": 5.0, "狂战士": 6.0, "影刃": 4.0, "石像鬼": 8.0,
	}
	var expected_skill_count := {
		"训练兵": 2, "铁盾兵": 3, "爆破手": 3, "术师": 3,
		"医疗兵": 3, "狂战士": 3, "影刃": 3, "石像鬼": 3,
	}

	for name in paths:
		var char_data := load(paths[name]) as CharacterData
		if char_data == null:
			_assert(false, "5a: %s 加载失败" % name)
			continue
		_assert(char_data.character_name == name, "5b: %s 名称正确" % name)
		_assert(char_data.max_hp == expected_hp[name], "5c: %s HP=%d（实际=%.1f）" % [name, expected_hp[name], char_data.max_hp])
		_assert(char_data.skills.size() == expected_skill_count[name], "5d: %s 技能数=%d（实际=%d）" % [name, expected_skill_count[name], char_data.skills.size()])
		# 所有小怪必须有尖塔祝福被动
		var has_blessing := false
		for s in char_data.skills:
			if s.is_passive and s.skill_name == "尖塔祝福":
				has_blessing = true
		_assert(has_blessing, "5e: %s 有尖塔祝福" % name)
		# 普攻必须存在且非被动
		var has_basic_attack := false
		for s in char_data.skills:
			if s.skill_name == "普攻" and not s.is_passive:
				has_basic_attack = true
		_assert(has_basic_attack, "5f: %s 有普攻" % name)

# ═════════ 测试6：多怪战斗（setup_game 支持多敌人） ════════
func _test_multi_enemy_battle(naruto_char: CharacterData) -> void:
	print("--- 测试6：多怪战斗 ---")
	var gm := GameManager

	# 用2只小怪测试 setup_game 多敌人支持
	var trainee := load("res://resources/characters/tower/训练兵.tres") as CharacterData
	var mage := load("res://resources/characters/tower/术师.tres") as CharacterData

	gm.setup_game({
		"players": [
			{ "name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1 },
			{ "name": "训练兵", "character": trainee, "is_human": false, "team_id": 2 },
			{ "name": "术师", "character": mage, "is_human": false, "team_id": 2 },
		],
		"tower_mode": true,
	})
	await get_tree().process_frame

	var team1 := gm.get_alive_players().filter(func(p): return p.team_id == 1)
	var team2 := gm.get_alive_players().filter(func(p): return p.team_id == 2)
	_assert(team1.size() == 1, "6a: 玩家队1人（实际=%d）" % team1.size())
	_assert(team2.size() == 2, "6b: 敌人队2人（实际=%d）" % team2.size())

	# 两只小怪都有尖塔祝福2气
	for e in team2:
		_assert(e.energy == 2, "6c: %s 尖塔祝福2气（实际=%d）" % [e.character.character_name, e.energy])

	# 杀一只小怪 → 另一只还活着 → 不触发game_over
	team2[0].hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	var still_alive := gm.get_alive_players().filter(func(p): return p.team_id == 2)
	_assert(still_alive.size() == 1, "6d: 杀1只后剩1只（实际=%d）" % still_alive.size())

	# 杀第二只 → 敌人全灭 → game_over
	still_alive[0].hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame
	var remaining := gm.get_alive_players().filter(func(p): return p.team_id == 2)
	_assert(remaining.size() == 0, "6e: 全杀后敌人队清空（实际=%d）" % remaining.size())

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
