## 回合快照 — 记录一个回合（或加赛）的完整数据，用于战斗回放
class_name RoundSnapshot
extends RefCounted

var round_number: int                              ## 回合编号
var is_tiebreak: bool = false                      ## 是否为加赛回合
var tiebreak_candidates: Array[int] = []           ## 加赛候选玩家ID列表
var gestures: Dictionary = {}                      ## {player_id: Gesture} 所有玩家出的手势
var winners: Array[int] = []                       ## 本回合胜者ID列表
var losers: Array[int] = []                        ## 本回合败者ID列表
var is_draw: bool = false                          ## 是否平局
var actions: Array[ActionLog] = []                 ## 本回合执行的行动记录
var player_states_after: Array[PlayerStateSnapshot] = []  ## 回合结束后的玩家状态快照
var events: Array[String] = []                     ## 关键事件文本（淘汰、麻痹触发等）

## 序列化为字典（网络传输用）
func to_dict() -> Dictionary:
	var action_dicts: Array[Dictionary] = []
	for a in actions:
		action_dicts.append(a.to_dict())
	var state_dicts: Array[Dictionary] = []
	for s in player_states_after:
		state_dicts.append(s.to_dict())
	return {
		"round_number": round_number,
		"is_tiebreak": is_tiebreak,
		"tiebreak_candidates": tiebreak_candidates,
		"gestures": gestures,
		"winners": winners,
		"losers": losers,
		"is_draw": is_draw,
		"actions": action_dicts,
		"player_states_after": state_dicts,
		"events": events,
	}
