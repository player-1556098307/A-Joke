## 对局记录 — 完整的一局游戏数据，结算时传递给 GameOver 场景
class_name MatchRecord
extends RefCounted

var total_rounds: int = 0                          ## 总回合数
var tiebreak_count: int = 0                        ## 加赛次数
var winner_id: int = -1                            ## 胜者ID（-1表示平局）
var player_stats: Dictionary = {}                  ## {player_id: PlayerMatchStats} 每位玩家的统计数据
var round_snapshots: Array[RoundSnapshot] = []     ## 每回合快照（含加赛），用于回放
var skill_use_logs: Array[SkillUseLog] = []        ## 技能使用日志列表
