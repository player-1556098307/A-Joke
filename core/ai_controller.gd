## AI控制器 — 非人类玩家（AI）的决策逻辑
## 手势随机选择，技能按条件筛选后随机使用，无可用技能时自动充能
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
func decide_action(
	player: PlayerState,
	alive_players: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var others: Array[PlayerState] = []
	for p in alive_players:
		if p.player_id != player.player_id:
			others.append(p)

	# 收集所有能量足够且有合法目标的技能
	var all_skills := player.get_all_skills()
	var usable: Array[Dictionary] = []
	for i in range(all_skills.size()):
		var skill: SkillData = all_skills[i]
		if player.energy < skill.energy_cost:
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

		return { "action": PlayerState.ActionType.USE_SKILL, "skill_index": skill_index, "target_id": target_id }

	return { "action": PlayerState.ActionType.CHARGE, "skill_index": -1, "target_id": -1 }

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
