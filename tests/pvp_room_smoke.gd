extends SceneTree
## 经典 PVP 联机冒烟测试：服务器(127.0.0.1:7777) + 双客户端 ffa 完整对局
## 用法：
##   1. 启动本地无头服务器：Godot --headless --path . res://server/server_main.tscn
##   2. Godot --headless --path . --script res://tests/pvp_room_smoke.gd -- role=join
##   3. Godot --headless --path . --script res://tests/pvp_room_smoke.gd -- role=create
## 角色来源：命令行 user args（role=xxx）优先，其次环境变量 SMOKE_ROLE；
## 服务器地址：环境变量 GAME_SERVER_IP 优先，默认 127.0.0.1（本地联机测试）。
## 先启动 join（等待房间号文件出现），再启动 create（创建房间并写入房间号）。
## 双方均显式选择春野樱（疾风传）— 纯普攻/治疗，无特殊输入弹窗，避免卡死。
## 成功标准：双方均收到 game_over_received、服务器日志出现「销毁房间」，全程无 SCRIPT ERROR

const PVP_CHAR_ID := "sakura_fy"  # 春野樱（疾风传）：普攻/怪力/恢复，无特殊输入

var _rm
var _gm
var _sm
var _code := ""
var _my_index := 0
var _nc  # NetworkGameClient
var _battle_started := false
var _hooked := false
var _game_over := false
var _last_slots: Array = []
var _last_sync: Dictionary = {}  # 最近一次 lobby_sync 原始数据（取 host_peer_id 判断房主）
var _my_action_count := 0  # 行动计数：3聚1攻循环（普攻耗3气，聚气+1）
var _role := ""  # 本客户端角色（join/create），初始化后填充


## 解析角色：user args（-- role=xxx）优先，回退环境变量 SMOKE_ROLE
func _resolve_role() -> String:
	var env_role := OS.get_environment("SMOKE_ROLE")
	if env_role != "":
		return env_role
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("role="):
			return arg.substr(5)
	return ""


func _initialize() -> void:
	_rm = root.get_node("RoomManager")
	_gm = root.get_node("GameManager")
	_sm = root.get_node("SceneManager")
	_rm.lobby_sync_received.connect(_on_sync)
	_rm.game_starting.connect(_on_game_starting)
	_run()


func _run() -> void:
	await process_frame
	_role = _resolve_role()
	if _role == "":
		print("SMOKE_FAIL: 未指定角色（-- role=join/create 或 SMOKE_ROLE）")
		quit(1)
		return
	var nm = root.get_node("NetworkManager")
	var ip := OS.get_environment("GAME_SERVER_IP")
	if ip == "":
		ip = "127.0.0.1"  # 本地冒烟测试默认连本机
	nm.connect_to_game_server(ip, nm.GAME_SERVER_PORT, "")
	var waited := 0.0
	while not nm.is_connected_to_game:
		await process_frame
		waited += root.get_process_delta_time()
		if waited > 10.0:
			print("SMOKE_FAIL: 连接超时")
			quit(1)
			return
	print("SMOKE: connected")
	if _role == "create":
		await _role_create()
	else:
		await _role_join()
	await _battle_loop()


func _role_create() -> void:
	_rm.create_room.rpc_id(1, {"mode": "ffa", "max_players": 4, "player_name": "C1"})
	var waited := 0.0
	while _code == "" and waited < 8.0:
		await process_frame
		waited += root.get_process_delta_time()
	if _code == "":
		print("SMOKE_FAIL: 创建房间未收到同步")
		quit(1)
		return
	var f := FileAccess.open("user://pvp_room_code.txt", FileAccess.WRITE)
	f.store_string(_code)
	f.close()
	print("SMOKE_C1: 房间已创建 %s" % _code)
	# 房主显式选角（非必须，选则杜绝随机到特殊机制角色）
	_rm.select_character.rpc_id(1, PVP_CHAR_ID)
	# 等待 C2 加入并完成准备（窗口 60 秒：Nakama 认证/session refresh 可能拖慢对方启动）
	var waited2 := 0.0
	var synced := false
	while waited2 < 60.0:
		synced = _check_slots_ready()
		if synced:
			break
		await process_frame
		waited2 += root.get_process_delta_time()
	if not synced:
		print("SMOKE_FAIL: C2 未在时限内就绪")
		quit(1)
		return
	print("SMOKE_C1: start_game")
	_rm.start_game.rpc_id(1)


func _check_slots_ready() -> bool:
	# 与服务器 start_game 校验一致：非房主的人类槽位 ready 即可开始
	# （房主创建房间时 is_ready=false 且无需 ready）
	if _last_slots.size() < 2:
		return false
	var host_peer: int = _last_sync.get("host_peer_id", 0)
	for s in _last_slots:
		if s.get("peer_id", 0) > 0 and not s.get("is_ai", false):
			if int(s.get("peer_id", 0)) != host_peer and not s.get("is_ready", false):
				return false
	return true


func _role_join() -> void:
	var waited := 0.0
	while waited < 60.0:
		if FileAccess.file_exists("user://pvp_room_code.txt"):
			var f := FileAccess.open("user://pvp_room_code.txt", FileAccess.READ)
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
	await _wait(0.5)
	_rm.select_character.rpc_id(1, PVP_CHAR_ID)
	await _wait(0.5)
	_rm.toggle_ready.rpc_id(1)

func _on_sync(data: Dictionary) -> void:
	_code = str(data.get("room_code", _code))
	_last_sync = data
	_last_slots = data.get("slots", [])
	_last_sync = data
	print("SMOKE_SYNC[%s] code=%s slots=%d" % [
		_role, _code, _last_slots.size(),
	])


func _on_game_starting(config: Dictionary) -> void:
	if config.get("mode", "") != "ffa":
		return
	_my_index = int(config.get("my_player_id", 0))
	_sm.last_game_config = config
	print("SMOKE: game starting my_index=%d" % _my_index)
	var main_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(main_scene)
	_battle_started = true


func _battle_loop() -> void:
	var loops := 0
	var start_ms := Time.get_ticks_msec()
	var timeout_ms := 420_000  # 7 分钟上限
	while loops < 900:
		loops += 1
		await _wait(0.5)
		if not _battle_started:
			continue
		if _nc == null or not is_instance_valid(_nc):
			_nc = _rm.get_node_or_null("Room_" + str(_sm.last_game_config.get("room_code", "")))
			if _nc != null and not _hooked:
				_hooked = true
				_nc.phase_changed.connect(_on_server_phase)
				_nc.game_over_received.connect(_on_game_over)
				_nc.full_state_received.connect(_on_full_state)
		# 提前退出：已收到对局结束
		if _game_over:
			print("SMOKE_%s: PASS 收到 game_over_received" % _role)
			quit(0)
			return
		if Time.get_ticks_msec() - start_ms > timeout_ms:
			print("SMOKE_FAIL: 对局超时")
			quit(1)
			return


## 服务器阶段广播驱动（对齐服务端时序）
func _on_server_phase(phase: int, data: Dictionary = {}) -> void:
	if _my_index < 0 or _nc == null:
		return
	if phase == _gm.GamePhase.GESTURE_INPUT or phase == _gm.GamePhase.TIEBREAK_INPUT:
		_nc.submit_gesture(randi_range(1, 3) as PlayerState.Gesture)
	elif phase == _gm.GamePhase.ACTION_INPUT:
		var winner_id: int = int(data.get("winner_id", -1))
		if winner_id == _my_index:
			# 春野樱普攻耗3气、聚气+1：3聚1攻循环保证能量够用且持续造成伤害
			_my_action_count += 1
			if _my_action_count % 4 == 0:
				_nc.submit_action(PlayerState.ActionType.USE_SKILL, 0, _first_enemy_id(), 0)
			else:
				_nc.submit_action(PlayerState.ActionType.CHARGE, -1, -1)


func _first_enemy_id() -> int:
	# 2人ffa：本地状态未同步时直接用环形另一端 id
	if _gm.get_alive_players().is_empty():
		return (_my_index + 1) % 2
	for p in _gm.get_alive_players():
		if p.player_id != _my_index:
			return p.player_id
	return -1


func _on_full_state(players: Array, _phase: int, _round: int) -> void:
	# 客户端本地 GameManager 由 GameUI._setup_from_sync 填充，
	# 但 headless 下 GameUI 不渲染、_setup_from_sync 可能不走，这里兜底同步
	if _gm.get_alive_players().is_empty():
		_gm._players.clear()
		for data in players:
			var char_res = load(data.get("char_id", ""))
			if char_res == null:
				continue
			var ps = PlayerState.new(data["id"], data["name"], char_res, data.get("is_human", false))
			ps.team_id = data.get("team", 0)
			ps.hp = data["hp"]
			ps.energy = data["energy"]
			ps.is_alive = data["alive"]
			_gm._players.append(ps)
		_gm._distance_system = DistanceSystem.new()
		var ids: Array[int] = []
		for p in _gm._players:
			ids.append(p.player_id)
		_gm._distance_system.setup(ids)


func _on_game_over(winner_id: int, _match_data: Dictionary = {}) -> void:
	if _game_over:
		return
	_game_over = true
	print("SMOKE[%s]: game_over winner_id=%d" % [_role, winner_id])


func _wait(secs: float) -> void:
	await create_timer(secs).timeout