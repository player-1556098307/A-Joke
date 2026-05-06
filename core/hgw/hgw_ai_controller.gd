## HGWAIController — AI decision-making for HGW mode
## Handles move, action, RPS gesture, and skill selection for AI players
class_name HGWAIController
extends RefCounted

func decide_move(player: HGWPlayerState, reachable: Array[Vector2i], game_mgr: HGWGameManager) -> Vector2i:
	if reachable.is_empty():
		return Vector2i(player.hex_q, player.hex_r)

	# Simple heuristic: prefer cells closer to enemies, or random
	var enemies := _get_alive_enemies(player, game_mgr)
	if not enemies.is_empty():
		var best := reachable[0]
		var best_score := -1.0
		for cell: Vector2i in reachable:
			var nearest_enemy_dist := 999
			for enemy: HGWPlayerState in enemies:
				var dist := _hex_distance(cell.x, cell.y, enemy.hex_q, enemy.hex_r)
				if dist < nearest_enemy_dist:
					nearest_enemy_dist = dist
			# Prefer cells that bring us closer to at least one enemy but not adjacent to multiple
			var score := 6.0 - float(nearest_enemy_dist)
			# Slight preference for resources
			var map_cell = game_mgr.get_cell(cell.x, cell.y)
			if map_cell and map_cell.is_resource:
				score += 0.5
			# Penalty for being adjacent to many enemies (dangerous)
			var adjacent_enemies := 0
			for enemy: HGWPlayerState in enemies:
				var ed := _hex_distance(cell.x, cell.y, enemy.hex_q, enemy.hex_r)
				if ed <= 1:
					adjacent_enemies += 1
			score -= float(adjacent_enemies) * 0.3
			if score > best_score:
				best_score = score
				best = cell
		return best

	return reachable[randi() % reachable.size()]

func decide_action(player: HGWPlayerState, enemies_in_range: Array[HGWPlayerState], _game_mgr: HGWGameManager) -> Dictionary:
	if not enemies_in_range.is_empty() and player.energy >= 2:
		var target := _find_weakest(enemies_in_range)
		return {"type": "attack", "target_id": target.player_id}
	if player.energy < 4:
		return {"type": "gather", "target_id": -1}
	# Small chance to skip even when energy is high
	if randi() % 5 == 0:
		return {"type": "skip", "target_id": -1}
	return {"type": "gather", "target_id": -1}

func decide_rps_gesture() -> int:
	return randi() % 3

func decide_skill(available_skills: Array, player_energy: int) -> int:
	var best_idx := 0
	var best_cost := -1
	for i in available_skills.size():
		var sk: SkillData = available_skills[i]
		if sk.energy_cost <= player_energy and sk.energy_cost > best_cost:
			best_cost = sk.energy_cost
			best_idx = i
	return best_idx

func decide_b_skill(player: HGWPlayerState) -> int:
	# Return index of a B-class skill to use, or -1 if none
	if player.character == null:
		return -1
	var skills: Array = player.character.skills
	for i in skills.size():
		var sk: SkillData = skills[i]
		if _is_b_class(sk) and player.energy >= sk.energy_cost:
			# Use shadow clone if HP is low and energy available
			for effect: SkillEffect in sk.effects:
				if effect.effect_type == SkillEffect.EffectType.CLONE_SHIELD and player.clone_count == 0:
					return i
				if effect.effect_type == SkillEffect.EffectType.HEAL and player.hp < player.max_hp * 0.5:
					return i
	return -1

func _is_b_class(skill: SkillData) -> bool:
	for effect: SkillEffect in skill.effects:
		if effect.target in [SkillEffect.EffectTarget.ENEMY_SINGLE, SkillEffect.EffectTarget.ENEMY_ALL, SkillEffect.EffectTarget.ENEMY_SPLASH]:
			return false
	return true

func _get_alive_enemies(player: HGWPlayerState, game_mgr: HGWGameManager) -> Array[HGWPlayerState]:
	var enemies: Array[HGWPlayerState] = []
	for other in game_mgr.get_alive_players():
		if other.player_id != player.player_id:
			enemies.append(other)
	return enemies

func _find_weakest(enemies: Array[HGWPlayerState]) -> HGWPlayerState:
	var weakest := enemies[0]
	for e in enemies:
		if e.hp < weakest.hp:
			weakest = e
	return weakest

func _hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	return maxi(abs(q1 - q2), maxi(abs(r1 - r2), abs((q1 + r1) - (q2 + r2))))
