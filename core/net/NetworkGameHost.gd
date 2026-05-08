## NetworkGameHost — 服务器端，包装 GameManager，将信号转为 RPC 广播
class_name NetworkGameHost
extends Node

signal room_empty

var room_id: String = ""
var room_config: Dictionary = {}

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

func _connect_signals() -> void:
	_game_manager.phase_changed.connect(_on_phase_changed)
	_game_manager.gesture_submitted.connect(_on_gesture_submitted)
	_game_manager.round_resolved.connect(_on_round_resolved)
	_game_manager.action_required.connect(_on_action_required)
	_game_manager.skill_applied.connect(_on_skill_applied)
	_game_manager.player_paralyzed.connect(_on_player_paralyzed_broadcast)
	_game_manager.player_charged.connect(_on_player_charged)
	_game_manager.player_eliminated.connect(_on_player_eliminated)
	_game_manager.game_over.connect(_on_game_over)
	_game_manager.skill_unlocked.connect(_on_skill_unlocked)
	_game_manager.delayed_damage_triggered.connect(_on_delayed_damage)
	_game_manager.distance_changed.connect(_on_distance_changed)
	_game_manager.tiebreak_started.connect(_on_tiebreak_started)
	_game_manager.tiebreak_resolved.connect(_on_tiebreak_resolved)

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
	_game_manager.setup_game({"players": config["players"]})
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
func client_submit_action(action: int, skill_index: int, target_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	var player_id: int = _peer_to_player.get(peer_id, -1)
	print("[NetHost] client_submit_action peer_id=%d player_id=%d action=%d skill_index=%d target_id=%d" % [peer_id, player_id, action, skill_index, target_id])
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
		action as PlayerState.ActionType, skill_index, target_id)

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

# ─────────────────────────────────────────────────────────────
# GameManager 信号 → RPC 广播
# ─────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameManager.GamePhase) -> void:
	_broadcast(NetworkProtocol.SrvOp.PHASE_ENTER, {"phase": phase}, _spectator_peers)
	if phase == GameManager.GamePhase.ROUND_END:
		_broadcast(NetworkProtocol.SrvOp.STATE_HASH,
			{"hash": _compute_state_hash()}, _spectator_peers)

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

func _on_player_charged(player_id: int, new_energy: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "charge", "player_id": player_id, "energy": new_energy},
		_spectator_peers)

func _on_player_eliminated(player_id: int) -> void:
	_broadcast(NetworkProtocol.SrvOp.PHASE_ENTER,
		{"phase": GameManager.GamePhase.ELIMINATION, "player_id": player_id},
		_spectator_peers)

func _on_game_over(winner_id: int, _record) -> void:
	_broadcast(NetworkProtocol.SrvOp.GAME_OVER_RESULT,
		{"winner_id": winner_id, "match_record": _record.to_dict()}, _spectator_peers)
	# 2秒后销毁：让最后一帧 RPC 送达客户端
	get_tree().create_timer(2.0).timeout.connect(func(): room_empty.emit(), CONNECT_ONE_SHOT)

func _on_skill_unlocked(player_id: int, skill_name: String) -> void:
	_broadcast(NetworkProtocol.SrvOp.ACTION_RESULT,
		{"type": "skill_unlocked", "player_id": player_id, "skill": skill_name},
		_spectator_peers)

func _on_delayed_damage(player_id: int, damage: int, remaining_hp: int) -> void:
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
		parts.append("%d:%d:%d:%d:%d:%d" % [
			p.player_id, p.hp, p.energy, p.shield,
			p.clone_count, p.paralyze_turns
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
