## 漩涡鸣人（疾风传）机制冒烟测试
## 覆盖：角色属性、技能定义、螺旋丸伤害、螺旋手里剑（伤害+击飞+溅射击飞）、
## 影分身（挡伤害+聚气加成）
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 漩涡鸣人（疾风传）冒烟测试 ===")
	await get_tree().process_frame

	var naruto_fy := load("res://resources/characters/漩涡鸣人（疾风传）.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if naruto_fy == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# ══ 测试1：角色属性 ══════════════════════════════════════════
	_assert(naruto_fy.character_name == "漩涡鸣人（疾风传）", "1a: 角色名=漩涡鸣人（疾风传）（实际=%s）" % naruto_fy.character_name)
	_assert(naruto_fy.max_hp == 8, "1b: HP=8（实际=%d）" % naruto_fy.max_hp)
	_assert(naruto_fy.basic_attack_cost == 1, "1c: 普攻耗气1（实际=%d）" % naruto_fy.basic_attack_cost)
	_assert(naruto_fy.grade == "B", "1d: 等级B（实际=%s）" % naruto_fy.grade)
	_assert("法师" in naruto_fy.tags and "刺客" in naruto_fy.tags, "1e: 标签=法师+刺客")
	_assert(naruto_fy.portrait != null, "1f: 立绘已绑定")

	var skill_names: Array[String] = []
	for s in naruto_fy.skills:
		skill_names.append(s.skill_name)
	_assert("普攻" in skill_names and "螺旋丸" in skill_names and "螺旋手里剑" in skill_names and "影分身" in skill_names, "1g: 技能列表含普攻/螺旋丸/螺旋手里剑/影分身")

	# ═════════ 测试2：技能属性 ══════════════════════════════════
	var ba: SkillData = null
	var rasengan: SkillData = null
	var shuriken: SkillData = null
	var clone: SkillData = null
	for s in naruto_fy.skills:
		match s.skill_name:
			"普攻": ba = s
			"螺旋丸": rasengan = s
			"螺旋手里剑": shuriken = s
			"影分身": clone = s

	_assert(ba != null and ba.energy_cost == 1 and ba.effects[0].effect_type == SkillEffect.EffectType.DAMAGE and ba.effects[0].value == 1.0, "2a: 普攻1耗1伤")
	_assert(ba != null and ba.min_range == 1 and ba.max_range == 1, "2b: 普攻射程1")

	_assert(rasengan != null and rasengan.energy_cost == 2, "2c: 螺旋丸耗气2（实际=%s）" % str(rasengan.energy_cost if rasengan else -1))
	_assert(rasengan != null and rasengan.effects.size() == 1 and rasengan.effects[0].effect_type == SkillEffect.EffectType.DAMAGE and rasengan.effects[0].value == 3.0, "2d: 螺旋丸直接3伤")
	_assert(rasengan != null and rasengan.min_range == 1 and rasengan.max_range == 1, "2e: 螺旋丸射程1")

	_assert(shuriken != null and shuriken.energy_cost == 3, "2f: 螺旋手里剑耗气3（实际=%s）" % str(shuriken.energy_cost if shuriken else -1))
	_assert(shuriken != null and shuriken.max_range == 999, "2g: 螺旋手里剑无视距离（max_range=999）")
	_assert(shuriken != null and shuriken.effects.size() == 3, "2h: 螺旋手里剑含3个效果（伤+击飞+溅射击飞，实际=%d）" % (shuriken.effects.size() if shuriken else -1))
	_assert(shuriken != null and shuriken.effects[0].effect_type == SkillEffect.EffectType.DAMAGE and shuriken.effects[0].value == 3.0 and shuriken.effects[0].target == SkillEffect.EffectTarget.ENEMY_SINGLE, "2i: 效果1=主目标3伤")
	_assert(shuriken != null and shuriken.effects[1].effect_type == SkillEffect.EffectType.KNOCKDOWN and shuriken.effects[1].value == 1.0 and shuriken.effects[1].target == SkillEffect.EffectTarget.ENEMY_SINGLE, "2j: 效果2=主目标击飞1回合")
	_assert(shuriken != null and shuriken.effects[2].effect_type == SkillEffect.EffectType.KNOCKDOWN and shuriken.effects[2].value == 1.0 and shuriken.effects[2].target == SkillEffect.EffectTarget.ENEMY_SPLASH and shuriken.effects[2].splash_range == 1, "2k: 效果3=溅射击飞1回合(splash_range=1)")

	_assert(clone != null and clone.energy_cost == 1, "2l: 影分身耗气1（实际=%s）" % str(clone.energy_cost if clone else -1))
	_assert(clone != null and clone.effects.size() == 1 and clone.effects[0].effect_type == SkillEffect.EffectType.CLONE_SHIELD and clone.effects[0].target == SkillEffect.EffectTarget.SELF, "2m: 影分身=CLONE_SHIELD自身")

	# ═════════ 测试3：螺旋丸伤害 ════════════════════════════════
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_fy, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
			{"name": "小樱", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	var naruto: PlayerState = gm.get_player(0)
	var sasuke: PlayerState = gm.get_player(1)
	_assert(naruto != null and naruto.hp == 8, "3a: 疾风鸣人初始HP=8（实际=%d）" % (naruto.hp if naruto else -1))

	naruto.energy = 2
	var rasengan_idx := _find_skill_index(naruto, "螺旋丸")
	_assert(rasengan_idx >= 0, "3b: 螺旋丸技能索引找到")
	naruto.current_gesture = PlayerState.Gesture.ROCK
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.get_player(2).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "3c: 鸣人赢得本回合")
	var sas_hp3: float = sasuke.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, rasengan_idx, 1)
	_assert(naruto.energy == 0, "3d: 螺旋丸消耗2气（2→0，实际=%d）" % naruto.energy)
	_assert(sasuke.hp == sas_hp3 - 3, "3e: 螺旋丸造成3伤（佐助HP %d→%d）" % [sas_hp3, sasuke.hp])

	# ═════════ 测试4：螺旋手里剑（主目标伤害+击飞，溅射击飞） ════
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_fy, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
			{"name": "小樱", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	naruto = gm.get_player(0)
	sasuke = gm.get_player(1)
	var sakura: PlayerState = gm.get_player(2)
	naruto.energy = 3
	var shuriken_idx := _find_skill_index(naruto, "螺旋手里剑")
	_assert(shuriken_idx >= 0, "4a: 螺旋手里剑技能索引找到")
	naruto.current_gesture = PlayerState.Gesture.ROCK
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	sakura.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "4b: 鸣人赢得本回合")
	var sas_hp4: float = sasuke.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, shuriken_idx, 1)
	_assert(naruto.energy == 0, "4c: 螺旋手里剑消耗3气（3→0，实际=%d）" % naruto.energy)
	_assert(sasuke.hp == sas_hp4 - 3, "4d: 主目标受3伤（佐助HP %d→%d）" % [sas_hp4, sasuke.hp])
	_assert(sasuke.knockdown_turns >= 1, "4e: 主目标被击飞（knockdown_turns=%d）" % sasuke.knockdown_turns)
	_assert(sasuke.paralyze_turns == 0, "4f: 主目标未被麻痹（paralyze_turns=%d，击飞不是麻痹）" % sasuke.paralyze_turns)

	# ═════════ 测试4b：击飞玩家可猜拳获得回合但只能聚气 ═══
	# 接测试4状态：佐助被击飞1回合。让他赢下下回合猜拳，验证行动被强制聚气
	# 先结束当前回合（鸣人行动后进入回合结束，击飞递减前佐助仍有 knockdown=1）
	# 佐助（AI）赢猜拳 → 进入行动 → _apply_actions 强制 CHARGE
	sasuke.is_human = false
	sasuke.knockdown_turns = 1  # 确保击飞状态
	sasuke.energy = 0
	naruto.current_gesture = PlayerState.Gesture.SCISSORS
	sasuke.current_gesture = PlayerState.Gesture.ROCK  # 佐助赢
	sakura.current_gesture = PlayerState.Gesture.SCISSORS
	var sas_energy_before: int = sasuke.energy
	# AI 同步执行：_resolve_round → _start_action_input → decide_action → submit_action → _apply_actions
	# 击飞状态下 decide_action 返回 CHARGE，_apply_actions 强制聚气加气
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "4g: 被击飞的佐助仍可猜拳并赢得回合（winner=%d）" % gm.get("_sole_winner_id"))
	_assert(sasuke.energy == sas_energy_before + 1, "4h: 击飞玩家被强制聚气（气 %d→%d，预期+1）" % [sas_energy_before, sasuke.energy])
	_assert(sasuke.knockdown_turns == 0, "4i: 击飞每回合统一递减到0（knockdown_turns=%d）" % sasuke.knockdown_turns)

	# ═════════ 测试5：影分身（挡伤害+聚气加成） ════════════════
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_fy, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
			{"name": "小樱", "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame
	naruto = gm.get_player(0)
	sasuke = gm.get_player(1)
	naruto.energy = 1
	var clone_idx := _find_skill_index(naruto, "影分身")
	_assert(clone_idx >= 0, "5a: 影分身技能索引找到")
	naruto.current_gesture = PlayerState.Gesture.ROCK
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.get_player(2).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "5b: 鸣人赢得本回合")
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, clone_idx, 0)
	_assert(naruto.energy == 0, "5c: 影分身消耗1气（1→0，实际=%d）" % naruto.energy)
	_assert(naruto.clone_count == 1, "5d: 影分身创建分身（clone_count=%d）" % naruto.clone_count)

	# 验证聚气加成：有分身时聚气+2
	naruto.energy = 0
	naruto.current_gesture = PlayerState.Gesture.ROCK
	sasuke.current_gesture = PlayerState.Gesture.SCISSORS
	gm.get_player(2).current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, 0)
	_assert(naruto.energy == 2, "5e: 有分身时聚气+2（0→2，实际=%d）" % naruto.energy)

	# ═════════ 测试6：注册表完整性 ══════════════════════════════
	var found_in_list := false
	for d in Characters.LIST:
		if d.get("id") == "naruto_fy":
			found_in_list = true
			_assert(d.name == "漩涡鸣人（疾风传）", "6a: characters.gd 名称正确")
			_assert(d.hp == 8, "6b: characters.gd HP=8")
			_assert(d.role == "法师/刺客", "6c: characters.gd 角色定位=法师/刺客")
			break
	_assert(found_in_list, "6d: 疾风鸣人已注册到 characters.gd")

	print("=== 疾风鸣人测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

## 在玩家的全部技能中查找技能索引
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
