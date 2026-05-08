## 回合结算器 — 纯静态工具类，无状态，所有方法均为静态函数
## 负责手势胜负判定和技能效果执行，可复用于网络对战等场景
class_name RoundResolver

## 猜拳结算：过滤 SKIP 玩家，按石头剪刀布规则判定胜负
## 特殊规则：仅1人出有效手势 → 直接胜出；全部跳过 → all_skipped 标记
## 返回 {winners: Array[int], losers: Array[int], is_draw: bool, [all_skipped]: bool}
static func resolve_gestures(gestures: Dictionary) -> Dictionary:
	var result: Dictionary = { "winners": [], "losers": [], "is_draw": false }

	var active: Dictionary = {}
	for pid in gestures:
		if gestures[pid] != PlayerState.Gesture.SKIP:
			active[pid] = gestures[pid]

	if active.is_empty():
		result["is_draw"] = true
		result["all_skipped"] = true
		return result

	# 只剩 1 人有效出拳（其余全部跳过）→ 该玩家直接胜出，不判平
	if active.size() == 1:
		result["winners"].append(active.keys()[0])
		return result

	var has_rock     := false
	var has_scissors := false
	var has_paper    := false
	for pid in active:
		match active[pid]:
			PlayerState.Gesture.ROCK:     has_rock     = true
			PlayerState.Gesture.SCISSORS: has_scissors = true
			PlayerState.Gesture.PAPER:    has_paper    = true

	var types := (1 if has_rock else 0) + (1 if has_scissors else 0) + (1 if has_paper else 0)
	if types == 1 or (has_rock and has_scissors and has_paper):
		result["is_draw"] = true
		return result

	var winning: PlayerState.Gesture
	if has_rock and has_scissors:
		winning = PlayerState.Gesture.ROCK
	elif has_scissors and has_paper:
		winning = PlayerState.Gesture.SCISSORS
	else:
		winning = PlayerState.Gesture.PAPER

	for pid in active:
		if active[pid] == winning:
			result["winners"].append(pid)
		else:
			result["losers"].append(pid)

	return result

## 技能可用性校验：检查能量是否足够 且 目标在技能射程内
static func can_use_skill(
	attacker: PlayerState,
	skill: SkillData,
	target: PlayerState,
	distance_system: DistanceSystem
) -> bool:
	if attacker.energy < skill.energy_cost:
		return false
	var dist := distance_system.get_distance(attacker.player_id, target.player_id)
	return dist >= skill.min_range and dist <= skill.max_range

## 执行技能的所有效果，返回效果结算日志数组
## splash_targets 由 GameManager 按 splash_range 预计算后传入，避免重复计算
static func apply_effects(
	attacker: PlayerState,
	skill: SkillData,
	targets: Array[PlayerState],
	distance_system: DistanceSystem,
	splash_targets: Array[PlayerState] = []
) -> Array[Dictionary]:
	attacker.energy -= skill.energy_cost
	var logs: Array[Dictionary] = []

	for effect in skill.effects:
		match effect.target:
			SkillEffect.EffectTarget.SELF:
				var res := _apply_single_effect(effect, attacker, attacker, distance_system)
				logs.append({
					"attacker_id": attacker.player_id,
					"target_id":   attacker.player_id,
					"effect_type": effect.effect_type,
					"value":       effect.value,
					"result":      res
				})

			SkillEffect.EffectTarget.ENEMY_SINGLE, SkillEffect.EffectTarget.ENEMY_ALL:
				for tgt in targets:
					var dist := distance_system.get_distance(attacker.player_id, tgt.player_id)
					if dist >= skill.min_range and dist <= skill.max_range:
						var res := _apply_single_effect(effect, attacker, tgt, distance_system)
						logs.append({
							"attacker_id": attacker.player_id,
							"target_id":   tgt.player_id,
							"effect_type": effect.effect_type,
							"value":       effect.value,
							"result":      res
						})

			SkillEffect.EffectTarget.ENEMY_SPLASH:
				# 溅射目标由 game_manager 按 splash_range 预计算，此处直接应用
				for tgt in splash_targets:
					var res := _apply_single_effect(effect, attacker, tgt, distance_system)
					logs.append({
						"attacker_id": attacker.player_id,
						"target_id":   tgt.player_id,
						"effect_type": effect.effect_type,
						"value":       effect.value,
						"result":      res
					})

	return logs

## 应用单个技能效果到目标，处理伤害吸收链：影分身 → 无限盾 → 数值盾 → HP
static func _apply_single_effect(
	effect: SkillEffect,
	attacker: PlayerState,
	target: PlayerState,
	distance_system: DistanceSystem
) -> Dictionary:
	match effect.effect_type:
		SkillEffect.EffectType.DAMAGE:
			var raw := effect.value
			var dmg: int = raw
			var absorbed: int = 0
			var clone_broken: bool = false
			if target.clone_count > 0:
				target.clone_count -= 1
				absorbed = raw
				dmg = 0
				clone_broken = true
			elif target.shield == -1:
				absorbed = raw
				dmg = 0
				target.shield = 0
			elif target.shield > 0:
				absorbed = min(raw, target.shield)
				dmg = max(0, raw - target.shield)
				target.shield = max(0, target.shield - raw)
			target.hp = max(0, target.hp - dmg)
			return { "damage_dealt": dmg, "shield_absorbed": absorbed, "remaining_hp": target.hp, "clone_destroyed": clone_broken }

		SkillEffect.EffectType.SHIELD:
			target.shield = effect.value
			return { "shield_value": effect.value }

		SkillEffect.EffectType.PARALYZE:
			target.paralyze_turns += effect.value
			return { "turns": target.paralyze_turns }

		SkillEffect.EffectType.CHANGE_DISTANCE:
			distance_system.modify_distance(attacker.player_id, target.player_id, effect.value)
			var new_dist: int = distance_system.get_distance(attacker.player_id, target.player_id)
			return { "delta": effect.value, "new_distance": new_dist }

		SkillEffect.EffectType.HEAL:
			var heal: int = min(effect.value, target.character.max_hp - target.hp)
			target.hp += heal
			return { "heal_amount": heal, "remaining_hp": target.hp }

		SkillEffect.EffectType.DELAYED_DAMAGE:
			target.delayed_damages.append({ "damage": effect.value, "trigger_in": effect.duration, "attacker_id": attacker.player_id })
			return { "delay": effect.duration, "damage": effect.value }

		SkillEffect.EffectType.CLONE_SHIELD:
			target.clone_count += 1
			return { "shield_value": -1, "clone_count": target.clone_count }

		SkillEffect.EffectType.UNLOCK_SKILL:
			if effect.unlock_skill != null and not attacker.unlocked_skills.has(effect.unlock_skill):
				attacker.unlocked_skills.append(effect.unlock_skill)
			var sname: String = effect.unlock_skill.skill_name if effect.unlock_skill != null else ""
			var spath: String = effect.unlock_skill.resource_path if effect.unlock_skill != null else ""
			return { "skill_name": sname, "skill_path": spath }

	return {}
