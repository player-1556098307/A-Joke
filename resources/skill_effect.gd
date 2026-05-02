class_name SkillEffect
extends Resource

enum EffectType {
	# ── v2 原有 ──
	DAMAGE,
	SHIELD,
	PARALYZE,
	CHANGE_DISTANCE,
	HEAL,
	# ── 补丁新增 ──
	DELAYED_DAMAGE,   # 延迟伤害：挂 buff，N 回合结束时触发
	UNLOCK_SKILL,     # 永久解锁技能到施法者列表
	CLONE_SHIELD,     # 影分身：一次性全挡 + 聚气加成，击破同时消失
}

enum EffectTarget {
	ENEMY_SINGLE,
	ENEMY_ALL,
	SELF,
	ENEMY_SPLASH,     # 以主目标为圆心，splash_range 内的其他存活玩家
}

@export var effect_type: EffectType
@export var value: int
@export var target: EffectTarget
@export var duration: int = 1        # DELAYED_DAMAGE: N回合后的回合结束时触发（1=本回合末，2=下回合末
@export var unlock_skill: SkillData = null  # UNLOCK_SKILL：解锁后加入施法者的技能
@export var splash_range: int = 1    # ENEMY_SPLASH：溅射半径
