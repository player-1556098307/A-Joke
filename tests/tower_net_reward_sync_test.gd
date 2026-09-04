extends SceneTree
## 尖塔联机多场景测试：双真人祝福选择同步（服务器+双客户端多进程）
## 覆盖场景：
##   1. offer 只送达玩家本人（player_index 隔离，无串线）
##   2. 双真人各选不同祝福 → 服务器广播双方 PICKED（对方选择可见）
##   3. 伪造提交他人索引 → 服务器 actor 校验 REJECT（服务器日志确认）
##   4. 全员选定 → 服务器推进第2层 → 双端 tower_buffs_per_player 各归各
##   5. 第2层注入：各自 GameManager 中拥有自己的祝福效果（含 AI 自动选可见）
##   6. 断线重连快照恢复（ buffs_per_player 快照）——沿用 net_room_smoke 模式，本测试不覆盖
## 注意：本脚本以 --script 方式运行，autoload 尚未注册时全局类名不可用，
##       故所有节点引用均不使用类型标注（与 net_room_smoke.gd 一致）
## 用法（三终端）：
##   服务器：Godot --headless --path . res://server/server_main.tscn
##   C1: SMOKE_ROLE=create Godot --headless --path . --script res://tests/tower_net_reward_sync_test.gd
##   C2: SMOKE_ROLE=join   Godot --headless --path . --script res://tests/tower_net_reward_sync_test.gd
## 成功标准：双端打印 TOWER_SYNC_PASS 汇总，全程无 SCRIPT ERROR；
##           服务器日志出现 REJECT（actor 校验场景 3）

var _rm
var _gm
var _sm
var _code := ""
var _my_index := 0
var _nc  # NetworkGameClient（无类型标注，避免 --script 模式下编译失败）
var _battle_started := false
var _hooked := false
var _my_picked := ""            # 我最终选择的 buff id
var _picked_records: Array = []  # [{player_index, buff_id}] 全部 PICKED 广播（含对方/AI）
var _offer_indices: Array = []   # 收到的 offer player_index 列表（应只含自己的）
var _floor2_seen := false
var _checks_done := false   # 第2层注入检查完成标志（_finish 依据）
var _offer_count := 0       # 本人收到 offer 的次数（≥2 说明服务器重发了选项）
var _fails: Array = []
const RewardPoolScript = preload("res://scenes/tower/tower_reward_ui.gd")  # headless 下 class_name 不可靠，用 preload
const SkillEffectScript = preload("res://resources/skill_effect.gd")  # 同上：--script 模式下用 preload 访问 EffectType 枚举
var _slots_seen := 1

## 客户端本地镜像：本方 player_id 对应的 PlayerState（用于智能选技判断能量/技能）
var _my_ps = null


func _initialize() -> void:
	_rm = root.get_node("RoomManager")
	_gm = root.get_node("GameManager")
	_sm = root.get_node("SceneManager")
	_rm.lobby_sync_received.connect(_on_sync)
	_rm.game_starting.connect(_on_game_starting)
	_run()


func _run() -> void:
	await process_frame
	var nm = root.get_node("NetworkManager")
	nm.connect_to_game_server(nm.GAME_SERVER_IP, nm.GAME_SERVER_PORT, "")
	var waited := 0.0
	while not nm.is_connected_to_game:
		await process_frame
		waited += root.get_process_delta_time()
		if waited > 10.0:
			print("TOWER_SYNC_FAIL: 连接超时")
			quit(1)
			return
	print("TOWER_SYNC: connected")
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
		print("TOWER_SYNC_FAIL: 创建房间未收到同步")
		quit(1)
		return
	var f := FileAccess.open("user://tower_room_code.txt", FileAccess.WRITE)
	f.store_string(_code)
	f.close()
	print("TOWER_SYNC_C1: 房间已创建 %s" % _code)
	# 等 C2 加入（lobby_sync slots≥2 人类）——C2 join 后服务器会广播 sync
	var w2 := 0.0
	while _slots_seen < 2 and w2 < 20.0:
		await process_frame
		w2 += root.get_process_delta_time()
	if _slots_seen < 2:
		print("TOWER_SYNC_FAIL: C2 未在 20s 内加入（slots=%d）" % _slots_seen)
		quit(1)
		return
	print("TOWER_SYNC_C1: C2 已加入，加 AI 并开局")
	await _wait(1.0)
	_rm.add_ai.rpc_id(1)
	await _wait(1.0)
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
		print("TOWER_SYNC_FAIL: 未读到房间号")
		quit(1)
		return
	_rm.join_room.rpc_id(1, _code, "C2")
	# 加入成功后等开局通知（on_game_starting 信号）
	await _wait(20.0)


func _on_sync(data: Dictionary) -> void:
	_code = str(data.get("room_code", _code))
	var slots: Array = data.get("slots", [])
	_slots_seen = slots.size()
	# 检测他人 slot（仅 create 角色用来判断 C2 加入；join 角色自己就占一个）
	var names: Array = []
	for s in slots:
		names.append(str(s.get("player_name", "?")))
	print("TOWER_SYNC[%s] code=%s slots=%d names=%s" % [
		OS.get_environment("SMOKE_ROLE"), _code, slots.size(), names,
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
	print("TOWER_SYNC: game starting my_index=%d party=%d" % [_my_index, party.size()])
	var tb = load("res://scenes/tower/tower_battle.tscn").instantiate()
	root.add_child(tb)
	_battle_started = true


func _battle_loop() -> void:
	var loops := 0
	while loops < 1440:  # 12 分钟上限
		loops += 1
		await _wait(0.5)
		if not _battle_started:
			continue
		if _nc == null or not is_instance_valid(_nc):
			_nc = _rm.get_node_or_null("Room_" + str(_sm.last_game_config.get("room_code", "")))
			if _nc != null and not _hooked:
				_hooked = true
				_nc.tower_reward_offer_received.connect(_on_offer)
				_nc.tower_reward_picked_received.connect(_on_picked)
				_nc.tower_floor_start_received.connect(_on_floor_start)
				_nc.phase_changed.connect(_on_server_phase)
		# 完成条件：注入检查完成（_on_floor_start 中置位，含 3s 等待）
		if _checks_done:
			_finish()
			return
	# 循环耗尽仍未完成
	print("TOWER_SYNC_FAIL: 超时未到第2层")
	for f in _fails:
		print("  - " + f)
	quit(1)


## 服务器阶段广播驱动（对齐服务器时序，模拟真人出拳）
func _on_server_phase(phase: int, _data: Dictionary = {}) -> void:
	if _my_index < 0 or _nc == null:
		return
	if phase == _gm.GamePhase.GESTURE_INPUT or phase == _gm.GamePhase.TIEBREAK_INPUT:
		_nc.submit_gesture(randi_range(1, 3) as PlayerState.Gesture)
	elif phase == _gm.GamePhase.ACTION_INPUT:
		_submit_smart_action()

## 智能出招：优先选有伤害效果、当前能量够、射程够得着的技能；否则蓄力。
## 注：固定 skill_index=0 在奥伯龙（0号技能=夜之帷幕，纯buff）等角色上会把对局拖成拉锯，
##     6 分钟都打不完第1层，这是上一轮测试超时的根因。
func _submit_smart_action() -> void:
	_refresh_my_ps()
	if _my_ps == null:
		_nc.submit_action(PlayerState.ActionType.CHARGE, 0, -1, 0)
		return
	var target_id := 0
	for p in _gm.get_alive_players():
		if p.team_id == 2:
			target_id = p.player_id
			break
	# 尝试选一个打得动的伤害技能
	if target_id > 0:
		var skills: Array = _my_ps.get_all_skills()
		var target = _gm.get_player(target_id)
		for i in skills.size():
			var sk = skills[i]
			if sk == null or sk.is_passive or sk.energy_cost > _my_ps.energy:
				continue
			if not _skill_has_damage(sk):
				continue
			# 射程检查（距离系统）：目标在射程内才选
			var dist: int = _gm._distance_system.get_distance(_my_ps.player_id, target_id)
			if dist < sk.min_range or dist > sk.max_range:
				continue
			# 目标合法性预检（存活、可被选定）
			if target != null and target.is_alive and target.untargetable_turns <= 0:
				_nc.submit_action(PlayerState.ActionType.USE_SKILL, i, target_id, 0)
				print("TOWER_SYNC_ACTION: player_id=%d 技能[%s] cost=%d 能量=%d -> 目标%d 距离%d" % [
					_my_ps.player_id, sk.skill_name, sk.energy_cost, _my_ps.energy, target_id, dist])
				return
	# 兑现不了伤害就蓄力攒气
	_nc.submit_action(PlayerState.ActionType.CHARGE, 0, -1, 0)
	print("TOWER_SYNC_ACTION: player_id=%d 蓄力（能量=%d）" % [_my_ps.player_id, _my_ps.energy])

## 技能是否含伤害效果（含各类多段/延迟伤害型效果）
func _skill_has_damage(sk) -> bool:
	var ET = SkillEffectScript.EffectType
	for e in sk.effects:
		if e == null:
			continue
		match e.effect_type:
			ET.DAMAGE, ET.TRUE_DAMAGE, ET.PIERCE_DAMAGE, ET.DELAYED_DAMAGE, \
			ET.NINE_TAILS, ET.SUSANOO_SLASH, ET.SUSANOO_SPIRAL, ET.SUSANOO_NINETY_NINE, \
			ET.HIANO_KAGEROHI, ET.DEATH_SENTENCE:
				return true
	return false

## 从本地 GameManager 镜像中取本方 PlayerState
## （塔模式 player_id 即 party 索引，_gm 为服务器状态的全量镜像）
func _refresh_my_ps() -> void:
	_my_ps = _gm.get_player(_my_index)


## 场景1：offer 必须只发给本人（player_index 隔离）
## 场景3加强：第一次 offer 双方都提交同一个 unique（斩魂）强制冲突，
##           验证服务器 REJECT 后提交者并重发选项（第二次 offer）
func _on_offer(player_index: int, char_name: String, choices: Array) -> void:
	_offer_indices.append(player_index)
	if player_index != _my_index:
		_fails.append("收到他人 offer player_index=%d 我的=%d" % [player_index, _my_index])
		print("TOWER_SYNC_FAIL: offer 串线！player_index=%d（我的=%d）" % [player_index, _my_index])
		return
	if choices.is_empty():
		_fails.append("offer 选项为空")
		print("TOWER_SYNC_FAIL: offer 选项为空")
		return
	_offer_count += 1
	var buff: Dictionary
	var role: String = OS.get_environment("SMOKE_ROLE")
	if _offer_count == 1:
		# 第一次：强制冲突——双方都提交斩魂（unique），先提交者成功、后提交者被拒重发
		for r in RewardPoolScript.REWARD_POOL:
			if r.get("id", "") == "soul_slash":
				buff = r
				break
		print("TOWER_SYNC_OFFER[%s]: 收到 offer#%d player_index=%d 角色=%s 选项数=%d → 强制提交冲突祝福 soul_slash" % [
				role, _offer_count, player_index, char_name, choices.size(),
			])
	else:
		# 服务器重发（上一次提交的 unique 已被他人持有）：正常选择（create 选最后，join 选第一，尽量不同）
		var pick_idx: int = 0
		if role == "create":
			pick_idx = choices.size() - 1
		buff = choices[pick_idx]
		print("TOWER_SYNC_OFFER[%s]: 收到重发 offer#%d player_index=%d → 重选 idx=%d id=%s" % [
			role, _offer_count, player_index, pick_idx, str(buff.get("id", "")),
			])
	# 先伪造提交他人索引（actor 校验），再正式提交本次选择
	_nc.submit_reward_pick(1 - _my_index, buff)
	_nc.submit_reward_pick(_my_index, buff)
	print("TOWER_SYNC: 已提交（含一次伪造索引提交，预期被服务器 REJECT）")


## 场景2：对方/AI 的 PICKED 对全员广播（可见性）；自己的 PICKED 确认最终持有
func _on_picked(player_index: int, buff: Dictionary) -> void:
	var bid := str(buff.get("id", ""))
	_picked_records.append({"player_index": player_index, "buff_id": bid})
	if player_index == _my_index:
		# 服务器权威回执：确认我最终持有的祝福（强制冲突场景下可能与提交值不同）
		_my_picked = bid
	print("TOWER_SYNC_PICKED: 收到玩家%d 选择 id=%s（我方=%d）" % [player_index, bid, _my_index])


## 场景4/5：第2层开始后验证 buff 隔离 + 注入
func _on_floor_start(floor_num: int, enemy_name: String, seed_val: int, enemy_buffs: Array) -> void:
	if _floor2_seen:
		return
	_floor2_seen = true
	print("TOWER_SYNC_FLOOR: 第%d层开始 — %s" % [floor_num, enemy_name])
	if floor_num >= 2:
		# 等待场景推进：过渡动画 + _begin_floor_battle + 注入
		await _wait(3.0)
		_check_separation()
		_check_injection()
		_checks_done = true
		print("TOWER_SYNC_INFO: 第2层检查完成")
	# 第1层：只记录，不检查（检查在 floor>=2 时做）


## 校验：双端持久化 buff 各归各（隔离）+ AI 选择可见
func _check_separation() -> void:
	var per_player: Array = _sm.last_tower_config.get("tower_buffs_per_player", [])
	var other_buff_id := ""
	for rec in _picked_records:
		if rec["player_index"] != _my_index:
			other_buff_id = str(rec["buff_id"])
	var role: String = OS.get_environment("SMOKE_ROLE")
	print("TOWER_SYNC[%s]: tower_buffs_per_player=%s" % [role, str(per_player)])
	# 1. 我的索引处只含我的选择
	if per_player.size() <= _my_index or not (per_player[_my_index] is Array):
		_fails.append("per_player 没有我的索引")
	elif _my_picked != "":
		var mine: Array = per_player[_my_index]
		var mine_ids: Array = mine.map(func(b): return str(b.get("id", "")))
		if _my_picked in mine_ids:
			print("TOWER_SYNC_PASS: 我的持久化列表含我选的 %s" % _my_picked)
		else:
			_fails.append("我的持久化列表缺 %s，实际=%s" % [_my_picked, mine_ids])
			print("TOWER_SYNC_FAIL: 我的持久化列表缺 %s" % _my_picked)
	# 2. 对方索引只含对方选择（不得混入我的）
	if other_buff_id != "" and per_player.size() > (1 - _my_index) and (per_player[1 - _my_index] is Array):
		var other: Array = per_player[1 - _my_index]
		var other_ids: Array = other.map(func(b): return str(b.get("id", "")))
		if other_buff_id in other_ids:
			print("TOWER_SYNC_PASS: 对方持久化列表含其选择 %s" % other_buff_id)
		else:
			_fails.append("对方持久化列表缺 %s，实际=%s" % [other_buff_id, other_ids])
			print("TOWER_SYNC_FAIL: 对方持久化列表缺 %s" % other_buff_id)
		if _my_picked != "" and _my_picked in other_ids:
			_fails.append("对方的祝福混入了我的 %s" % _my_picked)
			print("TOWER_SYNC_FAIL: 我的 %s 混入对方列表！" % _my_picked)
	# 3. offer 隔离：只收到过自己的 offer
	for idx in _offer_indices:
		if idx != _my_index:
			_fails.append("offer 串线: %s" % _offer_indices)
	if not _offer_indices.is_empty():
		print("TOWER_SYNC_INFO: 共收到 offer %d 次（本人 offer 次数=%d，>1 表示服务器重发了选项）" % [_offer_indices.size(), _offer_count])
	# 4. AI 自动选也广播可见（索引 2）
	if per_player.size() > 2 and (per_player[2] is Array) and not (per_player[2] as Array).is_empty():
		print("TOWER_SYNC_PASS: AI（索引2）选择可见：%s" % [(per_player[2] as Array).map(func(b): return str(b.get("id", "")))])
	else:
		print("TOWER_SYNC_INFO: AI 索引2 无祝福（可能未选到 unique 或池空，忽略）")


## 校验：第2层注入 —— GameManager 中 team_id=1 玩家应拥有自己的祝福效果
func _check_injection() -> void:
	var team1: Array = []
	for p in _gm.get_alive_players():
		if p.team_id == 1:
			team1.append(p)
	if team1.size() < 2:
		_fails.append("存活队伍不足2人，无法验证注入")
		return
	var ids_by_index: Dictionary = {}
	for rec in _picked_records:
		ids_by_index[rec["player_index"]] = str(rec["buff_id"])
	for team_idx in range(team1.size()):
		var p = team1[team_idx]
		var bid: String = ids_by_index.get(team_idx, "")
		if bid == "":
			continue
		var ok := _check_player_field(p, bid)
		var tag := "PASS" if ok else "FAIL"
		print("TOWER_SYNC_%s: 第2层注入检查 玩家%d(%s) 祝福[%s] -> %s" % [
			tag, team_idx, p.player_name, bid, "已生效" if ok else "未生效",
		])
		if not ok:
			_fails.append("注入失败 idx=%d id=%s" % [team_idx, bid])


## 根据 buff id 检查 PlayerState 对应字段
func _check_player_field(p, bid: String) -> bool:
	match bid:
		"blade_power", "blade_power_2":
			return p.damage_bonus_basic > 0.0
		"charge_bonus":
			return p.charge_bonus > 0
		"shield_wall":
			return p.damage_reduction > 0.0
		"regen", "regen_2":
			return p.regen_per_round > 0.0
		"clone":
			return p.clone_count > 0
		"swift", "swift_2":
			return p.max_energy > 0 or p.energy > 0
		"protect", "protect_2":
			return p.shield > 0
		"vitality", "vitality_2":
			return p.max_hp_bonus > 0.0
		"lifesteal":
			return p.lifesteal_per_hit > 0.0
		"pojun":
			return p.pojun_active
		"bati":
			return p.bati_active
		"immortal_medal":
			return p.immortal_medal
		"niepan":
			return p.niepan_active
		"soul_slash":
			for s in p.unlocked_skills:
				if s != null and s.skill_name == "斩魂":
					return true
			return false
		"spring":
			for s in p.unlocked_skills:
				if s != null and s.skill_name == "回春":
					return true
			return false
	return true  # 未知 id 不误报


func _finish() -> void:
	if _fails.is_empty():
		print("TOWER_SYNC_PASS: 双真人祝福同步全部通过")
	else:
		print("TOWER_SYNC_FAIL: 存在 %d 处失败" % _fails.size())
		for f in _fails:
			print("  - " + f)
	quit(0 if _fails.is_empty() else 1)


func _wait(secs: float) -> void:
	await create_timer(secs).timeout