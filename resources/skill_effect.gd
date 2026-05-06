## 技能效果 — 定义一个技能中的单个效果，含类型、数值、目标、持续等参数
class_name SkillEffect
extends Resource

## 效果类型枚举
enum EffectType {
	## 直接伤害：value=伤害量
	DAMAGE,
	## 护盾：value=-1为全挡, value>0为数值护盾
	SHIELD,
	## 麻痹：value=回合数，目标跳过出拳
	PARALYZE,
	## 改变距离：value=偏移量，可为负数
	CHANGE_DISTANCE,
	## 治疗：value=回复量，不超过最大HP
	HEAL,
	## 延迟伤害：挂buff，duration回合结束时触发
	DELAYED_DAMAGE,
	## 永久解锁技能到施法者列表
	UNLOCK_SKILL,
	## 影分身：一次性全挡伤害 + 充能加成
	CLONE_SHIELD,
}

## 效果目标枚举
enum EffectTarget {
	ENEMY_SINGLE,  ## 单一敌人
	ENEMY_ALL,     ## 所有敌人
	SELF,          ## 自身
	ENEMY_SPLASH,  ## 主目标周围 splash_range 内的其他敌人
}

@export var effect_type: EffectType             ## 效果类型
@export var value: int                          ## 效果数值（含义因类型而异）
@export var target: EffectTarget                ## 目标类型
@export var duration: int = 1                   ## DELAYED_DAMAGE：延迟回合数
@export var unlock_skill: SkillData = null      ## UNLOCK_SKILL：要解锁的技能资源
@export var splash_range: int = 1               ## ENEMY_SPLASH：溅射半径
