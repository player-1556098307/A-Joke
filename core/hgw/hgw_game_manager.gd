## HGWGameManager — HGW mode main state machine
## Coordinates all sub-modules: map, energy, combat, seals, ring, grail
class_name HGWGameManager
extends Node

enum Phase {
	SETUP,
	TURN_START,
	MOVE_PHASE,
	ACTION_PHASE,
	RPS_INPUT,
	RPS_RESOLVING,
	SKILL_SELECT,
	SKILL_APPLYING,
	TURN_END,
	GAME_OVER,
}

# ── Signals (for UI) ─────────────────────────────────────────────────────────────
signal phase_changed(new_phase: Phase)
signal player_turn_started(player_id: int)
signal player_moved(player_id: int, from_q: int, from_r: int, to_q: int, to_r: int)
signal energy_changed(player_id: int, new_energy: int)
signal rps_needed(attacker_id: int, defender_id: int)
signal combat_hit(log: Dictionary)
signal combat_miss(attacker_id: int)
signal skill_needed(attacker_id: int, skills: Array)
signal player_eliminated(player_id: int)
signal seal_event(seal_index: int, event_type: String, data: Dictionary)
signal grail_opened()
signal game_over(winner_id: int, reason: String)
signal terrain_effect_triggered(player_id: int, terrain: int, effect_desc: String)

# ── Sub-modules ──────────────────────────────────────────────────────────────────
var _energy_mgr: EnergyManager
var _damage_resolver: DamageResolver
var _terrain_effect: TerrainEffect
var _event_table: EventTable
var _combat_mgr: CombatManager
var _seal_mgr: SealManager
var _boss_ai: BossAI
var _shrink_ring: ShrinkRing
var _grail_mgr: GrailManager

# ── Game state ───────────────────────────────────────────────────────────────────
var _players: Array[HGWPlayerState] = []
var _turn_order: Array[int] = []
var _current_turn_index: int = 0
var _round_number: int = 0
var _map_cells: Dictionary = {}
var _map_radius: int = 0
var _current_phase: Phase = Phase.SETUP
var _rng: RandomNumberGenerator
var _ai_controller: HGWAIController

# ── Combat context ───────────────────────────────────────────────────────────────
var _combat_attacker_id: int = -1
var _combat_defender_id: int = -1
var _combat_pending_skill: SkillData = null
var _rps_attacker_gesture: int = -1
var _rps_defender_gesture: int = -1

# ── Fortress tracking ────────────────────────────────────────────────────────────
var _fortress_first_visit: Dictionary = {}
# ── Reward pool tracking ─────────────────────────────────────────────────────────
var _reward_pool: Dictionary = {}  # { Vector2i: accumulated_amount }

# ── Initialization ───────────────────────────────────────────────────────────────

func _init() -> void:
	_energy_mgr = EnergyManager.new()
	_damage_resolver = DamageResolver.new()
	_terrain_effect = TerrainEffect.new()
	_event_table = EventTable.new()
	_combat_mgr = CombatManager.new(_damage_resolver, _energy_mgr, _terrain_effect)
	_seal_mgr = SealManager.new()
	_boss_ai = BossAI.new()
	_shrink_ring = ShrinkRing.new()
	_grail_mgr = GrailManager.new()
	_rng = RandomNumberGenerator.new()
	_ai_controller = HGWAIController.new()

func _ready() -> void:
	_connect_internal_signals()

func _connect_internal_signals() -> void:
	_energy_mgr.energy_changed.connect(func(pid, amt, delta, src): energy_changed.emit(pid, amt))
	_combat_mgr.rps_required.connect(func(aid, did): rps_needed.emit(aid, did))
	_combat_mgr.rps_result.connect(_on_rps_result)
	_combat_mgr.skill_selection_required.connect(func(aid, sk): skill_needed.emit(aid, sk))
	_combat_mgr.combat_resolved.connect(_on_combat_resolved)
	_seal_mgr.seal_unlocked.connect(_on_seal_unlocked)
	_grail_mgr.grail_opened.connect(func(): grail_opened.emit())
	_grail_mgr.victory_grail.connect(func(pid): _end_game(pid, "grail_occupation"))
	_shrink_ring.ring_shrunk.connect(func(r): print("Ring shrunk to radius: ", r))

# ── Setup ────────────────────────────────────────────────────────────────────────

func setup(config: Dictionary) -> void:
	_current_phase = Phase.SETUP

	var num_players: int = config.get("num_players", 3)
	var seed_val: int = config.get("seed", randi() % 99999 + 1)
	var radius_override: int = config.get("map_radius", 0)
	_map_radius = radius_override if radius_override > 0 else HGWMapGenerator.PLAYERS_TO_RADIUS.get(num_players, 8)

	_rng.seed = seed_val

	# Generate map
	var gen := HGWMapGenerator.new(_map_radius, seed_val, num_players)
	gen.generate()
	_map_cells = gen.cells
	_map_radius = gen.game_radius

	# Create players
	var player_configs: Array = config.get("players", [])
	for i in range(player_configs.size()):
		var pc: Dictionary = player_configs[i]
		var state := HGWPlayerState.new()
		state.player_id = i
		state.player_name = pc.get("name", "Player %d" % i)
		state.character = pc.get("character", null)
		state.is_human = pc.get("is_human", false)
		state.max_hp = state.character.max_hp if state.character else 20
		state.hp = state.max_hp
		state.energy = 0

		# Place at spawn
		if i < gen.spawns.size():
			state.hex_q = gen.spawns[i].x
			state.hex_r = gen.spawns[i].y

		_players.append(state)

	# Turn order
	_turn_order.clear()
	for p in _players:
		_turn_order.append(p.player_id)

	# Grail at center
	_grail_mgr.grail_q = 0
	_grail_mgr.grail_r = 0

	# Place seal positions on the map
	_place_seals(gen)

	_enter_phase(Phase.TURN_START)

# ── Phase machine ────────────────────────────────────────────────────────────────

func _enter_phase(phase: Phase) -> void:
	_current_phase = phase
	phase_changed.emit(phase)

	match phase:
		Phase.TURN_START:
			_start_turn()
		Phase.MOVE_PHASE:
			pass  # Wait for UI/AI move input
		Phase.ACTION_PHASE:
			pass  # Wait for UI/AI action input
		Phase.RPS_INPUT:
			_setup_rps()
		Phase.RPS_RESOLVING:
			pass  # Resolved in submit_rps
		Phase.SKILL_SELECT:
			pass  # Wait for skill selection from UI/AI
		Phase.SKILL_APPLYING:
			_apply_skill()
		Phase.TURN_END:
			_end_turn()
		Phase.GAME_OVER:
			pass

func _start_turn() -> void:
	_round_number += 1
	_current_turn_index = 0
	_accumulate_reward_pools()
	_next_player_turn()

func _accumulate_reward_pools() -> void:
	for pos: Vector2i in _map_cells:
		var cell = _map_cells[pos]
		if cell.is_reward:
			_reward_pool[pos] = _reward_pool.get(pos, 0) + 2

func _next_player_turn() -> void:
	while _current_turn_index < _turn_order.size():
		var pid := _turn_order[_current_turn_index]
		var player := get_player(pid)
		if player != null and player.is_alive:
			_energy_mgr.on_turn_start(player)
			player.reset_turn_data()

			# Check desert debuff
			if player.skip_next_action:
				player.skip_next_action = false
				player.acted_this_turn = true
				_advance_turn()
				return

			player_turn_started.emit(pid)
			_enter_phase(Phase.MOVE_PHASE)

			# AI auto-play
			if not player.is_human:
				get_tree().create_timer(0.3).timeout.connect(
					func(): _ai_execute_move(player), CONNECT_ONE_SHOT)
			return
		_current_turn_index += 1

	_end_round()

# ── Public API (called by UI / AI) ───────────────────────────────────────────────

func get_current_player() -> HGWPlayerState:
	if _current_turn_index < _turn_order.size():
		return get_player(_turn_order[_current_turn_index])
	return null

func get_player(player_id: int) -> HGWPlayerState:
	for p in _players:
		if p.player_id == player_id:
			return p
	return null

func get_alive_players() -> Array[HGWPlayerState]:
	var result: Array[HGWPlayerState] = []
	for p in _players:
		if p.is_alive:
			result.append(p)
	return result

func get_players_at(q: int, r: int) -> Array[HGWPlayerState]:
	var result: Array[HGWPlayerState] = []
	for p in _players:
		if p.is_alive and p.hex_q == q and p.hex_r == r:
			result.append(p)
	return result

# ── Movement ─────────────────────────────────────────────────────────────────────

func get_reachable_cells(player: HGWPlayerState) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var start := Vector2i(player.hex_q, player.hex_r)
	var max_dist := player.get_movement()

	var visited: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]

	while not queue.is_empty():
		var cur := queue.pop_front() as Vector2i
		var cur_dist: int = visited[cur]
		if cur_dist >= max_dist:
			continue
		for nb: Vector2i in HGWMapGenerator.hex_neighbors(cur.x, cur.y):
			if not _map_cells.has(nb):
				continue
			var cell = _map_cells[nb]
			if cell.is_void:
				continue
			if cell.terrain == HGWMapGenerator.Terrain.MOUNTAIN:
				continue
			if visited.has(nb):
				continue
			# Check occupied
			var occ := false
			for op in _players:
				if op.is_alive and op.player_id != player.player_id and op.hex_q == nb.x and op.hex_r == nb.y:
					occ = true
					break
			if occ:
				continue
			visited[nb] = cur_dist + 1
			queue.append(nb)
			result.append(nb)

	return result

func submit_move(player_id: int, to_q: int, to_r: int) -> bool:
	if _current_phase != Phase.MOVE_PHASE:
		return false
	var player := get_player(player_id)
	if player == null or player.player_id != get_current_player().player_id:
		return false

	var reachable := get_reachable_cells(player)
	var target := Vector2i(to_q, to_r)
	if not reachable.has(target):
		return false

	var old_q := player.hex_q
	var old_r := player.hex_r
	player.hex_q = to_q
	player.hex_r = to_r
	player.moved_this_turn = true
	player_moved.emit(player_id, old_q, old_r, to_q, to_r)

	# Terrain enter effects
	_apply_terrain_enter(player)

	# Try relic pickup (Seal 3)
	if try_pick_relic(player_id):
		_log_seal_pickup(player_id, 3)

	_enter_phase(Phase.ACTION_PHASE)
	return true

func skip_move(player_id: int) -> void:
	if _current_phase != Phase.MOVE_PHASE:
		return
	var player := get_player(player_id)
	if player == null or player.player_id != get_current_player().player_id:
		return
	_enter_phase(Phase.ACTION_PHASE)

func _apply_terrain_enter(player: HGWPlayerState) -> void:
	var pos := Vector2i(player.hex_q, player.hex_r)
	if not _map_cells.has(pos):
		return
	var cell = _map_cells[pos]
	var terrain: int = cell.terrain
	var pid := player.player_id

	# Fortress first occupation
	if terrain == HGWMapGenerator.Terrain.FORTRESS:
		var key := "%d,%d" % [pos.x, pos.y]
		if not _fortress_first_visit.get(key, false):
			_fortress_first_visit[key] = true
			_energy_mgr.gain(player, 3, EnergyManager.SOURCE_FORTRESS_FIRST)
			terrain_effect_triggered.emit(pid, terrain, "首次占领要塞，获得3气")
		else:
			terrain_effect_triggered.emit(pid, terrain, "进入要塞（伤害减半）")

	# Forest stealth
	if terrain == HGWMapGenerator.Terrain.FOREST:
		terrain_effect_triggered.emit(pid, terrain, "进入森林，获得潜行状态")

	# Desert event
	if terrain == HGWMapGenerator.Terrain.DESERT:
		var event: int = _event_table.roll_desert_event(_rng)
		_event_table.apply_desert_event(player, event, _energy_mgr, _map_cells, _rng)
		seal_event.emit(7, "desert_event", {"player_id": pid, "event": event})
		var enames := {0: "沙暴（跳过下回合行动）", 1: "绿洲（回复1HP）", 2: "遗物（获得1气）", 3: "迷失（随机传送）"}
		terrain_effect_triggered.emit(pid, terrain, "沙漠事件：" + enames.get(event, "未知"))

	# Snow slide
	if terrain == HGWMapGenerator.Terrain.SNOW:
		var occupied: Array[Vector2i] = []
		for p in _players:
			if p.is_alive and p.player_id != pid:
				occupied.append(Vector2i(p.hex_q, p.hex_r))
		var slide_to := _event_table.roll_snow_slide(player.hex_q, player.hex_r, _map_cells, occupied, _rng)
		if slide_to.x != player.hex_q or slide_to.y != player.hex_r:
			player.hex_q = slide_to.x
			player.hex_r = slide_to.y
			player_moved.emit(pid, pos.x, pos.y, slide_to.x, slide_to.y)
			terrain_effect_triggered.emit(pid, terrain, "雪地滑移 → (%d, %d)" % [slide_to.x, slide_to.y])
		else:
			terrain_effect_triggered.emit(pid, terrain, "进入雪地，未滑移")

	# Mountain
	if terrain == HGWMapGenerator.Terrain.MOUNTAIN:
		terrain_effect_triggered.emit(pid, terrain, "进入山脉（受到伤害-1）")

	# Resource tile → +2 energy
	if cell.is_resource:
		_energy_mgr.gain(player, 2, EnergyManager.SOURCE_RESOURCE_TILE)
		var tier_name: String = {"common": "普通", "rare": "稀有", "core": "核心"}.get(cell.res_tier, "")
		terrain_effect_triggered.emit(pid, terrain, "采集%s资源，获得2气" % tier_name)
		cell.is_resource = false
		cell.res_tier = ""

	# Reward pool → grant accumulated energy
	if cell.is_reward:
		var pool_amount: int = _reward_pool.get(pos, 0)
		if pool_amount > 0:
			_energy_mgr.gain(player, pool_amount, EnergyManager.SOURCE_REWARD_POOL)
			terrain_effect_triggered.emit(pid, terrain, "领取悬赏池，获得%d气" % pool_amount)
			_reward_pool[pos] = 0

	# Highland range bonus (temporary while present)
	if terrain == HGWMapGenerator.Terrain.HIGHLAND:
		player.on_highland = true
		terrain_effect_triggered.emit(pid, terrain, "进入高地（攻击距离+1）")
	else:
		player.on_highland = false

# ── Actions ──────────────────────────────────────────────────────────────────────

func submit_gather(player_id: int) -> bool:
	if _current_phase != Phase.ACTION_PHASE:
		return false
	var player := get_player(player_id)
	if player == null or player.player_id != get_current_player().player_id:
		return false
	if player.acted_this_turn:
		return false

	player.acted_this_turn = true
	player.gathered_this_turn = true
	_energy_mgr.gain(player, 1, EnergyManager.SOURCE_GATHER)
	_advance_turn()
	return true

func submit_attack(player_id: int, target_id: int) -> bool:
	if _current_phase != Phase.ACTION_PHASE:
		return false
	var attacker := get_player(player_id)
	var defender := get_player(target_id)
	if attacker == null or defender == null:
		return false
	if attacker.player_id != get_current_player().player_id:
		return false
	if attacker.gathered_this_turn:
		return false
	if attacker.energy < 1:
		return false
	if attacker.acted_this_turn:
		return false

	# Check range
	var dist := maxi(abs(attacker.hex_q - defender.hex_q), maxi(abs(attacker.hex_r - defender.hex_r), abs((attacker.hex_q + attacker.hex_r) - (defender.hex_q + defender.hex_r))))
	if dist > attacker.get_attack_range():
		return false

	# Ensure attacker can afford at least one skill after paying attack cost (1 energy)
	if attacker.character:
		var can_afford_skill := false
		for sk: SkillData in attacker.character.skills:
			if sk.energy_cost <= attacker.energy - 1:
				can_afford_skill = true
				break
		if not can_afford_skill:
			return false

	attacker.acted_this_turn = true
	attacker.attacked_this_turn = true
	_combat_attacker_id = player_id
	_combat_defender_id = target_id
	_combat_mgr.initiate_attack(attacker, defender)
	_enter_phase(Phase.RPS_INPUT)
	return true

func submit_skip_action(player_id: int) -> void:
	if _current_phase != Phase.ACTION_PHASE:
		return
	var player := get_player(player_id)
	if player == null or player.player_id != get_current_player().player_id:
		return
	if player.acted_this_turn:
		return
	player.acted_this_turn = true
	_advance_turn()

# ── RPS ──────────────────────────────────────────────────────────────────────────

func submit_attack_rps(gesture: int) -> void:
	if _current_phase != Phase.RPS_INPUT:
		return
	_rps_attacker_gesture = gesture
	_try_resolve_rps()

func submit_defend_rps(gesture: int) -> void:
	if _current_phase != Phase.RPS_INPUT:
		return
	_rps_defender_gesture = gesture
	_try_resolve_rps()

func _try_resolve_rps() -> void:
	if _rps_attacker_gesture < 0 or _rps_defender_gesture < 0:
		return
	var attacker := get_player(_combat_attacker_id)
	var defender := get_player(_combat_defender_id)
	if attacker == null or defender == null:
		_advance_turn()
		return
	_combat_mgr.submit_rps(_rps_attacker_gesture, _rps_defender_gesture, attacker, defender)

func _setup_rps() -> void:
	_rps_attacker_gesture = -1
	_rps_defender_gesture = -1

	var attacker := get_player(_combat_attacker_id)
	var defender := get_player(_combat_defender_id)

	if attacker and not attacker.is_human:
		get_tree().create_timer(0.8).timeout.connect(
			func(): submit_attack_rps(_rng.randi_range(0, 2)), CONNECT_ONE_SHOT)

	if defender and not defender.is_human:
		get_tree().create_timer(1.0).timeout.connect(
			func(): submit_defend_rps(_rng.randi_range(0, 2)), CONNECT_ONE_SHOT)

func _on_rps_result(attacker_id: int, hit: bool) -> void:
	if hit:
		_enter_phase(Phase.SKILL_SELECT)
		# AI auto-selects skill after a brief delay
		var attacker := get_player(attacker_id)
		if attacker and not attacker.is_human:
			get_tree().create_timer(0.4).timeout.connect(
				func(): _ai_execute_skill_select(attacker), CONNECT_ONE_SHOT)
	else:
		combat_miss.emit(attacker_id)
		_advance_turn()

# ── Skill ────────────────────────────────────────────────────────────────────────

func submit_skill(skill_index: int) -> void:
	if _current_phase != Phase.SKILL_SELECT:
		return
	var attacker := get_player(_combat_attacker_id)
	if attacker == null:
		_advance_turn()
		return
	var skills := attacker.character.skills if attacker.character else []
	if skill_index < 0 or skill_index >= skills.size():
		_advance_turn()
		return
	_combat_pending_skill = skills[skill_index]
	_enter_phase(Phase.SKILL_APPLYING)

func cancel_skill() -> void:
	if _current_phase != Phase.SKILL_SELECT:
		return
	_advance_turn()

func _apply_skill() -> void:
	var attacker := get_player(_combat_attacker_id)
	var defender := get_player(_combat_defender_id)
	if attacker == null or defender == null or _combat_pending_skill == null:
		_advance_turn()
		return

	var pos := Vector2i(defender.hex_q, defender.hex_r)
	var terrain: int = HGWMapGenerator.Terrain.PLAIN
	if _map_cells.has(pos):
		terrain = _map_cells[pos].terrain

	var result := _combat_mgr.resolve_skill(attacker, defender, _combat_pending_skill, terrain)
	_combat_pending_skill = null
	# _on_combat_resolved handles elimination and turn advance

func _on_combat_resolved(log: Dictionary) -> void:
	combat_hit.emit(log)

	# Check elimination
	var def_id: int = log.get("defender_id", -1)
	var defender := get_player(def_id)
	if defender != null and not defender.is_alive:
		_eliminate_player(def_id, "in_combat")

	# Interrupt grail occupation if defender was occupying
	if log.get("final_damage", 0) > 0:
		_grail_mgr.interrupt_if_occupying(def_id)

	_advance_turn()

# ── Seal placement ────────────────────────────────────────────────────────────────

func _place_seals(gen: HGWMapGenerator) -> void:
	var spawns := gen.spawns

	# Seal 1: Boss at a fortress cell away from spawns
	var boss_candidates: Array[Vector2i] = []
	for pos: Vector2i in _map_cells:
		var cell = _map_cells[pos]
		if cell.terrain == HGWMapGenerator.Terrain.FORTRESS and not cell.is_void:
			var too_close := false
			for sp: Vector2i in spawns:
				if _hex_distance(pos.x, pos.y, sp.x, sp.y) < 4:
					too_close = true
					break
			if not too_close:
				boss_candidates.append(pos)
	if not boss_candidates.is_empty():
		_seal_mgr.boss_position = boss_candidates[_rng.randi_range(0, boss_candidates.size() - 1)]

	# Seal 2: Altar at a key cell away from spawns
	var altar_candidates: Array[Vector2i] = []
	for pos: Vector2i in _map_cells:
		var cell = _map_cells[pos]
		if cell.is_key and not cell.is_void:
			var too_close := false
			for sp: Vector2i in spawns:
				if _hex_distance(pos.x, pos.y, sp.x, sp.y) < 3:
					too_close = true
					break
			if not too_close:
				altar_candidates.append(pos)
	if not altar_candidates.is_empty():
		_seal_mgr.altar_position = altar_candidates[_rng.randi_range(0, altar_candidates.size() - 1)]

	# Seal 3: Relic at a passable cell at least 5 hexes from all spawns
	var relic_candidates: Array[Vector2i] = []
	for pos: Vector2i in _map_cells:
		var cell = _map_cells[pos]
		if cell.is_void or cell.terrain == HGWMapGenerator.Terrain.MOUNTAIN:
			continue
		var far_enough := true
		for sp: Vector2i in spawns:
			if _hex_distance(pos.x, pos.y, sp.x, sp.y) < 5:
				far_enough = false
				break
		if far_enough:
			relic_candidates.append(pos)
	if not relic_candidates.is_empty():
		_seal_mgr.relic_position = relic_candidates[_rng.randi_range(0, relic_candidates.size() - 1)]

# ── Seal interactions ────────────────────────────────────────────────────────────

func attack_boss(player_id: int, damage: int) -> Dictionary:
	var player := get_player(player_id)
	if player == null:
		return {}
	var bp := _seal_mgr.boss_position
	if bp == Vector2i(-999, -999):
		return {"error": "boss not placed"}
	var dist := _hex_distance(player.hex_q, player.hex_r, bp.x, bp.y)
	if dist > 1:
		return {"error": "too far from boss (distance %d, need <=1)" % dist}
	var result := _seal_mgr.attack_boss(player, damage)
	if result["killed"]:
		var killer := get_player(result["unlocker_id"])
		if killer:
			killer.has_energy_per_turn_buff = true
	return result

func inject_to_altar(player_id: int, amount: int) -> bool:
	var player := get_player(player_id)
	if player == null:
		return false
	var ap := _seal_mgr.altar_position
	if ap == Vector2i(-999, -999):
		return false
	if player.hex_q != ap.x or player.hex_r != ap.y:
		return false
	return _seal_mgr.inject_energy(player, amount, _energy_mgr)

func enter_ruin(player_id: int) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	_seal_mgr.enter_ruin(player, _map_cells, _rng)

func try_pick_relic(player_id: int) -> bool:
	var player := get_player(player_id)
	if player == null:
		return false
	return _seal_mgr.try_pick_relic(player)

func get_seal_mgr() -> SealManager:
	return _seal_mgr

func _on_seal_unlocked(seal_index: int, unlocker_id: int) -> void:
	var unlocker := get_player(unlocker_id)
	if unlocker == null:
		return

	match seal_index:
		1:
			unlocker.has_energy_per_turn_buff = true
		2:
			unlocker.has_movement_bonus = true
			unlocker.bonus_movement += 2
		3:
			unlocker.has_range_bonus = true
			unlocker.bonus_attack_range += 1

	seal_event.emit(seal_index, "unlocked", {"unlocker_id": unlocker_id})

	# Check all seals unlocked → open grail
	if _seal_mgr.are_all_seals_unlocked() and not _grail_mgr.is_open:
		_grail_mgr.open_grail()
		_shrink_ring.activate(_map_radius)

# ── Turn sequencing ──────────────────────────────────────────────────────────────

func _advance_turn() -> void:
	var finished_player := get_current_player()
	if finished_player != null:
		_grail_mgr.on_player_turn_end(finished_player)
	_current_turn_index += 1
	_next_player_turn()

func _end_turn() -> void:
	# Process delayed damages
	for player in _players:
		if not player.is_alive:
			continue
		var triggered: Array[Dictionary] = []
		for entry in player.delayed_damages:
			entry["trigger_in"] -= 1
			if entry["trigger_in"] <= 0:
				triggered.append(entry)
		for entry in triggered:
			player.delayed_damages.erase(entry)
			_damage_resolver.apply(player, entry["damage"])
			if player.hp <= 0:
				_eliminate_player(player.player_id, "delayed_damage")

	# Shrink ring damage
	if _shrink_ring.active:
		_shrink_ring.apply_ring_damage(_players, _damage_resolver)

	# Re-sync highland bonus (on_highland flag managed via _apply_terrain_enter on each move)
	for player in _players:
		if not player.is_alive:
			continue
		var pos := Vector2i(player.hex_q, player.hex_r)
		if _map_cells.has(pos):
			var cell = _map_cells[pos]
			player.on_highland = (cell.terrain == HGWMapGenerator.Terrain.HIGHLAND)

	# Desert debuff reduces
	for player in _players:
		player.skip_next_action = false

	# Check elimination again
	var alive := get_alive_players()
	if alive.size() <= 1:
		var winner_id := alive[0].player_id if alive.size() == 1 else -1
		_end_game(winner_id, "last_standing")
		return

	_enter_phase(Phase.TURN_START)

func _end_round() -> void:
	_shrink_ring.on_round_end()
	_end_turn()

func _eliminate_player(player_id: int, reason: String) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	player.is_alive = false
	player_eliminated.emit(player_id)

func _end_game(winner_id: int, reason: String) -> void:
	_current_phase = Phase.GAME_OVER
	game_over.emit(winner_id, reason)

# ── AI execution ──────────────────────────────────────────────────────────────────

func _ai_execute_move(player: HGWPlayerState) -> void:
	if _current_phase != Phase.MOVE_PHASE:
		return
	var reachable := get_reachable_cells(player)
	var target_pos := _ai_controller.decide_move(player, reachable, self)
	if target_pos == Vector2i(player.hex_q, player.hex_r) or not reachable.has(target_pos):
		skip_move(player.player_id)
	else:
		submit_move(player.player_id, target_pos.x, target_pos.y)
	get_tree().create_timer(0.3).timeout.connect(
		func(): _ai_execute_action(player), CONNECT_ONE_SHOT)

func _ai_execute_action(player: HGWPlayerState) -> void:
	if _current_phase != Phase.ACTION_PHASE:
		return

	# Try B-class skill first
	var b_skill_idx := _ai_controller.decide_b_skill(player)
	if b_skill_idx >= 0:
		submit_b_skill(player.player_id, b_skill_idx)
		return

	var enemies_in_range: Array[HGWPlayerState] = []
	for other in get_alive_players():
		if other.player_id == player.player_id:
			continue
		var dist := _hex_distance(player.hex_q, player.hex_r, other.hex_q, other.hex_r)
		if dist <= player.get_attack_range():
			enemies_in_range.append(other)

	var decision := _ai_controller.decide_action(player, enemies_in_range, self)
	match decision["type"]:
		"attack":
			submit_attack(player.player_id, decision["target_id"])
		"gather":
			submit_gather(player.player_id)
		"skip":
			submit_skip_action(player.player_id)

func _ai_execute_skill_select(player: HGWPlayerState) -> void:
	if _current_phase != Phase.SKILL_SELECT:
		return
	var skills: Array = player.character.skills if player.character else []
	var idx := _ai_controller.decide_skill(skills, player.energy)
	submit_skill(idx)

# ── B-Class skill ─────────────────────────────────────────────────────────────────

func submit_b_skill(player_id: int, skill_index: int) -> bool:
	if _current_phase != Phase.ACTION_PHASE:
		return false
	var player := get_player(player_id)
	if player == null or player.player_id != get_current_player().player_id:
		return false
	if player.acted_this_turn:
		return false
	var skills: Array = player.character.skills if player.character else []
	if skill_index < 0 or skill_index >= skills.size():
		return false
	var skill: SkillData = skills[skill_index]
	if player.energy < skill.energy_cost:
		return false
	_energy_mgr.spend(player, skill.energy_cost)
	_apply_b_skill_effects(player, skill)
	player.acted_this_turn = true
	_advance_turn()
	return true

func _apply_b_skill_effects(player: HGWPlayerState, skill: SkillData) -> void:
	for effect: SkillEffect in skill.effects:
		match effect.effect_type:
			SkillEffect.EffectType.CLONE_SHIELD:
				player.clone_count += effect.value
			SkillEffect.EffectType.SHIELD:
				player.shield = effect.value
			SkillEffect.EffectType.HEAL:
				player.hp = mini(player.max_hp, player.hp + effect.value)

func _log_seal_pickup(player_id: int, seal_idx: int) -> void:
	var msg := ""
	match seal_idx:
		3: msg = "封印3（遗物）已被拾取！"
		_: msg = "封印%d 事件触发！" % seal_idx
	if msg != "":
		seal_event.emit(seal_idx, "picked_up", {"unlocker_id": player_id})

# ── Helpers ──────────────────────────────────────────────────────────────────────

func get_cell(q: int, r: int):
	return _map_cells.get(Vector2i(q, r), null)

func get_map_cells() -> Dictionary:
	return _map_cells

func get_all_players() -> Array[HGWPlayerState]:
	return _players

func get_map_radius() -> int:
	return _map_radius

func get_phase() -> Phase:
	return _current_phase

func get_current_turn_player_id() -> int:
	var p := get_current_player()
	return p.player_id if p else -1

func _hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	return maxi(abs(q1 - q2), maxi(abs(r1 - r2), abs((q1 + r1) - (q2 + r2))))
