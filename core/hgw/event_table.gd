## EventTable — desert d100 random events + snow slide direction
class_name EventTable
extends RefCounted

enum DesertEvent { DUST_STORM, OASIS, RELIC, LOST }

# Pointy-top hex 6-direction offsets
const HEX_DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func roll_desert_event(rng: RandomNumberGenerator) -> DesertEvent:
	var roll := rng.randi_range(1, 100)
	if roll <= 25:
		return DesertEvent.DUST_STORM
	elif roll <= 50:
		return DesertEvent.OASIS
	elif roll <= 75:
		return DesertEvent.RELIC
	return DesertEvent.LOST

static func apply_desert_event(player: HGWPlayerState, event: DesertEvent, energy_mgr: EnergyManager, map_cells: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	match event:
		DesertEvent.DUST_STORM:
			player.skip_next_action = true
			return {"event": "dust_storm", "effect": "skip_next_action"}
		DesertEvent.OASIS:
			player.hp = mini(player.max_hp, player.hp + 1)
			return {"event": "oasis", "effect": "heal_1", "hp_after": player.hp}
		DesertEvent.RELIC:
			energy_mgr.gain(player, 1, EnergyManager.SOURCE_DESERT_EVENT)
			return {"event": "relic", "effect": "energy_+1"}
		DesertEvent.LOST:
			var target := _random_land_cell(map_cells, rng)
			var old_q := player.hex_q
			var old_r := player.hex_r
			player.hex_q = target.x
			player.hex_r = target.y
			return {"event": "lost", "effect": "teleport", "from": [old_q, old_r], "to": [target.x, target.y]}
	return {}

static func roll_snow_slide(from_q: int, from_r: int, map_cells: Dictionary, occupied: Array[Vector2i], rng: RandomNumberGenerator) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for dir: Vector2i in HEX_DIRS:
		var tq := from_q + dir.x
		var tr := from_r + dir.y
		var key := Vector2i(tq, tr)
		if not map_cells.has(key):
			continue
		var cell = map_cells[key]
		if cell.is_void:
			continue
		var blocked := false
		for occ: Vector2i in occupied:
			if occ.x == tq and occ.y == tr:
				blocked = true
				break
		if not blocked:
			candidates.append(key)
	if candidates.is_empty():
		return Vector2i(from_q, from_r)
	var idx := rng.randi_range(0, candidates.size() - 1)
	return candidates[idx]

static func _random_land_cell(map_cells: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var land: Array[Vector2i] = []
	for pos: Vector2i in map_cells:
		var cell = map_cells[pos]
		if not cell.is_void:
			land.append(pos)
	if land.is_empty():
		return Vector2i(0, 0)
	return land[rng.randi_range(0, land.size() - 1)]
