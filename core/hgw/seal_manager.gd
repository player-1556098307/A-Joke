## SealManager — three seals state, unlock triggers & reward distribution
class_name SealManager
extends RefCounted

signal seal_unlocked(seal_index: int, unlocker_id: int)

# ── Seal 1: Boss (Monster) ──────────────────────────────────────────────────────
var boss_position: Vector2i = Vector2i(-999, -999)
var boss_hp: int = 20
var boss_damage_log: Dictionary = {}
var seal1_unlocked: bool = false

# ── Seal 2: Altar ───────────────────────────────────────────────────────────────
var altar_position: Vector2i = Vector2i(-999, -999)
var altar_required_energy: int = 10
var altar_progress: Dictionary = {}
var altar_first_injector_id: int = -1
var seal2_unlocked: bool = false
var seal2_winner_id: int = -1

# ── Seal 3: Relic in Ruins ───────────────────────────────────────────────────────
var relic_position: Vector2i = Vector2i(-999, -999)
var relic_known_to: Array[int] = []
var relic_picked_up_by: int = -1
var seal3_unlocked: bool = false

func are_all_seals_unlocked() -> bool:
	return seal1_unlocked and seal2_unlocked and seal3_unlocked

# ── Seal 1 ───────────────────────────────────────────────────────────────────────

func attack_boss(attacker: HGWPlayerState, damage: int) -> Dictionary:
	boss_hp = maxi(0, boss_hp - damage)
	boss_damage_log[attacker.player_id] = boss_damage_log.get(attacker.player_id, 0) + damage
	var killed := (boss_hp <= 0)
	if killed:
		seal1_unlocked = true
		seal_unlocked.emit(1, attacker.player_id)
	return {"boss_hp_remaining": boss_hp, "killed": killed, "unlocker_id": attacker.player_id if killed else -1}

func get_boss_killer_id() -> int:
	for pid in boss_damage_log:
		if boss_damage_log[pid] > 0:
			return pid
	return -1

# ── Seal 2 ───────────────────────────────────────────────────────────────────────

func inject_energy(player: HGWPlayerState, amount: int, energy_mgr: EnergyManager) -> bool:
	if not energy_mgr.spend(player, amount):
		return false
	if altar_first_injector_id < 0:
		altar_first_injector_id = player.player_id
	altar_progress[player.player_id] = altar_progress.get(player.player_id, 0) + amount
	var total := 0
	for pid in altar_progress:
		total += altar_progress[pid]
	if total >= altar_required_energy and not seal2_unlocked:
		seal2_unlocked = true
		seal2_winner_id = altar_first_injector_id
		seal_unlocked.emit(2, seal2_winner_id)
		return true
	return false

# ── Seal 3 ───────────────────────────────────────────────────────────────────────

func enter_ruin(player: HGWPlayerState, map_cells: Dictionary, rng: RandomNumberGenerator) -> void:
	if relic_position != Vector2i(-999, -999):
		if not relic_known_to.has(player.player_id):
			relic_known_to.append(player.player_id)
		return

	var land_cells: Array[Vector2i] = []
	for pos: Vector2i in map_cells:
		var cell = map_cells[pos]
		if not cell.is_void:
			var dist := maxi(abs(pos.x - player.hex_q), maxi(abs(pos.y - player.hex_r), abs((pos.x + pos.y) - (player.hex_q + player.hex_r))))
			if dist >= 3:
				land_cells.append(pos)
	if land_cells.is_empty():
		relic_position = Vector2i(5, 0)
	else:
		relic_position = land_cells[rng.randi_range(0, land_cells.size() - 1)]
	relic_known_to.append(player.player_id)

func try_pick_relic(player: HGWPlayerState) -> bool:
	if relic_picked_up_by >= 0:
		return false
	if player.hex_q == relic_position.x and player.hex_r == relic_position.y:
		relic_picked_up_by = player.player_id
		seal3_unlocked = true
		seal_unlocked.emit(3, player.player_id)
		return true
	return false
