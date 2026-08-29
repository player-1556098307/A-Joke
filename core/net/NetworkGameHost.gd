## NetworkGameHost — 服务器端，包装 GameManager，将信号转为 RPC 广播
class_name NetworkGameHost
extends Node

signal room_empty
signal tower_reward_pick_received(player_index: int, buff: Dictionary)
signal player_rejoined(peer_id: int, player_id: int)

var room_id: String = ""
var room_config: Dictionary = {}
## 塔模式权威控制器（TowerMatchHost），由 RoomManager 在开局时注入
var tower_host: Node = null

## key = peer_id, value = player_id
var _peer_to_player: Dictionary = {}
## key = player_id, value = peer_id（-1表示断线中）
var _player_to_peer: Dictionary = {}
## key = token, value = player_id（断线重连用）
var _tokens: Dictionary = {}

var _game_manager: GameManager
var _spectator_peers: Array[int] = []

const RECONNECT_TIMEOUT := 60.0  # 断线后保留槽位的秒数

func _ready() -> void:
	_game_manager = GameManager
	_game_manager._is_network_game = true
	_connect_signals()
	_hook_decision_failsafes()

func _connect_signals() -> void:
	_game_manager.phase_changed.connect(_on_phase_changed)
	_game_manager.gesture_submitted.connect(_on_gesture_submitted)
	_game_manager.round_resolved.connect(_on_round_resolved)
	_game_manager.action_required.connect(_on_action_required)
	_game_manager.skill_applied.connect(_on_skill_applied)
	_game_manager.player_paralyzed.connect(_on_player_paralyzed_broadcast)
	_game_manager.player_knocked_down.connect(_on_player_knocked_down_broadcast)
	_game_manager.player_charged.connect(_on_player_charged)
	_game_manager.player_eliminated.connect(_on_player_eliminated)
	_game_manager.game_over.connect(_on_game_over)
	_game_manager.skill_unlocked.connect(_on_skill_unlocked)
	_game_manager.delayed_damage_triggered.connect(_on_delayed_damage)
	_game_manager.distance_changed.connect(_on_distance_changed)
	_game_manager.tiebreak_started.connect(_on_tiebreak_started)
	_game_manager.tiebreak_resolved.connect(_on_tiebreak_resolved)
	_game_manager.bell_gained.connect(_on_bell_gained)
	_game_manager.counter_stance_entered.connect(_on_counter_stance_entered)
	_game_manager.counter_stance_triggered.connect(_on_counter_stance_triggered)
	_game_manager.counter_stance_ended.connect(_on_counter_stance_ended)
	_game_manager.skill_disabled.connect(_on_skill_disabled_broadcast)
	_game_manager.end_phase_bell_decision_required.connect(_on_end_phase_bell_decision_required)
	_game_manager.player_invincible.connect(_on_player_invincible)
	_game_manager.player_burning.connect(_on_player_burning)
	_game_manager.player_berserker.connect(_on_player_berserker)
	_game_manager.gate_changed.connect(_on_gate_changed)
	_game_manager.eighth_gate_opened.connect(_on_eighth_gate_opened)
	_game_manager.skill_lost.connect(_on_skill_lost)
	_game_manager.burn_damage_triggered.connect(_on_burn_damage_triggered)
	_game_manager.hp_payment_made.connect(_on_hp_payment_made)
	_game_manager.ftg_marks_changed.connect(_on_ftg_marks_changed)
	_game_manager.ftg_mark_applied.connect(_on_ftg_mark_applied)
	_game_manager.ftg_mark_removed.connect(_on_ftg_mark_removed)
	_game_manager.ftg_swap_triggered.connect(_on_ftg_swap_triggered)
	_game_manager.ftg_dodge_triggered.connect(_on_ftg_dodge_triggered)
	_game_manager.nine_tails_stage_changed.connect(_on_nine_tails_stage_changed)
	_game_manager.nine_tails_invincible_started.connect(_on_nine_tails_invincible_started)
	_game_manager.nine_tails_invincible_ended.connect(_on_nine_tails_invincible_ended)
	_game_manager.nine_tails_attack.connect(_on_nine_tails_attack)
	_game_manager.ftg_intercept_required.connect(_on_ftg_intercept_required)
	_game_manager.rasengan_counter_required.connect(_on_rasengan_counter_required)
	# ── 卫宫信号 ──
	_game_manager.project_skill_required.connect(_on_project_skill_required)
	_game_manager.project_skill_made.connect(_on_project_skill_made)
	_game_manager.binding_field_started.connect(_on_binding_field_started)
	_game_manager.binding_field_ended.connect(_on_binding_field_ended)
	_game_manager.projected_skill_gained.connect(_on_projected_skill_gained)
	_game_manager.projected_skill_lost.connect(_on_projected_skill_lost)
	# ── 新止水（天劫）信号 ──
	_game_manager.phantom_dodge_required.connect(_on_phantom_dodge_required)
	_game_manager.backtrack_required.connect(_on_backtrack_required)
	_game_manager.hiroari_targets_required.connect(_on_hiroari_targets_required)
	_game_manager.phantom_changed.connect(_on_phantom_changed)
	_game_manager.hiroari_used.connect(_on_hiroari_used)
	_game_manager.backtrack_performed.connect(_on_backtrack_performed)
	# ── 奥伯龙 / 卡斯特 决策弹窗信号 ──
	_game_manager.dream_end_required.connect(_on_dream_end_required)
	_game_manager.lake_blessing_required.connect(_on_lake_blessing_required)
	_game_manager.sword_forge_required.connect(_on_sword_forge_required)
	# ── 卡斯特 完成/回退事件广播（客户端日志显示） ──
	_game_manager.dream_end_used.connect(_on_dream_end_used)
	_game_manager.lake_blessing_used.connect(_on_lake_blessing_used)
	_game_manager.sword_forge_used.connect(_on_sword_forge_used)
	_game_manager.sword_forge_fallback.connect(_on_sword_forge_fallback)
	_game_manager.pilgrimage_shield_gained.connect(_on_pilgrimage_shield_gained)
	_game_manager.sword_forge_unlocked_signal.connect(_on_sword_forge_unlocked)
	_game_manager.caliburn_used.connect(_on_caliburn_used)

# ─────────────────────────────────────────────────────────────
# 玩家加入/断线
# ─────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func on_player_join(peer_id: int, token: String) -> void:
	# 尝试断线重连
	if _tokens.has(token):
		var player_id: int = _tokens[token]
		_player_to_peer[player_id] = peer_id
		_peer_to_player[peer_id] = player_id
		# 恢复人类控制
		var player = _game_manager.get_player(player_id)
		if player:
			player.is_ai_controlled = false
			player.is_human = true
		_send_full_sync(peer_id)
		_broadcast(NetworkProtocol.SrvOp.PLAYER_RECONNECTED,
			{"player_id": player_id}, _spectator_peers)
		player_rejoined.emit(peer_id, player_id)
		return
	# 如果游戏已通过 room 配置初始化，仅同步状态
	if not room_config.is_empty() and room_config.has("players"):
		_send_full_sync(peer_id)
		return
	# 新玩家
	var player_id = _peer_to_player.size()  # 简单递增ID
	_peer_to_player[peer_id] = player_id
	_player_to_peer[player_id] = peer_id
	var new_token = _make_token(peer_id)
	_tokens[new_token] = player_id
	# 返回给客户端
	rpc_id(peer_id, "receive_join_ack",
		{"player_id": player_id, "token": new_token, "room_id": room_id})
	_maybe_start_game()

func on_player_disconnect(peer_id: int) -> void:
	if not _peer_to_player.has(peer_id):
		return
	var player_id: int = _peer_to_player[peer_id]
	_player_to_peer[player_id] = -1
	# 切换为 AI 托管
	var player = _game_manager.get_player(player_id)
	if player and player.is_alive:
		player.is_human = false
		player.is_ai_controlled = true
	_broadcast(NetworkProtocol.SrvOp.PLAYER_DISCONNECTED,
		{"player_id": player_id}, [])
	# 60秒后若未重连，保持AI（不删除槽位）
	_schedule_empty_check()

func _maybe_start_game() -> void:
	var expected: int = room_config.get("max_players", 2)
	if _peer_to_player.size() >= expected:
		_start_game()

func _start_game() -> void:
	_game_manager.setup_game(room_config)

## 从预构建的 player config 直接初始化（跳过 runtime join 流程）
func initialize_from_config(config: Dictionary) -> void:
	room_config = config
	_game_manager._is_network_game = true
	if config.get("tower_mode", false):
		# 塔模式：GameManager 由 TowerMatchHost 逐层 setup_game 驱动，这里只建立映射
		pass
	else:
		_game_manager.setup_game({"players": config["players"], "tower_mode": false})
	# 建立 peer_id → player_id 映射（从 config 读取实际 peer_id）
	for i in range(config["players"].size()):
		var pc = config["players"][i]
		var peer_id: int = pc.get("peer_id", -1)
		# AI: 强制负数标记，不占真实 peer slot
		if not pc["is_human"]:
			peer_id = -1
		# 人类玩家：peer_id >= 2（服务器是 peer 1，不参与游戏）
		elif peer_id <= 1:
			peer_id = i + 2  # 安全回退，正常情况不应触发
		_peer_to_player[peer_id] = i
		_player_to_peer[i] = peer_id
		var token = _make_token(peer_id)
		_tokens[token] = i

# ─────────────────────────────────────────────────────────────
# 接收客户端输入（RPC any_peer）
# ─────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func client_submit_gesture(gesture: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	print("[DEBUG][NetHost] client_submit_gesture peer=%d player=%d gesture=%d phase=%d" % [peer_id, player_id, gesture, _game_manager._current_phase])
	if player_id < 0:
		return
	if gesture < 0 or gesture > 4:
		return
	var phase := _game_manager._current_phase
	if phase == GameManager.GamePhase.TIEBREAK_INPUT:
		if not _game_manager._tiebreak_candidates.has(player_id):
			return
		_game_manager.submit_tiebreak_gesture(player_id, gesture as PlayerState.Gesture)
	elif phase == GameManager.GamePhase.GESTURE_INPUT:
		_game_manager.submit_gesture(player_id, gesture as PlayerState.Gesture)

@rpc("any_peer", "reliable")
func client_submit_action(action: int, skill_index: int, target_id: int, hp_paid: int = 0) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	print("[NetHost] client_submit_action peer_id=%d player_id=%d action=%d skill_index=%d target_id=%d hp_paid=%d" % [peer_id, player_id, action, skill_index, target_id, hp_paid])
	if player_id < 0:
		print("[NetHost] client_submit_action REJECT: unknown peer")
		return
	if player_id != _game_manager._sole_winner_id:
		print("[NetHost] client_submit_action REJECT: player_id=%d != _sole_winner_id=%d" % [player_id, _game_manager._sole_winner_id])
		return
	if _game_manager._current_phase != GameManager.GamePhase.ACTION_INPUT:
		print("[NetHost] client_submit_action REJECT: phase=%d != ACTION_INPUT" % _game_manager._current_phase)
		return
	if action < 0 or action > PlayerState.ActionType.USE_SKILL:
		print("[NetHost] client_submit_action REJECT: invalid action=%d" % action)
		return
	if action == PlayerState.ActionType.USE_SKILL:
		var winner := _game_manager.get_player(player_id)
		if winner == null:
			print("[NetHost] client_submit_action REJECT: winner not found")
			return
		var all_skills := winner.get_all_skills()
		if skill_index < 0 or skill_index >= all_skills.size():
			print("[NetHost] client_submit_action REJECT: skill_index=%d out of range [0, %d)" % [skill_index, all_skills.size()])
			return
		if target_id >= 0:
			var tgt := _game_manager.get_player(target_id)
			if tgt == null or not tgt.is_alive:
				print("[NetHost] client_submit_action REJECT: target_id=%d invalid or dead" % target_id)
				return
	print("[NetHost] client_submit_action ACCEPT: calling GameManager.submit_action")
	_game_manager.submit_action(player_id,
		action as PlayerState.ActionType, skill_index, target_id, hp_paid)

@rpc("any_peer", "unreliable")
func client_ping(ts: float) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	rpc_id(peer_id, "server_pong", ts)
	# 计算并广播延迟警告
	var rtt_ms = (Time.get_unix_time_from_system() - ts) * 1000.0
	if rtt_ms > 100.0:
		var player_id: int = _peer_to_player.get(peer_id, -1)
		if player_id >= 0:
			_broadcast(NetworkProtocol.SrvOp.HIGH_LATENCY,
				{"player_id": player_id, "ms": rtt_ms}, _spectator_peers)

@rpc("any_peer", "reliable")
func client_send_chat(message: String) -> void:
	if message.length() > 200:
		message = message.left(200)
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	var sender_name := "Unknown"
	if player_id >= 0:
		var player = _game_manager.get_player(player_id)
		if player:
			sender_name = player.player_name
	_broadcast(NetworkProtocol.SrvOp.CHAT_MESSAGE,
		{"sender_id": player_id, "sender_name": sender_name, "message": message}, _spectator_peers)

@rpc("any_peer", "reliable")
func client_request_spectate() -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	if _spectator_peers.size() >= room_config.get("max_spectators", 0):
		rpc_id(peer_id, "server_broadcast", 99, {"error": "spectator_full"})
		return
	_spectator_peers.append(peer_id)
	_send_full_sync(peer_id)

## 塔模式：客户端提交祝福选择（actor 校验：只能为自己的角色选）
@rpc("any_peer", "reliable")
func client_submit_reward_pick(player_index: int, buff: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	if player_id != player_index:
		print("[NetHost] client_submit_reward_pick REJECT: player_id=%d != player_index=%d" % [player_id, player_index])
		return
	tower_reward_pick_received.emit(player_index, buff)

## 塔模式：TowerMatchHost 用此广播楼层/奖励事件
func broadcast_tower_op(op: int, data: Dictionary) -> void:
	_broadcast(op, data, _spectator_peers)

## 塔模式：整局结束，稍后销毁房间（对齐经典模式 GAME_OVER 后的节奏）
func finish_run() -> void:
	get_tree().create_timer(2.0).timeout.connect(func(): room_empty.emit(), CONNECT_ONE_SHOT)

## 断线重连：查某 player_id 的重连 token（开局时随 rpc_game_starting 下发）
func get_token_for_player(player_id: int) -> String:
	for t in _tokens:
		if _tokens[t] == player_id:
			return t
	return ""

# ────────────────────────── ᵘ RPC 发送端存根 ─────────────────────
# ⚠ rpc_id() 从本节点发出，故本脚本也必须声明这些 @rpc 方法
@rpc("authority", "reliable")
func server_broadcast(_op: int, _data: Dictionary) -> void:
	pass

@rpc("authority", "reliable")
func receive_join_ack(_info: Dictionary) -> void:
	pass

@rpc("authority", "reliable")
func join_room_failed(_reason: String) -> void:
	pass

@rpc("authority", "unreliable")
func server_pong(_client_ts: float) -> void:
	pass

# 客户端拉取状态（pull-based 握手，取代 push-based _send_initial_syncs）
@rpc("any_peer", "reliable")
func client_request_sync() -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	if player_id < 0:
		return
	var token := ""
	for t in _tokens:
		if _tokens[t] == player_id:
			token = t
			break
	rpc_id(peer_id, "receive_join_ack",
		{"player_id": player_id, "token": token, "room_id": room_id})
	_send_full_sync(peer_id)

@rpc("any_peer", "reliable")
func client_submit_bell_decision(player_id: int, use_bell: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	if _game_manager._current_phase != GameManager.GamePhase.END_PHASE:
		return
	GameManager.submit_bell_decision(player_id, use_bell)

@rpc("any_peer", "reliable")
func client_submit_ftg_intercept(player_id: int, choice: int, swap_target_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_ftg_intercept(player_id, choice, swap_target_id)

@rpc("any_peer", "reliable")
func client_submit_rasengan_counter(player_id: int, use_counter: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_rasengan_counter(player_id, use_counter)

@rpc("any_peer", "reliable")
func client_submit_project_skill(player_id: int, target_id: int, skill_path: String) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_project_skill(player_id, target_id, skill_path)

@rpc("any_peer", "reliable")
func client_submit_phantom_dodge(player_id: int, dodge: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_phantom_dodge(player_id, dodge)

@rpc("any_peer", "reliable")
func client_submit_backtrack_decision(player_id: int, use_backtrack: bool) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_backtrack_decision(player_id, use_backtrack)

@rpc("any_peer", "reliable")
func client_submit_hiroari_targets(player_id: int, targets: Array[int]) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != player_id:
		return
	GameManager.submit_hiroari_targets(player_id, targets)

@rpc("any_peer", "reliable")
func client_submit_dream_end(caster_id: int, target_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != caster_id:
		return
	GameManager.submit_dream_end(caster_id, target_id)

@rpc("any_peer", "reliable")
func client_submit_lake_blessing(caster_id: int, target_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != caster_id:
		return
	GameManager.submit_lake_blessing(caster_id, target_id)

@rpc("any_peer", "reliable")
func client_submit_sword_forge(target_id: int, skill_index: int, attack_target_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var sender_player_id: int = _peer_to_player.get(peer_id, -1)
	if sender_player_id < 0 or sender_player_id != target_id:
		return
	GameManager.submit_sword_forge(target_id, skill_index, attack_target_id)

# ─────────────────────────────────────────────────────────────
# GameManager 信号 → RPC 广播
# ─────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	_broadcast(NetworkProtocol.SrvOp.PHASE_ENTER, {"phase": phase}, _spectator_peers)
	if phase == GameManager.GamePhase.ROUND_END:
		_broadcast(NetworkProtocol.SrvOp.STATE_HASH,
			{"hash": _compute_state_hash()}, _spectator_peers)
	_arm_turn_failsafe(phase)

# ── 塔模式决策兜底 ────────────────────────────────────────────
# 准备阶段投影/结束阶段钟/闪避类决策若玩家 20 秒未响应，自动按"跳过/拒绝"处理，
# 防止服务器停在等待决策的阶段造成整局永久卡死

const DECISION_FAILSAFE := 20.0
var _decision_pending: Dictionary = {}

func _arm_decision_failsafe(key: String, player_id: int, decline: Callable) -> void:
	if not room_config.get("tower_mode", false):
		return
	var k := "%s_%d" % [key, player_id]
	if _decision_pending.has(k):
		return
	_decision_pending[k] = true
	var t := get_tree().create_timer(DECISION_FAILSAFE)
	t.timeout.connect(func():
		if _decision_pending.erase(k) == false:
			return
		decline.call()
	)

func _hook_decision_failsafes() -> void:
	_game_manager.end_phase_bell_decision_required.connect(func(player_id: int, _bell: int):
		_arm_decision_failsafe("bell", player_id,
			func(): _game_manager.submit_bell_decision(player_id, false)))
	_game_manager.project_skill_required.connect(func(player_id: int, _targets: Array):
		_arm_decision_failsafe("project", player_id,
			func(): _game_manager.submit_project_skill(player_id, -1, "")))
	_game_manager.phantom_dodge_required.connect(func(player_id: int, _attacker: int):
		_arm_decision_failsafe("dodge", player_id,
			func(): _game_manager.submit_phantom_dodge(player_id, false)))
	_game_manager.backtrack_required.connect(func(player_id: int):
		_arm_decision_failsafe("backtrack", player_id,
			func(): _game_manager.submit_backtrack_decision(player_id, false)))

# ── 塔模式回合推进保险 ────────────────────────────────────────
# 客户端相位漂移或真人卡住时，服务器兜底提交（SKIP/蓄力），保证整局推进不卡死

const TURN_FAILSAFE_GESTURE := 20.0
const TURN_FAILSAFE_ACTION := 25.0

var _failsafe_timer: Timer

func _arm_turn_failsafe(phase: GameManager.GamePhase) -> void:
	if not room_config.get("tower_mode", false):
		return
	if _failsafe_timer != null and is_instance_valid(_failsafe_timer):
		_failsafe_timer.queue_free()
	_failsafe_timer = null
	var timeout := 0.0
	if phase == GameManager.GamePhase.GESTURE_INPUT \
			or phase == GameManager.GamePhase.TIEBREAK_INPUT:
		timeout = TURN_FAILSAFE_GESTURE
	elif phase == GameManager.GamePhase.ACTION_INPUT:
		timeout = TURN_FAILSAFE_ACTION
	if timeout <= 0.0:
		return
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = timeout
	t.timeout.connect(_on_turn_failsafe.bind(phase))
	add_child(t)
	t.start()
	_failsafe_timer = t

func _on_turn_failsafe(phase: GameManager.GamePhase) -> void:
	_failsafe_timer = null
	if _game_manager._current_phase != phase:
		return
	for p in _game_manager.get_alive_players():
		if not p.is_human or p.is_ai_controlled:
			continue
		if (phase == GameManager.GamePhase.GESTURE_INPUT
				or phase == GameManager.GamePhase.TIEBREAK_INPUT):
			if p.current_gesture == PlayerState.Gesture.NONE:
				_game_manager.submit_gesture(p.player_id, PlayerState.Gesture.SKIP)
		elif phase == GameManager.GamePhase.ACTION_INPUT:
			if _game_manager._sole_winner_id == p.player_id \
					and p.pending_action == PlayerState.ActionType.NONE:
				_game_manager.submit_action(p.player_id,
					PlayerState.ActionType.CHARGE, -1, -1, 0)

func _on_gesture_submitted(player_id: int, gesture: int) -> void:
		_broadcast(NetworkProtocol.SrvOp.GESTURE_DECIDED,
			{"player_id": player_id}, _spectator_peers)

func _on_round_resolved(result: Dictionary) -> void:
	var gestures: Dictionary = {}
	for p in _game_manager._players:
		if p.is_alive:
			gestures[p.player_id] = p.current_gesture
	_broadcast(NetworkProtocol.SrvOp.GESTURES_REVEALED,
		{"gestures": gestures, "result": result}, _spectator_peers)

func _on_action_required(player_id: int) -> void:
	# 仅通知胜者
	var peer_id: int = _player_to_peer.get(player_id, -1)
	print("[NetHost] _on_action_required player_id=%d peer_id=%d my_id=%d" % [player_id, peer_id, multiplayer.get_unique_id()])
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		print("[NetHost] _on_action_required SENDING targeted ACTION_INPUT to peer %d" % peer_id)
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.PHASE_ENTER,
			{"phase": GameManager.GamePhase.ACTION_INPUT, "winner_id": player_id})
	else:
		print("[NetHost] _on_action_required SKIP: peer_id <= 0 or is self")

func _on_skill_applied(logs: Array[Dictionary]) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "skill", "logs": logs}, _spectator_peers)

func _on_player_paralyzed_broadcast(player_id: int, turns: int) -> void:
	if turns == 0:
		_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
			{"type": "paralyze", "player_id": player_id, "turns": 0}, _spectator_peers)

func _on_player_knocked_down_broadcast(player_id: int, turns: int) -> void:
	if turns == 0:
		_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
			{"type": "knockdown", "player_id": player_id, "turns": 0}, _spectator_peers)

func _on_player_charged(player_id: int, new_energy: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "charge", "player_id": player_id, "energy": new_energy},
		_spectator_peers)

func _on_player_eliminated(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.PHASE_ENTER,
		{"phase": GameManager.GamePhase.ELIMINATION, "player_id": player_id},
		_spectator_peers)

func _on_game_over(winner_id: int, _record) -> void:
	# 塔模式：game_over 是每层事件，整局结束由 TowerMatchHost 决定并广播
	if room_config.get("tower_mode", false):
		return
	_broadcast(NetworkProtocol.SrvOp.GAME_OVER_RESULT,
		{"winner_id": winner_id, "match_record": _record.to_dict()}, _spectator_peers)
	# 2秒后销毁：让最后一帧 RPC 送达客户端
	get_tree().create_timer(2.0).timeout.connect(func(): room_empty.emit(), CONNECT_ONE_SHOT)

func _on_skill_unlocked(player_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "skill_unlocked", "player_id": player_id, "skill": skill_name},
		_spectator_peers)

func _on_delayed_damage(player_id: int, damage: float, remaining_hp: float) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "delayed_damage", "player_id": player_id,
		 "damage": damage, "hp": remaining_hp}, _spectator_peers)

func _on_distance_changed(from_id: int, to_id: int, new_distance: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "distance", "from": from_id, "to": to_id, "dist": new_distance},
		_spectator_peers)

func _on_tiebreak_started(candidates: Array[int]) -> void:
	_broadcast(NetworkProtocol.SrvOp.PHASE_ENTER,
		{"phase": GameManager.GamePhase.TIEBREAK_INPUT, "candidates": candidates},
		_spectator_peers)

func _on_tiebreak_resolved(winner_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "tiebreak_winner", "player_id": winner_id}, _spectator_peers)

func _on_bell_gained(player_id: int, bell_count: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "bell_gained", "player_id": player_id, "bell_count": bell_count},
		_spectator_peers)

func _on_counter_stance_entered(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "counter_stance", "player_id": player_id}, _spectator_peers)

func _on_counter_stance_triggered(target_id: int, attacker_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "counter_triggered", "target_id": target_id, "attacker_id": attacker_id},
		_spectator_peers)

func _on_counter_stance_ended(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "counter_ended", "player_id": player_id}, _spectator_peers)

func _on_skill_disabled_broadcast(player_id: int, turns: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "skill_disabled", "player_id": player_id, "turns": turns},
		_spectator_peers)

func _on_end_phase_bell_decision_required(player_id: int, bell_count: int) -> void:
	# 仅通知有钟机制的玩家（人类玩家才需要弹UI）
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.END_PHASE_BELL,
			{"player_id": player_id, "bell_count": bell_count})

func _on_player_invincible(player_id: int, turns: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "invincible", "player_id": player_id, "turns": turns}, _spectator_peers)

func _on_player_burning(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "burning", "player_id": player_id}, _spectator_peers)

func _on_player_berserker(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "berserker", "player_id": player_id}, _spectator_peers)

func _on_gate_changed(player_id: int, gate_count: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "gate_changed", "player_id": player_id, "gate_count": gate_count}, _spectator_peers)

func _on_eighth_gate_opened(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "eighth_gate", "player_id": player_id}, _spectator_peers)

func _on_skill_lost(player_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "skill_lost", "player_id": player_id, "skill_name": skill_name}, _spectator_peers)

func _on_burn_damage_triggered(player_id: int, damage: float, remaining_hp: float, reason: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "burn_damage", "player_id": player_id, "damage": damage, "hp": remaining_hp, "reason": reason}, _spectator_peers)

## 血付广播：客户端需同步 HP 扣减与气增加
func _on_hp_payment_made(player_id: int, hp_paid: float) -> void:
	var p := _game_manager.get_player(player_id)
	if p == null:
		return
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "hp_payment", "player_id": player_id, "hp_paid": hp_paid,
		 "hp": p.hp, "energy": p.energy}, _spectator_peers)

# ── 波风水门信号广播 ──

func _on_ftg_marks_changed(player_id: int, marks: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "ftg_marks_changed", "player_id": player_id, "marks": marks}, _spectator_peers)

func _on_ftg_mark_applied(target_id: int, attacker_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "ftg_mark_applied", "target_id": target_id, "attacker_id": attacker_id}, _spectator_peers)

func _on_ftg_mark_removed(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "ftg_mark_removed", "player_id": player_id}, _spectator_peers)

func _on_ftg_swap_triggered(swapper_id: int, swapped_id: int, original_target_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "ftg_swap", "swapper_id": swapper_id, "swapped_id": swapped_id, "original_target_id": original_target_id}, _spectator_peers)

func _on_ftg_dodge_triggered(player_id: int, attacker_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "ftg_dodge", "player_id": player_id, "attacker_id": attacker_id}, _spectator_peers)

func _on_nine_tails_stage_changed(player_id: int, stage: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "nine_tails_stage", "player_id": player_id, "stage": stage}, _spectator_peers)

func _on_nine_tails_invincible_started(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "nine_tails_invincible_started", "player_id": player_id}, _spectator_peers)

func _on_nine_tails_invincible_ended(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "nine_tails_invincible_ended", "player_id": player_id}, _spectator_peers)

func _on_nine_tails_attack(player_id: int, stage: int, damage: float, target_ids: Array[int]) -> void:
	var hp_updates: Dictionary = {}
	for tid in target_ids:
		var tp := _game_manager.get_player(tid)
		if tp:
			hp_updates[str(tid)] = tp.hp
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "nine_tails_attack", "player_id": player_id, "stage": stage,
			 "damage": damage, "target_ids": target_ids, "hp_updates": hp_updates}, _spectator_peers)

## 飞雷神拦截决策请求：仅发给被拦截的水门玩家
func _on_ftg_intercept_required(target_id: int, attacker_id: int, marked_player_ids: Array[int], attacker_is_marked: bool) -> void:
	var peer_id: int = _player_to_peer.get(target_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.FTG_INTERCEPT,
			{"target_id": target_id, "attacker_id": attacker_id,
			 "marked_player_ids": marked_player_ids, "attacker_is_marked": attacker_is_marked})

## 闪避后反击确认请求：仅发给闪避的水门玩家
func _on_rasengan_counter_required(target_id: int, attacker_id: int, minato_energy: int) -> void:
	var peer_id: int = _player_to_peer.get(target_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.FTG_COUNTER_CONFIRM,
			{"target_id": target_id, "attacker_id": attacker_id, "minato_energy": minato_energy})

# ── 卫宫信号广播 ──

## 投影决策请求：仅发给被投影的人类玩家（AI 由 GameManager 自动决策）
func _on_project_skill_required(player_id: int, target_ids: Array[int]) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.PROJECT_SKILL_REQUIRED,
			{"player_id": player_id, "target_ids": target_ids})

# ── 新止水（天劫）信号广播 ──

## 幻影闪避决策请求：仅发给被攻击的新止水人类玩家
func _on_phantom_dodge_required(player_id: int, attacker_id: int) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.PHANTOM_DODGE_REQUIRED,
			{"player_id": player_id, "attacker_id": attacker_id})

## 别天神回溯决策请求：仅发给新止水人类玩家（准备阶段）
func _on_backtrack_required(player_id: int) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.BACKTRACK_REQUIRED,
			{"player_id": player_id})

## 日影舞目标选择请求：仅发给新止水人类玩家（行动阶段）
func _on_hiroari_targets_required(player_id: int, target_ids: Array[int]) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.HIROARI_REQUIRED,
			{"player_id": player_id, "target_ids": target_ids})

## 幻影数量变化：广播给所有客户端（徽章刷新）
func _on_phantom_changed(player_id: int, count: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "phantom_changed", "player_id": player_id, "count": count}, _spectator_peers)

## 日影舞释放：广播给所有客户端（日志/UI）
func _on_hiroari_used(player_id: int, target_ids: Array[int]) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "hiroari_used", "player_id": player_id, "target_ids": target_ids}, _spectator_peers)

## 别天神回溯完成：广播给所有客户端（全体状态已恢复）
## 回溯恢复的是快照状态，客户端无法用增量 ACTION_RESULT 表达，需全量同步 + 日志通知
func _on_backtrack_performed(player_id: int, round: int) -> void:
	# 先发日志通知（UI 显示），再发全量状态同步（恢复客户端状态）
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "backtrack_performed", "player_id": player_id, "round": round}, _spectator_peers)
	var state = []
	for p in _game_manager._players:
		state.append(NetworkProtocol.serialize_player_state(p))
	_broadcast(NetworkProtocol.SrvOp.FULL_STATE_SYNC,
		{"players": state, "phase": _game_manager._current_phase,
		 "round": _game_manager._current_round_number}, _spectator_peers)

func _on_project_skill_made(player_id: int, target_id: int, skill_path: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "project_skill_made", "player_id": player_id, "target_id": target_id, "skill_path": skill_path},
		_spectator_peers)

func _on_binding_field_started(player_id: int, turns: int, target_ids: Array[int]) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "binding_field_started", "player_id": player_id, "turns": turns, "target_ids": target_ids},
		_spectator_peers)

func _on_binding_field_ended(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "binding_field_ended", "player_id": player_id}, _spectator_peers)

func _on_projected_skill_gained(player_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "projected_skill_gained", "player_id": player_id, "skill_name": skill_name},
		_spectator_peers)

func _on_projected_skill_lost(player_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "projected_skill_lost", "player_id": player_id, "skill_name": skill_name},
		_spectator_peers)

# ── 奥伯龙 / 卡斯特 决策弹窗信号 ──

## 梦之终结目标选择请求：仅发给奥伯龙人类玩家（结束阶段）
func _on_dream_end_required(player_id: int, target_ids: Array[int]) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.DREAM_END_REQUIRED,
			{"player_id": player_id, "target_ids": target_ids})

## 湖之加护目标选择请求：仅发给卡斯特人类玩家（结束阶段）
func _on_lake_blessing_required(player_id: int, target_ids: Array[int]) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.LAKE_BLESSING_REQUIRED,
			{"player_id": player_id, "target_ids": target_ids})

## 圣剑锻造技能+目标选择请求：仅发给被锻造的目标人类玩家
func _on_sword_forge_required(player_id: int, skill_names: Array[String], attack_target_ids: Array[int]) -> void:
	var peer_id: int = _player_to_peer.get(player_id, -1)
	if peer_id > 0 and peer_id != multiplayer.get_unique_id():
		rpc_id(peer_id, "server_broadcast",
			NetworkProtocol.SrvOp.SWORD_FORGE_REQUIRED,
			{"player_id": player_id, "skill_names": skill_names, "attack_target_ids": attack_target_ids})

# ── 卡斯特 完成/回退 事件广播（客户端日志显示） ──

func _on_dream_end_used(caster_id: int, target_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "dream_end_used", "caster_id": caster_id, "target_id": target_id}, _spectator_peers)

func _on_lake_blessing_used(caster_id: int, target_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "lake_blessing_used", "caster_id": caster_id, "target_id": target_id}, _spectator_peers)

func _on_sword_forge_used(caster_id: int, target_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "sword_forge_used", "caster_id": caster_id, "target_id": target_id, "skill_name": skill_name}, _spectator_peers)

func _on_sword_forge_fallback(caster_id: int, target_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "sword_forge_fallback", "caster_id": caster_id, "target_id": target_id}, _spectator_peers)

func _on_pilgrimage_shield_gained(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "pilgrimage_shield_gained", "player_id": player_id}, _spectator_peers)

func _on_sword_forge_unlocked(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "sword_forge_unlocked", "player_id": player_id}, _spectator_peers)

func _on_caliburn_used(caster_id: int, target_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "caliburn_used", "caster_id": caster_id, "target_id": target_id}, _spectator_peers)

# ─────────────────────────────────────────────────────────────
# 广播工具
# ─────────────────────────────────────────────────────────────

## 向所有玩家（及可选的观战者）广播
func _broadcast(op: int, data: Dictionary, extra_peers: Array[int]) -> void:
	var my_id = multiplayer.get_unique_id()
	for player_id in _player_to_peer:
		var peer_id: int = _player_to_peer[player_id]
		if peer_id > 0 and peer_id != my_id:
			rpc_id(peer_id, "server_broadcast", op, data)
	for peer_id in extra_peers:
		if peer_id != my_id:
			rpc_id(peer_id, "server_broadcast", op, data)

## 向单个 peer 发送当前完整状态（用于重连）
func _send_full_sync(peer_id: int) -> void:
	var state = []
	for p in _game_manager._players:
		state.append(NetworkProtocol.serialize_player_state(p))
	rpc_id(peer_id, "server_broadcast",
		NetworkProtocol.SrvOp.FULL_STATE_SYNC,
		{"players": state, "phase": _game_manager._current_phase,
		 "round": _game_manager._current_round_number})

func _compute_state_hash() -> int:
	var parts: Array[String] = []
	for p in _game_manager._players:
		# 卫宫字段追加：投影技能路径、投影已用标记、结界回合数、结界锁定目标数、结界技能数
		# 新止水字段追加：幻影数量（phantom_count）
		parts.append("%d:%.1f:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%s:%d:%d:%d:%d" % [
			p.player_id, p.hp, p.energy, p.shield,
			p.clone_count, p.paralyze_turns, p.knockdown_turns, p.bell_count,
			1 if p.counter_stance else 0, p.skill_disabled_turns,
			p.gate_count, p.invincible_turns,
			1 if p.burning else 0, 1 if p.berserker else 0,
			p.ftg_marks, p.nine_tails_stage,
			p.max_energy, p.stomp_active,
			p.projected_skill.resource_path if p.projected_skill != null else "",
			1 if p.projected_used_this_round else 0,
			p.binding_field_turns,
			p.binding_field_targets.size() + p.binding_field_skills.size(),
			p.phantom_count,
		])
	parts.sort()
	return hash(",".join(PackedStringArray(parts)))

func _make_token(_peer_id: int) -> String:
	var crypto := Crypto.new()
	return crypto.generate_random_bytes(16).hex_encode()

func _schedule_empty_check() -> void:
	get_tree().create_timer(RECONNECT_TIMEOUT).timeout.connect(func():
		for pid in _player_to_peer:
			if _player_to_peer[pid] >= 0:
				return  # 有人重连了，不销毁
		room_empty.emit()
	, CONNECT_ONE_SHOT)
