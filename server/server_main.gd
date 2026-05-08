## 无头服务器入口 — 仅在 --headless 模式下使用
## RoomManager 已注册为 autoload，由引擎自动创建并管理所有房间
extends Node

const PORT      := 7777
const MAX_PEERS := 64

func _ready() -> void:
	if not OS.has_feature("dedicated_server") and not DisplayServer.get_name() == "headless":
		return
	print("[Server] 启动，监听端口 %d" % PORT)
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PEERS)
	if err != OK:
		push_error("[Server] 端口绑定失败: %d" % err)
		get_tree().quit()
		return
	get_tree().get_multiplayer().multiplayer_peer = peer
	print("[Server] 就绪，等待连接...")
	# RoomManager autoload 在 _ready 里同步完成 Nakama 认证后再接受连接
