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
