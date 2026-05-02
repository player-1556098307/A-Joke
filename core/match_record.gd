class_name MatchRecord
extends RefCounted

var total_rounds: int = 0
var tiebreak_count: int = 0
var winner_id: int = -1
var player_stats: Dictionary = {}        # { player_id: PlayerMatchStats }
var round_snapshots: Array[RoundSnapshot] = []
var skill_use_logs: Array[SkillUseLog] = []
