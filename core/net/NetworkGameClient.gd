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

func submit_action(action: PlayerState.ActionType, skill_index: int, target_id: int) -> void:
	print("[NetClient] submit_action action=%d skill_index=%d target_id=%d -> sending to host" % [action, skill_index, target_id])
	rpc_id(1, "client_submit_action", action, skill_index, target_id)

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
func client_submit_action(_action: int, _skill_index: int, _target_id: int) -> void:
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

## RoomManager 通知加入失败时调用
@rpc("authority", "reliable")
func join_room_failed(reason: String) -> void:
	push_error("[NetworkGameClient] 加入房间失败: " + reason)
