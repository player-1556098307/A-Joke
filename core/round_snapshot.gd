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
