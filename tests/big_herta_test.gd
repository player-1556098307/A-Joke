## 大黑塔完整机制测试
## 覆盖：角色属性/技能定义、解读标记（上标记/距离-1/增伤+1）、
##      格局打开（任何来源受伤回气）、魔法（主目标+AOE含主目标）、
##      魔法AOE新标记、AI策略
## 说明：全人类4人局（座位[0,1,2,3]），手动推进回合
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 大黑塔完整机制测试 ===")
	await get_tree().process_frame

	var bh_char := load("res://resources/characters/大黑塔.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if bh_char == null or naruto_char == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	await _test_stats_and_skills(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_jiedu_mark(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_open_mind(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_magic(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_magic_aoe_new_mark(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_double_herta(bh_char, naruto_char, sasuke_char, sakura_char)
	await _test_ai(bh_char, naruto_char, sasuke_char, sakura_char)

	print("=== 大黑塔测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## ═════════ 测试1：角色属性与技能定义 ═══════════════════════
func _test_stats_and_skills(bh_char: CharacterData, naruto_char: CharacterData, _sasuke_char: CharacterData, _sakura_char: CharacterData) -> void:
	print("--- 测试1：角色属性与技能定义 ---")
	_assert(bh_char.max_hp == 8, "1a: 大黑塔HP=8（实际=%d）" % bh_char.max_hp)
	_assert(bh_char.grade == "A", "1b: 等级A（实际=%s）" % bh_char.grade)
	_assert("法师" in bh_char.tags and bh_char.tags.size() == 1, "1c: 标签=法师（实际=%s）" % str(bh_char.tags))

	var names: Array[String] = []
	for s in bh_char.skills:
		names.append(s.skill_name)
	_assert("普攻" in names and "解读" in names and "格局打开" in names and "魔法" in names, "1d: 技能=普攻/解读/格局打开/魔法（实际=%s）" % str(names))

	var basic: SkillData = null
	var jiedu: SkillData = null
	var open_mind: SkillData = null
	var magic: SkillData = null
	for s in bh_char.skills:
		match s.skill_name:
			"普攻": basic = s
			"解读": jiedu = s
			"格局打开": open_mind = s
			"魔法": magic = s
	_assert(basic != null and basic.energy_cost == 1 and basic.max_range == 2, "1e: 普攻耗1气/范围2（实际=%s/%s）" % [str(basic.energy_cost if basic else -1), str(basic.max_range if basic else -1)])
	_assert(jiedu != null and jiedu.is_passive and jiedu.energy_cost == 0, "1f: 解读被动/0耗（实际=%s/%s）" % [str(jiedu.is_passive if jiedu else false), str(jiedu.energy_cost if jiedu else -1)])
	_assert(jiedu != null and jiedu.effects[0].effect_type == SkillEffect.EffectType.JIEDU, "1g: 解读效果=JIEDU(%d)（实际=%d）" % [SkillEffect.EffectType.JIEDU, jiedu.effects[0].effect_type if jiedu else -1])
	_assert(open_mind != null and open_mind.is_passive and open_mind.energy_cost == 0, "1h: 格局打开被动/0耗（实际=%s/%s）" % [str(open_mind.is_passive if open_mind else false), str(open_mind.energy_cost if open_mind else -1)])
	_assert(open_mind != null and open_mind.effects[0].effect_type == SkillEffect.EffectType.OPEN_MIND, "1i: 格局打开效果=OPEN_MIND(%d)（实际=%d）" % [SkillEffect.EffectType.OPEN_MIND, open_mind.effects[0].effect_type if open_mind else -1])
	_assert(magic != null and magic.energy_cost == 3 and magic.max_range == 999, "1j: 魔法耗3气/全屏（实际=%s/%s）" % [str(magic.energy_cost if magic else -1), str(magic.max_range if magic else -1)])
	_assert(magic != null and magic.effects[0].effect_type == SkillEffect.EffectType.MAGIC, "1k: 魔法效果=MAGIC(%d)（实际=%d）" % [SkillEffect.EffectType.MAGIC, magic.effects[0].effect_type if magic else -1])
	# 被动不出现在主动列表
	var gm2 := GameManager
	gm2.setup_game({
		"players": [
			{"name": "大黑塔", "character": bh_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var bh: PlayerState = gm2.get_player(0)
	var vis: Array[String] = []
	for s in bh.get_all_skills():
		vis.append(s.skill_name)
	_assert(vis == ["普攻", "魔法"], "1l: 可见技能=普攻/魔法（实际=%s）" % str(vis))

## ═════════ 测试2：解读标记（上标记+距离-1+增伤） ═══════════
func _test_jiedu_mark(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试2：解读标记 ---")
	var arr = await _setup4(bh_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var bh: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]
	var dist: DistanceSystem = gm.get("_distance_system")

	_assert(dist.get_distance(0, 2) == 2, "2a: 初始0-2距离2（实际=%d）" % dist.get_distance(0, 2))
	# 大黑塔赢 → 普攻2号（6血）：1伤 + 上【解】 + 距离-1
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var jd_sig: Array = []
	gm.jiedu_applied.connect(func(tid: int, hid: int): jd_sig.append([tid, hid]))
	gm.call("_resolve_round")
	bh.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "普攻"), 2)
	_assert(p2.hp == 5.0, "2b: 首次普攻1伤（6→5，实际=%.1f）" % p2.hp)
	_assert(p2.jiedu_by.has(0), "2c: 2号获得大黑塔0的【解】标记")
	_assert(dist.get_distance(0, 2) == 1, "2d: 【解】距离-1（0-2=1，实际=%d）" % dist.get_distance(0, 2))
	_assert(jd_sig.size() == 1 and jd_sig[0][0] == 2 and jd_sig[0][1] == 0, "2e: jiedu_applied信号（实际=%s）" % str(jd_sig))
	# 再次普攻2号：解读增伤+1 → 2伤
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	bh.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "普攻"), 2)
	_assert(p2.hp == 3.0, "2f: 【解】增伤普攻2伤（5→3，实际=%.1f）" % p2.hp)
	_assert(dist.get_distance(0, 2) == 1, "2g: 距离不重复减（实际=%d）" % dist.get_distance(0, 2))

## ═════════ 测试3：格局打开（【解】玩家受伤回气） ═══════════
func _test_open_mind(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试3：格局打开回气 ---")
	var arr = await _setup4(bh_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var bh: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 首次普攻2号：耗1气 + 上标记；受伤前无标记 → 不回气（严格语义）
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var om_sig: Array = []
	gm.open_mind_triggered.connect(func(hid: int): om_sig.append(hid))
	gm.call("_resolve_round")
	bh.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "普攻"), 2)
	_assert(bh.energy == 0, "3a: 首击普攻耗1不回气（1→0，实际=%d）" % bh.energy)
	_assert(om_sig.is_empty(), "3b: 首击不触发格局打开（实际=%d）" % om_sig.size())
	# 其他角色（1号鸣人）打【解】玩家2号 → 大黑塔回气（任何来源）
	bh.current_gesture = PlayerState.Gesture.SCISSORS
	p1.current_gesture = PlayerState.Gesture.ROCK
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "3c: 1号胜（实际=%d）" % gm.get("_sole_winner_id"))
	var bh_e_before: int = bh.energy
	p1.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(p1, "普攻"), 2)
	_assert(p2.hp == 4.0, "3d: 1号普攻2号（5→4，实际=%.1f）" % p2.hp)
	_assert(bh.energy == bh_e_before + 1, "3e: 他人打【解】玩家大黑塔+1气（%d→%d）" % [bh_e_before, bh.energy])
	_assert(om_sig.size() == 1, "3f: 格局打开共1次（实际=%d）" % om_sig.size())

## ═════════ 测试4：魔法（主目标+AOE含主目标） ═══════════════
func _test_magic(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试4：魔法 ---")
	var arr = await _setup4(bh_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var bh: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 先给2号上【解】：普攻2号（6→5，标记）
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	bh.energy = 5
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "普攻"), 2)
	_assert(p2.jiedu_by.has(0) and p2.hp == 5.0, "4a: 2号【解】HP5（实际=%.1f）" % p2.hp)
	_assert(bh.energy == 4, "4b: 首击普攻耗1不回气 → 4（实际=%d）" % bh.energy)

	# 魔法打1号（无标记）：主目标2伤（1号4→... 1号6血）→ 1号获得【解】 → AOE打1号（1+1=2）和2号（1+1=2）
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var mg_sig: Array = []
	gm.magic_used.connect(func(cid: int, tid: int): mg_sig.append([cid, tid]))
	var om_count: int = om_sig_count(gm)
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "魔法"), 1)
	_assert(p1.hp == 2.0, "4c: 1号主目标2伤+AOE2伤=4（6→2，实际=%.1f）" % p1.hp)
	_assert(p2.hp == 3.0, "4d: 2号受AOE2伤（5→3，实际=%.1f）" % p2.hp)
	_assert(p3.hp == 8.0, "4e: 3号未标记不受AOE（实际=%.1f）" % p3.hp)
	_assert(p1.jiedu_by.has(0), "4f: 1号获得【解】")
	_assert(mg_sig.size() == 1, "4g: magic_used信号（实际=%d）" % mg_sig.size())
	_assert(bh.energy == 3, "4h: 4耗1（普攻）+耗3（魔法）+回2（AOE）=3（实际=%d）" % bh.energy)

## ═════════ 测试5：魔法AOE只打【解】玩家 ═══════════════════
func _test_magic_aoe_new_mark(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData) -> void:
	print("--- 测试5：魔法AOE新标记 ---")
	var arr = await _setup4(bh_char, naruto_char, sasuke_char, sakura_char)
	var gm: GameManager = arr[0]
	var bh: PlayerState = arr[1]
	var p1: PlayerState = arr[2]
	var p2: PlayerState = arr[3]
	var p3: PlayerState = arr[4]

	# 只有1号有【解】（手动设来源=0），魔法打2号（无标记）
	p1.jiedu_by = [0]
	p1.hp = 5.0
	bh.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	bh.energy = 3
	var p2_hp5: float = p2.hp
	var p3_hp5: float = p3.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(bh, "魔法"), 2)
	# 主目标2号：2伤 → 获得【解】 → AOE打1号（5→3）和2号
	_assert(p2.hp == p2_hp5 - 4.0, "5a: 2号主目标2伤+被标记后AOE2伤=4（%.1f→%.1f）" % [p2_hp5, p2.hp])
	_assert(p1.hp == 3.0, "5b: 1号【解】受AOE2伤（5→3，实际=%.1f）" % p1.hp)
	_assert(p3.hp == p3_hp5, "5c: 3号未标记不受影响（实际=%.1f）" % p3.hp)
	_assert(p2.jiedu_by.has(0), "5d: 2号被魔法标记")

## ═════════ 测试6：AI策略 ═══════════════════════════════════
func _test_ai(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, _sakura_char: CharacterData) -> void:
	print("--- 测试6：AI策略 ---")
	var ai := AIController.new()
	var bh_ai := PlayerState.new(0, "大黑塔AI", bh_char, false)
	bh_ai.hp = 8.0
	bh_ai.energy = 5
	var nar_ai := PlayerState.new(1, "鸣人", naruto_char, false)
	var sas_ai := PlayerState.new(2, "佐助", sasuke_char, false)
	var dist_ai := DistanceSystem.new()
	dist_ai.setup([0, 1, 2])
	var dec := ai.decide_action(bh_ai, [bh_ai, nar_ai, sas_ai], dist_ai)
	_assert(dec["action"] == PlayerState.ActionType.USE_SKILL, "6a: 5气AI用技能（实际=%d）" % dec["action"])
	if dec["action"] == PlayerState.ActionType.USE_SKILL and dec["skill_index"] >= 0:
		var used_name: String = bh_ai.get_all_skills()[dec["skill_index"]].skill_name
		_assert(used_name == "魔法", "6b: 3气以上优先魔法（实际=%s）" % used_name)

	var bh_ai2 := PlayerState.new(0, "大黑塔AI2", bh_char, false)
	bh_ai2.hp = 8.0
	bh_ai2.energy = 1
	var dec2 := ai.decide_action(bh_ai2, [bh_ai2, nar_ai, sas_ai], dist_ai)
	_assert(dec2["action"] == PlayerState.ActionType.USE_SKILL, "6c: 1气AI用技能（实际=%d）" % dec2["action"])
	if dec2["action"] == PlayerState.ActionType.USE_SKILL and dec2["skill_index"] >= 0:
		var s2_name: String = bh_ai2.get_all_skills()[dec2["skill_index"]].skill_name
		_assert(s2_name == "普攻", "6d: 1气普攻（实际=%s）" % s2_name)

## ═════════ 测试7：双大黑塔极端场景（回气只给标记者） ═════════
func _test_double_herta(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, _sakura_char: CharacterData) -> void:
	print("--- 测试7：双大黑塔回气只给标记者 ---")
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "大黑塔A", "character": bh_char, "is_human": true},
			{"name": "大黑塔B", "character": bh_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var herta_a: PlayerState = gm.get_player(0)
	var herta_b: PlayerState = gm.get_player(1)
	var p2: PlayerState = gm.get_player(2)
	var p3: PlayerState = gm.get_player(3)

	# R1：A(0)胜 → 普攻2号 → 2号上【解】（来源=A）
	herta_a.current_gesture = PlayerState.Gesture.ROCK
	herta_b.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	herta_a.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(herta_a, "普攻"), 2)
	_assert(p2.jiedu_by.has(0), "7a: 2号标记来源=A(0)（实际=%s）" % str(p2.jiedu_by))

	# R2：B(1)胜 → 普攻2号（已有【解】不重新标记；伤害2；回气给A）
	herta_a.current_gesture = PlayerState.Gesture.SCISSORS
	herta_b.current_gesture = PlayerState.Gesture.ROCK
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	p3.current_gesture = PlayerState.Gesture.SCISSORS
	var om_sig: Array = []
	gm.open_mind_triggered.connect(func(hid: int): om_sig.append(hid))
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "7b: R2 B胜（实际=%d）" % gm.get("_sole_winner_id"))
	var a_e_before: int = herta_a.energy
	var p2_hp7: float = p2.hp
	herta_b.energy = 1
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(herta_b, "普攻"), 2)
	# B 未标记过2号 → 无增伤（1伤）；B 给2号追加B的标记；回气只给既有标记者A
	_assert(p2.hp == p2_hp7 - 1.0, "7c: B普攻2号1伤（B无自己的标记，%.1f→%.1f）" % [p2_hp7, p2.hp])
	_assert(p2.jiedu_by.has(0) and p2.jiedu_by.has(1), "7d: 2号有A、B两枚标记（实际=%s）" % str(p2.jiedu_by))
	_assert(herta_a.energy == a_e_before + 1, "7e: A（标记者）回1气（%d→%d）" % [a_e_before, herta_a.energy])
	_assert(herta_b.energy == 0, "7f: B不回气（设1耗1后=0，实际=%d）" % herta_b.energy)
	_assert(om_sig.size() == 1 and om_sig[0] == 0, "7g: 格局打开信号=标记者A（实际=%s）" % str(om_sig))

## 统计格局打开信号次数（通过信号连接）
func om_sig_count(gm: GameManager) -> int:
	var c: int = 0
	gm.open_mind_triggered.connect(func(hid: int): c += 1)
	return c

## 搭建4人全人类局（大黑塔0 鸣人1 佐助2 樱3）
func _setup4(bh_char: CharacterData, naruto_char: CharacterData, sasuke_char: CharacterData, sakura_char: CharacterData):
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "大黑塔", "character": bh_char, "is_human": true},
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
