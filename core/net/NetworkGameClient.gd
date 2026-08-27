## NetworkGameClient — 客户端，接收服务器 RPC，映射到本地 UI 信号
class_name NetworkGameClient
extends Node

## 透传给 UI 层的信号（与 GameManager 信号名一致，方便 UI 兼容）
signal phase_changed(phase: int, data: Dictionary)
signal gestures_revealed(gestures: Dictionary, result: Dictionary)
signal action_result(data: Dictionary)
signal full_state_received(state: Array, phase: int, round: int)
signal gesture_decided(player_id: int)
signal player_disconnected_notice(player_id: int)
signal player_reconnected_notice(player_id: int)
signal high_latency_notice(player_id: int, ms: int)
signal game_over_received(winner_id: int, match_data: Dictionary)
signal state_hash_received(hash_val: int)
signal end_phase_bell_received(player_id: int, bell_count: int)
signal end_phase_result_received(player_id: int, use_bell: bool)
signal ftg_intercept_received(target_id: int, attacker_id: int, marked_player_ids: Array[int], attacker_is_marked: bool)
signal rasengan_counter_received(target_id: int, attacker_id: int, minato_energy: int)
signal project_skill_received(player_id: int, target_ids: Array[int])
signal phantom_dodge_received(player_id: int, attacker_id: int)
signal backtrack_received(player_id: int)
signal hiroari_received(player_id: int, target_ids: Array[int])
signal dream_end_received(player_id: int, target_ids: Array[int])
signal lake_blessing_received(player_id: int, target_ids: Array[int])
signal sword_forge_received(player_id: int, skill_names: Array[String], attack_target_ids: Array[int])

var my_player_id: int = -1
var reconnect_token: String = ""
var room_id: String = ""

var _latency_monitor  # LatencyMonitor

func _ready() -> void:
	_latency_monitor = LatencyMonitor.new()
	_latency_monitor.set_client(self)
	add_child(_latency_monitor)
	# 拉取状态：向主机请求同步（取代 push-based _send_initial_syncs）
	rpc_id(1, "client_request_sync")

## 服务器调用此 RPC 将消息推送到客户端
@rpc("authority", "reliable")
func server_broadcast(op: int, data: Dictionary) -> void:
	match op:
		NetworkProtocol.SrvOp.GESTURE_DECIDED:
			gesture_decided.emit(data.get("player_id", -1))
		NetworkProtocol.SrvOp.PHASE_ENTER:
			phase_changed.emit(data.get("phase", 0), data)
		NetworkProtocol.SrvOp.GESTURES_REVEALED:
			gestures_revealed.emit(data.get("gestures", {}), data.get("result", {}))
		NetworkProtocol.SrvOp.ACTION_RESULT:
			action_result.emit(data)
		NetworkProtocol.SrvOp.FULL_STATE_SYNC:
			full_state_received.emit(
				data.get("players", []),
				data.get("phase", 0),
				data.get("round", 0))
		NetworkProtocol.SrvOp.PLAYER_DISCONNECTED:
			player_disconnected_notice.emit(data.get("player_id", -1))
		NetworkProtocol.SrvOp.PLAYER_RECONNECTED:
			player_reconnected_notice.emit(data.get("player_id", -1))
		NetworkProtocol.SrvOp.HIGH_LATENCY:
			high_latency_notice.emit(data.get("player_id", -1), data.get("ms", 0))
		NetworkProtocol.SrvOp.GAME_OVER_RESULT:
			game_over_received.emit(data.get("winner_id", -1), data.get("match_record", {}))
		NetworkProtocol.SrvOp.STATE_HASH:
			state_hash_received.emit(data.get("hash", 0))
		NetworkProtocol.SrvOp.END_PHASE_BELL:
			end_phase_bell_received.emit(data.get("player_id", -1), data.get("bell_count", 0))
		NetworkProtocol.SrvOp.END_PHASE_RESULT:
			end_phase_result_received.emit(data.get("player_id", -1), data.get("use_bell", false))
		NetworkProtocol.SrvOp.FTG_INTERCEPT:
			ftg_intercept_received.emit(
				data.get("target_id", -1),
				data.get("attacker_id", -1),
				data.get("marked_player_ids", []),
				data.get("attacker_is_marked", false))
		NetworkProtocol.SrvOp.FTG_COUNTER_CONFIRM:
			rasengan_counter_received.emit(
				data.get("target_id", -1),
				data.get("attacker_id", -1),
				data.get("minato_energy", 0))
		NetworkProtocol.SrvOp.PROJECT_SKILL_REQUIRED:
			project_skill_received.emit(
				data.get("player_id", -1),
				data.get("target_ids", []))
		NetworkProtocol.SrvOp.PHANTOM_DODGE_REQUIRED:
			phantom_dodge_received.emit(
				data.get("player_id", -1),
				data.get("attacker_id", -1))
		NetworkProtocol.SrvOp.BACKTRACK_REQUIRED:
			backtrack_received.emit(data.get("player_id", -1))
		NetworkProtocol.SrvOp.HIROARI_REQUIRED:
			hiroari_received.emit(
				data.get("player_id", -1),
				data.get("target_ids", []))
		NetworkProtocol.SrvOp.DREAM_END_REQUIRED:
			dream_end_received.emit(
				data.get("player_id", -1),
				data.get("target_ids", []))
		NetworkProtocol.SrvOp.LAKE_BLESSING_REQUIRED:
			lake_blessing_received.emit(
				data.get("player_id", -1),
				data.get("target_ids", []))
		NetworkProtocol.SrvOp.SWORD_FORGE_REQUIRED:
			sword_forge_received.emit(
				data.get("player_id", -1),
				data.get("skill_names", []),
				data.get("attack_target_ids", []))

## 服务器调用：确认加入成功，返回 token 和 player_id
@rpc("authority", "reliable")
func receive_join_ack(info: Dictionary) -> void:
	my_player_id = info.get("player_id", -1)
	reconnect_token = info.get("token", "")
	room_id = info.get("room_id", "")
	# 持久化 token（用于断线重连）
	NetworkManager._save_pref("reconnect_token", reconnect_token)
	NetworkManager._save_pref("reconnect_room", room_id)

## 服务器调用：响应 Ping
@rpc("authority", "unreliable")
func server_pong(client_ts: float) -> void:
	var rtt = (Time.get_unix_time_from_system() - client_ts) * 1000.0
	_latency_monitor.update_latency(rtt)

# ─────────────────────────────────────────────────────────────
# 客户端发送输入
# ─────────────────────────────────────────────────────────────

func submit_gesture(gesture: PlayerState.Gesture) -> void:
	rpc_id(1, "client_submit_gesture", gesture)  # 1 = server peer_id

func submit_action(action: PlayerState.ActionType, skill_index: int, target_id: int, hp_paid: int = 0) -> void:
	print("[NetClient] submit_action action=%d skill_index=%d target_id=%d hp_paid=%d -> sending to host" % [action, skill_index, target_id, hp_paid])
	rpc_id(1, "client_submit_action", action, skill_index, target_id, hp_paid)

func submit_bell_decision(player_id: int, use_bell: bool) -> void:
	rpc_id(1, "client_submit_bell_decision", player_id, use_bell)

func submit_ftg_intercept(player_id: int, choice: int, swap_target_id: int = -1) -> void:
	rpc_id(1, "client_submit_ftg_intercept", player_id, choice, swap_target_id)

func submit_rasengan_counter(player_id: int, use_counter: bool) -> void:
	rpc_id(1, "client_submit_rasengan_counter", player_id, use_counter)

func submit_project_skill(player_id: int, target_id: int, skill_path: String) -> void:
	rpc_id(1, "client_submit_project_skill", player_id, target_id, skill_path)

func submit_phantom_dodge(player_id: int, dodge: bool) -> void:
	rpc_id(1, "client_submit_phantom_dodge", player_id, dodge)

func submit_backtrack_decision(player_id: int, use_backtrack: bool) -> void:
	rpc_id(1, "client_submit_backtrack_decision", player_id, use_backtrack)

func submit_hiroari_targets(player_id: int, targets: Array[int]) -> void:
	rpc_id(1, "client_submit_hiroari_targets", player_id, targets)

func submit_dream_end(caster_id: int, target_id: int) -> void:
	rpc_id(1, "client_submit_dream_end", caster_id, target_id)

func submit_lake_blessing(caster_id: int, target_id: int) -> void:
	rpc_id(1, "client_submit_lake_blessing", caster_id, target_id)

func submit_sword_forge(target_id: int, skill_index: int, attack_target_id: int) -> void:
	rpc_id(1, "client_submit_sword_forge", target_id, skill_index, attack_target_id)

func send_ping() -> void:
	rpc_id(1, "client_ping", Time.get_unix_time_from_system())

# ────────────────────────── ᵘ RPC 发送端存根 ─────────────────────
# ⚠ rpc_id() 从本节点发出，故本脚本也必须声明这些 @rpc 方法
@rpc("any_peer", "unreliable")
func client_ping(_ts: float) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_gesture(_gesture: int) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_action(_action: int, _skill_index: int, _target_id: int, _hp_paid: int = 0) -> void:
	pass

@rpc("any_peer", "reliable")
func client_request_spectate() -> void:
	pass

@rpc("any_peer", "reliable")
func on_player_join(_peer_id: int, _token: String) -> void:
	pass

@rpc("any_peer", "reliable")
func client_request_sync() -> void:
	pass

@rpc("any_peer", "reliable")
func client_send_chat(_message: String) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_bell_decision(_player_id: int, _use_bell: bool) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_ftg_intercept(_player_id: int, _choice: int, _swap_target_id: int) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_rasengan_counter(_player_id: int, _use_counter: bool) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_project_skill(_player_id: int, _target_id: int, _skill_path: String) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_phantom_dodge(_player_id: int, _dodge: bool) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_backtrack_decision(_player_id: int, _use_backtrack: bool) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_hiroari_targets(_player_id: int, _targets: Array[int]) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_dream_end(_caster_id: int, _target_id: int) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_lake_blessing(_caster_id: int, _target_id: int) -> void:
	pass

@rpc("any_peer", "reliable")
func client_submit_sword_forge(_target_id: int, _skill_index: int, _attack_target_id: int) -> void:
	pass

## RoomManager 通知加入失败时调用
@rpc("authority", "reliable")
func join_room_failed(reason: String) -> void:
	push_error("[NetworkGameClient] 加入房间失败: " + reason)
