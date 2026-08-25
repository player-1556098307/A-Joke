## 慈悲尖塔层间奖励选择测试
## 覆盖：PlayerState buff 字段、round_resolver 增伤/减伤、
##       game_manager 聚气加成/回血、tower_battle buff 注入、
##       TowerRewardUI 奖励池/随机选择、buff 持久化
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 慈悲尖塔层间奖励测试 ===")
	await get_tree().process_frame

	await _test_player_state_buff_fields()
	await _test_damage_bonus_basic()
	await _test_damage_reduction()
	await _test_charge_bonus()
	await _test_regen_per_round()
	await _test_inject_tower_buffs()
	await _test_reward_ui_pool()
	await _test_reward_ui_random_pick()
	await _test_buff_persistence()
	await _test_all_buff_types_inject()
	await _test_ai_auto_select_buff()
	await _test_consumed_limited_buff()
	await _test_pojun_crit()
	await _test_bati_immune()
	await _test_death_protection()

	print("=== 塔奖励测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 测试1：PlayerState 新增 buff 字段默认值
func _test_player_state_buff_fields() -> void:
	print("--- PlayerState buff 字段默认值 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var p := PlayerState.new(0, "测试", char_data, true)
	_assert(p.damage_bonus_basic == 0.0, "1a: damage_bonus_basic 默认0")
	_assert(p.charge_bonus == 0, "1b: charge_bonus 默认0")
	_assert(p.damage_reduction == 0.0, "1c: damage_reduction 默认0")
	_assert(p.regen_per_round == 0.0, "1d: regen_per_round 默认0")
	_assert(p.max_hp_bonus == 0.0, "1e: max_hp_bonus 默认0")
	_assert(p.start_energy_bonus == 0, "1f: start_energy_bonus 默认0")
	_assert(p.get_max_hp() == p.character.max_hp, "1g: get_max_hp 默认=角色原始上限")

## 测试2：damage_bonus_basic 普攻增伤
func _test_damage_bonus_basic() -> void:
	print("--- damage_bonus_basic 普攻增伤 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var attacker := PlayerState.new(0, "攻击者", char_data, true)
	var target := PlayerState.new(1, "目标", char_data, false)
	attacker.damage_bonus_basic = 1.0  # 锋刃之力 +1

	# 构建普攻效果（value=1）
	var effect := SkillEffect.new()
	effect.effect_type = SkillEffect.EffectType.DAMAGE
	effect.value = 1.0
	effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE

	var dist := DistanceSystem.new()
	dist.setup([0, 1])

	var hp_before := target.hp
	RoundResolver.apply_effect_standalone(effect, attacker, target, dist)
	var hp_after := target.hp
	var actual_dmg := hp_before - hp_after

	# 普攻1 + 增伤1 = 2
	_assert(actual_dmg == 2.0, "2a: 普攻1+增伤1=2伤（实际=%.1f）" % actual_dmg)

## 测试3：damage_reduction 固定减伤
func _test_damage_reduction() -> void:
	print("--- damage_reduction 固定减伤 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var attacker := PlayerState.new(0, "攻击者", char_data, true)
	var target := PlayerState.new(1, "目标", char_data, false)
	target.damage_reduction = 1.0  # 坚壁 -1

	# 构建伤害效果（value=3）
	var effect := SkillEffect.new()
	effect.effect_type = SkillEffect.EffectType.DAMAGE
	effect.value = 3.0
	effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE

	var dist := DistanceSystem.new()
	dist.setup([0, 1])

	var hp_before := target.hp
	RoundResolver.apply_effect_standalone(effect, attacker, target, dist)
	var hp_after := target.hp
	var actual_dmg := hp_before - hp_after

	# 伤害3 - 减伤1 = 2
	_assert(actual_dmg == 2.0, "3a: 伤害3-减伤1=2伤（实际=%.1f）" % actual_dmg)

	# 减伤不会使伤害变为负数
	target.damage_reduction = 10.0  # 减伤 > 伤害
	var effect2 := SkillEffect.new()
	effect2.effect_type = SkillEffect.EffectType.DAMAGE
	effect2.value = 3.0
	effect2.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var hp_before2 := target.hp
	RoundResolver.apply_effect_standalone(effect2, attacker, target, dist)
	var actual_dmg2 := hp_before2 - target.hp
	_assert(actual_dmg2 == 0.0, "3b: 减伤>伤害时伤害=0（实际=%.1f）" % actual_dmg2)

## 测试4：charge_bonus 聚气加成
func _test_charge_bonus() -> void:
	print("--- charge_bonus 聚气加成 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	SceneManager.last_tower_config["tower_buffs"] = [
		{ "id": "charge_bonus", "value": 1 }
	]
	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "4a: 玩家存在")
	if player == null:
		tower.queue_free()
		return

	# 手动注入 charge_bonus buff
	player.charge_bonus = 1

	# 模拟聚气：调用 _apply_actions 中的聚气逻辑
	# 先设置玩家为唯一赢家
	gm.set("_sole_winner_id", player.player_id)
	player.pending_action = PlayerState.ActionType.CHARGE

	# 记录聚气前能量
	var energy_before := player.energy
	gm.call("_apply_actions")
	await get_tree().process_frame

	# 普通聚气=1 + charge_bonus=1 = 2
	var energy_gain := player.energy - energy_before
	_assert(energy_gain == 2, "4b: 聚气1+charge_bonus1=2气（实际=%d）" % energy_gain)

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs")
	tower.queue_free()

## 测试5：regen_per_round 回血
func _test_regen_per_round() -> void:
	print("--- regen_per_round 回血 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "5a: 玩家存在")
	if player == null:
		tower.queue_free()
		return

	# 设置玩家受伤 + 回生 buff
	player.hp = player.hp - 3.0  # 受3点伤
	player.regen_per_round = 1.0
	var hp_before := player.hp

	# 调用 _process_tower_regen（行动权拥有者回合开始时）
	gm.call("_process_tower_regen", player)
	await get_tree().process_frame

	var heal := player.hp - hp_before
	_assert(heal == 1.0, "5b: 回生自己回合开始回1血（实际=%.1f）" % heal)

	# 满血时不回血
	player.hp = player.get_max_hp()
	var hp_full := player.hp
	gm.call("_process_tower_regen", player)
	_assert(player.hp == hp_full, "5c: 满血时不回血（实际=%.1f→%.1f）" % [hp_full, player.hp])

	# 回血量不会超过生命上限（vitality 提升上限后正常）
	player.hp = player.get_max_hp() - 0.5
	gm.call("_process_tower_regen", player)
	_assert(player.hp == player.get_max_hp(), "5d: 回血不超过上限（实际=%.1f）" % player.hp)

	tower.queue_free()

## 测试6：tower_battle._inject_tower_buffs 注入逻辑
func _test_inject_tower_buffs() -> void:
	print("--- tower_battle buff 注入 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	# 设置 buff 列表（shield_wall 已平衡为 0.5）
	SceneManager.last_tower_config["tower_buffs"] = [
		{ "id": "blade_power", "value": 1.0 },
		{ "id": "shield_wall", "value": 0.5 },
		{ "id": "charge_bonus", "value": 1 },
		{ "id": "regen", "value": 1.0 },
		{ "id": "clone", "value": 1 },
		{ "id": "swift", "value": 2 },
		{ "id": "protect", "value": 2 },
		{ "id": "vitality", "value": 1 },
	]

	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "6a: 玩家存在")
	if player == null:
		tower.queue_free()
		return

	# 手动注入 buff（模拟 tower_battle._inject_tower_buffs）
	var buffs: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	for b in buffs:
		match b.get("id", ""):
			"blade_power":
				player.damage_bonus_basic += b.get("value", 1.0)
			"shield_wall":
				player.damage_reduction += b.get("value", 1.0)
			"charge_bonus":
				player.charge_bonus += b.get("value", 1)
			"regen":
				player.regen_per_round += b.get("value", 1.0)
			"clone":
				player.clone_count += b.get("value", 1)
			"swift":
				player.add_energy(b.get("value", 2))
			"protect":
				player.shield += b.get("value", 2)
			"vitality":
				player.max_hp_bonus += b.get("value", 3)
				player.hp += b.get("value", 3)

	_assert(player.damage_bonus_basic == 1.0, "6b: damage_bonus_basic=1（实际=%.1f）" % player.damage_bonus_basic)
	_assert(player.damage_reduction == 0.5, "6c: damage_reduction=0.5（实际=%.1f）" % player.damage_reduction)
	_assert(player.charge_bonus == 1, "6d: charge_bonus=1（实际=%d）" % player.charge_bonus)
	_assert(player.regen_per_round == 1.0, "6e: regen_per_round=1（实际=%.1f）" % player.regen_per_round)
	_assert(player.clone_count == 1, "6f: clone_count=1（实际=%d）" % player.clone_count)
	_assert(player.energy == 2, "6g: swift开局+2气（实际=%d）" % player.energy)
	_assert(player.shield == 2, "6h: shield=2（实际=%d）" % player.shield)
	_assert(player.max_hp_bonus == 1.0, "6i: max_hp_bonus=1（实际=%.1f）" % player.max_hp_bonus)
	_assert(player.get_max_hp() == player.character.max_hp + 1.0, "6j: get_max_hp=原始上限+1（实际=%.1f）" % player.get_max_hp())

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs")
	tower.queue_free()

## 测试7：TowerRewardUI 奖励池完整性
func _test_reward_ui_pool() -> void:
	print("--- TowerRewardUI 奖励池 ---")
	var ui := TowerRewardUI.new()
	add_child(ui)

	var pool := ui.get_reward_pool()
	_assert(pool.size() == 20, "7a: 奖励池20种（实际=%d）" % pool.size())

	# 每个奖励都有 tier 字段，且只允许 normal/elite 两种值
	for i in range(pool.size()):
		var tier: String = pool[i].get("tier", "")
		_assert(tier == "normal" or tier == "elite", "7a%d: 奖励%d的tier合法=%s" % [i, i, tier])

	# 每个奖励都有必要字段
	var ids_seen: Array[String] = []
	for i in range(pool.size()):
		var r: Dictionary = pool[i]
		_assert(r.has("id"), "7b%d: 奖励%d有id" % [i, i])
		_assert(r.has("name"), "7c%d: 奖励%d有name" % [i, i])
		_assert(r.has("desc"), "7d%d: 奖励%d有desc" % [i, i])
		_assert(r.has("icon"), "7e%d: 奖励%d有icon" % [i, i])
		_assert(r.has("value"), "7f%d: 奖励%d有value" % [i, i])
		var rid: String = r.get("id", "")
		_assert(not rid in ids_seen, "7g%d: 奖励id不重复=%s" % [i, rid])
		ids_seen.append(rid)

	# 检查所有 id 都存在
	var expected_ids := ["blade_power", "charge_bonus", "shield_wall", "regen", "clone", "swift", "protect", "vitality", "blade_power_2", "regen_2", "swift_2", "vitality_2", "protect_2", "lifesteal", "soul_slash", "spring", "immortal_medal", "pojun", "bati", "niepan"]
	for eid in expected_ids:
		_assert(eid in ids_seen, "7h: 奖励id=%s 存在" % eid)

	# 气上限祝福已删除（气海/天罡）
	_assert(not "energy_cap" in ids_seen, "7h1: energy_cap 已删除")
	_assert(not "energy_cap_2" in ids_seen, "7h2: energy_cap_2 已删除")

	# normal 池 11 种（含回生回归+免死金牌），elite 池 9 种（含破军/霸体/涅槃+再生unique）
	var normal_count := 0
	var elite_count := 0
	for r in pool:
		if r.get("tier", "normal") == "elite":
			elite_count += 1
		else:
			normal_count += 1
	_assert(normal_count == 11, "7i: normal池11种（实际=%d）" % normal_count)
	_assert(elite_count == 9, "7j: elite池9种（实际=%d）" % elite_count)

	# unique 字段校验：蓄锐/坚壁/回生/再生/影分身/嗜血/斩魂/回春/免死金牌/破军/霸体/涅槃 必须为 unique
	var unique_map := {}
	for r in pool:
		if r.get("unique", false):
			unique_map[r.get("id", "")] = true
	_assert(unique_map.has("charge_bonus"), "7k: charge_bonus 为唯一祝福")
	_assert(unique_map.has("shield_wall"), "7l: shield_wall 为唯一祝福")
	_assert(unique_map.has("regen"), "7m: regen 为唯一祝福")
	_assert(unique_map.has("regen_2"), "7m0: regen_2 为唯一祝福")
	_assert(unique_map.has("clone"), "7m2: clone 为唯一祝福")
	_assert(unique_map.has("lifesteal"), "7m3: lifesteal 为唯一祝福")
	_assert(unique_map.has("soul_slash"), "7m4: soul_slash 为唯一祝福")
	_assert(unique_map.has("spring"), "7m5: spring 为唯一祝福")
	_assert(unique_map.has("immortal_medal"), "7m6: immortal_medal 为唯一祝福")
	_assert(unique_map.has("pojun"), "7m7: pojun 为唯一祝福")
	_assert(unique_map.has("bati"), "7m8: bati 为唯一祝福")
	_assert(unique_map.has("niepan"), "7m9: niepan 为唯一祝福")
	_assert(unique_map.size() == 12, "7n: 唯一祝福共12个（实际=%d）" % unique_map.size())

	ui.queue_free()

## 测试8：TowerRewardUI 随机选择不重复
func _test_reward_ui_random_pick() -> void:
	print("--- TowerRewardUI 随机选择 ---")
	# 测试 _pick_random_rewards 返回不重复的 3 个
	var ui := TowerRewardUI.new()
	add_child(ui)

	# 多次随机验证不重复
	var all_unique := true
	for _i in range(20):
		var choices = ui._pick_random_rewards(3)
		var ids: Array[String] = []
		for c in choices:
			ids.append(c.get("id", ""))
		if ids.size() != 3:
			all_unique = false
			break
		var seen: Array[String] = []
		for id in ids:
			if id in seen:
				all_unique = false
				break
			seen.append(id)
	_assert(all_unique, "8a: 20次随机3选均不重复")

	# 选择的 3 个都在奖励池中
	var pool := ui.get_reward_pool()
	var pool_ids: Array[String] = []
	for r in pool:
		pool_ids.append(r.get("id", ""))
	var choices = ui._pick_random_rewards(3)
	var all_in_pool := true
	for c in choices:
		if not c.get("id", "") in pool_ids:
			all_in_pool = false
			break
	_assert(all_in_pool, "8b: 选择的奖励都在池中")

	# --- 分级验证：默认（小怪层）只出 normal ---
	var only_normal := true
	for _i in range(20):
		var choices2 = ui._pick_random_rewards(3, false)
		for c in choices2:
			if c.get("tier", "normal") != "normal":
				only_normal = false
				break
		if not only_normal:
			break
	_assert(only_normal, "8c: allow_elite=false 只出普通祝福")

	# --- 分级：allow_elite=true 时 20 次中应出现 elite ---
	var saw_elite := false
	for _i in range(20):
		var choices3 = ui._pick_random_rewards(3, true)
		for c in choices3:
			if c.get("tier", "normal") == "elite":
				saw_elite = true
				break
		if saw_elite:
			break
	_assert(saw_elite, "8d: allow_elite=true 可抽到高级祝福")

	# --- 分级：allow_elite=true 抽取的都在全池中 ---
	var all_in_full_pool := true
	for _i in range(20):
		var choices4 = ui._pick_random_rewards(3, true)
		for c in choices4:
			if not c.get("id", "") in pool_ids:
				all_in_full_pool = false
				break
		if not all_in_full_pool:
			break
	_assert(all_in_full_pool, "8e: allow_elite=true 抽取的奖励都在全池中")

	# --- unique：已获取的唯一祝福不再出现 ---
	# 蓄锐已获取 → 20 次抽取都不应再出现 charge_bonus
	var obtained := ["charge_bonus"]
	var no_obtained_unique := true
	for _i in range(30):
		var choices5 := ui._pick_random_rewards(3, true, obtained)
		for c in choices5:
			if c.get("id", "") == "charge_bonus":
				no_obtained_unique = false
				break
		if not no_obtained_unique:
			break
	_assert(no_obtained_unique, "8f: 已获取的unique祝福不再出现")

	# 已获取的非 unique 祝福仍可出现（blade_power）
	var obtained2 := ["blade_power"]
	var saw_non_unique := false
	for _i in range(30):
		var choices6 := ui._pick_random_rewards(3, true, obtained2)
		for c in choices6:
			if c.get("id", "") == "blade_power":
				saw_non_unique = true
				break
		if saw_non_unique:
			break
	_assert(saw_non_unique, "8g: 已获取的非唯一祝福仍可出现")

	# 蓄锐/坚壁/回生 全部获取后，normal+elite 全池抽取时均不出现
	var obtained3 := ["charge_bonus", "shield_wall", "regen"]
	var none_obtained := true
	for _i in range(30):
		var choices7 := ui._pick_random_rewards(3, true, obtained3)
		for c in choices7:
			if c.get("id", "") in obtained3:
				none_obtained = false
				break
		if not none_obtained:
			break
	_assert(none_obtained, "8h: 3个唯一祝福全获取后均不再出现")

	ui.queue_free()

## 测试9：buff 持久化到 SceneManager
func _test_buff_persistence() -> void:
	print("--- buff 持久化到 SceneManager ---")
	# 清空 tower_buffs
	SceneManager.last_tower_config.erase("tower_buffs")

	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	# 第一层启动
	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	# 模拟选择了一个 buff
	var buff := { "id": "blade_power", "value": 1.0 }
	var buffs: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	buffs.append(buff)
	SceneManager.last_tower_config["tower_buffs"] = buffs

	# 验证持久化
	var stored: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	_assert(stored.size() == 1, "9a: buff已持久化（size=%d）" % stored.size())
	_assert(stored[0].get("id", "") == "blade_power", "9b: 持久化的buff id正确")

	# 模拟第二层：buff 应该在新层注入
	_kill_all_enemies(gm)
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "9c: 第二层玩家存在")
	if player != null:
		# 手动注入
		for b in stored:
			if b.get("id", "") == "blade_power":
				player.damage_bonus_basic += b.get("value", 1.0)
		_assert(player.damage_bonus_basic == 1.0, "9d: 第二层注入buff后damage_bonus_basic=1（实际=%.1f）" % player.damage_bonus_basic)

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs")
	tower.queue_free()

## 测试10：所有 buff 类型注入验证
func _test_all_buff_types_inject() -> void:
	print("--- 所有 buff 类型注入验证 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "10a: 玩家存在")
	if player == null:
		tower.queue_free()
		return

	# 逐个验证 10 种 buff 的注入
	# blade_power
	player.damage_bonus_basic = 0.0
	_apply_single_buff(player, { "id": "blade_power", "value": 1.0 })
	_assert(player.damage_bonus_basic == 1.0, "10b: blade_power注入")

	# charge_bonus
	player.charge_bonus = 0
	_apply_single_buff(player, { "id": "charge_bonus", "value": 1 })
	_assert(player.charge_bonus == 1, "10c: charge_bonus注入")

	# shield_wall
	player.damage_reduction = 0.0
	_apply_single_buff(player, { "id": "shield_wall", "value": 0.5 })
	_assert(player.damage_reduction == 0.5, "10d: shield_wall=0.5注入")

	# regen
	player.regen_per_round = 0.0
	_apply_single_buff(player, { "id": "regen", "value": 1.0 })
	_assert(player.regen_per_round == 1.0, "10e: regen注入")

	# clone
	player.clone_count = 0
	_apply_single_buff(player, { "id": "clone", "value": 1 })
	_assert(player.clone_count == 1, "10f: clone注入")

	# swift
	player.energy = 0
	_apply_single_buff(player, { "id": "swift", "value": 2 })
	_assert(player.energy == 2, "10g: swift注入")

	# protect
	player.shield = 0
	_apply_single_buff(player, { "id": "protect", "value": 2 })
	_assert(player.shield == 2, "10i: protect注入")

	# vitality（生机）：生命上限+1，并同步补血
	var base_max := player.get_max_hp()
	var hp_before_v := player.hp
	player.max_hp_bonus = 0.0
	_apply_single_buff(player, { "id": "vitality", "value": 1 })
	_assert(player.max_hp_bonus == 1.0, "10j: vitality提升max_hp_bonus=1")
	_assert(player.get_max_hp() == player.character.max_hp + 1.0, "10k: vitality后get_max_hp正确")
	_assert(player.hp == hp_before_v + 1.0, "10l: vitality同步补血+1")

	# vitality_2（龙血）：生命上限+3
	player.max_hp_bonus = 0.0
	_apply_single_buff(player, { "id": "vitality_2", "value": 3 })
	_assert(player.max_hp_bonus == 3.0, "10m: vitality_2提升max_hp_bonus=3")

	# blade_power_2（锋芒/精英）：普攻+2
	player.damage_bonus_basic = 0.0
	_apply_single_buff(player, { "id": "blade_power_2", "value": 2.0 })
	_assert(player.damage_bonus_basic == 2.0, "10p: blade_power_2注入")

	# regen_2（再生/精英）：回2血
	player.regen_per_round = 0.0
	_apply_single_buff(player, { "id": "regen_2", "value": 2.0 })
	_assert(player.regen_per_round == 2.0, "10q: regen_2注入")

	# swift_2（疾风/精英）：开局+5气
	player.energy = 0
	_apply_single_buff(player, { "id": "swift_2", "value": 5 })
	_assert(player.energy == 5, "10r: swift_2注入")

	# protect_2（铁壁/精英）：5护盾
	player.shield = 0
	_apply_single_buff(player, { "id": "protect_2", "value": 5 })
	_assert(player.shield == 5, "10t: protect_2注入")

	# ── 新增祝福注入验证 ──
	# immortal_medal（免死金牌）：一次性被动
	player.immortal_medal = false
	_apply_single_buff(player, { "id": "immortal_medal", "value": 1.0 })
	_assert(player.immortal_medal == true, "10u: immortal_medal注入")

	# pojun（破军）：普攻可暴击
	player.pojun_active = false
	_apply_single_buff(player, { "id": "pojun", "value": 1.0 })
	_assert(player.pojun_active == true, "10v: pojun注入")

	# bati（霸体）：免疫控制
	player.bati_active = false
	_apply_single_buff(player, { "id": "bati", "value": 1.0 })
	_assert(player.bati_active == true, "10w: bati注入")

	# niepan（涅槃）：死亡半血重生
	player.niepan_active = false
	_apply_single_buff(player, { "id": "niepan", "value": 1.0 })
	_assert(player.niepan_active == true, "10x: niepan注入")

	tower.queue_free()

## 测试11：AI队友自动选祝福（不弹窗，自动随机选择）
func _test_ai_auto_select_buff() -> void:
	print("--- AI自动选祝福 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var char_data2 := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	# 配置：1人类 + 1AI队友
	SceneManager.last_tower_config.erase("tower_buffs")
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	SceneManager.last_tower_config["players"] = [
		{ "character": char_data, "is_human": true },
		{ "character": char_data2, "is_human": false },
	]

	# 实例化 tower_battle（fast_mode=true 快速过场）
	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	battle.fast_mode = true
	add_child(battle)
	await get_tree().process_frame

	# 等待第1层战斗启动
	for i in range(900):
		await get_tree().process_frame
		if battle._phase == "battle":
			break

	_assert(battle._phase == "battle", "11a: 第1层战斗已启动（实际=%s）" % battle._phase)

	# 直接调用 _show_reward_selection 模拟层胜利后的祝福选择
	# 设置 _party_size 并手动触发 reward 流程
	battle._party_size = 2
	battle._reward_player_index = 0
	# fast_mode 下 _show_reward_for_current_player 自动选第一个buff
	# 角色0（人类，fast_mode自动选）→ 角色1（AI，应自动选）→ 完成
	battle._phase = "reward"
	battle._show_reward_for_current_player()
	await get_tree().process_frame
	# fast_mode 下角色0立即自动选完，应推进到角色1
	await get_tree().process_frame

	# 等待所有角色选完（reward阶段结束）
	for i in range(100):
		await get_tree().process_frame
		if battle._phase != "reward":
			break

	# 验证两个角色都获得了 bless（per_player 数组有2个元素）
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	_assert(per_player.size() == 2, "11b: 2个角色各有祝福列表（实际=%d）" % per_player.size())
	if per_player.size() >= 2:
		_assert(per_player[0] is Array and per_player[0].size() >= 1, "11c: 角色0获得祝福")
		_assert(per_player[1] is Array and per_player[1].size() >= 1, "11d: 角色1（AI）获得祝福")
		# AI获得的祝福在池中
		var ai_buff: Dictionary = per_player[1][0]
		var ai_id: String = ai_buff.get("id", "")
		var pool_ids: Array[String] = []
		for r in TowerRewardUI.REWARD_POOL:
			pool_ids.append(r.get("id", ""))
		_assert(ai_id in pool_ids, "11e: AI祝福在池中（id=%s）" % ai_id)

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	battle.queue_free()

# ═════════ 辅助函数 ═══════════════════════════════════════

## 测试12：一次性技能祝福（斩魂/回春）消耗品逻辑
## 用完一次永久失效（跨层不可再用），用完后从持有列表移除→祝福池可再次随机到
func _test_consumed_limited_buff() -> void:
	print("--- 一次性技能祝福消耗品逻辑 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs")
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	SceneManager.last_tower_config["players"] = [
		{ "character": char_data, "is_human": true },
	]

	# 初始化：玩家持有斩魂祝福
	SceneManager.last_tower_config["tower_buffs_per_player"] = [
		[{ "id": "soul_slash", "value": 5.0 }]
	]

	# 用 tower_battle（fast_mode）管理整个流程，确保 _inject_tower_buffs 被调用
	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	battle.fast_mode = true
	add_child(battle)
	await get_tree().process_frame

	# 等待第1层战斗启动
	for i in range(900):
		await get_tree().process_frame
		if battle._phase == "battle":
			break

	var player := _get_player(gm)
	_assert(player != null, "12a: 玩家存在")
	if player == null:
		battle.queue_free()
		return

	# 验证斩魂技能已注入 unlocked_skills（_inject_tower_buffs 在 _begin_floor_battle 中调用）
	var has_skill := false
	for s in player.get_all_skills():
		if s.skill_name == "斩魂":
			has_skill = true
			break
	_assert(has_skill, "12b: 斩魂技能已注入可用")

	# 模拟使用斩魂：手动将技能名加入 limited_skills_used
	player.limited_skills_used.append("斩魂")

	# 验证用完后 get_all_skills 不再返回斩魂
	var still_has := false
	for s in player.get_all_skills():
		if s.skill_name == "斩魂":
			still_has = true
			break
	_assert(not still_has, "12c: 斩魂用完后从技能列表消失")

	# 调用清理函数（模拟换层前清理）
	battle._cleanup_consumed_limited_buffs()
	await get_tree().process_frame

	# 验证斩魂已从持久化列表移除
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	_assert(per_player.size() == 1, "12d: 持久化列表仍有1个角色")
	if per_player.size() >= 1 and per_player[0] is Array:
		var soul_slash_remaining := false
		for b in per_player[0]:
			if b is Dictionary and b.get("id", "") == "soul_slash":
				soul_slash_remaining = true
				break
		_assert(not soul_slash_remaining, "12e: 斩魂已从持久化列表移除（用完即弃）")
	else:
		_assert(false, "12e: 持久化列表结构异常")

	# 验证斩魂重新回到祝福池（不在 obtained_ids 中 → 可随机到）
	var obtained_ids: Array = []
	for buffs in per_player:
		if buffs is Array:
			for b in buffs:
				if b is Dictionary and b.has("id"):
					obtained_ids.append(b.get("id"))
	_assert(not "soul_slash" in obtained_ids, "12f: 斩魂不在obtained_ids中→祝福池可再随机到")

	# 验证祝福池包含斩魂（通过 _pick_random_rewards 验证可抽到）
	var ui := TowerRewardUI.new()
	add_child(ui)
	var can_pick_soul_slash := false
	for _i in range(50):
		var choices = ui._pick_random_rewards(3, false, obtained_ids)
		for c in choices:
			if c.get("id", "") == "soul_slash":
				can_pick_soul_slash = true
				break
		if can_pick_soul_slash:
			break
	_assert(can_pick_soul_slash, "12g: 斩魂用完后可在祝福池中再次随机到")

	# 对照组：未使用的斩魂保持在列表中（不清理）
	# 重置：给玩家一个未使用的斩魂，且 limited_skills_used 为空
	SceneManager.last_tower_config["tower_buffs_per_player"] = [
		[{ "id": "soul_slash", "value": 5.0 }]
	]
	player.limited_skills_used.clear()
	battle._cleanup_consumed_limited_buffs()
	var per_player2: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	var soul_slash_kept := false
	if per_player2.size() >= 1 and per_player2[0] is Array:
		for b in per_player2[0]:
			if b is Dictionary and b.get("id", "") == "soul_slash":
				soul_slash_kept = true
				break
	_assert(soul_slash_kept, "12h: 未使用的斩魂保持在列表中（不被清理）")

	# 回春同理：用完后从列表移除
	SceneManager.last_tower_config["tower_buffs_per_player"] = [
		[{ "id": "spring", "value": 5.0 }]
	]
	player.limited_skills_used.clear()
	player.limited_skills_used.append("回春")
	battle._cleanup_consumed_limited_buffs()
	var per_player3: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	var spring_removed := true
	if per_player3.size() >= 1 and per_player3[0] is Array:
		for b in per_player3[0]:
			if b is Dictionary and b.get("id", "") == "spring":
				spring_removed = false
				break
	_assert(spring_removed, "12i: 回春用完后从持久化列表移除")

	# 非限定技祝福不受影响（blade_power 不在清理范围）
	SceneManager.last_tower_config["tower_buffs_per_player"] = [
		[{ "id": "blade_power", "value": 1.0 }, { "id": "soul_slash", "value": 5.0 }]
	]
	player.limited_skills_used.clear()
	player.limited_skills_used.append("斩魂")
	battle._cleanup_consumed_limited_buffs()
	var per_player4: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	var blade_kept := false
	var soul_removed2 := true
	if per_player4.size() >= 1 and per_player4[0] is Array:
		for b in per_player4[0]:
			if b is Dictionary:
				if b.get("id", "") == "blade_power":
					blade_kept = true
				if b.get("id", "") == "soul_slash":
					soul_removed2 = false
	_assert(blade_kept, "12j: 非限定技祝福(blade_power)不受清理影响")
	_assert(soul_removed2, "12k: 斩魂被清理，blade_power保留")

	ui.queue_free()
	battle.queue_free()
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	SceneManager.last_tower_config.erase("players")

# ═════════ 辅助函数 ═══════════════════════════════════════

## 获取玩家 PlayerState
func _get_player(gm: Variant) -> PlayerState:
	for p in gm.get_alive_players():
		if p.team_id == 1:
			return p
	return null

## 杀死所有敌方单位并触发淘汰检查
func _kill_all_enemies(gm: Variant) -> void:
	for p in gm.get_alive_players():
		if p.team_id == 2:
			p.hp = 0.0
	gm.call("_check_elimination")

## 应用单个 buff（与 tower_battle._apply_buff 逻辑一致）
func _apply_single_buff(p: PlayerState, buff: Dictionary) -> void:
	match buff.get("id", ""):
		"blade_power", "blade_power_2":
			p.damage_bonus_basic += buff.get("value", 1.0)
		"charge_bonus":
			p.charge_bonus += buff.get("value", 1)
		"shield_wall":
			p.damage_reduction += buff.get("value", 1.0)
		"regen", "regen_2":
			p.regen_per_round += buff.get("value", 1.0)
		"clone":
			p.clone_count += buff.get("value", 1)
		"swift", "swift_2":
			p.add_energy(buff.get("value", 2))
		"protect", "protect_2":
			p.shield += buff.get("value", 2)
		"vitality", "vitality_2":
			p.max_hp_bonus += buff.get("value", 3)
			p.hp += buff.get("value", 3)
		"immortal_medal":
			p.immortal_medal = true
		"pojun":
			p.pojun_active = true
		"bati":
			p.bati_active = true
		"niepan":
			p.niepan_active = true

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

## 测试13：破军祝福 — 普攻可暴击（50%概率双倍伤害）
func _test_pojun_crit() -> void:
	print("--- 破军普攻暴击 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var attacker := PlayerState.new(0, "攻击者", char_data, true)
	var target := PlayerState.new(1, "目标", char_data, false)
	attacker.pojun_active = true

	# 构建普攻效果（value=1）
	var effect := SkillEffect.new()
	effect.effect_type = SkillEffect.EffectType.DAMAGE
	effect.value = 1.0
	effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE

	var dist := DistanceSystem.new()
	dist.setup([0, 1])

	# 多次测试：暴击概率约50%，伤害应为1或2
	var crit_count := 0
	var non_crit_count := 0
	for _i in range(100):
		target.hp = target.get_max_hp()
		var hp_before := target.hp
		RoundResolver.apply_effect_standalone(effect, attacker, target, dist, 0, false, "普攻")
		var dmg := hp_before - target.hp
		if dmg == 2.0:
			crit_count += 1
		elif dmg == 1.0:
			non_crit_count += 1
		else:
			_assert(false, "13a: 破军普攻伤害异常=%.1f" % dmg)
			return
	# 暴击应出现（概率约50%，100次中应有暴击）
	_assert(crit_count > 0, "13b: 破军暴击出现过（%d/100）" % crit_count)
	_assert(non_crit_count > 0, "13c: 破军未暴击也出现过（%d/100）" % non_crit_count)

	# 非普攻技能不触发破军暴击
	attacker.pojun_active = true
	var effect2 := SkillEffect.new()
	effect2.effect_type = SkillEffect.EffectType.DAMAGE
	effect2.value = 1.0
	effect2.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var crit_non_basic := 0
	for _i in range(100):
		target.hp = target.get_max_hp()
		var hp_before := target.hp
		RoundResolver.apply_effect_standalone(effect2, attacker, target, dist, 0, false, "螺旋丸")
		var dmg := hp_before - target.hp
		if dmg == 2.0:
			crit_non_basic += 1
	# 非普攻不应触发破军暴击（伤害恒为1）
	_assert(crit_non_basic == 0, "13d: 非普攻技能不触发破军暴击（暴击次数=%d）" % crit_non_basic)

	# 未持有破军时普攻不暴击
	attacker.pojun_active = false
	var crit_no_pojun := 0
	for _i in range(100):
		target.hp = target.get_max_hp()
		var hp_before := target.hp
		RoundResolver.apply_effect_standalone(effect, attacker, target, dist, 0, false, "普攻")
		var dmg := hp_before - target.hp
		if dmg == 2.0:
			crit_no_pojun += 1
	_assert(crit_no_pojun == 0, "13e: 无破军时普攻不暴击（暴击次数=%d）" % crit_no_pojun)

## 测试14：霸体祝福 — 免疫麻痹/击飞/封技
func _test_bati_immune() -> void:
	print("--- 霸体免疫控制 ---")
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var attacker := PlayerState.new(0, "攻击者", char_data, true)
	var target := PlayerState.new(1, "目标", char_data, false)
	target.bati_active = true

	var dist := DistanceSystem.new()
	dist.setup([0, 1])

	# 麻痹免疫
	var paralyze_effect := SkillEffect.new()
	paralyze_effect.effect_type = SkillEffect.EffectType.PARALYZE
	paralyze_effect.value = 2
	paralyze_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var res_p := RoundResolver.apply_effect_standalone(paralyze_effect, attacker, target, dist)
	_assert(target.paralyze_turns == 0, "14a: 霸体免疫麻痹（剩余=%d）" % target.paralyze_turns)
	_assert(res_p.get("bati", false) == true, "14b: 麻痹返回bati标记")

	# 击飞免疫
	var knockdown_effect := SkillEffect.new()
	knockdown_effect.effect_type = SkillEffect.EffectType.KNOCKDOWN
	knockdown_effect.value = 2
	knockdown_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var res_k := RoundResolver.apply_effect_standalone(knockdown_effect, attacker, target, dist)
	_assert(target.knockdown_turns == 0, "14c: 霸体免疫击飞（剩余=%d）" % target.knockdown_turns)
	_assert(res_k.get("bati", false) == true, "14d: 击飞返回bati标记")

	# 封技免疫
	var disable_effect := SkillEffect.new()
	disable_effect.effect_type = SkillEffect.EffectType.DISABLE_SKILL
	disable_effect.value = 2
	disable_effect.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	var res_d := RoundResolver.apply_effect_standalone(disable_effect, attacker, target, dist)
	_assert(target.skill_disabled_turns == 0, "14e: 霸体免疫封技（剩余=%d）" % target.skill_disabled_turns)
	_assert(res_d.get("bati", false) == true, "14f: 封技返回bati标记")

	# 无霸体时正常受控
	target.bati_active = false
	RoundResolver.apply_effect_standalone(paralyze_effect, attacker, target, dist)
	_assert(target.paralyze_turns == 2, "14g: 无霸体时正常受麻痹（剩余=%d）" % target.paralyze_turns)

## 测试15：免死金牌 + 涅槃 — 死亡保护
func _test_death_protection() -> void:
	print("--- 死亡保护：免死金牌/涅槃 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData

	SceneManager.last_tower_config.erase("tower_buffs")
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	SceneManager.last_tower_config["players"] = [
		{ "character": char_data, "is_human": true },
	]
	SceneManager.last_tower_config["tower_mode"] = true

	var tower := TowerManager.new()
	add_child(tower)
	tower.start_tower([{ "character": char_data, "is_human": true }])
	await get_tree().process_frame

	var player := _get_player(gm)
	_assert(player != null, "15a: 玩家存在")
	if player == null:
		tower.queue_free()
		return

	# ── 免死金牌：HP归零时保留1血 ──
	player.immortal_medal = true
	player.hp = 0.0
	var protected: bool = gm.call("_try_tower_death_protection", player)
	_assert(protected == true, "15b: 免死金牌触发保护")
	_assert(player.hp == 1.0, "15c: 免死金牌后HP=1（实际=%.1f）" % player.hp)
	_assert(player.immortal_medal == false, "15d: 免死金牌触发后标记清除")
	_assert(player.is_alive == true, "15e: 免死金牌后仍存活")

	# ── 涅槃：HP归零时半血重生 ──
	player.niepan_active = true
	player.hp = 0.0
	var protected2: bool = gm.call("_try_tower_death_protection", player)
	_assert(protected2 == true, "15f: 涅槃触发保护")
	_assert(player.hp == player.get_max_hp() * 0.5, "15g: 涅槃后半血（实际=%.1f，期望=%.1f）" % [player.hp, player.get_max_hp() * 0.5])
	_assert(player.niepan_active == false, "15h: 涅槃触发后标记清除")
	_assert(player.is_alive == true, "15i: 涅槃后仍存活")

	# ── 两者同时持有时：先消耗免死金牌 ──
	player.immortal_medal = true
	player.niepan_active = true
	player.hp = 0.0
	gm.call("_try_tower_death_protection", player)
	_assert(player.hp == 1.0, "15j: 免死金牌优先于涅槃（HP=1）")
	_assert(player.immortal_medal == false, "15k: 免死金牌先消耗")
	_assert(player.niepan_active == true, "15l: 涅槃未消耗（保留）")

	# ── 无祝福时HP归零不保护 ──
	player.immortal_medal = false
	player.niepan_active = false
	player.hp = 0.0
	var protected3: bool = gm.call("_try_tower_death_protection", player)
	_assert(protected3 == false, "15m: 无祝福时不触发保护")

	# ── HP>0时不触发 ──
	player.immortal_medal = true
	player.hp = 5.0
	var protected4: bool = gm.call("_try_tower_death_protection", player)
	_assert(protected4 == false, "15n: HP>0时不触发免死金牌")
	_assert(player.immortal_medal == true, "15o: HP>0时标记不消耗")

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs_per_player")
	SceneManager.last_tower_config.erase("players")
	SceneManager.last_tower_config.erase("tower_mode")
	tower.queue_free()
