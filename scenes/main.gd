## Main 场景脚本 — 游戏主场景入口
## 从 SceneManager 读取游戏配置并初始化 GameManager，或使用调试回退配置
extends Node

var _net_client: NetworkGameClient

func _ready() -> void:
	var config = SceneManager.last_game_config
	var is_network = config.get("is_network", false)
	var is_host = config.get("is_host", false)

	# 联机模式
	if is_network:
		_init_network_mode(is_host)
		# 主机：在 GameUI 就绪后再初始化 GameManager
		if is_host:
			var host = NetworkManager.get_node_or_null("CurrentGameHost")
			if host:
				host.initialize_from_config(config)
			$GameUI.setup_players(GameManager.get_alive_players())
	# 单机模式
	elif not config.is_empty():
		GameManager.setup_game(config)
	# 调试回退
	elif GameManager.get_alive_players().is_empty():
		var debug_cfg := {
			"players": [
				{ "name": "佐助",        "is_human": true,  "character": preload("res://resources/characters/宇智波佐助.tres") },
				{ "name": "AI-疾风佐助", "is_human": false, "character": preload("res://resources/characters/宇智波佐助（疾风传）.tres") },
				{ "name": "AI-佐助",     "is_human": false, "character": preload("res://resources/characters/宇智波佐助.tres") },
			]
		}
		GameManager.setup_game(debug_cfg)

	# setup_players 在 setup_game 延迟触发第一阶段之前执行，确保 UI 就绪
	if not is_network:
		$GameUI.setup_players(GameManager.get_alive_players())

	if config.get("is_spectator", false):
		$GameUI.is_spectating = true

func _init_network_mode(is_host: bool) -> void:
	# 权威服务器模型中所有客户端都是 is_host=false，此分支保留以兼容旧逻辑
	if is_host:
		return

	var config = SceneManager.last_game_config
	var room_code: String = config.get("room_code", "")

	_net_client = NetworkGameClient.new()
	# 节点名与服务器端 NetworkGameHost 保持一致，保证 RPC 路径匹配
	# 服务器：/root/RoomManager/Room_XXXXXX  客户端：/root/RoomManager/Room_XXXXXX
	_net_client.name = "Room_" + room_code if room_code != "" else "CurrentGameHost"
	RoomManager.add_child(_net_client)

	$GameUI.net_client = _net_client
	_net_client.phase_changed.connect($GameUI._on_phase_changed)
	_net_client.gesture_decided.connect($GameUI._mark_decided)
	_net_client.gestures_revealed.connect($GameUI._on_gestures_revealed)
	_net_client.action_result.connect($GameUI._on_action_result)
	_net_client.full_state_received.connect($GameUI._on_full_state_sync)
	_net_client.state_hash_received.connect($GameUI._on_state_hash_received)
	_net_client.game_over_received.connect($GameUI._on_game_over_result)

	if config.has("my_player_id"):
		_net_client.my_player_id = config["my_player_id"]

func _exit_tree() -> void:
	if _net_client != null and is_instance_valid(_net_client):
		_net_client.queue_free()
		_net_client = null
	var host_node = NetworkManager.get_node_or_null("CurrentGameHost")
	if host_node and host_node is NetworkGameHost:
		host_node.queue_free()
