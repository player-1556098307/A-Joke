## AI控制器 — 非人类玩家（AI）的决策逻辑
## 手势随机选择，技能按条件筛选后随机使用，无可用技能时自动充能
## 支持钟消耗、招架决策、限定技使用、血付选择、迈特凯八门策略
class_name AIController
extends RefCounted

## 随机选择手势：ROCK/SCISSORS/PAPER 等概率
func decide_gesture(_player: PlayerState) -> PlayerState.Gesture:
	var options := [
		PlayerState.Gesture.ROCK,
		PlayerState.Gesture.SCISSORS,
		PlayerState.Gesture.PAPER
	]
	return options[randi() % 3]

## 决定行动：在可用技能中随机选择，没有则充能
## 返回 {action: ActionType, skill_index: int, target_id: int}
## 迈特凯策略：八门未全开时优先聚气开门；有分身+夜凯时自动双龙；血付技能用血补气
func decide_action(
	player: PlayerState,
	alive_players: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	# 击飞状态：强制只能聚气
	if player.knockdown_turns > 0:
		return {
			"action": PlayerState.ActionType.CHARGE,
			"skill_index": -1,
			"target_id": -1,
		}

	# 目标池：排除自己；组队/塔模式（team_id != 0）下排除队友（AI不打自己人）
	var others: Array[PlayerState] = []
	for p in alive_players:
		if p.player_id == player.player_id:
			continue
		if player.team_id != 0 and p.team_id == player.team_id:
			continue
		others.append(p)

	# 迈特凯特殊策略
	if _is_might_gai(player):
		var result := _decide_might_gai_action(player, others, distance_system)
		if result.size() > 0:
			# 血付处理：可血付技能在气不足时设置 pending_hp_payment
			_setup_hp_payment_if_needed(player, result)
			return result

	# 波风水门特殊策略
	if _is_minato(player):
		var result := _decide_minato_action(player, others, distance_system)
		if result.size() > 0:
			return result

	# 希耶尔特殊策略
	if _is_xiye(player):
		var result := _decide_xiye_action(player, others, distance_system)
		if result.size() > 0:
			_setup_hp_payment_if_needed(player, result)
			return result

	# 卫宫特殊策略
	if _is_emiya(player):
		var result := _decide_emiya_action(player, others, distance_system)
		if result.size() > 0:
			_setup_hp_payment_if_needed(player, result)
			return result

	# 秽土柱间特殊策略
	if _is_edo_hashirama(player):
		var result := _decide_edo_hashirama_action(player, others, distance_system)
		if result.size() > 0:
			return result

	# 宇智波泉奈特殊策略
	if _is_izuna(player):
		var result := _decide_izuna_action(player, others, distance_system)
		if result.size() > 0:
			return result

	# 新止水（天劫）特殊策略
	if _is_new_shisui(player):
		var result := _decide_new_shisui_action(player, others, distance_system)
		if result.size() > 0:
			return result

	# 大黑塔特殊策略
	if _is_big_herta(player):
		var result := _decide_big_herta_action(player, others, distance_system)
		if result.size() > 0:
			return result

	# 收集所有能量+钟足够且有合法目标的技能
	var all_skills := player.get_all_skills()
	var usable: Array[Dictionary] = []
	for i in range(all_skills.size()):
		var skill: SkillData = all_skills[i]
		if player.energy < skill.energy_cost:
			continue
		if player.bell_count < skill.bell_cost:
			continue
		if skill.is_limited and skill.skill_name in player.limited_skills_used:
			continue
		if _has_valid_target(player, skill, others, distance_system):
			usable.append({ "index": i, "skill": skill })

	if usable.size() > 0:
		var chosen: Dictionary = usable[randi() % usable.size()]
		var skill: SkillData   = chosen["skill"]
		var skill_index: int   = chosen["index"]
		var target_id          := -1

		# 需要单一目标的技能，随机选一个合法目标
		var needs_single_target := false
		for effect in skill.effects:
			if effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE:
				needs_single_target = true
				break

		if needs_single_target:
			var valid: Array[PlayerState] = []
			for other in others:
				if RoundResolver.can_use_skill(player, skill, other, distance_system):
					valid.append(other)
			if valid.size() > 0:
				target_id = valid[randi() % valid.size()].player_id

		var result := { "action": PlayerState.ActionType.USE_SKILL, "skill_index": skill_index, "target_id": target_id }
		_setup_hp_payment_if_needed(player, result)
		return result

	return { "action": PlayerState.ActionType.CHARGE, "skill_index": -1, "target_id": -1 }

## 判断角色是否为迈特凯（通过技能名判断）
func _is_might_gai(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "八门遁甲":
			return true
	return false

## 判断角色是否为波风水门（通过技能名"飞雷神"判断）
func _is_minato(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "飞雷神":
			return true
	return false

## 判断角色是否为希耶尔（通过技能名"相位滑剑"判断）
func _is_xiye(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "相位滑剑":
			return true
	return false

## 判断角色是否为秽土柱间（通过独有技能"仙法·树界降诞"判断）
## 注意：不能用"仙人之力"判断——仙人鸣人（仙人模式）也有同名被动技能（聚气+1），会误判
func _is_edo_hashirama(player: PlayerState) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "仙法·树界降诞":
			return true
	return false

## 判断角色是否为卫宫（通过技能名"无限剑制"判断）
func _is_emiya(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "无限剑制":
			return true
	return false

## 判断角色是否为宇智波泉奈（通过技能名"宇智波的荣耀"判断）
func _is_izuna(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "宇智波的荣耀":
			return true
	return false

## 判断角色是否为新止水（天劫）：通过技能名"日影舞"判断
func _is_new_shisui(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "日影舞":
			return true
	return false

## 判断角色是否为大黑塔（通过技能名"解读"判断）
func _is_big_herta(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "解读":
			return true
	return false

## 大黑塔专用决策策略
## 优先级：魔法（3气，主目标优先【解】玩家/低血）> 普攻 > 充能
## 解读/格局打开为被动自动触发，AI只需决定主动行动
func _decide_big_herta_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 魔法：3气，主目标2伤 + 所有【解】玩家1伤（AOE）
	var magic_idx := _find_skill_index(all_skills, player, "魔法")
	if magic_idx >= 0 and player.energy >= 3:
		var target := _pick_best_target(player, all_skills[magic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": magic_idx, "target_id": target }

	# 2. 普攻：有气时攻击（触发解读标记）
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	# 返回空让调用方走默认充能逻辑
	return {}

## 宇智波泉奈专用决策策略
## 优先级：宇智波流（2耗，突进+招架，残血/被针对时防御性使用）> 豪火球（2耗，范围2，2伤+灼烧）> 普攻 > 充能
func _decide_izuna_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 宇智波流：2耗突进+招架（半血以下或气多时防御性使用，招架反制近战）
	if player.hp <= player.character.max_hp * 0.5:
		var stance_idx := _find_skill_index(all_skills, player, "宇智波流")
		if stance_idx >= 0 and player.energy >= 2:
			var target := _pick_best_target(player, all_skills[stance_idx], others, distance_system)
			if target >= 0:
				return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": stance_idx, "target_id": target }

	# 2. 豪火球：2耗，范围2，2伤+下回合末灼烧
	var fireball_idx := _find_skill_index(all_skills, player, "火遁·豪火球")
	if fireball_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[fireball_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": fireball_idx, "target_id": target }

	# 3. 普攻：有气时攻击
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	return {}

## 新止水（天劫）专用决策策略
## 优先级：日影舞（3幻影+3气，4段2伤爆发）> 普攻（攒幻影+增伤）> 充能
func _decide_new_shisui_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 日影舞：3幻影+3气时释放（4段2伤，优先低血目标）
	if player.phantom_count >= 3 and player.energy >= 3:
		var hiroari_idx := _find_skill_index(all_skills, player, "日影舞")
		if hiroari_idx >= 0:
			# 目标交给 GameManager 的 AI 分配（按血线），此处指定最低血目标即可
			var target := _pick_best_target(player, all_skills[hiroari_idx], others, distance_system)
			if target >= 0:
				return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": hiroari_idx, "target_id": target }

	# 2. 普攻：有气时攻击（命中+1幻影，每个幻影+0.5伤）
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	# 3. 幻影<3时聚气（攒幻影+攒气）
	if player.phantom_count < 3:
		return { "action": PlayerState.ActionType.CHARGE, "skill_index": -1, "target_id": -1 }

	return {}

## 秽土柱间专用决策策略
## 优先级：真数千手(4气全屏) > 明神门(限定技+2气禁锢) > 木人之术/木龙(2气高伤) > 树界降诞/花树界(2气禁锢) > 普攻 > 充能
func _decide_edo_hashirama_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 真数千手：4气全屏伤害，能量足够时优先
	var shinsusenju_idx := _find_skill_index(all_skills, player, "仙法·真数千手")
	if shinsusenju_idx >= 0 and player.energy >= 4:
		return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": shinsusenju_idx, "target_id": player.player_id }

	# 2. 明神门：2气限定技，禁锢+2气
	var meishinmon_idx := _find_skill_index(all_skills, player, "明神门")
	if meishinmon_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[meishinmon_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": meishinmon_idx, "target_id": target }

	# 3. 木人之术/木龙：2气高伤
	var mokujin_idx := _find_skill_index(all_skills, player, "木人之术")
	if mokujin_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[mokujin_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": mokujin_idx, "target_id": target }

	# 4. 树界降生/花树界：2气禁锢
	var tree_idx := _find_skill_index(all_skills, player, "树界降诞")
	if tree_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[tree_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": tree_idx, "target_id": target }

	# 5. 普攻：有气时攻击
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	# 返回空让调用方走默认充能逻辑
	return {}

## 希耶尔专用决策策略
## 优先级：断罪死（6耗斩杀，目标血量低或赢4次即死）> 断头台（4耗4伤无视防御）> 普攻 > 充能
func _decide_xiye_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 断罪死：6耗，无视距离，赢4次即死。目标血量低时优先（预期斩杀）
	var death_sentence_idx := _find_skill_index(all_skills, player, "第七圣典·断罪死")
	if death_sentence_idx >= 0 and player.energy >= 6:
		var target := _pick_best_target(player, all_skills[death_sentence_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": death_sentence_idx, "target_id": target }

	# 2. 断头台：4耗4伤无视防御，低血量目标优先（满血希耶尔还能x2）
	var guillotine_idx := _find_skill_index(all_skills, player, "原理血戒·断头台")
	if guillotine_idx >= 0 and player.energy >= 4:
		var target := _pick_best_target(player, all_skills[guillotine_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": guillotine_idx, "target_id": target }

	# 3. 普攻：有气时攻击（满血时普攻可x2）
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	return {}

## 卫宫专用决策策略
## 优先级：无限剑制（3耗，结界+下次必赢）> 结界内技能（原耗气）> 投影技能（用掉）> 伪·螺旋剑（2耗4伤）> 普攻 > 充能
func _decide_emiya_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 无限剑制：3耗开启结界，释放后下次猜拳必赢（无结界或结界将结束时优先）
	if player.binding_field_turns == 0:
		var ubw_idx := _find_skill_index(all_skills, player, "无限剑制")
		if ubw_idx >= 0 and player.energy >= 3:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": ubw_idx, "target_id": player.player_id }

	# 2. 结界内技能：优先使用高伤害/低耗技能（跳过投影、无限剑制、普攻自身）
	var best_bf_idx: int = -1
	var best_bf_skill: SkillData = null
	for i in range(all_skills.size()):
		var s: SkillData = all_skills[i]
		if s.skill_name == "投影" or s.skill_name == "无限剑制" or s.skill_name == "普攻":
			continue
		if s.is_passive:
			continue  # 被动技不需要主动使用
		if player.energy < s.energy_cost:
			continue
		if not _has_valid_target(player, s, others, distance_system):
			continue
		if best_bf_skill == null or s.energy_cost < best_bf_skill.energy_cost \
		or (s.energy_cost == best_bf_skill.energy_cost and _skill_damage(s) > _skill_damage(best_bf_skill)):
			best_bf_idx = i
			best_bf_skill = s
	if best_bf_idx >= 0:
		var target := _pick_best_target(player, best_bf_skill, others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": best_bf_idx, "target_id": target }

	# 3. 投影技能：用完即消失，有投影时优先用掉
	if player.projected_skill != null and not player.projected_used_this_round:
		var proj_idx := _find_skill_index(all_skills, player, player.projected_skill.skill_name)
		if proj_idx >= 0 and player.energy >= player.projected_skill.energy_cost:
			var pt := _pick_best_target(player, player.projected_skill, others, distance_system)
			if pt >= 0:
				return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": proj_idx, "target_id": pt }

	# 4. 伪·螺旋剑：2耗4伤
	var spiral_idx := _find_skill_index(all_skills, player, "伪·螺旋剑")
	if spiral_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[spiral_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": spiral_idx, "target_id": target }

	# 5. 普攻：有气时攻击
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	return {}

## 估算技能伤害（用于结界技能比较优先级）
func _skill_damage(skill: SkillData) -> float:
	var dmg: float = 0.0
	for effect in skill.effects:
		if effect.effect_type in [
			SkillEffect.EffectType.DAMAGE,
			SkillEffect.EffectType.TRUE_DAMAGE,
			SkillEffect.EffectType.PIERCE_DAMAGE,
		]:
			dmg = max(dmg, effect.value)
	return dmg

## 波风水门专用决策策略
## 优先级：漂泊九尾（高气+限定）> 螺旋丸（有气+有标记连击）> 飞雷神（有标记）> 飞雷神聚 > 普攻 > 充能
func _decide_minato_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 漂泊九尾：5气限定技，高气时优先释放
	var nine_tails_idx := _find_skill_index(all_skills, player, "漂泊九尾")
	if nine_tails_idx >= 0 and player.energy >= 5:
		# 策略：气满5时释放九尾
		return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": nine_tails_idx, "target_id": player.player_id }

	# 2. 螺旋丸：2气3伤，无视距离
	var rasengan_idx := _find_skill_index(all_skills, player, "螺旋丸")
	if rasengan_idx >= 0 and player.energy >= 2:
		var target := _pick_best_target(player, all_skills[rasengan_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": rasengan_idx, "target_id": target }

	# 3. 飞雷神：消耗1标记，0.5伤+标记
	var ftg_idx := _find_skill_index(all_skills, player, "飞雷神")
	if ftg_idx >= 0 and player.ftg_marks >= 1:
		var target := _pick_best_target(player, all_skills[ftg_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": ftg_idx, "target_id": target }

	# 4. 飞雷神聚：0气获得标记（需行动权）
	var ftg_charge_idx := _find_skill_index(all_skills, player, "飞雷神聚")
	if ftg_charge_idx >= 0 and player.ftg_marks < 5:
		return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": ftg_charge_idx, "target_id": player.player_id }

	# 5. 飞雷神拔除：被标记时拔除
	if player.ftg_marked_by.size() > 0:
		var ftg_remove_idx := _find_skill_index(all_skills, player, "飞雷神拔除")
		if ftg_remove_idx >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": ftg_remove_idx, "target_id": player.player_id }

	# 6. 普攻：有气时攻击
	var basic_idx := _find_skill_index(all_skills, player, "普攻")
	if basic_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[basic_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": basic_idx, "target_id": target }

	# 返回空让调用方走默认充能逻辑
	return {}

## 迈特凯专用决策策略
## 优先级：双龙戏珠（有分身+夜凯时）> 夜凯/昼虎（高伤害）> 夕象 > 分身 > 聚气
func _decide_might_gai_action(
	player: PlayerState,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var all_skills := player.get_all_skills()

	# 1. 双龙戏珠：有分身时夜凯自动变双龙（夜凯在技能列表中，使用时会自动变）
	if player.clone_count > 0:
		var night_kai_idx := _find_skill_index(all_skills, player, "夜凯")
		if night_kai_idx >= 0 and player.energy >= 5 and not "夜凯" in player.limited_skills_used:
			var target := _pick_best_target(player, all_skills[night_kai_idx], others, distance_system)
			if target >= 0:
				return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": night_kai_idx, "target_id": target }

	# 2. 昼虎：5耗4伤，高伤害优先
	var day_tiger_idx := _find_skill_index(all_skills, player, "昼虎")
	if day_tiger_idx >= 0 and player.energy >= 5:
		var target := _pick_best_target(player, all_skills[day_tiger_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": day_tiger_idx, "target_id": target }

	# 3. 夜凯（无分身时直接5伤）
	var night_kai_idx2 := _find_skill_index(all_skills, player, "夜凯")
	if night_kai_idx2 >= 0 and player.energy >= 5 and not "夜凯" in player.limited_skills_used:
		var target := _pick_best_target(player, all_skills[night_kai_idx2], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": night_kai_idx2, "target_id": target }

	# 4. 夕象：1耗，连续回合增伤
	var evening_elephant_idx := _find_skill_index(all_skills, player, "夕象")
	if evening_elephant_idx >= 0 and player.energy >= 1:
		var target := _pick_best_target(player, all_skills[evening_elephant_idx], others, distance_system)
		if target >= 0:
			return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": evening_elephant_idx, "target_id": target }

	# 5. 分身：2耗2伤，有分身时不可再放
	if player.clone_count == 0:
		var clone_idx := _find_skill_index(all_skills, player, "分身")
		if clone_idx >= 0 and player.energy >= 2:
			var target := _pick_best_target(player, all_skills[clone_idx], others, distance_system)
			if target >= 0:
				return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": clone_idx, "target_id": target }

	# 6. 八门未全开时优先聚气（八门遁甲被动，聚气=开门）
	# 返回空让 AI 走默认充能逻辑
	return {}

## 在技能列表中查找指定技能的索引
func _find_skill_index(all_skills: Array[SkillData], _player: PlayerState, skill_name: String) -> int:
	for i in range(all_skills.size()):
		if all_skills[i].skill_name == skill_name:
			return i
	return -1

## 选择最佳目标（最低HP的敌人）
func _pick_best_target(player: PlayerState, skill: SkillData, others: Array[PlayerState], distance_system: DistanceSystem) -> int:
	var valid: Array[PlayerState] = []
	for other in others:
		if RoundResolver.can_use_skill(player, skill, other, distance_system):
			valid.append(other)
	if valid.size() == 0:
		return -1
	# 优先攻击低HP目标
	valid.sort_custom(func(a, b): return a.hp < b.hp)
	return valid[0].player_id

## 血付处理：可血付技能在气不足时，设置 pending_hp_payment（用HP补足气缺口）
func _setup_hp_payment_if_needed(player: PlayerState, result: Dictionary) -> void:
	if result.get("action", -1) != PlayerState.ActionType.USE_SKILL:
		return
	var skill_index: int = result.get("skill_index", -1)
	if skill_index < 0:
		return
	var all_skills := player.get_all_skills()
	if skill_index >= all_skills.size():
		return
	var skill: SkillData = all_skills[skill_index]
	if skill.can_pay_with_hp and player.energy < skill.energy_cost:
		player.pending_hp_payment = skill.energy_cost - player.energy

## 招架决策：END_PHASE阶段有钟时是否消耗钟进入防反（招架）
## 策略：HP越低越倾向招架（低血量时招架减半伤害收益高），钟多时更倾向使用
func decide_bell_action(player: PlayerState, alive_players: Array[PlayerState]) -> bool:
	if player.bell_count <= 0:
		return false
	var hp_ratio: float = player.hp / player.character.max_hp
	# 血量越低越倾向招架；钟多也倾向使用
	if hp_ratio <= 0.35:
		return true
	if hp_ratio <= 0.6 and player.bell_count >= 2:
		return true
	if player.bell_count >= 3:
		return true
	return false

## 检查技能是否有至少一个合法目标（包含 SELF 类型和敌对目标）
func _has_valid_target(
	player: PlayerState,
	skill: SkillData,
	others: Array[PlayerState],
	distance_system: DistanceSystem
) -> bool:
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.SELF:
			return true
		for other in others:
			if RoundResolver.can_use_skill(player, skill, other, distance_system):
				return true
	return false