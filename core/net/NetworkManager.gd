## NetworkManager — 管理 Nakama 会话和 ENet 游戏连接
extends Node

# ── 配置（开发/生产分离）─────────────────────────────────────
const NAKAMA_HOST    := "8.130.49.62"
const NAKAMA_PORT    := 7350
const NAKAMA_KEY     := "defaultkey"           # 与 Nakama 服务器配置一致
const GAME_SERVER_IP := "8.130.49.62"
const GAME_SERVER_PORT := 7777

# ── 信号 ──────────────────────────────────────────────────────
signal authenticated(user_id: String, username: String)
signal auth_failed(error: String)
signal match_found(match_info: Dictionary)          # Nakama 匹配完成
signal connected_to_game_server()
signal disconnected_from_game_server()
signal game_message_received(op: int, data: Dictionary)

# ── Nakama 大厅层 ──────────────────────────────────────────────
var _client: NakamaClient
var _session: NakamaSession
var _socket: NakamaSocket

# ── ENet 游戏层 ────────────────────────────────────────────────
var _enet_peer: ENetMultiplayerPeer
var is_connected_to_game = false
var my_game_peer_id: int = 0

# ── 本地状态 ───────────────────────────────────────────────────
var reconnect_token: String = ""
var current_room_id: String = ""
var _reconnect_attempt: int = 0
const MAX_RECONNECT_ATTEMPTS := 5

func _ready() -> void:
	_client = Nakama.create_client(NAKAMA_KEY, NAKAMA_HOST, NAKAMA_PORT, "http")
	_try_restore_session()

# ─────────────────────────────────────────────────────────────
# 认证
# ─────────────────────────────────────────────────────────────

func _try_restore_session() -> void:
	var token = _load_pref("session_token", "")
	if token == "":
		return
	_session = NakamaClient.restore_session(token)
	if _session.is_exception() or _session.is_expired():
		_session = null

## 设备匿名登录（首次启动）
func login_device() -> void:
	var device_id = OS.get_unique_id()
	var result: NakamaSession = await _client.authenticate_device_async(device_id, null, true)
	if result.is_exception():
		auth_failed.emit(result.get_exception().message)
		return
	_session = result
	_save_session()
	authenticated.emit(_session.user_id, _session.username)

## 邮箱注册/登录（可选，用于跨设备账号）
func login_email(email: String, password: String, create: bool) -> void:
	var result: NakamaSession = await _client.authenticate_email_async(email, password, null, create)
	if result.is_exception():
		auth_failed.emit(result.get_exception().message)
		return
	_session = result
	_save_session()
	authenticated.emit(_session.user_id, _session.username)

func _save_session() -> void:
	if _session == null:
		return
	_save_pref("session_token", _session.token)
	if _session.refresh_token != "":
		_save_pref("refresh_token", _session.refresh_token)

func is_authenticated() -> bool:
	return _session != null and not _session.is_expired()

# ─────────────────────────────────────────────────────────────
# Nakama 实时 Socket（大厅通知）
# ─────────────────────────────────────────────────────────────

func connect_socket() -> void:
	if _socket != null:
		return
	_socket = Nakama.create_socket_from(_client)
	_socket.received_notification.connect(_on_nakama_notification)
	_socket.received_match_state.connect(_on_nakama_match_state)
	var result = await _socket.connect_async(_session)
	if result.is_exception():
		push_error("Socket connect failed: " + result.get_exception().message)

func _on_nakama_notification(event) -> void:
	pass  # 扩展：处理好友邀请、系统消息等

func _on_nakama_match_state(event) -> void:
	# Nakama relay 传来的消息（武将选择阶段用）
	var op = event.op_code
	var data: Dictionary = JSON.parse_string(event.data) if event.data else {}
	game_message_received.emit(op, data)

# ─────────────────────────────────────────────────────────────
# ENet 游戏连接
# ─────────────────────────────────────────────────────────────

func connect_to_game_server(ip: String, port: int, token: String) -> void:
	reconnect_token = token
	# 断开旧 peer 与信号，防止重复连接
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = ENetMultiplayerPeer.new()
	var mp = get_tree().get_multiplayer()
	if mp.connected_to_server.is_connected(_on_game_connected):
		mp.connected_to_server.disconnect(_on_game_connected)
	if mp.server_disconnected.is_connected(_on_game_disconnected):
		mp.server_disconnected.disconnect(_on_game_disconnected)
	var err = _enet_peer.create_client(ip, port)
	if err != OK:
		return
	mp.multiplayer_peer = _enet_peer
	mp.connected_to_server.connect(_on_game_connected)
	mp.server_disconnected.connect(_on_game_disconnected)

func _on_game_connected() -> void:
	my_game_peer_id = get_tree().get_multiplayer().get_unique_id()
	is_connected_to_game = true
	_reconnect_attempt = 0
	connected_to_game_server.emit()

func _on_game_disconnected() -> void:
	is_connected_to_game = false
	disconnected_from_game_server.emit()
	_attempt_reconnect()

func _attempt_reconnect() -> void:
	_reconnect_attempt += 1
	if reconnect_token == "" or current_room_id == "":
		_reconnect_attempt = 0
		return
	if _reconnect_attempt > MAX_RECONNECT_ATTEMPTS:
		push_warning("[NetworkManager] 重连超过最大次数，放弃")
		_reconnect_attempt = 0
		disconnected_from_game_server.emit()
		return
	var delay := minf(3.0 * pow(2.0, float(_reconnect_attempt - 1)), 60.0)
	push_warning("[NetworkManager] 第 %d 次重连，%0.1f 秒后尝试..." % [_reconnect_attempt, delay])
	await get_tree().create_timer(delay).timeout
	if is_connected_to_game:
		_reconnect_attempt = 0
		return
	connect_to_game_server(GAME_SERVER_IP, GAME_SERVER_PORT, reconnect_token)

# ─────────────────────────────────────────────────────────────
# 匹配队列
# ─────────────────────────────────────────────────────────────

## mode: "ffa_2" / "ffa_4" / "team_2v2" / "team_3v3"
func join_matchmaker(mode: String) -> void:
	if _socket == null:
		await connect_socket()
	var min_count = 2
	var max_count = 2
	match mode:
		"ffa_4":   min_count = 4; max_count = 4
		"team_2v2": min_count = 4; max_count = 4
		"team_3v3": min_count = 6; max_count = 6
	var ticket = await _socket.add_matchmaker_async("*", min_count, max_count,
		{"mode": mode})
	if ticket.is_exception():
		push_error("Matchmaker error: " + ticket.get_exception().message)
		return
	# matched 事件通过 received_matchmaker_matched 信号到达
	if not _socket.received_matchmaker_matched.is_connected(_on_matched):
		_socket.received_matchmaker_matched.connect(_on_matched)

func _on_matched(event) -> void:
	# event: NakamaRTAPI.MatchmakerMatched
	var matched: NakamaRTAPI.MatchmakerMatched = event
	var match_obj = await _socket.join_matched_async(matched)
	if match_obj.is_exception():
		push_error("Join match failed: " + match_obj.get_exception().message)
		return
	current_room_id = match_obj.match_id
	var game_addr: String = match_obj.label if match_obj.label else "%s:%d" % [GAME_SERVER_IP, GAME_SERVER_PORT]
	var parts = game_addr.split(":")
	var ip = parts[0]
	var port = int(parts[1]) if parts.size() > 1 else GAME_SERVER_PORT
	match_found.emit({"match_id": match_obj.match_id, "ip": ip, "port": port,
					  "users": matched.users})

# ─────────────────────────────────────────────────────────────
# 房间（私人/密码房）
# ─────────────────────────────────────────────────────────────

## 创建带密码的私人房间（写入 Nakama storage）
func create_private_room(config: Dictionary) -> String:
	# config: {name, password, mode, max_spectators}
	var code = _generate_room_code()
	var write_obj = NakamaWriteStorageObject.new("rooms", code, 2, 1,
		JSON.stringify(config), "")
	var result = await _client.write_storage_objects_async(_session, [write_obj])
	if result.is_exception():
		if "Auth token" in result.get_exception().message:
			_invalidate_session()
		return ""
	current_room_id = code
	return code

## 列出公开房间（通过服务端 RPC 跨用户查询）
func list_rooms() -> Array:
	var result = await _client.rpc_async(_session, "list_rooms")
	if result.is_exception():
		var msg = result.get_exception().message
		push_error("list_rooms RPC failed: " + msg)
		if "Auth token" in msg:
			_invalidate_session()
		return []
	var rooms = JSON.parse_string(result.payload)
	if rooms == null or not rooms is Array:
		return []
	for config in rooms:
		if not config.has("player_count"):
			config["player_count"] = 1
		if not config.has("max_players"):
			config["max_players"] = 8
		if not config.has("name"):
			config["name"] = config.get("room_code", "???")
		if not config.has("mode"):
			config["mode"] = "ffa"
		if not config.has("status"):
			config["status"] = "waiting"
	return rooms

func _generate_room_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code

## 客户端断开游戏连接并清理状态
func disconnect_from_game() -> void:
	if _enet_peer != null:
		_enet_peer.close()
	_enet_peer = null
	is_connected_to_game = false
	get_tree().get_multiplayer().multiplayer_peer = null
	for child in get_children():
		if child.name == "CurrentGameHost":
			child.queue_free()

func get_local_ip() -> String:
	var ips = IP.get_local_addresses()
	for ip in ips:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172.16."):
			return ip
	return "127.0.0.1"

func publish_room(room_code: String, info: Dictionary) -> void:
	if _client == null or not is_authenticated():
		push_error("publish_room: not authenticated, session=%s" % str(_session))
		return
	var write_obj = NakamaWriteStorageObject.new("rooms", room_code, 2, 1,
		JSON.stringify(info), "")
	var result = await _client.write_storage_objects_async(_session, [write_obj])
	if result.is_exception():
		var msg = result.get_exception().message
		push_error("publish_room failed: " + msg)
		if "Auth token" in msg:
			_invalidate_session()
		return
	current_room_id = room_code

func unpublish_room(room_code: String) -> void:
	if _client == null or _session == null:
		return
	var obj_id = NakamaStorageObjectId.new("rooms", room_code, _session.user_id)
	await _client.delete_storage_objects_async(_session, [obj_id])

# ─────────────────────────────────────────────────────────────
# 本地存储工具
# ─────────────────────────────────────────────────────────────

func _invalidate_session() -> void:
	_session = null
	_save_pref("session_token", "")
	_save_pref("refresh_token", "")

func _save_pref(key: String, value: String) -> void:
	var cfg = ConfigFile.new()
	cfg.load("user://network.cfg")
	cfg.set_value("auth", key, value)
	cfg.save("user://network.cfg")

func _load_pref(key: String, default: String) -> String:
	var cfg = ConfigFile.new()
	if cfg.load("user://network.cfg") != OK:
		return default
	return cfg.get_value("auth", key, default)
