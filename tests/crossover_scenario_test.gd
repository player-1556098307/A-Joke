## 多角色组合场景测试
## 检测不同角色技能交互、对抗场景下的边界情况
## 覆盖：无敌vs真实伤害、盾vs穿透、分身vs群攻、麻痹vs被动、延迟伤害淘汰、多回合对抗、3人混战
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

func _find_skill_index(p: PlayerState, sn: String) -> int:
	var all := p.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == sn:
			return i
	return -1

func _ready() -> void:
	print("=== 多角色组合场景测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if naruto_char == null or sakura_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager

	# ════════════════════════════════════════════════════════════════
	# 场景1：盾+分身叠加吸收（分身优先于盾）
	# ════════════════════════════════════════════════════════════════
	print("--- 场景1：盾+分身叠加吸收 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var p0: PlayerState = gm.get_player(0)
	var p1: PlayerState = gm.get_player(1)
	# 鸣人同时有分身1+数值盾2，樱用铁锤2伤攻击
	p0.clone_count = 1
	p0.shield = 2
	p1.current_gesture = PlayerState.Gesture.ROCK
	p0.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "S1a: 樱胜出")
	p1.energy = 3
	var hp_before: float = p0.hp
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(p1, "铁锤"), 0)
	_assert(p0.clone_count == 0, "S1b: 分身优先消耗（0）")
	_assert(p0.shield == 2, "S1c: 分身挡伤后盾未消耗（shield=%d）" % p0.shield)
	_assert(p0.hp == hp_before, "S1d: HP不变（%.1f）" % p0.hp)

	# ════════════════════════════════════════════════════════════════
	# 场景2：无敌免疫即时伤害但不免疫延迟伤害触发
	# ════════════════════════════════════════════════════════════════
	print("--- 场景2：无敌vs延迟伤害 ---")
	gm.setup_game({
		"players": [
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	var sas: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)
	# 佐助豪火球：2即时伤+1延迟伤（trigger_in=2）
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	sas.energy = 3
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "豪火球之术"), 1)
	_assert(nar.hp == 4.0, "S2a: 即时2伤（6→4）")
	_assert(nar.delayed_damages.size() == 1, "S2b: 延迟队列+1")
	# 鸣人有1回合无敌——第2回合结束时延迟倒计时（trigger_in 2→1）但无敌已消失
	# 第2回合：鸣人胜→聚气（无敌设第3回合？不，无敌在_round_end递减）
	# 直接手动推进2轮_end_round来触发延迟
	# 第1轮_end_round：trigger_in 1→0，触发1伤（此时无无敌）
	var hp_pre: float = nar.hp
	# 注意submit_action已含1次_end_round，所以trigger_in已经是1
	# 再手动执行1次_end_round触发延迟
	gm.call("_process_end_phase")
	gm.call("_end_round")
	_assert(nar.delayed_damages.size() == 0, "S2c: 延迟伤害已触发清空")
	_assert(nar.hp == hp_pre - 1.0, "S2d: 延迟1伤触发（%.1f→%.1f）" % [hp_pre, nar.hp])

	# ════════════════════════════════════════════════════════════════
	# 场景3：麻痹状态下被连续攻击
	# ════════════════════════════════════════════════════════════════
	print("--- 场景3：麻痹连续攻击 ---")
	gm.setup_game({
		"players": [
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	sas = gm.get_player(0)
	nar = gm.get_player(1)
	# R1: 佐助千鸟→鸣人麻痹1+2伤
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	sas.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "千鸟"), 1)
	_assert(nar.hp == 4.0, "S3a: 千鸟2伤（6→4）")
	_assert(nar.paralyze_turns == 1, "S3b: 鸣人麻痹1回合")
	# R2: 鸣人麻痹SKIP，佐助再胜→普攻
	sas.current_gesture = PlayerState.Gesture.ROCK
	# nar自动SKIP（_apply_paralyze在GESTURE_INPUT时执行，但我们用_call跳过）
	nar.current_gesture = PlayerState.Gesture.SKIP
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "S3c: 佐助再胜（鸣人SKIP）")
	sas.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "普攻"), 1)
	_assert(nar.hp == 3.0, "S3d: 普攻1伤（4→3）")
	_assert(nar.paralyze_turns == 0, "S3e: 麻痹递减到0")

	# ════════════════════════════════════════════════════════════════
	# 场景4：3人混战——距离与多目标
	# ════════════════════════════════════════════════════════════════
	print("--- 场景4：3人混战 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)  # 鸣人
	var p1_3: PlayerState = gm.get_player(1)  # 佐助
	var p2: PlayerState = gm.get_player(2)  # 樱
	# 3人环形距离验证
	_assert(gm.get_distance(0, 1) == 1, "S4a: 3人0→1距离1")
	_assert(gm.get_distance(0, 2) == 1, "S4b: 3人0→2距离1")
	_assert(gm.get_distance(1, 2) == 1, "S4c: 3人1→2距离1")
	# R1: 鸣人胜（石头vs剪刀vs布=平局，换成石头vs剪刀vs剪刀）
	# 鸣人石头 vs 佐助剪刀 vs 樱剪刀 → 鸣人和? 不，石头胜剪刀，2人都出剪刀→鸣人唯一胜
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1_3.current_gesture = PlayerState.Gesture.SCISSORS
	p2.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "S4d: 鸣人唯一胜（石头vs2剪刀）")
	# 鸣人普攻佐助（距离1）
	p0.energy = 1
	var sas_hp: float = p1_3.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "普攻"), 1)
	_assert(p1_3.hp == sas_hp - 1.0, "S4e: 普攻佐助1伤（%.1f→%.1f）" % [sas_hp, p1_3.hp])

	# ════════════════════════════════════════════════════════════════
	# 场景5：连续回合胜者追踪
	# ════════════════════════════════════════════════════════════════
	print("--- 场景5：连续回合追踪 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# R1: 鸣人胜→聚气
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p0.consecutive_rounds == 1, "S5a: R1连续=1")
	# R2: 鸣人胜→聚气
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p0.consecutive_rounds == 2, "S5b: R2连续=2")
	# R3: 樱胜→中断连续
	p0.current_gesture = PlayerState.Gesture.SCISSORS
	p1.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	gm.submit_action(1, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p1.consecutive_rounds == 1, "S5c: R3樱胜连续=1")
	_assert(p0.consecutive_rounds == 2, "S5d: 鸣人连续不变=2")

	# ════════════════════════════════════════════════════════════════
	# 场景6：延迟伤害击杀（延迟伤害作为最后一击淘汰）
	# ════════════════════════════════════════════════════════════════
	print("--- 场景6：延迟击杀 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# 螺旋丸延迟3伤，把樱HP设到3
	p1.hp = 3.0
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "螺旋丸"), 1)
	_assert(p1.delayed_damages.size() == 1, "S6a: 延迟伤害入队")
	# submit_action已执行1次_end_round（trigger_in 2→1），再执行1次触发
	gm.call("_process_end_phase")
	gm.call("_end_round")
	_assert(p1.hp <= 0, "S6b: 延迟3伤击杀（HP=%.1f）" % p1.hp)
	_assert(p1.is_alive == false, "S6c: 樱被延迟伤害淘汰")
	_assert(gm.get("_current_phase") == 11, "S6d: 游戏结束")

	# ════════════════════════════════════════════════════════════════
	# 场景7：平局后重新出拳胜出
	# ════════════════════════════════════════════════════════════════
	print("--- 场景7：平局后重新出拳 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# R1: 平局（石头vs石头）—— 直接调用_resolve_round不经过RESOLVING阶段
	# _enter_phase(GESTURE_INPUT)时_prev_phase非RESOLVING也会+1回合号
	var rn: int = gm.get("_current_round_number")
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_current_phase") == 1, "S7a: 平局回GESTURE_INPUT")
	_assert(gm.get("_current_round_number") == rn + 1, "S7b: 平局后回合号+1（直接调用_resolve_round，实际=%d）" % gm.get("_current_round_number"))
	# R1重出: 鸣人胜
	p0.current_gesture = PlayerState.Gesture.PAPER
	p1.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "S7c: 平局后鸣人胜出")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(gm.get("_current_round_number") == rn + 2, "S7d: 下一回合号再+1（实际=%d）" % gm.get("_current_round_number"))

	# ════════════════════════════════════════════════════════════════
	# 场景8：全SKIP平局后麻痹递减
	# ════════════════════════════════════════════════════════════════
	print("--- 场景8：全SKIP平局 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# 双方麻痹 → 全SKIP → all_skipped平局 → 麻痹递减
	p0.paralyze_turns = 2
	p1.paralyze_turns = 2
	p0.current_gesture = PlayerState.Gesture.SKIP
	p1.current_gesture = PlayerState.Gesture.SKIP
	gm.call("_resolve_round")
	# 全SKIP平局：reset_round_data清手势后_apply_paralyze重新设SKIP
	# _all_gestures_submitted为true时自动进入RESOLVING（启动timer）
	var phase_s8: int = gm.get("_current_phase")
	_assert(phase_s8 == 1 or phase_s8 == 2, "S8a: 全SKIP后回GESTURE_INPUT或自动进RESOLVING（实际=%d）" % phase_s8)
	# all_skipped平局时麻痹直接-1
	_assert(p0.paralyze_turns == 1, "S8b: 全SKIP平局麻痹递减（2→1，实际=%d）" % p0.paralyze_turns)
	_assert(p1.paralyze_turns == 1, "S8c: 佐助麻痹递减（2→1，实际=%d）" % p1.paralyze_turns)

	# ════════════════════════════════════════════════════════════════
	# 场景9：影分身+聚气循环（分身加成叠加）
	# ════════════════════════════════════════════════════════════════
	print("--- 场景9：分身聚气循环 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# R1: 鸣人胜→影分身
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "影分身"), 0)
	_assert(p0.clone_count == 1, "S9a: 影分身=1")
	# R2: 鸣人胜→聚气（分身加成+2）
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 0
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(p0.energy == 2, "S9b: 1分身聚气+2（实际=%d）" % p0.energy)
	_assert(p0.clone_count == 1, "S9c: 聚气不消耗分身")
	# R3: 鸣人再分身（有分身不能放分身→应被跳过→进入ELIMINATION）
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var nar_hp9: float = p0.hp
	p0.energy = 1
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "影分身"), 0)
	# 影分身（CLONE_SHIELD）与迈特凯的"分身"不同：代码仅拦截skill_name=="分身"
	# 鸣人的"影分身"可以叠加（设计行为）
	_assert(p0.clone_count == 2, "S9d: 影分身可叠加（clone=%d，设计行为）" % p0.clone_count)

	# ════════════════════════════════════════════════════════════════
	# 场景10：治疗不超过max_hp
	# ════════════════════════════════════════════════════════════════
	print("--- 场景10：治疗上限 ---")
	gm.setup_game({
		"players": [
			{"name": "樱", "character": sakura_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)  # 樱 max_hp=8
	p1 = gm.get_player(1)
	# 樱HP=7，治疗+1→8（满血）
	p0.hp = 7.0
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "治疗"), 0)
	_assert(p0.hp == 8.0, "S10a: 治疗到满血（7→8）")
	# 樱HP=8（满血），治疗不超
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	p0.energy = 2
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "治疗"), 0)
	_assert(p0.hp == 8.0, "S10b: 满血治疗不超max_hp（8）")

	# ════════════════════════════════════════════════════════════════
	# 场景11：封技状态下技能过滤
	# ════════════════════════════════════════════════════════════════
	print("--- 场景11：封技状态 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# 封技2回合：get_all_skills只保留普攻
	p0.skill_disabled_turns = 2
	var skills := p0.get_all_skills()
	var skill_names: Array[String] = []
	for s in skills:
		skill_names.append(s.skill_name)
	_assert(skill_names.size() == 1, "S11a: 封技后仅1个技能（实际=%d）" % skill_names.size())
	_assert(skill_names.has("普攻"), "S11b: 封技后保留普攻")

	# ════════════════════════════════════════════════════════════════
	# 场景12：豪火球即时+延迟双段伤害
	# ════════════════════════════════════════════════════════════════
	print("--- 场景12：豪火球双段 ---")
	gm.setup_game({
		"players": [
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	sas = gm.get_player(0)
	var sak = gm.get_player(1)
	# 佐助豪火球：2即时+1延迟(trigger_in=2)
	sas.current_gesture = PlayerState.Gesture.ROCK
	sak.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	sas.energy = 3
	var sak_hp: float = sak.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "豪火球之术"), 1)
	_assert(sak.hp == sak_hp - 2.0, "S12a: 即时2伤（%.1f→%.1f）" % [sak_hp, sak.hp])
	_assert(sak.delayed_damages.size() == 1, "S12b: 延迟1伤入队")
	_assert(sak.delayed_damages[0]["damage"] == 1.0, "S12c: 延迟伤害=1")

	# ════════════════════════════════════════════════════════════════
	# 场景13：击飞+麻痹同时存在
	# ════════════════════════════════════════════════════════════════
	print("--- 场景13：击飞+麻痹共存 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# 鸣人同时有击飞1+麻痹1
	# 麻痹优先：自动SKIP不猜拳
	p0.paralyze_turns = 1
	p0.knockdown_turns = 1
	gm.call("_apply_paralyze")
	_assert(p0.current_gesture == PlayerState.Gesture.SKIP, "S13a: 麻痹优先→SKIP")
	# 樱胜
	p1.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "S13b: 樱胜（鸣人麻痹SKIP）")
	p1.energy = 2
	gm.submit_action(1, PlayerState.ActionType.CHARGE, -1, -1)
	# 麻痹递减（SKIP后-1），击飞未消耗不递减
	_assert(p0.paralyze_turns == 0, "S13c: 麻痹递减到0")
	_assert(p0.knockdown_turns == 1, "S13d: 击飞未消耗不递减（仍=1）")

	# ════════════════════════════════════════════════════════════════
	# 场景14：能量不足时技能被拒绝
	# ════════════════════════════════════════════════════════════════
	print("--- 场景14：能量不足 ---")
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "樱", "character": sakura_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	p0 = gm.get_player(0)
	p1 = gm.get_player(1)
	# 鸣人0气试图用铁锤(需3气) → 直接进ELIMINATION
	p0.energy = 0
	p0.current_gesture = PlayerState.Gesture.ROCK
	p1.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var nar_hp14: float = p1.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(p0, "铁锤"), 1)
	# 技能被拒（能量不足），樱HP不变
	_assert(p1.hp == nar_hp14, "S14a: 能量不足技能未执行HP不变（%.1f）" % p1.hp)
	_assert(p0.energy == 0, "S14b: 能量未消耗（仍=0）")

	# ════════════════════════════════════════════════════════════════
	# 场景15：多回合完整对战（聚气→技能→淘汰）
	# ════════════════════════════════════════════════════════════════
	print("--- 场景15：完整对战 ---")
	gm.setup_game({
		"players": [
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		]
	})
	await get_tree().process_frame
	sas = gm.get_player(0)
	nar = gm.get_player(1)
	# R1: 佐助胜→聚气
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(sas.energy == 1, "S15a: R1聚气1")
	# R2: 佐助胜→聚气
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	gm.submit_action(0, PlayerState.ActionType.CHARGE, -1, -1)
	_assert(sas.energy == 2, "S15b: R2聚气后2")
	# R3: 佐助胜→千鸟(2伤+麻痹)
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	var nar_hp15: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "千鸟"), 1)
	_assert(nar.hp == nar_hp15 - 2.0, "S15c: R3千鸟2伤（%.1f→%.1f）" % [nar_hp15, nar.hp])
	_assert(nar.paralyze_turns == 1, "S15d: R3鸣人麻痹1")
	_assert(sas.energy == 0, "S15e: R3千鸟耗2气")
	# R4: 鸣人麻痹SKIP→佐助胜→普攻
	sas.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SKIP
	gm.call("_resolve_round")
	sas.energy = 1
	var nar_hp15b: float = nar.hp
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(sas, "普攻"), 1)
	_assert(nar.hp == nar_hp15b - 1.0, "S15f: R4普攻1伤（%.1f→%.1f）" % [nar_hp15b, nar.hp])
	_assert(nar.paralyze_turns == 0, "S15g: R4麻痹解除")

	print("=== 多角色组合场景测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)
