## 行动记录 — 记录单个玩家的一次行动（充能或使用技能），用于回放
class_name ActionLog
extends RefCounted

var actor_id: int                         ## 行动者ID
var action_type: int                      ## 行动类型: PlayerState.ActionType (CHARGE / USE_SKILL)
var skill_name: String = ""               ## 使用的技能名称（充能时为空）
var target_ids: Array[int] = []           ## 目标玩家ID列表
var effect_results: Array[Dictionary] = []  ## 每个效果的结算详情
