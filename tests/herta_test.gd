## 黑塔完整机制测试
## 覆盖：角色属性/技能定义、genjutsu 距离-1（累积/最小1）、
##      送你砖石跨50%触发、AOE范围1判定、连锁触发（防无限循环）、
##      不跨阈值不触发、砖石AOE也触发genjutsu/连锁
## 说明：全人类4人局（座位[0,1,2,3]），手动推进回合
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 黑塔完整机制测试 ===")
	await get_tree().process_frame

	var herta_char := load("res://resources/characters/黑塔.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if herta_char == null or naruto_char == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_stats_and_skills(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_genjutsu_distance(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_diamond_trigger(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_diamond_no_trigger(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_diamond_chain(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_diamond_range(herta_char, naruto_char, sasuke_char, sakura_char)
	await _test_genjutsu_via_diamond(herta_char, naruto_char, sasuke_char, sakura_char)

	print("=== 黑塔测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ 测试1：角色属性与技能定义 ═══════════════════════
func _test_stats_and_skills(herta_char: CharacterData, _naruto_char: CharacterData, _sasuke_char: CharacterData, _sakura_char: CharacterData) -> void:
	print("--- 测试1：角色属性与技能定义 ---")
	_assert(herta_char.max_hp == 6, "1a: 黑塔HP=6（实际=%d）" % herta_char.max_hp)
	_assert(herta_char.grade == "B", "1b: 等级B（实际=%s）" % herta_char.grade)
	_assert("法师" in herta_char.tags and herta_char.tags.size() == 1, "1c: 标签=法师（实际=%s）" % str(herta_char.tags))

	var names: Array[String] = []
	for s in herta_char.skills:
		names.append(s.skill_name)
	_assert("普攻" in names and "送你砖石" in names and "genjutsu" in names, "1d: 技能=普攻/送你砖石/genjutsu（实际=%s）" % str(names))

	var basic: SkillData = null
	var diamond: SkillData = null
	var genjutsu: SkillData = null
	for s in herta_char.skills:
		match s.skill_name:
			"普攻": basic = s
			"送你砖石": diamond = s
			"genjutsu": genjutsu = s
	_assert(basic != null and basic.energy_cost == 1 and basic.max_range == 2, "1e: 普攻耗1气/范围2（实际=%s/%s）" % [str(basic.energy_cost if basic else -1), str(basic.max_range if basic else -1)])
	_assert(basic != null and basic.effects[0].effect_type == SkillEffect.EffectType.DAMAGE and basic.effects[0].value == 1.0, "1f: 普攻1伤（实际=%d/%s）" % [basic.effects[0].effect_type if basic else -1, str(basic.effects[0].value if basic else -1)])
	_assert(diamond != null and diamond.is_passive and diamond.energy_cost == 0, "1g: 送你砖石被动/0耗（实际=%s/%s）" % [str(diamond.is_passive if diamond else false), str(diamond.energy_cost if diamond else -1)])
	_assert(diamond != null and diamond.effects[0].effect_type == SkillEffect.EffectType.GIFT_DIAMOND, "1h: 砖石效果=GIFT_DIAMOND(%d)（实际=%d）" % [SkillEffect.EffectType.GIFT_DIAMOND, diamond.effects[0].effect_type if diamond else -1])
	_assert(genjutsu != null and genjutsu.is_passive and genjutsu.energy_cost == 0, "1i: genjutsu被动/0耗（实际=%s/%s）" % [str(genjutsu.is_passive if genjutsu else false), str(genjutsu.energy_cost if genjutsu else -1)])
	_assert(genjutsu != null and genjutsu.effects[0].effect_type == SkillEffect.EffectType.GENJUTSU, "1j: genjutsu效果=GENJUTSU(%d)（实际=%d）" % [SkillEffect.EffectType.GENJUTSU, genjutsu.effects[0].effect_type if genjutsu else -1])
	# 被动不出现在可主动使用列表
	var gm2 := GameManager
	gm2.setup_game({
		"players": [
			{"name": "黑塔", "character": herta_char, "is_human": true},
			{"name": "鸣人", "character": _naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var ht: PlayerState = gm2.get_player(0)
	var vis: Array[String] = []
	for s in ht.get_all_skills():
		vis.append(s.skill_name)
	_assert(vis == ["普攻"], "1k: 可见技能仅普攻（实际=%s）" % str(vis))

## ═════════ 测试2：genjutsu 距离-1（累积至最小1） ═══════════
func _test_genjutsu_distance(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试2：genjutsu 距离-1 ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]
	var dist: DistanceSystem = gm.get("_distance_system")

	# 初始：0-2 距离2，0-1 / 0-3 距离1
	_assert(dist.get_distance(0, 2) == 2, "2a: 初始0-2距离2（实际=%d）" % dist.get_distance(0, 2))
	# 黑塔赢 → 普攻2号
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "2b: 黑塔胜（实际=%d）" % gm.get("_sole_winner_id"))
	ht.energy = 1
	var p2_hp2: float = p2.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(p2.hp == p2_hp2 - 1.0, "2c: 普攻2号1伤（%.1f→%.1f）" % [p2_hp2, p2.hp])
	_assert(dist.get_distance(0, 2) == 1, "2d: genjutsu后0-2距离1（实际=%d）" % dist.get_distance(0, 2))
	_assert(dist.get_distance(0, 1) == 1 and dist.get_distance(0, 3) == 1, "2e: 其他距离不变（1/1，实际=%d/%d）" % [dist.get_distance(0, 1), dist.get_distance(0, 3)])

	# 再普攻2号：距离已最小1，不再减
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(dist.get_distance(0, 2) == 1, "2f: 距离最小1不继续减（实际=%d）" % dist.get_distance(0, 2))

## ═════════ 测试3：送你砖石跨50%触发 ═══════════════════════
func _test_diamond_trigger(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试3：送你砖石跨50%触发 ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 2号（6血）HP设3（=50%），普攻 → 3→2 跨50% → 砖石AOE打距离1的1/2/3号
	p2.hp = 3.0
	var p1_hp3: float = p1.hp
	var p3_hp3: float = p3.hp
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var dia_sig: Array = []
	gm.herta_diamond_triggered.connect(func(pid: int, tids: Array): dia_sig.append([pid, tids.duplicate()]))
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(p2.hp == 1.0, "3a: 2号3→2（普攻）→1（AOE补刀）（实际=%.1f）" % p2.hp)
	_assert(p1.hp == p1_hp3 - 1.0, "3b: 1号受AOE 1伤（%.1f→%.1f）" % [p1_hp3, p1.hp])
	_assert(p3.hp == p3_hp3 - 1.0, "3c: 3号受AOE 1伤（%.1f→%.1f）" % [p3_hp3, p3.hp])
	_assert(dia_sig.size() == 1, "3d: 砖石信号触发（实际=%d）" % dia_sig.size())
	_assert(dia_sig.size() > 0 and dia_sig[0][0] == 0, "3e: 触发者=黑塔（实际=%s）" % str(dia_sig))

## ═════════ 测试4：不跨阈值不触发 ═════════════════════════
func _test_diamond_no_trigger(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试4：不跨阈值不触发 ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 2号HP设4（>50%），普攻 → 4→3（=50%，不低于）→ 不触发
	p2.hp = 4.0
	var p1_hp4: float = p1.hp
	var p3_hp4: float = p3.hp
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var dia_sig: Array = []
	gm.herta_diamond_triggered.connect(func(pid: int, tids: Array): dia_sig.append([pid, tids.duplicate()]))
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(p2.hp == 3.0, "4a: 2号4→3（实际=%.1f）" % p2.hp)
	_assert(p1.hp == p1_hp4 and p3.hp == p3_hp4, "4b: 1/3号未受AOE（实际=%.1f/%.1f）" % [p1.hp, p3.hp])
	_assert(dia_sig.is_empty(), "4c: 未触发砖石（实际=%d）" % dia_sig.size())
	# 2号HP设2（已<50%），普攻 → 2→1 → 仍是<50%，不触发（不是"使...低于"）
	p2.hp = 2.0
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(p2.hp == 1.0, "4d: 2号2→1（实际=%.1f）" % p2.hp)
	_assert(dia_sig.is_empty(), "4e: 已低于50%%不再触发（实际=%d）" % dia_sig.size())

## ═════════ 测试5：砖石连锁触发（AOE再跨50%） ═════════════
func _test_diamond_chain(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试5：砖石连锁触发 ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 1号、2号HP都设3。普攻2号跨50% → 砖石AOE：1号3→2（跨50%）→ 连锁第二次砖石
	p1.hp = 3.0
	p2.hp = 3.0
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var dia_sig: Array = []
	gm.herta_diamond_triggered.connect(func(pid: int, tids: Array): dia_sig.append([pid, tids.duplicate()]))
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	# 第1次AOE：1号3→2、2号3→2、3号6→5；第2次AOE（1号连锁）：1号2→1、2号2→1、3号5→4
	_assert(p1.hp == 1.0, "5a: 1号连锁后=1（实际=%.1f）" % p1.hp)
	_assert(p2.hp == 0.0, "5b: 2号普攻+2次AOE后=0（实际=%.1f）" % p2.hp)
	_assert(p3.hp == 6.0, "5c: 3号（樱8血）受2次AOE=6（实际=%.1f）" % p3.hp)
	_assert(dia_sig.size() == 2, "5d: 砖石连锁触发2次（实际=%d）" % dia_sig.size())

## ═════════ 测试6：AOE范围1判定（距离2不打） ═══════════════
func _test_diamond_range(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试6：AOE范围1判定 ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 1号（距离1）HP设3，普攻1号跨50% → AOE打1号/3号（距离1），2号（距离2）不打
	p1.hp = 3.0
	var p2_hp6: float = p2.hp
	var p3_hp6: float = p3.hp
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 1)
	_assert(p1.hp == 1.0, "6a: 1号3→2（普攻）→1（AOE）（实际=%.1f）" % p1.hp)
	_assert(p3.hp == p3_hp6 - 1.0, "6b: 3号（距离1）受AOE（实际=%.1f）" % p3.hp)
	_assert(p2.hp == p2_hp6, "6c: 2号（距离2）不受AOE（实际=%.1f）" % p2.hp)

## ═════════ 测试7：砖石AOE也触发genjutsu ═══════════════════
func _test_genjutsu_via_diamond(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试7：砖石AOE触发genjutsu ---")
	var arr = await _setup4(herta_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var ht: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]
	var dist: DistanceSystem = gm.get("_distance_system")

	# 2号（距离2）HP设3，普攻2号 → 跨50% → genjutsu使0-2距离1 → AOE打1/2/3号
	# AOE打1号（距离1，6→5）→ genjutsu对1号：0-1距离1（不变）；AOE打3号 → 0-3不变
	p2.hp = 3.0
	ht.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	ht.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(ht, "普攻"), 2)
	_assert(dist.get_distance(0, 2) == 1, "7a: 普攻2号genjutsu 0-2距离1（实际=%d）" % dist.get_distance(0, 2))
	_assert(p1.hp == 5.0, "7b: AOE打1号（实际=%.1f）" % p1.hp)
	_assert(p3.hp == 7.0, "7c: AOE打3号（樱8血-1=7）（实际=%.1f）" % p3.hp)

## 搭建4人全人类局（黑塔0 鸣人1 佐助2 樱3）
func _setup4(herta_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData):
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "黑塔", "character": herta_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	return [gm, gm.get_player(0), gm.get_player(1), gm.get_player(2), gm.get_player(3)]

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
