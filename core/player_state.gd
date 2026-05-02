class_name PlayerState
extends RefCounted

enum Gesture { NONE, ROCK, SCISSORS, PAPER, SKIP }
enum ActionType { NONE, CHARGE, USE_SKILL }

var player_id: int
var player_name: String
var character: CharacterData
var hp: int
var energy: int
var shield: int = 0          # -1=一次性全挡, >0=数值护盾
var paralyze_turns: int = 0  # 剩余麻痹回合
var is_alive: bool
var is_human: bool

# ── 补丁新增字段 ─────────────────────────────────────────────────────────────
var delayed_damages: Array[Dictionary] = []  # [{ "damage": int, "trigger_in": int, "attacker_id": int }]
var clone_count: int = 0                     # 影分身数量
var unlocked_skills: Array[SkillData] = []   # 运行时动态解锁的技能（跨回合持续）

# ── 回合临时数据 ──────────────────────────────────────────────────────────────
var current_gesture: Gesture
var pending_action: ActionType
var skill_target_id: int
var pending_skill_index: int

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

func reset_round_data() -> void:
	current_gesture     = Gesture.NONE
	pending_action      = ActionType.NONE
	skill_target_id     = -1
	pending_skill_index = -1
	# shield/paralyze_turns/delayed_damages/clone_count/unlocked_skills 跨回合，不在此重置

# 返回角色固有技能 + 运行时解锁技能的合并列表
func get_all_skills() -> Array[SkillData]:
	var all: Array[SkillData] = []
	all.append_array(character.skills)
	all.append_array(unlocked_skills)
	return all
