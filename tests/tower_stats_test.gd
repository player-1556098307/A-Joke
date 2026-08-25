## 塔战报统计测试
## 验证 PlayerMatchStats 的 total_damage_dealt/taken/blocked/healing/win_count 字段
## 在各伤害路径下被正确累积
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔战报统计测试 ===")
	await get_tree().process_frame

	# 测试1：PlayerMatchStats 新字段存在且默认为0
	_test_stats_fields()

	# 测试2：setup_game 后统计初始化正确
	_test_setup_init()
	await get_tree().process_frame
	await get_tree().process_frame

	# 测试3：DAMAGE 效果统计（伤害+抵挡）
	_test_damage_stats()

	# 测试4：护盾抵挡伤害统计
	_test_shield_block_stats()

	# 测试5：燃烧/狂战士伤害统计
	_test_burn_stats()

	# 测试6：回生治疗统计
	_test_regen_stats()

	# 测试7：round_resolver 返回值含 damage_blocked 和 lifesteal_heal
	_test_resolver_return_values()

	print("=== 塔战报统计测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 测试1：PlayerMatchStats 新字段存在且默认为0
func _test_stats_fields() -> void:
	var stats := PlayerMatchStats.new()
	_assert(stats.total_damage_blocked == 0.0, "1: total_damage_blocked 默认=0")
	_assert(stats.total_damage_dealt == 0.0, "1b: total_damage_dealt 默认=0")
	_assert(stats.total_damage_taken == 0.0, "1c: total_damage_taken 默认=0")
	_assert(stats.total_healing == 0.0, "1d: total_healing 默认=0")
	_assert(stats.win_count == 0, "1e: win_count 默认=0")

## 测试2：setup_game 后统计初始化正确
func _test_setup_init() -> void:
	var char_data := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	GameManager.setup_game({
		"players": [
			{ "name": "玩家", "character": char_data, "is_human": true, "team_id": 1 },
			{ "name": "敌人", "character": char_data, "is_human": false, "team_id": 2 },
		],
		"tower_mode": true,
	})

	var stats: PlayerMatchStats = GameManager.get("_match_record").player_stats.get(0)
	_assert(stats != null, "2: setup_game 后 player_stats[0] 存在")
	if stats:
		_assert(stats.player_name == "玩家", "2b: player_name=玩家（实际=%s）" % stats.player_name)
		_assert(stats.total_damage_dealt == 0.0, "2c: 初始 damage_dealt=0")
		_assert(stats.total_damage_blocked == 0.0, "2d: 初始 damage_blocked=0")
		_assert(stats.total_healing == 0.0, "2e: 初始 healing=0")

## 辅助：构建测试用 SkillData（包装单个 SkillEffect）
func _make_test_skill(e_name: String, effect_type: int, value: float, target: int) -> SkillData:
	var effect := SkillEffect.new()
	effect.effect_type = effect_type
	effect.value = value
	effect.target = target
	var skill := SkillData.new()
	skill.skill_name = e_name
	skill.energy_cost = 0
	skill.min_range = 1
	skill.max_range = 1
	skill.effects = [effect]
	return skill

## 测试3：DAMAGE 效果统计
func _test_damage_stats() -> void:
	var attacker: PlayerState = GameManager.get_player(0)
	var target: PlayerState = GameManager.get_player(1)
	var dist: DistanceSystem = GameManager.get("_distance_system")

	target.hp = target.get_max_hp()
	var dmg_skill := _make_test_skill("测试普攻", SkillEffect.EffectType.DAMAGE, 3.0, SkillEffect.EffectTarget.ENEMY_SINGLE)
	attacker.energy = 10
	var logs := RoundResolver.apply_effects(attacker, dmg_skill, [target], dist)

	# 找到 DAMAGE 类型的日志
	var damage_result: Dictionary = {}
	for entry in logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
			damage_result = entry.get("result", {})
	_assert(logs.size() > 0, "3: apply_effects 返回非空日志")
	if damage_result.size() > 0:
		_assert(damage_result.has("damage_dealt"), "3b: result 含 damage_dealt")
		_assert(damage_result.has("damage_blocked"), "3c: result 含 damage_blocked")
		_assert(damage_result.has("lifesteal_heal"), "3d: result 含 lifesteal_heal")
		_assert(damage_result.get("damage_dealt", -1) == 3.0, "3e: damage_dealt=3（实际=%s）" % str(damage_result.get("damage_dealt", -1)))
		_assert(damage_result.get("damage_blocked", -1) == 0.0, "3f: damage_blocked=0（无护盾，实际=%s）" % str(damage_result.get("damage_blocked", -1)))

## 测试4：护盾抵挡伤害统计
func _test_shield_block_stats() -> void:
	var attacker: PlayerState = GameManager.get_player(0)
	var target: PlayerState = GameManager.get_player(1)
	var dist: DistanceSystem = GameManager.get("_distance_system")

	target.hp = target.get_max_hp()
	target.shield = 5  # 数值盾5

	var dmg_skill := _make_test_skill("测试护盾", SkillEffect.EffectType.DAMAGE, 3.0, SkillEffect.EffectTarget.ENEMY_SINGLE)
	attacker.energy = 10
	var logs := RoundResolver.apply_effects(attacker, dmg_skill, [target], dist)

	var damage_result: Dictionary = {}
	for entry in logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
			damage_result = entry.get("result", {})
	if damage_result.size() > 0:
		_assert(damage_result.get("damage_dealt", -1) == 0.0, "4: 护盾吸收后 damage_dealt=0（实际=%s）" % str(damage_result.get("damage_dealt", -1)))
		_assert(damage_result.get("damage_blocked", -1) == 3.0, "4b: damage_blocked=3（实际=%s）" % str(damage_result.get("damage_blocked", -1)))

	# 清除护盾
	target.shield = 0

## 测试5：燃烧/狂战士伤害统计
func _test_burn_stats() -> void:
	var player: PlayerState = GameManager.get_player(0)
	player.burning = true
	player.berserker = false
	player.took_damage_this_round = true
	player.hp = 10.0

	var stats: PlayerMatchStats = GameManager.get("_match_record").player_stats.get(0)
	var taken_before: float = stats.total_damage_taken

	GameManager.call("_process_burn_and_berserker")
	_assert(player.hp == 9.0, "5: 燃烧扣1血 HP10→9（实际=%s）" % str(player.hp))
	_assert(stats.total_damage_taken == taken_before + 1.0, "5b: 燃烧后 total_damage_taken +1（实际=%s，期望=%s）" % [str(stats.total_damage_taken), str(taken_before + 1.0)])

	player.burning = false
	player.berserker = false
	player.took_damage_this_round = false

## 测试6：回生治疗统计
func _test_regen_stats() -> void:
	var player: PlayerState = GameManager.get_player(0)
	var stats: PlayerMatchStats = GameManager.get("_match_record").player_stats.get(0)
	var heal_before: float = stats.total_healing

	# 设置回生属性：每回合回2血
	player.regen_per_round = 2.0
	player.hp = 1.0
	player.is_alive = true
	var max_hp: float = player.get_max_hp()
	var expected_heal: float = min(2.0, max_hp - 1.0)

	# _process_tower_regen 接收 player 参数
	GameManager.call("_process_tower_regen", player)

	_assert(player.hp == 1.0 + expected_heal, "6: 回生后 HP 1→%s（实际=%s）" % [str(1.0 + expected_heal), str(player.hp)])
	_assert(stats.total_healing == heal_before + expected_heal, "6b: 回生后 total_healing +%s（before=%s after=%s）" % [str(expected_heal), str(heal_before), str(stats.total_healing)])

	player.regen_per_round = 0.0

## 测试7：round_resolver 返回值含 damage_blocked 和 lifesteal_heal
func _test_resolver_return_values() -> void:
	var attacker: PlayerState = GameManager.get_player(0)
	var target: PlayerState = GameManager.get_player(1)
	var dist: DistanceSystem = GameManager.get("_distance_system")

	# TRUE_DAMAGE
	var td_skill := _make_test_skill("测试真伤", SkillEffect.EffectType.TRUE_DAMAGE, 2.0, SkillEffect.EffectTarget.ENEMY_SINGLE)
	target.hp = target.get_max_hp()
	attacker.energy = 10
	var td_logs := RoundResolver.apply_effects(attacker, td_skill, [target], dist)
	for entry in td_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE:
			var r: Dictionary = entry.get("result", {})
			_assert(r.has("damage_blocked"), "7: TRUE_DAMAGE result 含 damage_blocked")
			_assert(r.has("lifesteal_heal"), "7b: TRUE_DAMAGE result 含 lifesteal_heal")

	# PIERCE_DAMAGE
	var pd_skill := _make_test_skill("测试穿透", SkillEffect.EffectType.PIERCE_DAMAGE, 2.0, SkillEffect.EffectTarget.ENEMY_SINGLE)
	target.hp = target.get_max_hp()
	attacker.energy = 10
	var pd_logs := RoundResolver.apply_effects(attacker, pd_skill, [target], dist)
	for entry in pd_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.PIERCE_DAMAGE:
			var r: Dictionary = entry.get("result", {})
			_assert(r.has("damage_blocked"), "7c: PIERCE_DAMAGE result 含 damage_blocked")
			_assert(r.has("lifesteal_heal"), "7d: PIERCE_DAMAGE result 含 lifesteal_heal")

	# HEAL
	var heal_skill := _make_test_skill("测试治疗", SkillEffect.EffectType.HEAL, 3.0, SkillEffect.EffectTarget.SELF)
	target.hp = 1.0
	attacker.energy = 10
	var heal_logs := RoundResolver.apply_effects(attacker, heal_skill, [target], dist)
	for entry in heal_logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.HEAL:
			var r: Dictionary = entry.get("result", {})
			_assert(r.has("heal_amount"), "7e: HEAL result 含 heal_amount")

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
