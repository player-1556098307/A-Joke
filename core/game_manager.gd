extends Node

enum GamePhase {
	SETUP,
	GESTURE_INPUT,
	RESOLVING,
	TIEBREAK_INPUT,
	TIEBREAK_RESOLVING,
	ACTION_INPUT,
	APPLYING,
	ELIMINATION,
	ROUND_END,
	GAME_OVER
}

signal phase_changed(new_phase: GamePhase)
signal gesture_submitted(player_id: int, gesture: PlayerState.Gesture)
signal round_resolved(result: Dictionary)
signal action_required(player_id: int)
signal skill_applied(logs: Array[Dictionary])
signal player_charged(player_id: int, new_energy: int)
signal player_eliminated(player_id: int)
signal game_over(winner_id: int, record: MatchRecord)
signal tiebreak_started(candidate_ids: Array[int])
signal tiebreak_resolved(winner_id: int)
signal player_shielded(player_id: int, shield_value: int)
signal player_paralyzed(player_id: int, turns: int)
signal distance_changed(from_id: int, to_id: int, new_distance: int)
signal player_skipped(player_id: int)
# ── 补丁新增信号 ───────────────────────────────────────────────────────────────
signal delayed_damage_triggered(player_id: int, damage: int, remaining_hp: int)
signal clone_destroyed(player_id: int)
signal skill_unlocked(player_id: int, skill_name: String)

var _players: Array[PlayerState] = []
var _current_phase: GamePhase = GamePhase.SETUP
var _tiebreak_candidates: Array[int] = []
var _sole_winner_id: int = -1
var _ai_controller: AIController
var _distance_system: DistanceSystem

var _resolve_timer: Timer
var _match_record: MatchRecord
var _current_round_number: int = 0
var _prev_phase: int = -1
var _current_snapshot: RoundSnapshot
var _debug_force_scissors: bool = false

func _ready() -> void:
	_ai_controller = AIController.new()
	_resolve_timer = Timer.new()
	_resolve_timer.one_shot = true
	_resolve_timer.wait_time = 2.0
	_resolve_timer.timeout.connect(_on_resolve_timer_timeout)
	add_child(_resolve_timer)

func _on_resolve_timer_timeout() -> void:
	if _current_phase == GamePhase.RESOLVING:
		_resolve_round()
	elif _current_phase == GamePhase.TIEBREAK_RESOLVING:
		_resolve_tiebreak()

func setup_game(config: Dictionary) -> void:
	_players.clear()
	_tiebreak_candidates.clear()
	_sole_winner_id = -1
	_current_phase  = GamePhase.SETUP
	_current_round_number = 0

	var player_configs: Array = config["players"]
	for i in range(player_configs.size()):
		var pc: Dictionary = player_configs[i]
		var state := PlayerState.new(i, pc["name"], pc["character"], pc["is_human"])
		_players.append(state)

	_distance_system = DistanceSystem.new()
	var seat_order: Array[int] = []
	for p in _players:
		seat_order.append(p.player_id)
	_distance_system.setup(seat_order)

	_debug_force_scissors = config.get("debug_force_scissors", false)
	_init_match_record()
	_enter_phase.call_deferred(GamePhase.GESTURE_INPUT)

# ── 状态机 ─────────────────────────────────────────────────────────────────────

func _enter_phase(phase: GamePhase) -> void:
	_prev_phase = _current_phase
	_current_phase = phase
	if phase == GamePhase.GESTURE_INPUT:
		if _prev_phase != GamePhase.RESOLVING and _prev_phase != GamePhase.TIEBREAK_RESOLVING:
			_current_round_number += 1
		_apply_paralyze()
	phase_changed.emit(phase)

	match phase:
		GamePhase.GESTURE_INPUT:      _process_ai_gestures()
		GamePhase.RESOLVING:          _resolve_timer.start()
		GamePhase.TIEBREAK_INPUT:     _start_tiebreak_input()
		GamePhase.TIEBREAK_RESOLVING: _resolve_timer.start()
		GamePhase.ACTION_INPUT:       _start_action_input()
		GamePhase.APPLYING:           _apply_actions()
		GamePhase.ELIMINATION:        _check_elimination()
		GamePhase.ROUND_END:          _end_round()
		GamePhase.GAME_OVER:          _finish_game()

func _apply_paralyze() -> void:
	for player in _players:
		if player.is_alive and player.paralyze_turns > 0:
			player.current_gesture = PlayerState.Gesture.SKIP
			player_skipped.emit(player.player_id)

func _process_ai_gestures() -> void:
	var delay := SettingsManager.get_ai_delay()
	var _has_human_alive := false
	for p in _players:
		if p.is_alive and p.is_human:
			_has_human_alive = true
			break
	for player in _players:
		if player.is_alive and not player.is_human and player.current_gesture == PlayerState.Gesture.NONE:
			var gesture := PlayerState.Gesture.SCISSORS if _debug_force_scissors and _has_human_alive else _ai_controller.decide_gesture(player)
			get_tree().create_timer(delay).timeout.connect(
				_delayed_submit_gesture.bind(player.player_id, gesture), CONNECT_ONE_SHOT)
	if _current_phase == GamePhase.GESTURE_INPUT and _all_gestures_submitted():
		_enter_phase(GamePhase.RESOLVING)

func _delayed_submit_gesture(pid: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase == GamePhase.GESTURE_INPUT:
		submit_gesture(pid, gesture)

func _all_gestures_submitted() -> bool:
	for player in _players:
		if player.is_alive and player.current_gesture == PlayerState.Gesture.NONE:
			return false
	return true

func _all_tiebreak_gestures_submitted() -> bool:
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive and player.current_gesture == PlayerState.Gesture.NONE:
			return false
	return true

func _resolve_round() -> void:
	var gestures: Dictionary = {}
	for player in _players:
		if player.is_alive:
			gestures[player.player_id] = player.current_gesture

	var result := RoundResolver.resolve_gestures(gestures)
	round_resolved.emit(result)
	_record_round_snapshot(result)

	if result["is_draw"]:
		if result.get("all_skipped", false):
			for player in _players:
				if player.is_alive and player.paralyze_turns > 0:
					player.paralyze_turns -= 1
				player.reset_round_data()
			_enter_phase(GamePhase.GESTURE_INPUT)
		else:
			for player in _players:
				if player.is_alive:
					player.current_gesture = PlayerState.Gesture.NONE
			_enter_phase(GamePhase.GESTURE_INPUT)
	elif (result["winners"] as Array).size() == 1:
		_sole_winner_id = int((result["winners"] as Array)[0])
		var ws: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
		if ws:
			ws.win_count += 1
		_enter_phase(GamePhase.ACTION_INPUT)
	else:
		_tiebreak_candidates.clear()
		for id in (result["winners"] as Array):
			_tiebreak_candidates.append(int(id))
		for player in _players:
			player.current_gesture = PlayerState.Gesture.NONE
		tiebreak_started.emit(_tiebreak_candidates)
		_enter_phase(GamePhase.TIEBREAK_INPUT)

func _start_tiebreak_input() -> void:
	var delay := SettingsManager.get_ai_delay()
	var _has_human_in_tiebreak := false
	for tid in _tiebreak_candidates:
		var tp := get_player(tid)
		if tp != null and tp.is_human:
			_has_human_in_tiebreak = true
			break
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive and not player.is_human:
			var gesture := PlayerState.Gesture.SCISSORS if _debug_force_scissors and _has_human_in_tiebreak else _ai_controller.decide_gesture(player)
			get_tree().create_timer(delay).timeout.connect(
				_delayed_submit_tiebreak_gesture.bind(id, gesture), CONNECT_ONE_SHOT)

func _delayed_submit_tiebreak_gesture(pid: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase == GamePhase.TIEBREAK_INPUT:
		submit_tiebreak_gesture(pid, gesture)

func _resolve_tiebreak() -> void:
	var gestures: Dictionary = {}
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive:
			gestures[id] = player.current_gesture

	var result := RoundResolver.resolve_gestures(gestures)

	# Record tiebreak snapshot
	var snap := RoundSnapshot.new()
	snap.round_number = _current_round_number
	snap.is_tiebreak = true
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive:
			snap.gestures[id] = player.current_gesture
	snap.winners.assign(result.get("winners", []))
	snap.is_draw = result.get("is_draw", false)
	if not snap.is_draw:
		for id in snap.gestures:
			if not snap.winners.has(int(id)):
				snap.losers.append(int(id))
	for player in _players:
		var ss := PlayerStateSnapshot.new()
		ss.player_id = player.player_id
		ss.hp = player.hp
		ss.energy = player.energy
		ss.has_shield = (player.shield != 0)
		ss.paralyze_turns = player.paralyze_turns
		ss.is_alive = player.is_alive
		snap.player_states_after.append(ss)
	_match_record.round_snapshots.append(snap)
	_match_record.tiebreak_count += 1

	if result["is_draw"]:
		for id in _tiebreak_candidates:
			var player := get_player(id)
			if player != null:
				player.current_gesture = PlayerState.Gesture.NONE
		_enter_phase(GamePhase.TIEBREAK_INPUT)
	elif (result["winners"] as Array).size() == 1:
		_sole_winner_id = int((result["winners"] as Array)[0])
		var tws: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
		if tws:
			tws.tiebreak_win_count += 1
			tws.win_count += 1
		tiebreak_resolved.emit(_sole_winner_id)
		_enter_phase(GamePhase.ACTION_INPUT)
	else:
		_tiebreak_candidates.clear()
		for id in (result["winners"] as Array):
			_tiebreak_candidates.append(int(id))
		for id in _tiebreak_candidates:
			var player := get_player(id)
			if player != null:
				player.current_gesture = PlayerState.Gesture.NONE
		tiebreak_started.emit(_tiebreak_candidates)
		_enter_phase(GamePhase.TIEBREAK_INPUT)

func _start_action_input() -> void:
	var winner := get_player(_sole_winner_id)
	if winner == null or not winner.is_alive:
		_enter_phase(GamePhase.APPLYING)
		return

	action_required.emit(_sole_winner_id)

	if not winner.is_human:
		var decision := _ai_controller.decide_action(winner, get_alive_players(), _distance_system)
		submit_action(_sole_winner_id, decision["action"], decision["skill_index"], decision["target_id"])

func _apply_actions() -> void:
	var winner := get_player(_sole_winner_id)
	if winner == null or not winner.is_alive:
		_enter_phase(GamePhase.ELIMINATION)
		return

	match winner.pending_action:
		PlayerState.ActionType.CHARGE:
			# 影分身存在时聚气加成 +2，否则 +1
			var gain: int = 1 + winner.clone_count
			winner.energy += gain
			player_charged.emit(_sole_winner_id, winner.energy)
			var cs: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
			if cs:
				cs.charge_count += 1
			# Record charge action in replay snapshot
			if _current_snapshot:
				var alog := ActionLog.new()
				alog.actor_id = winner.player_id
				alog.action_type = PlayerState.ActionType.CHARGE
				alog.skill_name = "聚气"
				_current_snapshot.actions.append(alog)

		PlayerState.ActionType.USE_SKILL:
			var all_skills := winner.get_all_skills()
			var skill_idx  := winner.pending_skill_index
			if skill_idx < 0 or skill_idx >= all_skills.size():
				_enter_phase(GamePhase.ELIMINATION)
				return
			var skill: SkillData = all_skills[skill_idx]
			if winner.energy < skill.energy_cost:
				_enter_phase(GamePhase.ELIMINATION)
				return

			var targets       := _build_skill_targets(winner, skill)
			var splash_targets := _build_splash_targets(winner, skill)
			var logs := RoundResolver.apply_effects(winner, skill, targets, _distance_system, splash_targets)
			for entry in logs:
				_emit_effect_signals(entry)
			skill_applied.emit(logs)
			_record_action(winner, skill, logs)

	_enter_phase(GamePhase.ELIMINATION)

func _build_skill_targets(attacker: PlayerState, skill: SkillData) -> Array[PlayerState]:
	var has_enemy_all    := false
	var has_enemy_single := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_ALL:
			has_enemy_all = true
		elif effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE:
			has_enemy_single = true

	var targets: Array[PlayerState] = []
	if has_enemy_all:
		for p in _players:
			if p.is_alive and p.player_id != attacker.player_id:
				targets.append(p)
	elif has_enemy_single:
		var tgt := get_player(attacker.skill_target_id)
		if tgt != null and tgt.is_alive:
			targets.append(tgt)
	return targets

func _build_splash_targets(attacker: PlayerState, skill: SkillData) -> Array[PlayerState]:
	var splash_range := 1
	var has_splash   := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_SPLASH:
			has_splash   = true
			splash_range = effect.splash_range
			break
	if not has_splash:
		return []

	var main_target := get_player(attacker.skill_target_id)
	if main_target == null:
		return []

	var splash: Array[PlayerState] = []
	for p in _players:
		if not p.is_alive:
			continue
		if p.player_id == attacker.player_id or p.player_id == main_target.player_id:
			continue
		var dist: int = _distance_system.get_distance(main_target.player_id, p.player_id)
		if dist <= splash_range:
			splash.append(p)
	return splash

func _emit_effect_signals(entry: Dictionary) -> void:
	var res: Dictionary = entry.get("result", {})
	match entry.get("effect_type", -1):
		SkillEffect.EffectType.DAMAGE:
			if res.get("clone_destroyed", false):
				clone_destroyed.emit(entry["target_id"])
		SkillEffect.EffectType.SHIELD, SkillEffect.EffectType.CLONE_SHIELD:
			player_shielded.emit(entry["target_id"], res.get("shield_value", 0))
		SkillEffect.EffectType.PARALYZE:
			player_paralyzed.emit(entry["target_id"], res.get("turns", 0))
		SkillEffect.EffectType.CHANGE_DISTANCE:
			distance_changed.emit(
				entry.get("attacker_id", -1),
				entry["target_id"],
				res.get("new_distance", 0)
			)
		SkillEffect.EffectType.UNLOCK_SKILL:
			var sname: String = res.get("skill_name", "")
			if sname != "":
				skill_unlocked.emit(entry["target_id"], sname)

func _check_elimination() -> void:
	for player in _players:
		if player.is_alive and player.hp <= 0:
			player.is_alive = false
			_distance_system.remove_player(player.player_id)
			player_eliminated.emit(player.player_id)
			var es: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
			if es:
				es.elimination_round = _current_round_number
				es.elimination_reason = "HP归零"

	var alive := get_alive_players()
	if alive.size() <= 1 or _is_human_dead():
		_enter_phase(GamePhase.GAME_OVER)
	else:
		_enter_phase(GamePhase.ROUND_END)

func _is_human_dead() -> bool:
	for player in _players:
		if player.is_human and not player.is_alive:
			return true
	return false

func _end_round() -> void:
	# 触发延迟伤害
	_process_delayed_damages()
	# 延迟伤害后再次检测淘汰
	for player in _players:
		if player.is_alive and player.hp <= 0:
			player.is_alive = false
			_distance_system.remove_player(player.player_id)
			player_eliminated.emit(player.player_id)
			var es2: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
			if es2:
				es2.elimination_round = _current_round_number
				es2.elimination_reason = "延迟伤害"
	var alive := get_alive_players()
	if alive.size() <= 1 or _is_human_dead():
		for player in _players:
			player.reset_round_data()
		_enter_phase(GamePhase.GAME_OVER)
		return
	# 正常进入下一回合
	for player in _players:
		if player.paralyze_turns > 0 and player.current_gesture == PlayerState.Gesture.SKIP:
			player.paralyze_turns -= 1
		player.reset_round_data()
	_enter_phase(GamePhase.GESTURE_INPUT)

func _process_delayed_damages() -> void:
	for player in get_alive_players():
		var triggered: Array[Dictionary] = []
		for entry in player.delayed_damages:
			entry["trigger_in"] -= 1
			if entry["trigger_in"] <= 0:
				triggered.append(entry)
		for entry in triggered:
			player.delayed_damages.erase(entry)
			_apply_delayed_damage(player, entry["damage"], entry.get("attacker_id", -1))

func _apply_delayed_damage(player: PlayerState, damage: int, attacker_id: int = -1) -> void:
	var dmg: int = damage
	var clone_broken: bool = false
	if player.clone_count > 0:
		player.clone_count -= 1
		dmg = 0
		clone_broken = true
	elif player.shield == -1:
		dmg = 0
		player.shield = 0
	elif player.shield > 0:
		dmg = max(0, damage - player.shield)
		player.shield = max(0, player.shield - damage)
	player.hp = max(0, player.hp - dmg)
	if dmg > 0:
		if attacker_id >= 0:
			var a_stats: PlayerMatchStats = _match_record.player_stats.get(attacker_id)
			if a_stats:
				a_stats.total_damage_dealt += dmg
		var v_stats: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
		if v_stats:
			v_stats.total_damage_taken += dmg
	if clone_broken:
		clone_destroyed.emit(player.player_id)
	delayed_damage_triggered.emit(player.player_id, dmg, player.hp)

func _finish_game() -> void:
	var alive := get_alive_players()
	var winner_id := -1
	if alive.size() == 1:
		winner_id = alive[0].player_id
	_match_record.total_rounds = _current_round_number
	_match_record.winner_id = winner_id
	for p in _players:
		var stats: PlayerMatchStats = _match_record.player_stats.get(p.player_id)
		if stats:
			stats.final_hp = p.hp
			for s in p.unlocked_skills:
				stats.unlocked_skills.append(s.skill_name)
	game_over.emit(winner_id, _match_record)

# ── 数据收集 ──────────────────────────────────────────────────────────────────

func _init_match_record() -> void:
	_match_record = MatchRecord.new()
	for p in _players:
		var stats := PlayerMatchStats.new()
		stats.player_id = p.player_id
		stats.player_name = p.player_name
		stats.character = p.character
		stats.is_human = p.is_human
		stats.max_hp = p.character.max_hp
		_match_record.player_stats[p.player_id] = stats

func _record_round_snapshot(result: Dictionary) -> void:
	var snap := RoundSnapshot.new()
	snap.round_number = _current_round_number
	for player in _players:
		if player.is_alive:
			snap.gestures[player.player_id] = player.current_gesture
	snap.winners.assign(result.get("winners", []))
	if not result.get("is_draw", false):
		for id in snap.gestures:
			if not snap.winners.has(int(id)):
				snap.losers.append(int(id))
	snap.is_draw = result.get("is_draw", false)
	for player in _players:
		var ss := PlayerStateSnapshot.new()
		ss.player_id = player.player_id
		ss.hp = player.hp
		ss.energy = player.energy
		ss.has_shield = (player.shield != 0)
		ss.paralyze_turns = player.paralyze_turns
		ss.is_alive = player.is_alive
		snap.player_states_after.append(ss)
	_match_record.round_snapshots.append(snap)
	_current_snapshot = snap

func _record_action(winner: PlayerState, skill: SkillData, logs: Array[Dictionary]) -> void:
	var stats: PlayerMatchStats = _match_record.player_stats.get(winner.player_id)
	if stats == null:
		return
	stats.skill_use_count += 1
	for entry in logs:
		var etype: int = entry.get("effect_type", -1)
		var res: Dictionary = entry.get("result", {})
		match etype:
			SkillEffect.EffectType.DAMAGE:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
			SkillEffect.EffectType.HEAL:
				stats.total_healing += res.get("heal_amount", 0)
			SkillEffect.EffectType.PARALYZE:
				stats.paralyze_applied_count += 1
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.paralyze_suffered_count += 1
			SkillEffect.EffectType.SHIELD:
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.shield_blocked_count += 1
	# Build ActionLog for snapshot
	var alog := ActionLog.new()
	alog.actor_id = winner.player_id
	alog.action_type = PlayerState.ActionType.USE_SKILL
	alog.skill_name = skill.skill_name
	for entry in logs:
		var tid: int = entry.get("target_id", -1)
		alog.target_ids.append(tid)
		alog.effect_results.append(entry.get("result", {}))
	if _current_snapshot:
		_current_snapshot.actions.append(alog)

	# Build SkillUseLog
	var slog := SkillUseLog.new()
	slog.round_number = _current_round_number
	slog.actor_id = winner.player_id
	slog.actor_name = winner.player_name
	slog.skill_name = skill.skill_name
	for entry in logs:
		var tid: int = entry.get("target_id", -1)
		var tp := get_player(tid)
		if tp:
			slog.target_names.append(tp.player_name)
		var res: Dictionary = entry.get("result", {})
		slog.total_damage += res.get("damage_dealt", 0)
	# Build effects summary
	var parts: Array[String] = []
	for entry in logs:
		var etype: int = entry.get("effect_type", -1)
		var res: Dictionary = entry.get("result", {})
		match etype:
			SkillEffect.EffectType.DAMAGE:
				parts.append("%d伤害" % res.get("damage_dealt", 0))
			SkillEffect.EffectType.PARALYZE:
				parts.append("麻痹%d回合" % res.get("turns", 0))
			SkillEffect.EffectType.SHIELD:
				var sv: int = res.get("shield_value", 0)
				parts.append("全挡" if sv == -1 else "护盾%d" % sv)
			SkillEffect.EffectType.DELAYED_DAMAGE:
				parts.append("延迟%d伤" % res.get("damage", 0))
			SkillEffect.EffectType.HEAL:
				parts.append("回复%d" % res.get("heal_amount", 0))
			SkillEffect.EffectType.CLONE_SHIELD:
				parts.append("影分身")
			SkillEffect.EffectType.UNLOCK_SKILL:
				parts.append("解锁技能")
	slog.effects_summary = " + ".join(parts) if parts.size() > 0 else "-"
	_match_record.skill_use_logs.append(slog)

# ── 公开方法 ───────────────────────────────────────────────────────────────────

func submit_gesture(player_id: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase != GamePhase.GESTURE_INPUT:
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	player.current_gesture = gesture
	gesture_submitted.emit(player_id, gesture)
	if _all_gestures_submitted():
		_enter_phase(GamePhase.RESOLVING)

func submit_tiebreak_gesture(player_id: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase != GamePhase.TIEBREAK_INPUT:
		return
	if not _tiebreak_candidates.has(player_id):
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	player.current_gesture = gesture
	gesture_submitted.emit(player_id, gesture)
	if _all_tiebreak_gestures_submitted():
		_enter_phase(GamePhase.TIEBREAK_RESOLVING)

func submit_action(player_id: int, action: PlayerState.ActionType, skill_index: int, target_id: int) -> void:
	if _current_phase != GamePhase.ACTION_INPUT:
		return
	var player := get_player(player_id)
	if player == null:
		return
	player.pending_action      = action
	player.pending_skill_index = skill_index
	player.skill_target_id     = target_id
	_enter_phase(GamePhase.APPLYING)

func get_alive_players() -> Array[PlayerState]:
	var result: Array[PlayerState] = []
	for player in _players:
		if player.is_alive:
			result.append(player)
	return result

func get_player(player_id: int) -> PlayerState:
	for player in _players:
		if player.player_id == player_id:
			return player
	return null

func get_distance(from_id: int, to_id: int) -> int:
	return _distance_system.get_distance(from_id, to_id)
