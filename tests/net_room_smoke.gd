extends SceneTree
## 塔联机冒烟测试：服务器(127.0.0.1:7777) + 双客户端完整对局
## 用法：
##   1. 启动本地无头服务器：Godot --headless --path . res://server/server_main.tscn
##   2. GAME_SERVER_IP=127.0.0.1 SMOKE_ROLE=create Godot --headless --path . --script res://tests/net_room_smoke.gd
##   3. GAME_SERVER_IP=127.0.0.1 SMOKE_ROLE=join   Godot --headless --path . --script res://tests/net_room_smoke.gd
## C1 会在开战 20 秒后模拟断网，验证 token 自动重连（TOWER_RUN_SYNC 快照恢复）
## 成功标准：服务器日志出现「第2层开始」及（C1 断网后）「重连回房间」，全程无 SCRIPT ERROR

var _rm
var _gm
var _sm
var _code := ""
var _my_index := 0
var _nc  # NetworkGameClient
var _battle_started := false
var _reward_hooked := false


func _initialize() -> void:
	_rm = root.get_node("RoomManager")
	_gm = root.get_node("GameManager")
	_sm = root.get_node("SceneManager")
	_rm.lobby_sync_received.connect(_on_sync)
	_rm.game_starting.connect(_on_game_starting)
	_run()


func _run() -> void:
	await process_frame
	# 走 NetworkManager 连接（与真实客户端一致，支持自动重连测试）
	var nm = root.get_node("NetworkManager")
	nm.connect_to_game_server(nm.GAME_SERVER_IP, nm.GAME_SERVER_PORT, "")
	var waited := 0.0
	while not nm.is_connected_to_game:
		await process_frame
		waited += root.get_process_delta_time()
		if waited > 10.0:
			print("SMOKE_FAIL: 连接超时")
			quit(1)
			return
	print("SMOKE: connected")
	var role: String = OS.get_environment("SMOKE_ROLE")
	if role == "create":
		await _role_create()
	else:
		await _role_join()
	await _battle_loop()


func _role_create() -> void:
	_rm.create_room.rpc_id(1, {"mode": "tower", "max_players": 3, "player_name": "C1"})
	var waited := 0.0
	while _code == "" and waited < 8.0:
		await process_frame
		waited += root.get_process_delta_time()
	if _code == "":
		print("SMOKE_FAIL: 创建房间未收到同步")
		quit(1)
		return
	var f := FileAccess.open("user://tower_room_code.txt", FileAccess.WRITE)
	f.store_string(_code)
	f.close()
	print("SMOKE_C1: 房间已创建 %s" % _code)
	await _wait(2.5)
	_rm.add_ai.rpc_id(1)
	await _wait(1.5)
	print("SMOKE_C1: start_game")
	_rm.start_game.rpc_id(1)


func _role_join() -> void:
	var waited := 0.0
	while waited < 15.0:
		if FileAccess.file_exists("user://tower_room_code.txt"):
			var f := FileAccess.open("user://tower_room_code.txt", FileAccess.READ)
			_code = f.get_as_text().strip_edges()
			f.close()
			if _code.length() == 6:
				break
		await process_frame
		waited += root.get_process_delta_time()
	if _code == "":
		print("SMOKE_FAIL: 未读到房间号")
		quit(1)
		return
	_rm.join_room.rpc_id(1, _code, "C2")
	await _wait(5.0)


func _on_sync(data: Dictionary) -> void:
	_code = str(data.get("room_code", _code))
	print("SMOKE_SYNC[%s] code=%s slots=%d" % [
		OS.get_environment("SMOKE_ROLE"), _code, data.get("slots", []).size(),
	])


func _on_game_starting(config: Dictionary) -> void:
	if config.get("mode", "") != "tower":
		return
	_my_index = int(config.get("my_player_id", 0))
	var party: Array = []
	for entry in config.get("party", []):
		var cd: Dictionary = root.get_node("Characters").get_by_id(str(entry.get("character_id", "")))
		if cd.is_empty():
			continue
		var res = load(cd.get("res_path", ""))
		if res != null:
			party.append({"character": res, "is_human": bool(entry.get("is_human", false))})
	_sm.last_tower_config = {"players": party}
	_sm.last_game_config = config
	print("SMOKE: game starting my_index=%d party=%d" % [_my_index, party.size()])
	var tb = load("res://scenes/tower/tower_battle.tscn").instantiate()
	root.add_child(tb)
	_battle_started = true


func _battle_loop() -> void:
	var loops := 0
	var dropped := false
	while loops < 720:  # ~6 分钟上限
		loops += 1
		await _wait(0.5)
		if not _battle_started:
			continue
		# C1 专属：开战 20 秒后模拟断网（关闭 ENet + 触发断线处理），验证自动重连
		if OS.get_environment("SMOKE_ROLE") == "create" and not dropped and loops >= 40:
			dropped = true
			print("SMOKE: 模拟断网！")
			root.get_multiplayer().multiplayer_peer.close()
			var nm = root.get_node("NetworkManager")
			nm._on_game_disconnected()
		if _nc == null or not is_instance_valid(_nc):
			_nc = _rm.get_node_or_null("Room_" + str(_sm.last_game_config.get("room_code", "")))
			if _nc != null and not _reward_hooked:
				_reward_hooked = true
				_nc.tower_reward_offer_received.connect(_on_offer)
				# 挂服务器阶段广播：服务端刚进入阶段时立刻提交，时序保证对齐
				_nc.phase_changed.connect(_on_server_phase)


## 服务器阶段广播驱动（对齐服务端时序）
func _on_server_phase(phase: int, _data: Dictionary = {}) -> void:
	if _my_index < 0 or _nc == null:
		return
	if phase == _gm.GamePhase.GESTURE_INPUT or phase == _gm.GamePhase.TIEBREAK_INPUT:
		_nc.submit_gesture(randi_range(1, 3) as PlayerState.Gesture)
	elif phase == _gm.GamePhase.ACTION_INPUT:
		# 只有所属玩家是胜者时服务器才会接受，否则安全拒绝
		_nc.submit_action(PlayerState.ActionType.USE_SKILL, 0, _first_enemy_id(), 0)


func _first_enemy_id() -> int:
	for p in _gm.get_alive_players():
		if p.team_id == 2:
			return p.player_id
	return 0


func _on_offer(player_index: int, _char_name: String, choices: Array) -> void:
	if player_index != _my_index or _nc == null:
		return
	if choices.size() > 0:
		_nc.submit_reward_pick(player_index, choices[0])
		print("SMOKE: reward picked (player %d)" % player_index)


func _wait(secs: float) -> void:
	await create_timer(secs).timeout
