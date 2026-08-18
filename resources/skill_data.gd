## 技能数据 — 定义一个技能的名称、消耗、射程和效果列表
## 作为 .tres 资源文件存储，被 CharacterData 引用
class_name SkillData
extends Resource

@export var skill_name: String          ## 技能名称
@export var description: String         ## 技能描述文本
@export var energy_cost: int            ## 能量消耗
@export var min_range: int              ## 最小距离
@export var max_range: int              ## 最大距离（999表示无限）
@export var effects: Array[SkillEffect] ## 效果列表（按顺序执行）
@export var bell_cost: int = 0 ## 钟消耗（0=不需要钟）
@export var is_limited: bool = false ## 限定技（一局游戏只能使用一次）
@export var bonus_if_paralyzed: int = 0 ## 目标被禁锢时额外伤害（0=无增伤）
@export var is_passive: bool = false ## 被动技/锁定技（不在操作阶段技能列表显示）
@export var can_pay_with_hp: bool = false ## 可用生命值代替气支付
@export var ftg_cost: int = 0 ## 飞雷神标记消耗量（0=不需要标记）
