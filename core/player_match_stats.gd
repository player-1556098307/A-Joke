## 玩家对局统计 — 记录单个玩家在一局游戏中的完整统计数据
class_name PlayerMatchStats
extends RefCounted

var player_id: int                       ## 玩家ID
var player_name: String                  ## 玩家名称
var character: CharacterData             ## 使用的角色数据
var is_human: bool                       ## 是否为人类玩家

var final_hp: int                        ## 最终生命值
var max_hp: int                          ## 最大生命值
var total_damage_dealt: int = 0          ## 造成的总伤害
var total_damage_taken: int = 0          ## 承受的总伤害
var total_healing: int = 0               ## 总治疗量
var skill_use_count: int = 0             ## 使用技能次数
var charge_count: int = 0                ## 充能次数
var win_count: int = 0                   ## 猜拳胜出次数
var tiebreak_win_count: int = 0          ## 加赛胜出次数
var shield_blocked_count: int = 0        ## 护盾格挡次数
var paralyze_applied_count: int = 0      ## 造成麻痹次数
var paralyze_suffered_count: int = 0     ## 承受麻痹次数
var elimination_round: int = -1          ## 被淘汰的回合号（-1表示存活到最后）
var elimination_reason: String = ""      ## 被淘汰的原因描述
var unlocked_skills: Array[String] = []  ## 本局解锁的技能名列表

## 序列化为字典（网络传输用）
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"player_name": player_name,
		"character_path": character.resource_path,
		"is_human": is_human,
		"final_hp": final_hp,
		"max_hp": max_hp,
		"total_damage_dealt": total_damage_dealt,
		"total_damage_taken": total_damage_taken,
		"total_healing": total_healing,
		"skill_use_count": skill_use_count,
		"charge_count": charge_count,
		"win_count": win_count,
		"tiebreak_win_count": tiebreak_win_count,
		"shield_blocked_count": shield_blocked_count,
		"paralyze_applied_count": paralyze_applied_count,
		"paralyze_suffered_count": paralyze_suffered_count,
		"elimination_round": elimination_round,
		"elimination_reason": elimination_reason,
		"unlocked_skills": unlocked_skills,
	}
