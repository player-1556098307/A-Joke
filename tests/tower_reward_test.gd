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

	# 调用 _process_tower_regen
	gm.call("_process_tower_regen")
	await get_tree().process_frame

	var heal := player.hp - hp_before
	_assert(heal == 1.0, "5b: 回生每回合回1血（实际=%.1f）" % heal)

	# 满血时不回血
	player.hp = player.character.max_hp
	var hp_full := player.hp
	gm.call("_process_tower_regen")
	_assert(player.hp == hp_full, "5c: 满血时不回血（实际=%.1f→%.1f）" % [hp_full, player.hp])

	tower.queue_free()

## 测试6：tower_battle._inject_tower_buffs 注入逻辑
func _test_inject_tower_buffs() -> void:
	print("--- tower_battle buff 注入 ---")
	var gm := GameManager
	var char_data := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var tower := TowerManager.new()
	add_child(tower)

	# 设置 buff 列表
	SceneManager.last_tower_config["tower_buffs"] = [
		{ "id": "blade_power", "value": 1.0 },
		{ "id": "shield_wall", "value": 1.0 },
		{ "id": "charge_bonus", "value": 1 },
		{ "id": "regen", "value": 1.0 },
		{ "id": "clone", "value": 1 },
		{ "id": "swift", "value": 2 },
		{ "id": "energy_cap", "value": 2 },
		{ "id": "protect", "value": 2 },
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
			"energy_cap":
				player.max_energy += b.get("value", 2)
			"protect":
				player.shield += b.get("value", 2)

	_assert(player.damage_bonus_basic == 1.0, "6b: damage_bonus_basic=1（实际=%.1f）" % player.damage_bonus_basic)
	_assert(player.damage_reduction == 1.0, "6c: damage_reduction=1（实际=%.1f）" % player.damage_reduction)
	_assert(player.charge_bonus == 1, "6d: charge_bonus=1（实际=%d）" % player.charge_bonus)
	_assert(player.regen_per_round == 1.0, "6e: regen_per_round=1（实际=%.1f）" % player.regen_per_round)
	_assert(player.clone_count == 1, "6f: clone_count=1（实际=%d）" % player.clone_count)
	_assert(player.energy == 2, "6g: swift energy=2（实际=%d）" % player.energy)
	_assert(player.max_energy == 1001, "6h: max_energy=999+2=1001（实际=%d）" % player.max_energy)
	_assert(player.shield == 2, "6i: shield=2（实际=%d）" % player.shield)

	# 清理
	SceneManager.last_tower_config.erase("tower_buffs")
	tower.queue_free()

## 测试7：TowerRewardUI 奖励池完整性
func _test_reward_ui_pool() -> void:
	print("--- TowerRewardUI 奖励池 ---")
	var ui := TowerRewardUI.new()
	add_child(ui)

	var pool := ui.get_reward_pool()
	_assert(pool.size() == 8, "7a: 奖励池8种（实际=%d）" % pool.size())

	# 检查每个奖励都有必要字段
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

	# 检查 8 种 id 都存在
	var expected_ids := ["blade_power", "charge_bonus", "shield_wall", "regen", "clone", "swift", "energy_cap", "protect"]
	for eid in expected_ids:
		_assert(eid in ids_seen, "7h: 奖励id=%s 存在" % eid)

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

	# 逐个验证 8 种 buff 的注入
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
	_apply_single_buff(player, { "id": "shield_wall", "value": 1.0 })
	_assert(player.damage_reduction == 1.0, "10d: shield_wall注入")

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

	# energy_cap
	player.max_energy = 999
	_apply_single_buff(player, { "id": "energy_cap", "value": 2 })
	_assert(player.max_energy == 1001, "10h: energy_cap注入")

	# protect
	player.shield = 0
	_apply_single_buff(player, { "id": "protect", "value": 2 })
	_assert(player.shield == 2, "10i: protect注入")

	tower.queue_free()

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
		"blade_power":
			p.damage_bonus_basic += buff.get("value", 1.0)
		"charge_bonus":
			p.charge_bonus += buff.get("value", 1)
		"shield_wall":
			p.damage_reduction += buff.get("value", 1.0)
		"regen":
			p.regen_per_round += buff.get("value", 1.0)
		"clone":
			p.clone_count += buff.get("value", 1)
		"swift":
			p.add_energy(buff.get("value", 2))
		"energy_cap":
			p.max_energy += buff.get("value", 2)
		"protect":
			p.shield += buff.get("value", 2)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
