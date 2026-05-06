## 技能使用日志 — 用于"技能使用记录"面板中逐条展示
class_name SkillUseLog
extends RefCounted

var round_number: int                    ## 所在回合
var actor_id: int                        ## 使用者ID
var actor_name: String                   ## 使用者名称
var skill_name: String                   ## 技能名称
var target_names: Array[String] = []     ## 目标名称列表
var total_damage: int = 0                ## 造成的总伤害
var effects_summary: String = ""         ## 效果摘要文本
