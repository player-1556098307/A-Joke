extends RefCounted
## 慈悲尖塔祝福注入的共享逻辑（服务器 TowerMatchHost 与客户端 tower_battle 共用，
## 避免两端实现漂移）。仅操作 PlayerState 字段，不依赖场景/UI。


## 应用单个祝福到 PlayerState
static func apply_buff(p: PlayerState, buff: Dictionary) -> void:
	match buff.get("id", ""):
		"blade_power", "blade_power_2":
			p.damage_bonus_basic += buff.get("value", 1.0)
		"charge_bonus":
			p.charge_bonus += buff.get("value", 1)
		"shield_wall":
			p.damage_reduction += buff.get("value", 1.0)
		"regen", "regen_2":
			p.regen_per_round += buff.get("value", 1.0)
		"clone":
			p.clone_count += buff.get("value", 1)
		"swift", "swift_2":
			p.add_energy(buff.get("value", 2))
		"protect", "protect_2":
			p.shield += buff.get("value", 2)
		"vitality", "vitality_2":
			var max_bonus: float = buff.get("value", 3.0)
			p.max_hp_bonus += max_bonus
			p.hp += max_bonus  # 同步补血
		"lifesteal":
			p.lifesteal_per_hit += buff.get("value", 1.0)
		"soul_slash":
			# 一次性技能祝福：将斩魂技能副本加入 unlocked_skills（防重复）
			add_limited_skill(p, "斩魂", "res://resources/characters/skills/斩魂.tres")
		"spring":
			# 一次性技能祝福：将回春技能副本加入 unlocked_skills（防重复）
			add_limited_skill(p, "回春", "res://resources/characters/skills/回春.tres")
		"immortal_medal":
			# 免死金牌：一次性被动，免疫一次致命伤害
			p.immortal_medal = true
		"pojun":
			# 破军：普攻可暴击
			p.pojun_active = true
		"bati":
			# 霸体：免疫一切控制效果
			p.bati_active = true
		"niepan":
			# 涅槃：死亡时以半血重生（一次性被动）
			p.niepan_active = true


## 一次性技能祝福：将限定技加入玩家 unlocked_skills（防重复，每层注入幂等）
static func add_limited_skill(p: PlayerState, skill_name: String, skill_path: String) -> void:
	for existing in p.unlocked_skills:
		if existing != null and existing.skill_name == skill_name:
			return
	var skill_res := load(skill_path) as SkillData
	if skill_res == null:
		push_warning("[塔] 一次性技能祝福资源加载失败：%s" % skill_path)
		return
	var copy := SkillData.new()
	copy.skill_name = skill_res.skill_name
	copy.description = skill_res.description
	copy.energy_cost = skill_res.energy_cost
	copy.min_range = skill_res.min_range
	copy.max_range = skill_res.max_range
	copy.is_limited = skill_res.is_limited
	var effects_copy: Array[SkillEffect] = []
	for e in skill_res.effects:
		var ec := SkillEffect.new()
		ec.effect_type = e.effect_type
		ec.value = e.value
		ec.target = e.target
		ec.duration = e.duration
		ec.bonus_if_paralyzed = e.bonus_if_paralyzed
		effects_copy.append(ec)
	copy.effects = effects_copy
	p.unlocked_skills.append(copy)
