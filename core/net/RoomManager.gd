## RoomManager — 仅在服务器进程中运行，管理所有游戏房间
class_name RoomManager
extends Node

## key = room_id(String), value = NetworkGameHost 节点
var _rooms: Dictionary = {}
## key = peer_id(int), value = room_id(String)
var _peer_to_room: Dictionary = {}
## key = token(String), value = {room_id, player_id, peer_id}
var _reconnect_tokens: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func create_room(room_id: String, config: Dictionary) -> void:
	var host = preload("res://core/net/NetworkGameHost.gd").new()
	host.name = "Room_" + room_id
	host.room_id = room_id
	host.room_config = config
	add_child(host)
	_rooms[room_id] = host
	host.room_empty.connect(func(): destroy_room(room_id), CONNECT_ONE_SHOT)

func assign_peer_to_room(peer_id: int, room_id: String, token: String) -> void:
	_peer_to_room[peer_id] = room_id
	if _rooms.has(room_id):
		_rooms[room_id].on_player_join(peer_id, token)

## 客户端连接后发送此 RPC 请求加入指定房间
@rpc("any_peer", "reliable")
func request_join_room(room_id: String, token: String) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _rooms.has(room_id):
		rpc_id(peer_id, "join_room_failed", "房间不存在: " + room_id)
		return
	_peer_to_room[peer_id] = room_id
	_rooms[room_id].on_player_join(peer_id, token)

## 通知客户端加入失败（存根，客户端需实现）
@rpc("authority", "reliable")
func join_room_failed(_reason: String) -> void:
	pass

func destroy_room(room_id: String) -> void:
	if _rooms.has(room_id):
		_rooms[room_id].queue_free()
		_rooms.erase(room_id)
		print("[RoomManager] 房间销毁: %s" % room_id)

func _on_peer_connected(peer_id: int) -> void:
	print("[RoomManager] 新连接: peer %d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var room_id: String = _peer_to_room.get(peer_id, "")
	if room_id == "" or not _rooms.has(room_id):
		return
	_rooms[room_id].on_player_disconnect(peer_id)

func get_room(room_id: String) -> Node:
	return _rooms.get(room_id)
