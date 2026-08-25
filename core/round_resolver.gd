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

## 技能可用性校验：检查能量+钟是否足够 且 目标在技能射程内 且限定技未用
static func can_use_skill(
	attacker: PlayerState,
	skill: SkillData,
	target: PlayerState,
	distance_system: DistanceSystem
) -> bool:
	if attacker.energy < skill.energy_cost:
		return false
	if attacker.bell_count < skill.bell_cost:
		return false
	if skill.ftg_cost > 0 and attacker.ftg_marks < skill.ftg_cost:
		return false
	if skill.is_limited and skill.skill_name in attacker.limited_skills_used:
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
	# 消耗钟
	if skill.bell_cost > 0:
		attacker.bell_count = max(0, attacker.bell_count - skill.bell_cost)
	# 消耗飞雷神标记
	if skill.ftg_cost > 0:
		attacker.ftg_marks = max(0, attacker.ftg_marks - skill.ftg_cost)
	# 记录限定技使用
	if skill.is_limited:
		if not skill.skill_name in attacker.limited_skills_used:
			attacker.limited_skills_used.append(skill.skill_name)
	var logs: Array[Dictionary] = []

	# 判断当前技能是否包含伤害效果（用于决定防反是否免疫同技能的控制效果）
	# 防反规则：招架状态只免疫"伴随伤害的攻击"的控制效果；纯控制技能（无伤害）正常生效
	var has_damage: bool = false
	for e in skill.effects:
		match e.effect_type:
			SkillEffect.EffectType.DAMAGE, \
			SkillEffect.EffectType.TRUE_DAMAGE, \
			SkillEffect.EffectType.PIERCE_DAMAGE, \
			SkillEffect.EffectType.FTG_MARK, \
			SkillEffect.EffectType.DEATH_SENTENCE, \
			SkillEffect.EffectType.DELAYED_DAMAGE:
				has_damage = true
				break

	for effect in skill.effects:
		match effect.target:
			SkillEffect.EffectTarget.SELF:
				var res := _apply_single_effect(effect, attacker, attacker, distance_system, skill.bonus_if_paralyzed, has_damage)
				logs.append({
					"attacker_id": attacker.player_id,
					"target_id":   attacker.player_id,
					"skill_name":  skill.skill_name,
					"effect_type": effect.effect_type,
					"value":       effect.value,
					"result":      res
				})

			SkillEffect.EffectTarget.ENEMY_SINGLE, SkillEffect.EffectTarget.ENEMY_ALL:
				for tgt in targets:
					var dist := distance_system.get_distance(attacker.player_id, tgt.player_id)
					if dist >= skill.min_range and dist <= skill.max_range:
						var res := _apply_single_effect(effect, attacker, tgt, distance_system, skill.bonus_if_paralyzed, has_damage, skill.skill_name)
						logs.append({
							"attacker_id": attacker.player_id,
							"target_id":   tgt.player_id,
							"skill_name":  skill.skill_name,
							"effect_type": effect.effect_type,
							"value":       effect.value,
							"result":      res
						})

			SkillEffect.EffectTarget.ENEMY_SPLASH:
				# 溵射目标由 game_manager 按 splash_range 预计算，此处直接应用
				for tgt in splash_targets:
					var res := _apply_single_effect(effect, attacker, tgt, distance_system, skill.bonus_if_paralyzed, has_damage, skill.skill_name)
					logs.append({
						"attacker_id": attacker.player_id,
						"target_id":   tgt.player_id,
						"skill_name":  skill.skill_name,
						"effect_type": effect.effect_type,
						"value":       effect.value,
						"result":      res
					})

			SkillEffect.EffectTarget.ENEMY_SINGLE, SkillEffect.EffectTarget.ENEMY_ALL:
				for tgt in targets:
					var dist := distance_system.get_distance(attacker.player_id, tgt.player_id)
					if dist >= skill.min_range and dist <= skill.max_range:
						var res := _apply_single_effect(effect, attacker, tgt, distance_system, skill.bonus_if_paralyzed, has_damage)
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
					var res := _apply_single_effect(effect, attacker, tgt, distance_system, skill.bonus_if_paralyzed, has_damage)
					logs.append({
						"attacker_id": attacker.player_id,
						"target_id":   tgt.player_id,
						"effect_type": effect.effect_type,
						"value":       effect.value,
						"result":      res
					})

	return logs

## ── 希耶尔被动辅助方法 ────────────────────────────────────────────────────────

## 判断目标是否处于被控制状态（麻痹或封技）
## 规则：招架（防反）状态在被控制期间保留但不触发，控制解除后自然按原有规则过期
## 防反为一次性状态：触发后立即取消，未触发则持续到自身下回合开始时清除
static func is_controlled(player: PlayerState) -> bool:
	return player.paralyze_turns > 0 or player.skill_disabled_turns > 0 or player.knockdown_turns > 0

## 判断角色是否为希耶尔（通过技能名判断）
static func is_xiye(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "相位滑剑" or skill.skill_name == "代行者":
			return true
	return false

## 代行者：对带秽土转生/死徒/法师标签的敌人造成伤害+1
static func agent_bonus(attacker: PlayerState, target: PlayerState) -> float:
	if not is_xiye(attacker):
		return 0.0
	for tag in target.character.tags:
		if tag in ["秽土转生", "死徒", "法师"]:
			return 1.0
	return 0.0

## 判断角色是否为大黑塔（通过技能名"解读"判断）
static func is_big_herta(player: PlayerState) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "解读":
			return true
	return false

## 谋略（司马懿）：免疫判定效果（麻痹/封技/击飞/无法选择等控制）
static func is_strategist(player: PlayerState) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "谋略":
			return true
	return false

## 解读（大黑塔）：目标带有【该大黑塔施加的】解标记时，伤害+1
## 按施法者区分：只有标记者本人享受增伤，其他同角色大黑塔不互通
static func jiedu_bonus(attacker: PlayerState, target: PlayerState) -> float:
	if attacker == null or target == null:
		return 0.0
	if not is_big_herta(attacker):
		return 0.0
	if not target.jiedu_by.has(attacker.player_id):
		return 0.0
	return 1.0

## 相位滑剑：满血伤害x2；没气获得1气；伤害致濒死时置位可暴击
## 返回 {multiplier: float, energy_gained: int, crit_armed: bool}
static func phase_sword_pre_apply(attacker: PlayerState, dmg_before: float) -> Dictionary:
	var result := { "multiplier": 1.0, "energy_gained": 0, "crit_armed": false }
	if not is_xiye(attacker):
		return result
	# 满血 -> 伤害x2
	if attacker.hp >= attacker.get_max_hp():
		result["multiplier"] = 2.0
	# 没气 -> 获得1气
	if attacker.energy <= 0:
		attacker.add_energy(1)
		result["energy_gained"] = 1
	return result

## 结算暴击：若可暴击状态置位，50%概率暴击x2
## 返回 {crit: bool, multiplier: float}
static func crit_check(player: PlayerState) -> Dictionary:
	var result := { "crit": false, "multiplier": 1.0 }
	if not is_xiye(player):
		return result
	if player.can_crit_next and not player.crit_checked_this_round:
		player.crit_checked_this_round = true
		# 50%概率系统模拟猜拳：赢则暴击x2
		if randf() < 0.5:
			player.can_crit_next = false
			result["crit"] = true
			result["multiplier"] = 2.0
		else:
			player.can_crit_next = false
	return result

## 应用单个技能效果到目标（公开入口，供 GameManager 特殊结算复用）
## 与 _apply_single_effect 相同，但作为公开静态方法供外部调用
static func apply_effect_standalone(
	effect: SkillEffect,
	attacker: PlayerState,
	target: PlayerState,
	distance_system: DistanceSystem,
	bonus_if_paralyzed: int = 0,
	has_damage: bool = false,
	p_skill_name: String = ""
) -> Dictionary:
	return _apply_single_effect(effect, attacker, target, distance_system, bonus_if_paralyzed, has_damage, p_skill_name)

## 应用单个技能效果到目标，处理伤害吸收链：无敌 → 防反 → 影分身 → 无限盾 → 数值盾 → HP
## has_damage：当前技能是否包含伤害效果（防反只免疫伴随伤害的攻击的控制，纯控制技能正常生效）
static func _apply_single_effect(
	effect: SkillEffect,
	attacker: PlayerState,
	target: PlayerState,
	distance_system: DistanceSystem,
	bonus_if_paralyzed: int = 0,
	has_damage: bool = false,
	p_skill_name: String = ""
) -> Dictionary:
	match effect.effect_type:
		SkillEffect.EffectType.DAMAGE:
			# 无敌状态：完全免疫伤害（包括九尾无敌）
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "damage_dealt": 0, "shield_absorbed": effect.value, "remaining_hp": target.hp, "clone_destroyed": false, "counter_stance_triggered": false, "paralyze_bonus": 0, "counter_damage": 0, "invincible": true }
			var raw := effect.value
			# 禁锢增伤：施法瞬间目标已禁锢则额外伤害（effect 优先，兼容 skill 级配置）
			var paralyze_bonus: float = 0.0
			if target.paralyze_turns > 0 and (effect.bonus_if_paralyzed > 0 or bonus_if_paralyzed > 0):
				paralyze_bonus = effect.bonus_if_paralyzed if effect.bonus_if_paralyzed > 0 else bonus_if_paralyzed
				raw += paralyze_bonus
			# ── 希耶尔被动强化（对希耶尔造成的所有伤害生效）──
			# 代行者：目标带秽土/死徒/法师标签时+1
			raw += agent_bonus(attacker, target)
			# ── 大黑塔·解读强化（对【解】目标造成伤害+1）──
			raw += jiedu_bonus(attacker, target)
			# 相位滑剑：满血x2 + 没气得1气
			var ps := phase_sword_pre_apply(attacker, raw)
			raw *= ps["multiplier"]
			# 暴击：可暴击状态50%概率x2
			var crit := crit_check(attacker)
			raw *= crit["multiplier"]
			# ── 慈悲尖塔 buff：普攻固定增伤（锋刃之力）──
			raw += attacker.damage_bonus_basic
			# ── 慈悲尖塔祝福：破军（普攻可暴击，50%概率双倍伤害）──
			# 仅普攻触发，不与希耶尔暴击叠加（希耶尔走 crit_check）
			var pojun_crit: bool = false
			if not crit["crit"] and attacker.pojun_active and p_skill_name == "普攻":
				if randf() < 0.5:
					raw *= 2.0
					pojun_crit = true
			var dmg: float = raw
			var absorbed: float = 0.0
			var clone_broken: bool = false
			var counter_stance_triggered: bool = false
			# ── 泉奈·宇智波流招架：独立招架状态 ──────────────────────
			# 触发条件：处于 uchiha_stance 且未被控制（麻痹/封技）
			# 效果：伤害减半 + 泉奈进入无法选择状态1回合 + 对攻击者造成1伤并使其本回合失去所有技能
			var uchiha_counter_triggered: bool = false
			if target.uchiha_stance and not is_controlled(target):
				# 伤害减半
				dmg = ceilf(dmg / 2.0)
				uchiha_counter_triggered = true
				# 泉奈进入无法选择状态1回合
				target.untargetable_turns = max(target.untargetable_turns, 1)
				# 对攻击者造成1点伤害并使其本回合失去所有技能
				attacker.hp = max(0.0, attacker.hp - 1.0)
				attacker.skill_disabled_turns = max(attacker.skill_disabled_turns, 1)
				# 招架受击后解除
				target.uchiha_stance = false
			# 防反拦截：减半伤害+免疫控制+获得1气+反击1伤
			## 防反触发后立即取消招架状态（一次性的防反）
			## 被控制（麻痹/封技）期间：招架状态保留但不触发（不减伤、不得气、不反击）
			if target.counter_stance and not is_controlled(target):
				dmg = ceilf(dmg / 2.0)
				counter_stance_triggered = true
				target.add_energy(1)
				attacker.hp = max(0.0, attacker.hp - 1.0)
				target.counter_stance = false  # 触发后取消招架
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
				dmg = max(0.0, raw - target.shield)
				target.shield = max(0.0, target.shield - raw)
			# ── 慈悲尖塔 buff：固定减伤（坚壁），吸收链后扣 HP 前应用 ──
			dmg = max(0.0, dmg - target.damage_reduction)
			target.hp = max(0.0, target.hp - dmg)
			if dmg > 0:
				target.took_damage_this_round = true
				target.last_hit_by_id = attacker.player_id
			# 伤害致目标濒死（HP归零）→ 置位可暴击
			if target.hp <= 0 and dmg > 0:
				attacker.can_crit_next = true
			# 慈悲尖塔 buff：吸血（嗜血，造成伤害后恢复生命）
			_apply_lifesteal(attacker, dmg)
			return { "damage_dealt": dmg, "shield_absorbed": absorbed, "remaining_hp": target.hp, "clone_destroyed": clone_broken, "counter_stance_triggered": counter_stance_triggered, "paralyze_bonus": paralyze_bonus, "counter_damage": 1 if counter_stance_triggered else 0, "crit": crit["crit"] or pojun_crit, "multiplier": ps["multiplier"] * crit["multiplier"], "energy_gained": ps["energy_gained"], "uchiha_counter_triggered": uchiha_counter_triggered }

		SkillEffect.EffectType.TRUE_DAMAGE:
			# 真实伤害：无视护盾/圣盾（全挡护盾），仅此而已。
			# 无敌、伤害减免（防反/宇智波流招架）、分身等防御机制照常生效。
			# 无敌状态：完全免疫（包括九尾无敌）
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "damage_dealt": 0, "shield_absorbed": effect.value, "remaining_hp": target.hp, "clone_destroyed": false, "counter_stance_triggered": false, "paralyze_bonus": 0, "counter_damage": 0, "true_damage": true, "invincible": true }
			var tdmg: float = effect.value
			var clone_broken: bool = false
			var counter_stance_triggered: bool = false
			# 宇智波流招架（泉奈）：伤害减半 + 反击封技（伤害减免状态照常生效）
			var uchiha_counter_triggered: bool = false
			if target.uchiha_stance and not is_controlled(target):
				tdmg = ceilf(tdmg / 2.0)
				uchiha_counter_triggered = true
				target.untargetable_turns = max(target.untargetable_turns, 1)
				attacker.hp = max(0.0, attacker.hp - 1.0)
				attacker.skill_disabled_turns = max(attacker.skill_disabled_turns, 1)
				target.uchiha_stance = false
			# 防反：减半 + 获得1气 + 反击1伤（伤害减免状态照常生效）
			## 触发后立即取消招架状态（一次性的防反）
			if target.counter_stance and not is_controlled(target):
				tdmg = ceilf(tdmg / 2.0)
				counter_stance_triggered = true
				target.add_energy(1)
				attacker.hp = max(0.0, attacker.hp - 1.0)
				target.counter_stance = false  # 触发后取消招架
			# 分身抵挡（防御机制照常生效）
			if target.clone_count > 0:
				target.clone_count -= 1
				tdmg = 0
				clone_broken = true
			# 跳过护盾/圣盾：真实伤害无视护盾，直接扣HP
			target.hp = max(0.0, target.hp - tdmg)
			if tdmg > 0:
				target.took_damage_this_round = true
				target.last_hit_by_id = attacker.player_id
			# 慈悲尖塔 buff：吸血（嗜血，造成伤害后恢复生命）
			_apply_lifesteal(attacker, tdmg)
			return { "damage_dealt": tdmg, "shield_absorbed": 0, "remaining_hp": target.hp, "clone_destroyed": clone_broken, "counter_stance_triggered": counter_stance_triggered, "paralyze_bonus": 0, "counter_damage": 1 if counter_stance_triggered else 0, "true_damage": true, "uchiha_counter_triggered": uchiha_counter_triggered }

		SkillEffect.EffectType.PIERCE_DAMAGE:
			# 穿透伤害（断头台）：无视护盾(数值/全挡)、无敌、圣盾(全挡护盾)，直接扣HP
			# 被动强化：代行者+1 / 满血x2 / 暴击x2 全部生效
			var pdmg: float = effect.value
			pdmg += agent_bonus(attacker, target)
			var ps := phase_sword_pre_apply(attacker, pdmg)
			pdmg *= ps["multiplier"]
			var crit := crit_check(attacker)
			pdmg *= crit["multiplier"]
			target.hp = max(0.0, target.hp - pdmg)
			if pdmg > 0:
				target.took_damage_this_round = true
				target.last_hit_by_id = attacker.player_id
			if target.hp <= 0:
				attacker.can_crit_next = true
			# 慈悲尖塔 buff：吸血（嗜血，造成伤害后恢复生命）
			_apply_lifesteal(attacker, pdmg)
			return { "damage_dealt": pdmg, "shield_absorbed": 0, "remaining_hp": target.hp, "clone_destroyed": false, "counter_stance_triggered": false, "paralyze_bonus": 0, "counter_damage": 0, "pierce_damage": true, "crit": crit["crit"], "multiplier": ps["multiplier"] * crit["multiplier"] }

		SkillEffect.EffectType.PERCENT_DAMAGE:
			# 百分比伤害（慈悲尖塔一次性技能祝福：斩魂）：按目标当前生命值百分比结算
			# 与 DAMAGE 同等的减免链（无敌/护盾/分身/防反/坚壁），仅基础值计算不同
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "damage_dealt": 0, "shield_absorbed": effect.value, "remaining_hp": target.hp, "clone_destroyed": false, "counter_stance_triggered": false, "paralyze_bonus": 0, "counter_damage": 0, "percent_damage": true, "invincible": true }
			var pct_raw: float = target.hp * effect.value
			var pct_absorbed: float = 0.0
			var pct_clone_broken: bool = false
			var pct_counter_triggered: bool = false
			if target.counter_stance and not is_controlled(target):
				pct_raw = ceilf(pct_raw / 2.0)
				pct_counter_triggered = true
				target.add_energy(1)
				attacker.hp = max(0.0, attacker.hp - 1.0)
				target.counter_stance = false
			if target.clone_count > 0:
				target.clone_count -= 1
				pct_absorbed = pct_raw
				pct_raw = 0.0
				pct_clone_broken = true
			elif target.shield == -1:
				pct_absorbed = pct_raw
				pct_raw = 0.0
				target.shield = 0
			elif target.shield > 0:
				pct_absorbed = min(pct_raw, target.shield)
				pct_raw = max(0.0, pct_raw - target.shield)
				target.shield = max(0.0, target.shield - pct_raw)
			pct_raw = max(0.0, pct_raw - target.damage_reduction)
			target.hp = max(0.0, target.hp - pct_raw)
			if pct_raw > 0:
				target.took_damage_this_round = true
				target.last_hit_by_id = attacker.player_id
			if target.hp <= 0 and pct_raw > 0:
				attacker.can_crit_next = true
			# 慈悲尖塔 buff：吸血（嗜血，造成伤害后恢复生命）
			_apply_lifesteal(attacker, pct_raw)
			return { "damage_dealt": pct_raw, "shield_absorbed": pct_absorbed, "remaining_hp": target.hp, "clone_destroyed": pct_clone_broken, "counter_stance_triggered": pct_counter_triggered, "paralyze_bonus": 0, "counter_damage": 1 if pct_counter_triggered else 0, "percent_damage": true }

		SkillEffect.EffectType.DEATH_SENTENCE:
			# 断罪死：与目标进行7次猜拳
			# 每次赢造成1伤（吃代行者+1 / 满血x2 / 暴击x2），每次输自身回1血（上限当前最大HP）
			# 赢4次及以上则目标即死（直接淘汰）
			var win_count: int = 0
			var total_dmg: float = 0.0
			var total_heal: float = 0.0
			var rounds: Array[Dictionary] = []
			for i in range(int(effect.value)):
				var win: bool = randf() < 0.5
				if win:
					win_count += 1
					var rdmg: float = 1.0
					rdmg += agent_bonus(attacker, target)
					var rps := phase_sword_pre_apply(attacker, rdmg)
					rdmg *= rps["multiplier"]
					var rcrit := crit_check(attacker)
					rdmg *= rcrit["multiplier"]
					total_dmg += rdmg
					rounds.append({ "win": true, "dmg": rdmg, "heal": 0.0, "crit": rcrit["crit"] })
				else:
					var heal: float = min(1.0, attacker.get_max_hp() - attacker.hp)
					attacker.hp += heal
					total_heal += heal
					rounds.append({ "win": false, "dmg": 0.0, "heal": heal, "crit": false })
			var instant_kill: bool = win_count >= 4
			if instant_kill:
				target.hp = 0.0
			elif total_dmg > 0:
				target.hp = max(0.0, target.hp - total_dmg)
				target.took_damage_this_round = true
			if target.hp <= 0:
				attacker.can_crit_next = true
			return { "damage_dealt": total_dmg, "remaining_hp": target.hp, "rounds": rounds, "win_count": win_count, "lose_count": int(effect.value) - win_count, "total_heal": total_heal, "instant_kill": instant_kill }

		SkillEffect.EffectType.PARALYZE:
			# 无敌状态：免疫控制
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "turns": target.paralyze_turns, "counter_immune": true, "invincible": true }
			# 霸体（慈悲尖塔祝福）：免疫一切控制效果
			if target.bati_active:
				return { "turns": target.paralyze_turns, "counter_immune": true, "bati": true }
			# 谋略（司马懿）：免疫判定效果
			if is_strategist(target):
				return { "turns": target.paralyze_turns, "counter_immune": true }
			# 防反状态：只免疫伴随伤害的攻击的控制效果；纯控制技能（明神门等无伤害）正常生效
			if target.counter_stance and has_damage:
				return { "turns": target.paralyze_turns, "counter_immune": true }
			target.paralyze_turns += effect.value
			return { "turns": target.paralyze_turns }

		SkillEffect.EffectType.DISABLE_SKILL:
			# 无敌状态：免疫控制
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "disabled_turns": target.skill_disabled_turns, "counter_immune": true, "invincible": true }
			# 霸体（慈悲尖塔祝福）：免疫一切控制效果
			if target.bati_active:
				return { "disabled_turns": target.skill_disabled_turns, "counter_immune": true, "bati": true }
			# 谋略（司马懿）：免疫判定效果
			if is_strategist(target):
				return { "disabled_turns": target.skill_disabled_turns, "counter_immune": true }
			# 防反状态：只免疫伴随伤害的攻击效果；纯控制技能正常生效
			if target.counter_stance and has_damage:
				return { "disabled_turns": target.skill_disabled_turns, "counter_immune": true }
			target.skill_disabled_turns += effect.value
			return { "disabled_turns": target.skill_disabled_turns }

		SkillEffect.EffectType.KNOCKDOWN:
			# 无敌状态：免疫控制
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				return { "knockdown_turns": target.knockdown_turns, "counter_immune": true, "invincible": true }
			# 霸体（慈悲尖塔祝福）：免疫一切控制效果
			if target.bati_active:
				return { "knockdown_turns": target.knockdown_turns, "counter_immune": true, "bati": true }
			# 谋略（司马懿）：免疫判定效果
			if is_strategist(target):
				return { "knockdown_turns": target.knockdown_turns, "counter_immune": true }
			# 防反状态：只免疫伴随伤害的攻击的控制效果；纯控制技能正常生效
			if target.counter_stance and has_damage:
				return { "knockdown_turns": target.knockdown_turns, "counter_immune": true }
			target.knockdown_turns += int(effect.value)
			target.knockdown_applied_this_round = true
			return { "knockdown_turns": target.knockdown_turns }

		SkillEffect.EffectType.COUNTER_STANCE:
			target.counter_stance = true
			return { "counter_stance": true }

		SkillEffect.EffectType.SHIELD:
			# 数值护盾：value>0 在已有基础上累加；value=-1 为一次性全挡（不叠加，直接覆盖）
			if effect.value < 0:
				target.shield = -1
			else:
				if target.shield < 0:
					target.shield = 0
				target.shield += int(effect.value)
			return { "shield_value": int(effect.value), "total_shield": target.shield }

		SkillEffect.EffectType.CHANGE_DISTANCE:
			distance_system.modify_distance(attacker.player_id, target.player_id, effect.value)
			var new_dist: int = distance_system.get_distance(attacker.player_id, target.player_id)
			return { "delta": effect.value, "new_distance": new_dist }

		SkillEffect.EffectType.HEAL:
			# 回血上限使用有效最大生命值（含慈悲尖塔 buff 加成），避免治疗后血量溢出
			var heal: float = min(effect.value, target.get_max_hp() - target.hp)
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

		SkillEffect.EffectType.LOSE_SKILL:
			var lose_name: String = effect.lose_skill_name
			if lose_name != "" and not target.lost_skills.has(lose_name):
				target.lost_skills.append(lose_name)
			return { "lost_skill": lose_name }

		SkillEffect.EffectType.FTG_MARK:
			# 飞雷神标记：造成0.5伤害并标记目标
			var ftg_dmg: float = effect.value
			var ftg_counter_triggered: bool = false
			# 无敌/防反/分身/护盾拦截同DAMAGE
			## 被控制（麻痹/封技）期间：招架保留但不触发
			if target.invincible_turns > 0 or target.nine_tails_invincible:
				# 无敌只免疫伤害：标记作为状态仍照常施加（与DELAYED_DAMAGE不受无敌影响一致）
				if not target.ftg_marked_by.has(attacker.player_id):
					target.ftg_marked_by.append(attacker.player_id)
				return { "damage_dealt": 0, "ftg_marked": true, "remaining_hp": target.hp, "invincible": true }
			if target.counter_stance and not is_controlled(target):
				ftg_dmg = ceilf(ftg_dmg / 2.0)
				ftg_counter_triggered = true
				target.add_energy(1)
				attacker.hp = max(0.0, attacker.hp - 1.0)
				target.counter_stance = false  # 触发后取消招架
			if target.clone_count > 0:
				target.clone_count -= 1
				ftg_dmg = 0
			elif target.shield == -1:
				ftg_dmg = 0
				target.shield = 0
			elif target.shield > 0:
				ftg_dmg = max(0.0, ftg_dmg - target.shield)
				target.shield = max(0, target.shield - effect.value)
			target.hp = max(0.0, target.hp - ftg_dmg)
			if ftg_dmg > 0:
				target.took_damage_this_round = true
			# 标记目标
			if not target.ftg_marked_by.has(attacker.player_id):
				target.ftg_marked_by.append(attacker.player_id)
			return { "damage_dealt": ftg_dmg, "ftg_marked": true, "remaining_hp": target.hp, "counter_stance_triggered": ftg_counter_triggered, "counter_damage": 1 if ftg_counter_triggered else 0 }

		SkillEffect.EffectType.FTG_CHARGE:
			# 聚气：自身+1飞雷神标记
			target.ftg_marks += int(effect.value)
			return { "ftg_marks": target.ftg_marks }

		SkillEffect.EffectType.FTG_REMOVE:
			# 拔除：清除自身被标记的飞雷神
			target.ftg_marked_by.clear()
			return { "ftg_removed": true }

		SkillEffect.EffectType.NINE_TAILS:
			# 九尾释放：GameManager特殊处理，此处仅标记
			return { "nine_tails_triggered": true }

		SkillEffect.EffectType.UNTARGETABLE:
			# 无法选择：value=持续回合数，期间其他玩家任何技能无法指定该玩家为目标
			# 霸体（慈悲尖塔祝福）：免疫一切控制效果
			if target.bati_active:
				return { "untargetable_turns": target.untargetable_turns, "counter_immune": true, "bati": true }
			# 谋略（司马懿）：免疫判定效果
			if is_strategist(target):
				return { "untargetable_turns": target.untargetable_turns, "counter_immune": true }
			target.untargetable_turns = max(target.untargetable_turns, int(effect.value))
			return { "untargetable_turns": target.untargetable_turns }

		SkillEffect.EffectType.GLORY_TAKEOVER:
			# 荣耀夺取：由 GameManager 在准备阶段特殊处理（行动权转移+封技+伤害）
			# 此处仅返回占位日志，实际逻辑在 _apply_glory_takeover
			return { "glory_takeover": true }

		SkillEffect.EffectType.UCHIHA_STANCE:
			# 宇智波流招架：进入独立招架状态
			target.uchiha_stance = true
			return { "uchiha_stance": true }

		SkillEffect.EffectType.PROJECT_SKILL:
			# 投影：从目标玩家技能库中选择一个技能复制给施法者（用一次后消失）
			# 具体技能选择与交互由 GameManager/UI 处理，此处仅放置副本
			return { "projected": true }

		SkillEffect.EffectType.BINDING_FIELD:
			# 无限剑制：结界开启由 GameManager 处理（需设置 force_win + 锁定目标）
			return { "binding_field": true }

		SkillEffect.EffectType.HIANO_KAGEROHI:
			# 宇智波流·日晕舞（止水）：多段伤害由 GameManager 特殊处理（需预选中断点）
			# 此处仅放置占位日志，实际逐段结算走 apply_multi_hit_damage
			return { "hiaino": true }

		SkillEffect.EffectType.SUSANOO_SLASH:
			# 须佐能乎·斩：本回合无敌由 GameManager 处理，延迟伤害走 DELAYED_DAMAGE 效果
			return { "slash": true }

		SkillEffect.EffectType.SUSANOO_SPIRAL:
			# 须佐能乎·螺旋（止水）：多段伤害+无敌+封技+解锁九十九，由 GameManager 处理
			return { "spiral": true }

		SkillEffect.EffectType.SUSANOO_NINETY_NINE:
			# 须佐能乎·九十九（止水）：多段伤害+无敌，由 GameManager 处理
			return { "ninety_nine": true }

		SkillEffect.EffectType.KOTOAMATSUKAMI:
			# 别天神（止水，被动限定技）：击杀时触发夺舍，由 GameManager 处理
			return { "kotoamatsukami": true }

	return {}

## 多段伤害结算：逐段走标准吸收链（无敌→防反→分身→护盾→HP）
## 每段独立结算，目标死亡后停止后续段（避免无效攻击）
## break_after：日晕舞预选中断点，表示"第N段后中断"（1=1段后中断, 2=2段后中断, 0/负=不中断）
## 返回每段的结算日志数组（格式与 apply_effects 的日志一致）
static func apply_multi_hit_damage(
	attacker: PlayerState,
	target: PlayerState,
	damage_per_hit: float,
	hit_count: int,
	distance_system: DistanceSystem,
	break_after: int = 0,
	skill_name: String = ""
) -> Array[Dictionary]:
	var logs: Array[Dictionary] = []
	for i in range(hit_count):
		if target == null or not target.is_alive or target.hp <= 0:
			break
		var e := SkillEffect.new()
		e.effect_type = SkillEffect.EffectType.DAMAGE
		e.value = damage_per_hit
		e.target = SkillEffect.EffectTarget.ENEMY_SINGLE
		var res := _apply_single_effect(e, attacker, target, distance_system)
		logs.append({
			"attacker_id": attacker.player_id,
			"target_id":   target.player_id,
			"skill_name":  skill_name,
			"effect_type": SkillEffect.EffectType.DAMAGE,
			"value":       damage_per_hit,
			"result":      res,
		})
		# 到达预选中断点：中断剩余段（此时止水可在最后一段出伤前立即释放九十九）
		if break_after > 0 and i + 1 >= break_after:
			break
	return logs

## 慈悲尖塔 buff：吸血（嗜血祝福 — 造成伤害时恢复生命值）
## 在伤害结算后调用，按 attacker.lifesteal_per_hit 恢复（不超过最大生命值）
static func _apply_lifesteal(attacker: PlayerState, damage_dealt: float) -> void:
	if attacker == null or not attacker.is_alive:
		return
	if damage_dealt <= 0.0:
		return
	var ls: float = attacker.lifesteal_per_hit
	if ls <= 0.0:
		return
	var heal: float = min(ls, attacker.get_max_hp() - attacker.hp)
	if heal > 0.0:
		attacker.hp += heal
