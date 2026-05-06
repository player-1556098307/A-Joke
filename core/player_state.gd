## 玩家运行时状态 — 存储单个玩家在一局游戏中的完整状态
## 包含生命值、能量、手势、行动决策以及所有跨回合持续的 buff/debuff
class_name PlayerState
extends RefCounted

## 猜拳手势枚举
enum Gesture { NONE, ROCK, SCISSORS, PAPER, SKIP }
## 行动类型枚举
enum ActionType { NONE, CHARGE, USE_SKILL }

var player_id: int                    ## 玩家唯一ID
var player_name: String               ## 玩家名称
var character: CharacterData          ## 使用的角色数据
var hp: int                           ## 当前生命值
var energy: int                       ## 当前能量值
var shield: int = 0                   ## 护盾值：-1=一次性全挡, 0=无护盾, >0=数值护盾
var paralyze_turns: int = 0           ## 剩余麻痹回合数（自动跳过出拳）
var is_alive: bool                    ## 是否存活
var is_human: bool                    ## 是否人类玩家

## ── 持续状态字段（跨回合保留）─────────────────────────────────────────────────
## 延迟伤害队列 [{damage, trigger_in(剩余回合), attacker_id}]
var delayed_damages: Array[Dictionary] = []
## 影分身数量（每个抵挡一次伤害，同时增加充能收益）
var clone_count: int = 0
## 运行时动态解锁的技能（如麒麟），跨回合持续
var unlocked_skills: Array[SkillData] = []

## ── 回合临时数据（每回合开始时重置）───────────────────────────────────────────
var current_gesture: Gesture           ## 本回合出的手势
var pending_action: ActionType         ## 待执行的行动类型
var skill_target_id: int               ## 技能目标ID
var pending_skill_index: int           ## 待使用技能在技能列表中的索引

func _init(id: int, p_name: String, char_data: CharacterData, human: bool) -> void:
	player_id           = id
	player_name         = p_name
	character           = char_data
	hp                  = char_data.max_hp
	energy              = 0
	shield              = 0
	paralyze_turns      = 0
	clone_count         = 0
	delayed_damages     = []
	unlocked_skills     = []
	is_alive            = true
	is_human            = human
	current_gesture     = Gesture.NONE
	pending_action      = ActionType.NONE
	skill_target_id     = -1
	pending_skill_index = -1

## 重置回合临时数据（每回合开始时调用），持续状态字段不在此重置
func reset_round_data() -> void:
	current_gesture     = Gesture.NONE
	pending_action      = ActionType.NONE
	skill_target_id     = -1
	pending_skill_index = -1

## 返回角色固有技能 + 运行时解锁技能的合并列表
func get_all_skills() -> Array[SkillData]:
	var all: Array[SkillData] = []
	all.append_array(character.skills)
	all.append_array(unlocked_skills)
	return all
