## RoomManager — autoload，双端共享路径 /root/RoomManager
## 服务器端：管理所有房间 lobby + game 完整生命周期
## 客户端端：RPC 发起点 + 接收服务器推送后发射信号供 room.gd 使用
extends Node

# ── 客户端信号（room.gd 连接）──────────────────────────────────
signal lobby_sync_received(data: Dictionary)
signal game_starting(config: Dictionary)
signal join_failed(reason: String)
signal chat_received(sender_name: String, message: String)

# ── 服务器端状态 ────────────────────────────────────────────────
## key = room_code, value = room state dict
var _rooms: Dictionary = {}
## key = peer_id(int), value = room_code(String)
var _peer_to_room: Dictionary = {}

var _nakama_client = null
var _nakama_session = null
var _nakama_ready: bool = false

const NAKAMA_HOST    := "8.130.49.62"
const NAKAMA_PORT    := 7350
const NAKAMA_KEY     := "defaultkey"
const GAME_SERVER_IP := "8.130.49.62"

const GAME_MODES := {
	"ffa": {"min_players": 2, "max_players": 4, "team_count": 0},
	"2v2": {"min_players": 4, "max_players": 4, "team_count": 2},
}

func _ready() -> void:
	if not _is_dedicated_server():
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	await _init_nakama()
	# 定期检查 Nakama session 有效性
	var timer := Timer.new()
	timer.wait_time = 600.0  # 每 10 分钟检查一次
	timer.timeout.connect(_check_nakama_session)
	add_child(timer)
	timer.start()

func _is_dedicated_server() -> bool:
	return OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless"

func _init_nakama() -> void:
	_nakama_ready = false
	_nakama_client = Nakama.create_client(NAKAMA_KEY, NAKAMA_HOST, NAKAMA_PORT, "http")
	var result = await _nakama_client.authenticate_device_async("game_server_ecs_unique_001", null, true)
	if result.is_exception():
		push_error("[RoomManager] Nakama 认证失败: %s" % result.get_exception().message)
		_nakama_session = null
		return
	_nakama_session = result
	_nakama_ready = true
	print("[RoomManager] Nakama 认证成功, user_id=%s" % _nakama_session.user_id)

# ─────────────────────────────────────────────────────────────
# 客户端 → 服务器 RPC（any_peer；服务器侧有实际逻辑，客户端侧仅存根）
# ─────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func create_room(config: Dictionary) -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _peer_to_room.has(peer_id):
		rpc_id(peer_id, "rpc_join_failed", "已在房间中，请先离开当前房间")
		return
	var mode: String      = config.get("mode", "ffa")
	var max_players: int  = config.get("max_players", 4)
	var player_name: String = config.get("player_name", "玩家")
	var room_code := _gen_code()
	_rooms[room_code] = {
		"room_code":    room_code,
		"mode":         mode,
		"max_players":  max_players,
		"host_peer_id": peer_id,
		"slots": [{
			"peer_id":     peer_id,
			"player_name": player_name,
			"character":   "",
			"is_ready":    false,
			"is_ai":       false,
		}],
		"status":    "waiting",
		"game_host": null,
	}
	_peer_to_room[peer_id] = room_code
	_publish_room(room_code)
	_broadcast_sync(room_code)
	print("[RoomManager] 创建房间 %s  peer=%d" % [room_code, peer_id])

@rpc("any_peer", "reliable")
func join_room(room_code: String, player_name: String) -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _rooms.has(room_code):
		rpc_id(peer_id, "rpc_join_failed", "房间不存在: " + room_code)
		return
	var room: Dictionary = _rooms[room_code]
	if room["status"] != "waiting":
		rpc_id(peer_id, "rpc_join_failed", "游戏已开始，无法加入")
		return
	if room["slots"].size() >= room["max_players"]:
		rpc_id(peer_id, "rpc_join_failed", "房间已满")
		return
	if _peer_to_room.has(peer_id):
		rpc_id(peer_id, "rpc_join_failed", "已在另一房间中，请先离开")
		return
	room["slots"].append({
		"peer_id":     peer_id,
		"player_name": player_name if player_name != "" else "玩家",
		"character":   "",
		"is_ready":    false,
		"is_ai":       false,
	})
	_peer_to_room[peer_id] = room_code
	_publish_room(room_code)
	_broadcast_sync(room_code)
	print("[RoomManager] peer %d 加入房间 %s" % [peer_id, room_code])

@rpc("any_peer", "reliable")
func leave_room() -> void:
	if not _is_dedicated_server():
		return
	_remove_peer_from_room(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func set_player_name(player_name: String) -> void:
	if not _is_dedicated_server():
		return
	_update_slot_field(multiplayer.get_remote_sender_id(), "player_name", player_name)

@rpc("any_peer", "reliable")
func select_character(char_id: String) -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	if _rooms[room_code]["status"] != "waiting":
		return
	_update_slot_field(peer_id, "character", char_id)

@rpc("any_peer", "reliable")
func toggle_ready() -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	if room["status"] != "waiting":
		return
	for slot in room["slots"]:
		if slot["peer_id"] == peer_id:
			slot["is_ready"] = not slot["is_ready"]
			break
	_broadcast_sync(room_code)

@rpc("any_peer", "reliable")
func add_ai() -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	if room["host_peer_id"] != peer_id or room["status"] != "waiting":
		return
	if room["slots"].size() >= room["max_players"]:
		return
	var ai_idx: int = (room["slots"] as Array).size() + 1
	var char_list: Array = Characters.LIST
	var ai_char: String = char_list[randi() % char_list.size()]["id"]
	room["slots"].append({
		"peer_id":     -(ai_idx + 100),
		"player_name": "AI-%d" % ai_idx,
		"character":   ai_char,
		"is_ready":    true,
		"is_ai":       true,
	})
	_broadcast_sync(room_code)

@rpc("any_peer", "reliable")
func start_game() -> void:
	if not _is_dedicated_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	if room["host_peer_id"] != peer_id:
		rpc_id(peer_id, "rpc_join_failed", "只有房主可以开始游戏")
		return
	if room["status"] != "waiting":
		return
	var slots: Array = room["slots"]
	var mode_cfg: Dictionary = GAME_MODES.get(room["mode"], GAME_MODES["ffa"])
	if slots.size() < mode_cfg["min_players"]:
		rpc_id(peer_id, "rpc_join_failed", "需要至少 %d 名玩家" % mode_cfg["min_players"])
		return
	for slot in slots:
		if not slot["is_ai"] and slot["peer_id"] != room["host_peer_id"]:
			if not slot["is_ready"]:
				rpc_id(peer_id, "rpc_join_failed", "等待所有玩家准备就绪")
				return

	room["status"] = "playing"
	_publish_room(room_code)

	# 构建服务器端完整 config（含已加载的 Resource）
	var server_config := _build_server_config(room)

	# 通知各客户端切换场景（仅发 room_code + my_player_id，不发 Resource）
	for i in range(slots.size()):
		var slot = slots[i]
		if slot["peer_id"] > 0 and not slot["is_ai"]:
			rpc_id(slot["peer_id"], "rpc_game_starting", {
				"is_network":    true,
				"is_host":       false,
				"my_player_id":  i,
				"mode":          room["mode"],
				"room_code":     room_code,
			})

	# 服务器端创建 NetworkGameHost，挂在本节点下（路径与客户端 NetworkGameClient 一致）
	var host = preload("res://core/net/NetworkGameHost.gd").new()
	host.name = "Room_" + room_code
	host.room_id = room_code
	add_child(host)
	host.initialize_from_config(server_config)
	host.room_empty.connect(func(): _destroy_room(room_code), CONNECT_ONE_SHOT)
	room["game_host"] = host
	print("[RoomManager] 游戏开始: %s  %d 人" % [room_code, slots.size()])

@rpc("any_peer", "reliable")
func send_chat(sender_name: String, message: String) -> void:
	if not _is_dedicated_server():
		return
	if message.length() > 200:
		message = message.left(200)
	var peer_id := multiplayer.get_remote_sender_id()
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	var sender_id := peer_id
	for slot in _rooms[room_code]["slots"]:
		if slot["peer_id"] > 0 and not slot["is_ai"] and slot["peer_id"] != sender_id:
			rpc_id(slot["peer_id"], "rpc_chat_message", sender_name, message)

# ─────────────────────────────────────────────────────────────
# 服务器 → 客户端 RPC（authority；客户端接收后发射信号）
# ─────────────────────────────────────────────────────────────

@rpc("authority", "reliable")
func rpc_lobby_sync(data: Dictionary) -> void:
	lobby_sync_received.emit(data)

@rpc("authority", "reliable")
func rpc_game_starting(config: Dictionary) -> void:
	game_starting.emit(config)

@rpc("authority", "reliable")
func rpc_join_failed(reason: String) -> void:
	join_failed.emit(reason)

@rpc("authority", "reliable")
func rpc_chat_message(sender_name: String, message: String) -> void:
	chat_received.emit(sender_name, message)

# ─────────────────────────────────────────────────────────────
# 连接管理（服务器端）
# ─────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	print("[RoomManager] 连接: peer %d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("[RoomManager] 断开: peer %d" % peer_id)
	_remove_peer_from_room(peer_id)

func _remove_peer_from_room(peer_id: int) -> void:
	var room_code: String = _peer_to_room.get(peer_id, "")
	_peer_to_room.erase(peer_id)
	if room_code == "" or not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	for i in range(room["slots"].size()):
		if room["slots"][i]["peer_id"] == peer_id:
			room["slots"].remove_at(i)
			break
	var human_slots: Array = (room["slots"] as Array).filter(func(s): return not s["is_ai"])
	if human_slots.is_empty():
		_destroy_room(room_code)
		return
	if room["host_peer_id"] == peer_id:
		room["host_peer_id"] = human_slots[0]["peer_id"]
		print("[RoomManager] 房主转移 → peer %d" % room["host_peer_id"])
	_publish_room(room_code)
	_broadcast_sync(room_code)

func _destroy_room(room_code: String) -> void:
	if not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	if room["game_host"] != null and is_instance_valid(room["game_host"]):
		room["game_host"].queue_free()
	_rooms.erase(room_code)
	_unpublish_room(room_code)
	print("[RoomManager] 销毁房间: %s" % room_code)

# ─────────────────────────────────────────────────────────────
# 状态广播
# ─────────────────────────────────────────────────────────────

func _broadcast_sync(room_code: String) -> void:
	if not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	var data := _serialize_room(room)
	for slot in room["slots"]:
		var pid: int = slot["peer_id"]
		if pid > 0 and not slot["is_ai"]:
			rpc_id(pid, "rpc_lobby_sync", data)

func _serialize_room(room: Dictionary) -> Dictionary:
	var slots_out := []
	for slot in room["slots"]:
		slots_out.append({
			"peer_id":     slot["peer_id"],
			"player_name": slot["player_name"],
			"character":   slot["character"],
			"is_ready":    slot["is_ready"],
			"is_ai":       slot["is_ai"],
		})
	return {
		"room_code":    room["room_code"],
		"mode":         room["mode"],
		"max_players":  room["max_players"],
		"host_peer_id": room["host_peer_id"],
		"slots":        slots_out,
		"status":       room["status"],
	}

func _update_slot_field(peer_id: int, key: String, value: Variant) -> void:
	var room_code: String = _peer_to_room.get(peer_id, "")
	if room_code == "" or not _rooms.has(room_code):
		return
	for slot in _rooms[room_code]["slots"]:
		if slot["peer_id"] == peer_id:
			slot[key] = value
			break
	_broadcast_sync(room_code)

# ─────────────────────────────────────────────────────────────
# 游戏 config 构建（服务器端，含加载的 Resource）
# ─────────────────────────────────────────────────────────────

func _build_server_config(room: Dictionary) -> Dictionary:
	var slots: Array    = room["slots"]
	var mode: String    = room["mode"]
	var max_p: int      = room["max_players"]
	var tc: int         = GAME_MODES.get(mode, GAME_MODES["ffa"])["team_count"]
	var players := []
	for i in range(slots.size()):
		var slot = slots[i]
		var char_data: Dictionary = Characters.get_by_id(slot["character"])
		if char_data.is_empty():
			char_data = Characters.LIST[randi() % Characters.LIST.size()]
		var char_res = null
		var res_path: String = char_data.get("res_path", "")
		if res_path != "":
			char_res = load(res_path)
		if char_res == null and not Characters.LIST.is_empty():
			char_res = load(Characters.LIST[0].get("res_path", ""))
		var team_id := 0
		if tc > 0:
			var per_team: int = max(1, max_p / tc)
			team_id = (i / per_team) + 1
		players.append({
			"id":       i,
			"name":     slot["player_name"],
			"is_human": not slot["is_ai"],
			"character": char_res,
			"team_id":  team_id,
			"peer_id":  slot["peer_id"],
		})
	return {
		"mode":        mode,
		"max_players": max_p,
		"players":     players,
		"is_network":  true,
		"is_host":     false,
	}

# ─────────────────────────────────────────────────────────────
# Nakama storage 同步
# ─────────────────────────────────────────────────────────────

func _publish_room(room_code: String) -> void:
	if _nakama_client == null:
		push_error("[RoomManager] _publish_room: Nakama client 未初始化")
		return
	if _nakama_session == null:
		push_warning("[RoomManager] _publish_room: session 为空，尝试重新认证...")
		await _init_nakama()
		if _nakama_session == null:
			push_error("[RoomManager] _publish_room: 认证失败，房间 %s 无法写入 Nakama storage" % room_code)
			return
	if not _rooms.has(room_code):
		return
	var room: Dictionary = _rooms[room_code]
	var info := {
		"room_code":    room_code,
		"mode":         room["mode"],
		"max_players":  room["max_players"],
		"player_count": room["slots"].size(),
		"status":       room["status"],
		"name":         "游戏房间 " + room_code,
		"host_ip":      GAME_SERVER_IP,
		"port":         7777,
	}
	var write_obj = NakamaWriteStorageObject.new("rooms", room_code, 2, 1,
		JSON.stringify(info), "")
	var result = await _nakama_client.write_storage_objects_async(_nakama_session, [write_obj])
	if result.is_exception():
		var msg: String = result.get_exception().message
		push_error("[RoomManager] Nakama 写入失败: %s" % msg)
		if "Auth" in msg or "auth" in msg or "token" in msg:
			push_warning("[RoomManager] Auth 失败，重新认证后重试...")
			await _init_nakama()
			if _nakama_session != null:
				var retry = await _nakama_client.write_storage_objects_async(_nakama_session, [write_obj])
				if retry.is_exception():
					push_error("[RoomManager] 重试写入仍失败: %s" % retry.get_exception().message)
				else:
					print("[RoomManager] 重试写入成功: %s" % room_code)

func _unpublish_room(room_code: String) -> void:
	if _nakama_client == null or _nakama_session == null:
		return
	var obj_id = NakamaStorageObjectId.new("rooms", room_code, _nakama_session.user_id)
	var result = await _nakama_client.delete_storage_objects_async(_nakama_session, [obj_id])
	if result.is_exception():
		push_error("[RoomManager] Nakama 删除失败: %s" % result.get_exception().message)

func _check_nakama_session() -> void:
	if _nakama_session == null or _nakama_session.is_expired():
		push_warning("[RoomManager] Nakama session 已过期，重新认证...")
		await _init_nakama()

func _gen_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code
