## 玩家状态快照 — 用于战斗回放，记录某一时刻玩家的关键状态
class_name PlayerStateSnapshot
extends RefCounted

var player_id: int            ## 玩家ID
var hp: float                   ## 当前生命值
var energy: int               ## 当前能量
var has_shield: bool          ## 是否有护盾
var paralyze_turns: int       ## 剩余麻痹回合数
var knockdown_turns: int = 0  ## 剩余击飞回合数
var is_alive: bool            ## 是否存活
var bell_count: int = 0       ## 钟数量
var counter_stance: bool = false  ## 防反状态
var skill_disabled_turns: int = 0 ## 失去技能回合数
## ── 迈特凯专属快照字段 ──
var gate_count: int = 0           ## 八门计数
var invincible_turns: int = 0    ## 无敌回合数
var burning: bool = false         ## 燃烧状态
var berserker: bool = false       ## 狂战士状态
var consecutive_rounds: int = 0   ## 连续回合数
var lost_skills: Array[String] = [] ## 已失去技能列表
## ── 波风水门专属快照字段 ──
var ftg_marks: int = 0              ## 飞雷神标记数量
var ftg_marked_by: Array[int] = [] ## 被哪些玩家标记
var nine_tails_stage: int = 0      ## 九尾阶段
var nine_tails_invincible: bool = false ## 九尾无敌
## ── 秽土柱间专属快照字段 ──
var max_energy: int = 999          ## 气上限
var stomp_active: int = 0          ## 跺脚激活回合数
var force_win_next_round: bool = false ## 下回合强制判胜
## ── 泉奈专属快照字段 ──
var glory_unlocked: bool = false    ## 荣耀是否已解锁
var untargetable_turns: int = 0    ## 无法选择剩余回合数

## 序列化为字典（网络传输用）
func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"hp": hp,
		"energy": energy,
		"has_shield": has_shield,
		"paralyze_turns": paralyze_turns,
		"knockdown_turns": knockdown_turns,
		"is_alive": is_alive,
		"bell_count": bell_count,
		"counter_stance": counter_stance,
		"skill_disabled_turns": skill_disabled_turns,
		"gate_count": gate_count,
		"invincible_turns": invincible_turns,
		"burning": burning,
		"berserker": berserker,
		"consecutive_rounds": consecutive_rounds,
		"lost_skills": lost_skills,
		"ftg_marks": ftg_marks,
		"ftg_marked_by": ftg_marked_by,
		"nine_tails_stage": nine_tails_stage,
		"nine_tails_invincible": nine_tails_invincible,
		"max_energy": max_energy,
		"stomp_active": stomp_active,
		"force_win_next_round": 1 if force_win_next_round else 0,
		"glory_unlocked": 1 if glory_unlocked else 0,
		"untargetable_turns": untargetable_turns,
	}
