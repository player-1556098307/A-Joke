## 对局记录 — 完整的一局游戏数据，结算时传递给 GameOver 场景
class_name MatchRecord
extends RefCounted

var total_rounds: int = 0                          ## 总回合数
var tiebreak_count: int = 0                        ## 加赛次数
var winner_id: int = -1                            ## 胜者ID（-1表示平局）
var player_stats: Dictionary = {}                  ## {player_id: PlayerMatchStats} 每位玩家的统计数据
var round_snapshots: Array[RoundSnapshot] = []     ## 每回合快照（含加赛），用于回放
var skill_use_logs: Array[SkillUseLog] = []        ## 技能使用日志列表

## 序列化为字典（网络传输用）
func to_dict() -> Dictionary:
	var stats_dict := {}
	for pid in player_stats:
		stats_dict[str(pid)] = player_stats[pid].to_dict()
	var snapshot_dicts: Array[Dictionary] = []
	for s in round_snapshots:
		snapshot_dicts.append(s.to_dict())
	var log_dicts: Array[Dictionary] = []
	for l in skill_use_logs:
		log_dicts.append(l.to_dict())
	return {
		"total_rounds": total_rounds,
		"tiebreak_count": tiebreak_count,
		"winner_id": winner_id,
		"player_stats": stats_dict,
		"round_snapshots": snapshot_dicts,
		"skill_use_logs": log_dicts,
	}

## 从字典反序列化（客户端用）
static func from_dict(data: Dictionary) -> MatchRecord:
	var r := MatchRecord.new()
	r.total_rounds = data.get("total_rounds", 0)
	r.tiebreak_count = data.get("tiebreak_count", 0)
	r.winner_id = data.get("winner_id", -1)

	var stats_dict: Dictionary = data.get("player_stats", {})
	for pid_str in stats_dict:
		var d: Dictionary = stats_dict[pid_str]
		var ps := PlayerMatchStats.new()
		ps.player_id = d.get("player_id", 0)
		ps.player_name = d.get("player_name", "")
		var char_path: String = d.get("character_path", "")
		if char_path != "":
			ps.character = load(char_path) as CharacterData
		ps.is_human = d.get("is_human", false)
		ps.final_hp = d.get("final_hp", 0)
		ps.max_hp = d.get("max_hp", 0)
		ps.total_damage_dealt = d.get("total_damage_dealt", 0)
		ps.total_damage_taken = d.get("total_damage_taken", 0)
		ps.total_healing = d.get("total_healing", 0)
		ps.skill_use_count = d.get("skill_use_count", 0)
		ps.charge_count = d.get("charge_count", 0)
		ps.win_count = d.get("win_count", 0)
		ps.tiebreak_win_count = d.get("tiebreak_win_count", 0)
		ps.shield_blocked_count = d.get("shield_blocked_count", 0)
		ps.paralyze_applied_count = d.get("paralyze_applied_count", 0)
		ps.paralyze_suffered_count = d.get("paralyze_suffered_count", 0)
		ps.elimination_round = d.get("elimination_round", -1)
		ps.elimination_reason = d.get("elimination_reason", "")
		ps.unlocked_skills = d.get("unlocked_skills", [])
		r.player_stats[int(pid_str)] = ps

	for snap_data in data.get("round_snapshots", []):
		var snap := RoundSnapshot.new()
		snap.round_number = snap_data.get("round_number", 0)
		snap.is_tiebreak = snap_data.get("is_tiebreak", false)
		snap.tiebreak_candidates = snap_data.get("tiebreak_candidates", [])
		snap.gestures = snap_data.get("gestures", {})
		snap.winners = snap_data.get("winners", [])
		snap.losers = snap_data.get("losers", [])
		snap.is_draw = snap_data.get("is_draw", false)
		for ad in snap_data.get("actions", []):
			var alog := ActionLog.new()
			alog.actor_id = ad.get("actor_id", 0)
			alog.action_type = ad.get("action_type", 0)
			alog.skill_name = ad.get("skill_name", "")
			alog.target_ids = ad.get("target_ids", [])
			alog.effect_results = ad.get("effect_results", [])
			snap.actions.append(alog)
		for sd in snap_data.get("player_states_after", []):
			var pss := PlayerStateSnapshot.new()
			pss.player_id = sd.get("player_id", 0)
			pss.hp = sd.get("hp", 0)
			pss.energy = sd.get("energy", 0)
			pss.has_shield = sd.get("has_shield", false)
			pss.paralyze_turns = sd.get("paralyze_turns", 0)
			pss.is_alive = sd.get("is_alive", false)
			snap.player_states_after.append(pss)
		snap.events = snap_data.get("events", [])
		r.round_snapshots.append(snap)

	for log_data in data.get("skill_use_logs", []):
		var slog := SkillUseLog.new()
		slog.round_number = log_data.get("round_number", 0)
		slog.actor_id = log_data.get("actor_id", 0)
		slog.actor_name = log_data.get("actor_name", "")
		slog.skill_name = log_data.get("skill_name", "")
		slog.target_names = log_data.get("target_names", [])
		slog.total_damage = log_data.get("total_damage", 0)
		slog.effects_summary = log_data.get("effects_summary", "")
		r.skill_use_logs.append(slog)

	return r
