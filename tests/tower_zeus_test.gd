## 宙斯Boss战机制测试
## 覆盖：神赐开局5气、神怒被动获气、行动权系统（1阶段2/2阶段3）、
##       神罚AOE、神盾、神大罚限定技、变异军团召唤异种/克罗狄亚、
##       召唤物爆炸（异种1伤/克罗狄亚3伤）、二阶段转换、克罗狄亚壳技能
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 宙斯Boss战机制测试 ===")
	await get_tree().process_frame

	var zeus1_char := load("res://resources/characters/tower/宙斯（幻象）.tres") as CharacterData
	var zeus2_char := load("res://resources/characters/tower/宙斯（幻象·二阶段）.tres") as CharacterData
	var mutant_char := load("res://resources/characters/tower/异种.tres") as CharacterData
	var clodia_char := load("res://resources/characters/tower/克罗狄亚.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var might_gai_char := load("res://resources/characters/迈特凯.tres") as CharacterData
	if zeus1_char == null or zeus2_char == null or mutant_char == null or clodia_char == null or naruto_char == null or sasuke_char == null or might_gai_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# 验证角色资源基本属性
	_assert(zeus1_char.character_name == "宙斯（幻象）", "0a: 一阶段名字正确")
	_assert(zeus1_char.max_hp == 50, "0b: 一阶段HP=50（实际=%.0f）" % zeus1_char.max_hp)
	_assert(zeus1_char.skills.size() == 5, "0c: 一阶段5技能（实际=%d）" % zeus1_char.skills.size()) # 神罚/神盾/神大罚/变异军团/尖塔祝福
	_assert(zeus2_char.character_name == "宙斯（幻象·二阶段）", "0d: 二阶段名字正确")
	_assert(zeus2_char.max_hp == 50, "0e: 二阶段HP=50")
	_assert(mutant_char.max_hp == 6, "0f: 异种HP=6")
	_assert(clodia_char.max_hp == 15, "0g: 克罗狄亚HP=15")

	await _test_gift_and_wrath(zeus1_char, naruto_char)
	await _test_action_points_p1(zeus1_char, naruto_char)
	await _test_punish(zeus1_char, naruto_char, sasuke_char)
	await _test_shield(zeus1_char, naruto_char)
	await _test_judgement(zeus1_char, might_gai_char)
	await _test_mutant_summon_and_explosion(zeus1_char, naruto_char, mutant_char)
	await _test_phase_transition(zeus1_char, zeus2_char, naruto_char)
	await _test_p2_action_points_and_clodia(zeus2_char, naruto_char, clodia_char)
	await _test_clodia_shell(zeus2_char, naruto_char, clodia_char)
	await _test_wrath_on_damage(zeus1_char, naruto_char, sasuke_char)

	print("=== 宙斯Boss测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)


## ═════════ 测试1：神赐（开局5气）+ 神怒被动 ═════════════════
func _test_gift_and_wrath(zeus1_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试1：神赐与神怒 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	var player: PlayerState = gm.get_player(1)
	# 神赐：开局5气
	_assert(zeus.energy == 5, "1a: 宙斯开局5气（实际=%d）" % zeus.energy)
	_assert(zeus.is_zeus, "1b: is_zeus=true")
	_assert(zeus.is_zeus_boss, "1c: is_zeus_boss=true")
	_assert(not zeus.is_zeus_phase2, "1d: 一阶段is_zeus_phase2=false")

	# 神怒：宙斯自己不聚气（聚气时获得0气）
	# 让宙斯赢猜拳→聚气
	zeus.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var zeus_energy_before := zeus.energy
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(zeus.energy == zeus_energy_before, "1e: 宙斯聚气0气（之前=%d之后=%d）" % [zeus_energy_before, zeus.energy])

	# 神怒：玩家赢→聚气时宙斯+1气
	player.current_gesture = PlayerState.Gesture.ROCK
	zeus.current_gesture = PlayerState.Gesture.SCISSORS
	# 消耗宙斯剩余行动权以推进回合
	if zeus.action_points > 0:
		zeus.action_points = 0
	gm.call("_resolve_round")
	var zeus_e_before_player_charge := zeus.energy
	gm.submit_action(1, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(zeus.energy == zeus_e_before_player_charge + 1, "1f: 玩家聚气→宙斯神怒+1气（之前=%d之后=%d）" % [zeus_e_before_player_charge, zeus.energy])


## ═════════ 测试2：行动权系统（一阶段2点） ═════════════════════
func _test_action_points_p1(zeus1_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试2：行动权一阶段 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	var player: PlayerState = gm.get_player(1)
	# 宙斯赢→行动权应为2
	zeus.current_gesture = PlayerState.Gesture.ROCK
	player.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(zeus.action_points == 2, "2a: 一阶段行动权=2（实际=%d）" % zeus.action_points)
	# 神盾消耗1行动权 → 剩1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(zeus, "神盾"), 0)
	_assert(zeus.action_points == 1, "2b: 神盾后行动权=1（实际=%d）" % zeus.action_points)
	_assert(zeus.shield == 1, "2c: 神盾获得1盾（实际=%d）" % zeus.shield)
	# 再次行动：行动权=0后进入ELIMINATION
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(zeus, "神盾"), 0)
	_assert(zeus.action_points == 0, "2d: 二次行动后行动权=0（实际=%d）" % zeus.action_points)
	_assert(zeus.shield == 2, "2e: 二次神盾共2盾（实际=%d）" % zeus.shield)


## ═════════ 测试3：神罚（1耗AOE 1伤所有敌人） ═════════════════
func _test_punish(zeus1_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- 测试3：神罚 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "鸣人", "character": naruto_char, "is_human": true, "team_id": 1},
			{"name": "佐助", "character": sasuke_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	var p1: PlayerState = gm.get_player(1)
	var p2: PlayerState = gm.get_player(2)
	zeus.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var naruto_hp := p1.hp
	var sasuke_hp := p2.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(zeus, "神罚"), 1)
	_assert(p1.hp == naruto_hp - 1.0, "3a: 神罚对鸣人1伤（%.1f→%.1f）" % [naruto_hp, p1.hp])
	_assert(p2.hp == sasuke_hp - 1.0, "3b: 神罚对佐助1伤（%.1f→%.1f）" % [sasuke_hp, p2.hp])
	_assert(zeus.energy == 4, "3c: 神罚消耗1气（5→4，实际=%d）" % zeus.energy)


## ═════════ 测试4：神盾（0耗消耗行动权获1盾） ══════════════════
func _test_shield(zeus1_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试4：神盾 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	zeus.current_gesture = PlayerState.Gesture.ROCK
	gm.get_player(1).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var e_before := zeus.energy
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(zeus, "神盾"), 0)
	_assert(zeus.shield == 1, "4a: 神盾获得1盾（实际=%d）" % zeus.shield)
	_assert(zeus.energy == e_before, "4b: 神盾0耗气（之前=%d之后=%d）" % [e_before, zeus.energy])


## ═════════ 测试5：神大罚（限定技HP≤25，目标HP→1+麻痹3） ══════
func _test_judgement(zeus1_char: CharacterData, might_gai_char: CharacterData) -> void:
	print("--- 测试5：神大罚 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "靶子", "character": might_gai_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	var target: PlayerState = gm.get_player(1)
	# 宙斯HP设为20（≤25）以启用神大罚
	zeus.hp = 20.0
	zeus.current_gesture = PlayerState.Gesture.ROCK
	target.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var skill_idx := _find_skill_index(zeus, "神大罚")
	_assert(skill_idx >= 0, "5a: 神大罚在技能列表中")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, skill_idx, 1)
	_assert(target.hp == 1.0, "5b: 神大罚目标HP→1（实际=%.1f）" % target.hp)
	_assert(target.paralyze_turns == 3, "5c: 神大罚麻痹3回合（实际=%d）" % target.paralyze_turns)
	_assert(zeus.zeus_judgement_used, "5d: zeus_judgement_used=true")
	# 限定技使用后不再出现
	var skill_idx2 := _find_skill_index(zeus, "神大罚")
	_assert(skill_idx2 < 0, "5e: 神大罚使用后从列表消失")


## ═════════ 测试6：变异军团召唤异种+爆炸 ════════════════════════
func _test_mutant_summon_and_explosion(zeus1_char: CharacterData, naruto_char: CharacterData, mutant_char: CharacterData) -> void:
	print("--- 测试6：变异军团召唤异种+爆炸 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	zeus.current_gesture = PlayerState.Gesture.ROCK
	gm.get_player(1).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# 第一次召唤异种
	var summon_idx := _find_skill_index(zeus, "变异军团")
	_assert(summon_idx >= 0, "6a: 变异军团在技能列表中")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, summon_idx, 0)
	# 检查召唤物存在
	var mutant: PlayerState = null
	for p in gm.get_alive_players():
		if p.character.character_name == "异种":
			mutant = p
			break
	_assert(mutant != null, "6b: 异种被召唤")
	if mutant:
		_assert(mutant.hp == 6, "6c: 异种HP=6（实际=%.0f）" % mutant.hp)
		_assert(mutant.team_id == zeus.team_id, "6d: 异种与宙斯同队（实际=%d）" % mutant.team_id)
		# 再次用第二个行动权召唤第二只异种
		if zeus.action_points > 0:
			zeus.energy = 0  # 确保有资源消耗（变异军团0气，所以无需设）
			var summon_idx2 := _find_skill_index(zeus, "变异军团")
			if summon_idx2 >= 0:
				gm.submit_action(0, PlayerState.ActionType.USE_SKILL, summon_idx2, 0)
				var mutant_count := 0
				for p in gm.get_alive_players():
					if p.character.character_name == "异种":
						mutant_count += 1
				_assert(mutant_count == 2, "6e: 第二只异种被召唤（共%d只）" % mutant_count)

	# 测试异种爆炸：将异种HP设0模拟死亡
	if mutant:
		var zeus_hp_before := zeus.hp
		mutant.hp = 0.0
		# 触发淘汰检测（手动调用_check_elimination）
		gm.call("_check_elimination")
		_assert(not mutant.is_alive, "6f: 异种死亡后is_alive=false")
		_assert(zeus.hp == zeus_hp_before - 1.0, "6g: 异种爆炸对宙斯1伤（%.1f→%.1f）" % [zeus_hp_before, zeus.hp])


## ═════════ 测试7：二阶段转换 ══════════════════════════════════
func _test_phase_transition(zeus1_char: CharacterData, zeus2_char: CharacterData, naruto_char: CharacterData) -> void:
	print("--- 测试7：二阶段转换 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	# 将宙斯HP打到0触发二阶段
	zeus.hp = 0.0
	gm.call("_check_elimination")
	_assert(zeus.is_alive, "7a: 宙斯一阶段死亡后仍然存活（进入二阶段）")
	_assert(zeus.is_zeus_phase2, "7b: is_zeus_phase2=true")
	_assert(zeus.character.character_name == "宙斯（幻象·二阶段）", "7c: 角色切换为二阶段")
	_assert(zeus.hp == 50.0, "7d: 二阶段满血50（实际=%.1f）" % zeus.hp)
	_assert(not zeus.zeus_judgement_used, "7e: 限定技重置")


## ═════════ 测试8：二阶段3行动权+召唤克罗狄亚 ═══════════════════
func _test_p2_action_points_and_clodia(zeus2_char: CharacterData, naruto_char: CharacterData, clodia_char: CharacterData) -> void:
	print("--- 测试8：二阶段行动权与克罗狄亚召唤 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯2", "character": zeus2_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	# 手动标记为二阶段
	zeus.is_zeus = true
	zeus.is_zeus_boss = true
	zeus.is_zeus_phase2 = true
	zeus.energy = 5  # 开局5气

	zeus.current_gesture = PlayerState.Gesture.ROCK
	gm.get_player(1).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(zeus.action_points == 3, "8a: 二阶段行动权=3（实际=%d）" % zeus.action_points)

	# 召唤克罗狄亚
	var summon_idx := _find_skill_index(zeus, "变异军团")
	_assert(summon_idx >= 0, "8b: 变异军团在技能列表中")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, summon_idx, 0)
	var clodia: PlayerState = null
	for p in gm.get_alive_players():
		if p.character.character_name == "克罗狄亚":
			clodia = p
			break
	_assert(clodia != null, "8c: 克罗狄亚被召唤")
	if clodia:
		_assert(clodia.hp == 15, "8d: 克罗狄亚HP=15（实际=%.0f）" % clodia.hp)
		_assert(clodia.team_id == zeus.team_id, "8e: 克罗狄亚与宙斯同队")

	# 测试克罗狄亚爆炸
	if clodia:
		var zeus_hp_before := zeus.hp
		clodia.hp = 0.0
		gm.call("_check_elimination")
		_assert(not clodia.is_alive, "8f: 克罗狄亚死亡后is_alive=false")
		_assert(zeus.hp == zeus_hp_before - 3.0, "8g: 克罗狄亚爆炸对宙斯3伤（%.1f→%.1f）" % [zeus_hp_before, zeus.hp])


## ═════════ 测试9：克罗狄亚·壳（给宙斯+1盾） ═══════════════════
func _test_clodia_shell(zeus2_char: CharacterData, naruto_char: CharacterData, clodia_char: CharacterData) -> void:
	print("--- 测试9：克罗狄亚·壳技能 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus2_char, "is_human": true, "team_id": 2},
			{"name": "玩家", "character": naruto_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	zeus.is_zeus = true
	zeus.is_zeus_boss = true
	zeus.is_zeus_phase2 = true

	# 手动创建克罗狄亚加入游戏（is_human=true 避免AI自动决策消耗资源）
	var clodia := PlayerState.new(100, "克罗狄亚", clodia_char, true)
	clodia.team_id = zeus.team_id
	clodia.energy = 2  # 壳需要2气
	gm.get("_players").append(clodia)
	gm.get("_distance_system")._seat_order.append(100)

	# 让克罗狄亚赢猜拳并使用壳
	clodia.current_gesture = PlayerState.Gesture.ROCK
	zeus.current_gesture = PlayerState.Gesture.SCISSORS
	gm.get_player(1).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	# 清除宙斯的行动权状态（避免干扰）
	if zeus.action_points > 0:
		zeus.action_points = 0
	var shell_idx := _find_skill_index(clodia, "壳")
	_assert(shell_idx >= 0, "9a: 壳在技能列表中")
	var zeus_shield_before := zeus.shield
	gm.submit_action(100, PlayerState.ActionType.USE_SKILL, shell_idx, 100)
	_assert(clodia.shield >= 1, "9b: 克罗狄亚自身获得1盾（实际=%d）" % clodia.shield)
	_assert(zeus.shield >= zeus_shield_before + 1, "9c: 壳给宙斯+1盾（之前=%d之后=%d）" % [zeus_shield_before, zeus.shield])


## ═════════ 测试10：神怒·伤害触发 ══════════════════════════════
func _test_wrath_on_damage(zeus1_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData) -> void:
	print("--- 测试10：神怒·伤害触发获气 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "宙斯", "character": zeus1_char, "is_human": true, "team_id": 2},
			{"name": "鸣人", "character": naruto_char, "is_human": true, "team_id": 1},
			{"name": "佐助", "character": sasuke_char, "is_human": true, "team_id": 1},
		],
		"tower_mode": true,
	})
	await get_tree().process_frame
	var zeus: PlayerState = gm.get_player(0)
	var naruto: PlayerState = gm.get_player(1)
	var sasuke: PlayerState = gm.get_player(2)
	# 鸣人赢 → 普攻佐助 → 宙斯神怒触发+1气
	naruto.current_gesture = PlayerState.Gesture.ROCK
	zeus.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	naruto.energy = 1
	var zeus_e_before := zeus.energy  # 应为5+1（猜拳时触发的可能）
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(naruto, "普攻"), 2)
	_assert(zeus.energy == zeus_e_before + 1, "10a: 鸣人伤害佐助→宙斯神怒+1气（之前=%d之后=%d）" % [zeus_e_before, zeus.energy])


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
