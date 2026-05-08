## 无头服务器入口 — 仅在 --headless 模式下使用
extends Node

const PORT := 7777
const MAX_CLIENTS := 64

var _room_manager: RoomManager

func _ready() -> void:
	if not OS.has_feature("dedicated_server") and not DisplayServer.get_name() == "headless":
		return  # 非服务器模式不执行
	print("[Server] 启动，监听端口 %d" % PORT)
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("[Server] 端口绑定失败: %d" % err)
		get_tree().quit()
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	get_tree().get_multiplayer().peer_connected.connect(_on_peer_connected)
	get_tree().get_multiplayer().peer_disconnected.connect(_on_peer_disconnected)

	_room_manager = RoomManager.new()
	_room_manager.name = "RoomManager"
	add_child(_room_manager)
	print("[Server] 就绪，等待连接...")

func _on_peer_connected(peer_id: int) -> void:
	print("[Server] peer 已连接: %d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("[Server] peer 已断开: %d" % peer_id)

## 外部调用此 RPC 来创建游戏房间（由 Nakama 服务端脚本或管理工具触发）
@rpc("any_peer", "reliable")
func admin_create_room(room_id: String, config_json: String) -> void:
	if multiplayer.get_remote_sender_id() != 0:
		return
	var config: Dictionary = JSON.parse_string(config_json)
	if config == null:
		push_error("[Server] admin_create_room: 无效 JSON")
		return
	_room_manager.create_room(room_id, config)

## 便捷方法：直接在服务器代码中创建房间（用于测试）
func create_room_direct(room_id: String, config: Dictionary) -> void:
	_room_manager.create_room(room_id, config)
