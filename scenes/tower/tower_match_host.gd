class_name TowerMatchHost
extends Node
## 服务器权威的塔模式整局控制器（仅运行在专用服务器上）。
## 持有 TowerManager 逐层推进；战斗内阶段仍由服务器端 GameManager 权威驱动，
## NetworkGameHost 负责把对局状态广播给客户端；本节点负责塔元状态：
## 楼层推进、祝福三选一编排（人类 RPC 提交 / AI 自动选）、敌人强化、整局结束。
## 事件流：
##   start_run → floor_changed → TOWER_FLOOR_START 广播
##   层胜 → floor_cleared → TOWER_FLOOR_CLEARED 广播 → 逐人 TOWER_REWARD_OFFER
##   全员选定 → TOWER_REWARD_PICKED 广播 ×N → start_next_floor（下一层）
##   通关/团灭 → TOWER_RUN_ENDED 广播 → finish_run（销毁房间）

const REWARD_PICK_TIMEOUT := 45.0  # 人类玩家选祝福的超时（超时自动选）
const TowerBuffs := preload("res://scenes/tower/tower_buffs.gd")

var game_host: NetworkGameHost
var room_code: String = ""

var _tm: TowerManager
var _party: Array = []            # [{character: CharacterData, is_human: bool, peer_id: int}]
var _buffs_per_player: Array = [] # 与 _party 平行：每角色持久化祝福列表
var _meta_rng := RandomNumberGenerator.new()  # 奖励/敌人强化专用（不影响 TowerManager 的镜像随机流）
var _run_seed: int = 0
var _reward_phase := false
var _pending_humans: Array = []   # 待提交选择的 party 索引
var _pending_picks: Dictionary = {}  # party 索引 -> 祝福
var _run_over := false


func _ready() -> void:
	_meta_rng.randomize()


## 由 RoomManager 在开局时调用
func setup(host: NetworkGameHost, p_room_code: String, config: Dictionary) -> void:
	game_host = host
	room_code = p_room_code
	for pc in config.get("players", []):
		_party.append({
			"character": pc.get("character", null),
			"is_human": pc.get("is_human", false),
			"peer_id": pc.get("peer_id", -1),
		})
	_buffs_per_player.resize(_party.size())
	for i in _party.size():
		_buffs_per_player[i] = []
	game_host.tower_reward_pick_received.connect(_on_reward_pick)
	game_host.player_rejoined.connect(_on_player_rejoined)


## 断线重连：给重回的玩家补发塔元状态快照（+ 若处于奖励期则重发选项）
func _on_player_rejoined(peer_id: int, player_index: int) -> void:
	if _tm == null or not _tm.is_running():
		return
	game_host.rpc_id(peer_id, "server_broadcast", NetworkProtocol.SrvOp.TOWER_RUN_SYNC, {
		"floor": _tm.get_current_floor(),
		"seed": _run_seed,
		"enemy_name": _tm.get_current_enemy_name(),
		"buffs_per_player": _buffs_per_player,
	})
	if _reward_phase and player_index < _party.size() and _party[player_index]["is_human"]:
		game_host.rpc_id(peer_id, "server_broadcast", NetworkProtocol.SrvOp.TOWER_REWARD_OFFER, {
			"player_index": player_index,
			"char_name": (_party[player_index]["character"] as CharacterData).character_name,
			"choices": _pick_rewards(),
		})
	print("[TowerHost] 玩家 %d 重连（player_index=%d）" % [peer_id, player_index])


func start_run() -> void:
	_tm = TowerManager.new()
	_tm.name = "TowerMgr"
	_tm.set_auto_advance(false)
	# 联机下自动出拳必须关闭：出拳由真人经 RPC 提交，AI 由服务器 AIController 提交
	_tm.config_overrides = {"auto_rps": false}
	_run_seed = _meta_rng.randi()
	_tm.set_seed(_run_seed)
	add_child(_tm)
	_tm.floor_changed.connect(_on_floor_changed)
	_tm.floor_cleared.connect(_on_floor_cleared)
	_tm.tower_victory.connect(_on_run_over.bind(true))
	_tm.tower_defeat.connect(_on_run_over.bind(false))
	# 一次性被动祝福（免死金牌/涅槃）触发 → 标记消耗（下次选祝福回池的依据）
	GameManager.tower_blessing_triggered.connect(_on_blessing_triggered)
	var party_lite: Array = []
	for p in _party:
		party_lite.append({"character": p["character"], "is_human": p["is_human"]})
	print("[TowerHost] %s 开局：party=%d 人" % [room_code, _party.size()])
	_tm.start_tower(party_lite)


# ─────────────────────────────────────────────────────────────
# 楼层事件
# ─────────────────────────────────────────────────────────────

## TowerManager 每层 setup_game 完成后触发：注入队伍祝福与敌人强化，广播开局
func _on_floor_changed(floor_num: int, enemy_name: String) -> void:
	_inject_team_buffs()
	_apply_enemy_attack_bonus()
	var enemy_buffs := _roll_enemy_buffs()
	for entry in enemy_buffs:
		var p := GameManager.get_player(entry.get("player_id", -1))
		if p != null:
			for b in entry.get("buffs", []):
				TowerBuffs.apply_buff(p, b)
	game_host.broadcast_tower_op(NetworkProtocol.SrvOp.TOWER_FLOOR_START, {
		"floor": floor_num,
		"enemy_name": enemy_name,
		"seed": _run_seed,
		"enemy_buffs": enemy_buffs,
	})
	print("[TowerHost] 第%d层开始 — %s" % [floor_num, enemy_name])


## 层胜利：广播 + 启动祝福选择流程（人类三选一 / AI 自动）
func _on_floor_cleared(floor_num: int, _enemy_name: String) -> void:
	_cleanup_consumed_buffs()
	game_host.broadcast_tower_op(NetworkProtocol.SrvOp.TOWER_FLOOR_CLEARED, {
		"floor": floor_num,
	})
	_reward_phase = true
	_pending_humans.clear()
	_pending_picks.clear()
	for i in _party.size():
		if not _party[i]["is_human"]:
			_pending_picks[i] = _pick_one_reward()
			continue
		_pending_humans.append(i)
		var peer_id: int = _party[i]["peer_id"]
		if peer_id <= 0:
			_pending_picks[i] = _pick_one_reward()
			continue
		game_host.rpc_id(peer_id, "server_broadcast", NetworkProtocol.SrvOp.TOWER_REWARD_OFFER, {
			"player_index": i,
			"char_name": (_party[i]["character"] as CharacterData).character_name,
			"choices": _pick_rewards(),
		})
	if _pending_humans.is_empty():
		_finalize_rewards()
	else:
		var t := get_tree().create_timer(REWARD_PICK_TIMEOUT)
		t.timeout.connect(_on_pick_timeout)


## 客户端提交了祝福选择
func _on_reward_pick(player_index: int, buff: Dictionary) -> void:
	if not _reward_phase or not _pending_humans.has(player_index):
		return
	_pending_humans.erase(player_index)
	_pending_picks[player_index] = buff
	if _pending_humans.is_empty():
		_finalize_rewards()


## 选择超时：未提交的真人自动选
func _on_pick_timeout() -> void:
	if not _reward_phase:
		return
	for i in _pending_humans.duplicate():
		print("[TowerHost] 玩家 %d 选择超时，自动选祝福" % i)
		_pending_picks[i] = _pick_one_reward()
	_pending_humans.clear()
	_finalize_rewards()


## 全员选定 → 广播权威结果（含AI自动选，只广播一次）→ 推进下一层
func _finalize_rewards() -> void:
	if not _reward_phase:
		return
	_reward_phase = false
	for i in _pending_picks:
		var buff: Dictionary = _pending_picks[i]
		if buff.is_empty():
			continue
		while _buffs_per_player.size() <= i:
			_buffs_per_player.append([])
		_buffs_per_player[i].append(buff)
		game_host.broadcast_tower_op(NetworkProtocol.SrvOp.TOWER_REWARD_PICKED, {
			"player_index": i, "buff": buff,
		})
	_pending_picks = {}
	_tm.start_next_floor()


func _broadcast_pick(player_index: int) -> void:
	var buff: Dictionary = _pending_picks.get(player_index, {})
	if buff.is_empty():
		return
	game_host.broadcast_tower_op(NetworkProtocol.SrvOp.TOWER_REWARD_PICKED, {
		"player_index": player_index, "buff": buff,
	})


## 通关 / 团灭：广播整局结束并销毁房间
func _on_run_over(victory: bool) -> void:
	if _run_over:
		return
	_run_over = true
	game_host.broadcast_tower_op(NetworkProtocol.SrvOp.TOWER_RUN_ENDED, {
		"victory": victory, "floor": _tm.get_current_floor(),
	})
	print("[TowerHost] %s 整局结束 victory=%s floor=%d" % [room_code, victory, _tm.get_current_floor()])
	game_host.finish_run()


# ─────────────────────────────────────────────────────────────
# 祝福池 / 注入（服务器权威）
# ─────────────────────────────────────────────────────────────

func _reward_pool() -> Array[Dictionary]:
	var floor_num: int = _tm.get_current_floor()
	var allow_elite: bool = floor_num > 0 and floor_num < TowerManager.MAX_FLOORS and floor_num % 4 == 0
	var obtained := _all_obtained_ids()
	var pool: Array[Dictionary] = []
	for reward in TowerRewardUI.REWARD_POOL:
		if not allow_elite and reward.get("tier", "normal") != "normal":
			continue
		if reward.get("unique", false) and reward.get("id", "") in obtained:
			continue
		pool.append(reward)
	return pool


func _pick_rewards() -> Array:
	var pool := _reward_pool()
	var copy := pool.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := _meta_rng.randi_range(0, i)
		var tmp = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy.slice(0, min(3, copy.size()))


func _pick_one_reward() -> Dictionary:
	var choices := _pick_rewards()
	return choices[_meta_rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else {}


func _all_obtained_ids() -> Array:
	var ids: Array = []
	for buffs in _buffs_per_player:
		if buffs is Array:
			for b in buffs:
				if b is Dictionary and b.has("id"):
					ids.append(b.get("id"))
	# 本轮已定（含AI自动选）也计入，防止 unique 祝福本轮重复出现
	for i in _pending_picks:
		var b: Dictionary = _pending_picks[i]
		if b is Dictionary and b.has("id"):
			ids.append(b.get("id"))
	return ids


## 换层前清理已消耗的一次性祝福（斩魂/回春用完即弃；免死金牌/涅槃触发后回池）
func _cleanup_consumed_buffs() -> void:
	var consumed_ids := {"soul_slash": true, "spring": true, "immortal_medal": true, "niepan": true}
	var alive := GameManager.get_alive_players()
	var team_idx := 0
	for p in alive:
		if p.team_id != 1:
			continue
		if team_idx < _buffs_per_player.size() and (_buffs_per_player[team_idx] is Array):
			var buffs: Array = _buffs_per_player[team_idx]
			var to_remove := []
			for b in buffs:
				if not (b is Dictionary):
					continue
				var bid: String = b.get("id", "")
				if not consumed_ids.has(bid):
					continue
				var consumed := false
				match bid:
					"soul_slash":
						consumed = "斩魂" in p.limited_skills_used
					"spring":
						consumed = "回春" in p.limited_skills_used
					"immortal_medal", "niepan":
						consumed = b.get("_consumed", false)
				if consumed:
					to_remove.append(b)
			for b in to_remove:
				buffs.erase(b)
		team_idx += 1


## 一次性被动祝福触发回调：在持久化条目上标记 _consumed
func _on_blessing_triggered(player_id: int, blessing_name: String) -> void:
	var buff_id: String = ""
	match blessing_name:
		"免死金牌":
			buff_id = "immortal_medal"
		"涅槃":
			buff_id = "niepan"
	if buff_id == "":
		return
	var team_idx := 0
	for p in GameManager.get_alive_players():
		if p.team_id != 1:
			continue
		if p.player_id == player_id:
			if team_idx < _buffs_per_player.size():
				for b in _buffs_per_player[team_idx]:
					if b is Dictionary and b.get("id", "") == buff_id:
						b["_consumed"] = true
						break
			return
		team_idx += 1


## 注入队伍各角色的持久化祝福（每层 setup_game 后调用）
func _inject_team_buffs() -> void:
	var team_idx := 0
	for p in GameManager.get_alive_players():
		if p.team_id != 1:
			continue
		if team_idx < _buffs_per_player.size() and (_buffs_per_player[team_idx] is Array):
			for b in _buffs_per_player[team_idx]:
				TowerBuffs.apply_buff(p, b)
		team_idx += 1


## 后期小怪攻击力强化（确定性，无随机）
func _apply_enemy_attack_bonus() -> void:
	var atk_bonus := _tm.get_small_enemy_attack_bonus(_tm.get_current_floor())
	if atk_bonus <= 0:
		return
	for p in GameManager.get_alive_players():
		if p.team_id != 2:
			continue
		p.damage_bonus_basic += atk_bonus


## 后期小怪自带祝福（cycle≥3 的小怪层随机 0-2 个），返回分配表供广播给客户端镜像
func _roll_enemy_buffs() -> Array:
	var floor_num: int = _tm.get_current_floor()
	if floor_num > 0 and floor_num <= TowerManager.MAX_FLOORS and floor_num % 4 == 0:
		return []
	var cycle := ceili(float(floor_num) / 4.0)
	if cycle < 3:
		return []
	var normal_pool: Array = []
	for reward in TowerRewardUI.REWARD_POOL:
		if reward.get("tier", "normal") != "normal":
			continue
		if reward.get("id", "") in ["soul_slash", "spring", "immortal_medal"]:
			continue
		normal_pool.append(reward)
	if normal_pool.is_empty():
		return []
	var out: Array = []
	for p in GameManager.get_alive_players():
		if p.team_id != 2:
			continue
		var count := _meta_rng.randi_range(0, 2)
		var pool_copy := normal_pool.duplicate(true)
		for i in range(pool_copy.size() - 1, 0, -1):
			var j := _meta_rng.randi_range(0, i)
			var tmp = pool_copy[i]
			pool_copy[i] = pool_copy[j]
			pool_copy[j] = tmp
		out.append({
			"player_id": p.player_id,
			"buffs": pool_copy.slice(0, min(count, pool_copy.size())),
		})
	return out
