class_name AIController
extends RefCounted

func decide_gesture(_player: PlayerState) -> PlayerState.Gesture:
	var options := [
		PlayerState.Gesture.ROCK,
		PlayerState.Gesture.SCISSORS,
		PlayerState.Gesture.PAPER
	]
	return options[randi() % 3]

func decide_action(
	player: PlayerState,
	alive_players: Array[PlayerState],
	distance_system: DistanceSystem
) -> Dictionary:
	var others: Array[PlayerState] = []
	for p in alive_players:
		if p.player_id != player.player_id:
			others.append(p)

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
