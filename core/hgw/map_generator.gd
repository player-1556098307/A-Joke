## HGW Map Generator — 8-player shrinking-ring battle map
## Single continent, dual-field biome model, deterministic fix passes, scale-aware noise
class_name HGWMapGenerator
extends RefCounted

enum Terrain { VOID, PLAIN, FOREST, HIGHLAND, MOUNTAIN, FORTRESS, GRAIL, DESERT, SNOW }

const PLAYERS_TO_RADIUS := { 3: 8, 4: 10, 5: 12, 6: 14, 7: 16, 8: 18 }

# ── Tweakable parameters ──────────────────────────────────────────────────────

var LAND_THRESHOLD    := 0.38
var EDGE_DETAIL_AMP   := 0.08
var ELEVATION_FREQ    := 0.10
var MOISTURE_FREQ     := 0.12
var ELEVATION_LOW     := 0.22
var ELEVATION_MID     := 0.38
var ELEVATION_HIGH    := 0.58
var MOISTURE_FOREST   := 0.42
var FORTRESS_COUNT    := 6
var WARP_STRENGTH     := 0.42
var WARP_FREQ         := 0.18
var CA_PASSES         := 2

# ── Cell ──────────────────────────────────────────────────────────────────────

class Cell:
	var q: int
	var r: int
	var land_val: float = 0.0
	var elevation: float = 0.0
	var moisture: float = 0.0
	var temperature: float = 0.5
	var terrain: int = Terrain.PLAIN
	var is_void: bool = false
	var is_grail: bool = false
	var is_city: bool = false
	var is_key: bool = false
	var is_resource: bool = false
	var is_reward: bool = false
	var is_choke: bool = false
	var res_tier: String = ""

	func _init(pq: int, pr: int) -> void:
		q = pq
		r = pr

# ── Generator state ───────────────────────────────────────────────────────────

var game_radius: int
var radius: int
var base_seed: int
var num_players: int
var rng: RandomNumberGenerator
var cells: Dictionary = {}
var spawns: Array[Vector2i] = []
var stats: Dictionary = {}

var noise_continent: FastNoiseLite
var noise_coast: FastNoiseLite
var noise_elevation: FastNoiseLite
var noise_moisture: FastNoiseLite
var noise_warp_x: FastNoiseLite
var noise_warp_y: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_angle: FastNoiseLite

func _init(p_radius: int, p_seed: int, p_num_players: int = 4) -> void:
	game_radius = p_radius
	radius = p_radius + 2
	base_seed = p_seed
	num_players = p_num_players
	rng = RandomNumberGenerator.new()
	_init_noise()

# ── Noise init (scale-aware frequencies) ─────────────────────────────────────

func _init_noise() -> void:
	# Reference radius for frequency calibration — all frequencies tuned at R=10
	var scale: float = 10.0 / float(game_radius)

	noise_continent = FastNoiseLite.new()
	noise_continent.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_continent.frequency = 0.075 * scale
	noise_continent.fractal_octaves = 4
	noise_continent.fractal_lacunarity = 2.0
	noise_continent.fractal_gain = 0.5

	noise_coast = FastNoiseLite.new()
	noise_coast.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_coast.frequency = 0.09 * scale
	noise_coast.fractal_octaves = 2
	noise_coast.fractal_lacunarity = 2.0
	noise_coast.fractal_gain = 0.5

	noise_elevation = FastNoiseLite.new()
	noise_elevation.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_elevation.frequency = ELEVATION_FREQ * scale
	noise_elevation.fractal_octaves = 4
	noise_elevation.fractal_lacunarity = 2.0
	noise_elevation.fractal_gain = 0.5

	noise_moisture = FastNoiseLite.new()
	noise_moisture.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_moisture.frequency = MOISTURE_FREQ * scale
	noise_moisture.fractal_octaves = 3
	noise_moisture.fractal_lacunarity = 2.0
	noise_moisture.fractal_gain = 0.5

	noise_warp_x = FastNoiseLite.new()
	noise_warp_x.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_warp_x.frequency = 0.20 * scale
	noise_warp_x.fractal_octaves = 2
	noise_warp_x.fractal_lacunarity = 2.0
	noise_warp_x.fractal_gain = 0.5

	noise_warp_y = FastNoiseLite.new()
	noise_warp_y.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_warp_y.frequency = 0.20 * scale
	noise_warp_y.fractal_octaves = 2
	noise_warp_y.fractal_lacunarity = 2.0
	noise_warp_y.fractal_gain = 0.5

	noise_temperature = FastNoiseLite.new()
	noise_temperature.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_temperature.frequency = 0.08
	noise_temperature.fractal_octaves = 2
	noise_temperature.fractal_lacunarity = 2.0
	noise_temperature.fractal_gain = 0.5

	noise_angle = FastNoiseLite.new()
	noise_angle.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_angle.frequency = 0.8
	noise_angle.fractal_octaves = 2
	noise_angle.fractal_lacunarity = 2.0
	noise_angle.fractal_gain = 0.5
# ── Hex grid ──────────────────────────────────────────────────────────────────

static func hex_distance(q1: int, r1: int, q2: int, r2: int) -> int:
	return (abs(q1 - q2) + abs(q1 + r1 - q2 - r2) + abs(r1 - r2)) / 2

static func hex_neighbors(q: int, r: int) -> Array[Vector2i]:
	return [
		Vector2i(q + 1, r),
		Vector2i(q + 1, r - 1),
		Vector2i(q, r - 1),
		Vector2i(q - 1, r),
		Vector2i(q - 1, r + 1),
		Vector2i(q, r + 1),
	]

func make_grid() -> void:
	cells.clear()
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			cells[Vector2i(q, r)] = Cell.new(q, r)

# ── Land shape ────────────────────────────────────────────────────────────────

func generate_land_shape(seed_val: int) -> void:
	noise_continent.seed = seed_val
	noise_warp_x.seed    = seed_val + 11111
	noise_warp_y.seed    = seed_val + 22222
	noise_coast.seed     = seed_val + 33333
	noise_angle.seed    = seed_val + 44444

	# Warp amplitude scales with map size but with diminishing returns for very large maps
	var warp_amp: float = float(game_radius) * WARP_STRENGTH * clampf(10.0 / float(game_radius), 0.6, 1.4)

	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		var fq: float = float(cell.q)
		var fr: float = float(cell.r)
		var dist: int = hex_distance(cell.q, cell.r, 0, 0)
		var dist_norm: float = clampf(float(dist) / float(game_radius), 0.0, 1.0)

		if dist > game_radius + 1:
			cell.terrain = Terrain.VOID
			cell.is_void = true
			cell.land_val = 0.0
			continue

		var wx: float = noise_warp_x.get_noise_2d(fq * WARP_FREQ, fr * WARP_FREQ) * warp_amp
		var wy: float = noise_warp_y.get_noise_2d(fq * WARP_FREQ + 97.3, fr * WARP_FREQ + 97.3) * warp_amp

		var continent_val: float = (noise_continent.get_noise_2d(fq + wx, fr + wy) + 1.0) / 2.0
		var detail: float = noise_coast.get_noise_2d(fq * 0.28, fr * 0.28) * EDGE_DETAIL_AMP

		# Angle-driven irregular mask for realistic island shape
		var angle: float = atan2(fr, fq)
		var angle_reach: float = 1.0 + noise_angle.get_noise_1d(angle * 2.0) * 0.35
		var coast_jag: float = noise_angle.get_noise_1d(angle * 8.0 + 17.3) * 0.12
		var effective_radius: float = dist_norm / (angle_reach + coast_jag)
		var radial_mask: float = clampf(1.0 - effective_radius * effective_radius, 0.0, 1.0)

		cell.land_val = clampf(continent_val * radial_mask + detail * (1.0 - dist_norm * 0.6), 0.0, 1.0)

		if cell.land_val < LAND_THRESHOLD:
			cell.terrain = Terrain.VOID
			cell.is_void = true

	# Force center to land
	var center_cell: Cell = cells[Vector2i(0, 0)]
	center_cell.land_val = 1.0
	center_cell.is_void = false

	# Remove fully isolated land cells (no land neighbors)
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void:
			continue
		var land_nbs: int = 0
		for nb: Vector2i in hex_neighbors(cell.q, cell.r):
			if cells.has(nb) and not (cells[nb] as Cell).is_void:
				land_nbs += 1
		if land_nbs == 0:
			cell.terrain = Terrain.VOID
			cell.is_void = true

# ── Connectivity repair ───────────────────────────────────────────────────────

func _flood_fill(start: Vector2i) -> Dictionary:
	var visited: Dictionary = {}
	if not cells.has(start) or (cells[start] as Cell).is_void:
		return visited
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for nb: Vector2i in hex_neighbors(cur.x, cur.y):
			if cells.has(nb) and not visited.has(nb) and not (cells[nb] as Cell).is_void:
				visited[nb] = true
				queue.append(nb)
	return visited

func _get_border_cells(comp: Dictionary) -> Array[Vector2i]:
	# Only cells adjacent to void — avoids O(N²) bridge search on full component
	var border: Array[Vector2i] = []
	for pos: Vector2i in comp:
		for nb: Vector2i in hex_neighbors(pos.x, pos.y):
			if not comp.has(nb):
				border.append(pos)
				break
	return border

func _repair_connectivity() -> void:
	var center := Vector2i(0, 0)
	if not cells.has(center) or (cells[center] as Cell).is_void:
		return

	var main_comp := _flood_fill(center)

	var disconnected: Array[Vector2i] = []
	for pos: Vector2i in cells:
		if not (cells[pos] as Cell).is_void and not main_comp.has(pos):
			disconnected.append(pos)

	if disconnected.is_empty():
		return

	var dc_visited: Dictionary = {}
	var clusters: Array[Array] = []
	for pos: Vector2i in disconnected:
		if dc_visited.has(pos):
			continue
		var cluster: Array[Vector2i] = []
		var queue: Array[Vector2i] = [pos]
		dc_visited[pos] = true
		while not queue.is_empty():
			var cur: Vector2i = queue.pop_front()
			cluster.append(cur)
			for nb: Vector2i in hex_neighbors(cur.x, cur.y):
				if cells.has(nb) and not dc_visited.has(nb) and not (cells[nb] as Cell).is_void and not main_comp.has(nb):
					dc_visited[nb] = true
					queue.append(nb)
		clusters.append(cluster)

	for cluster: Array in clusters:
		var best_score := 1e9
		var best_path: Array[Vector2i] = []
		var main_border := _get_border_cells(main_comp)

		for c_pos: Vector2i in cluster:
			for m_pos: Vector2i in main_border:
				var path := _hex_line(c_pos, m_pos)
				var score := 0.0
				var valid := true
				for p: Vector2i in path:
					if not cells.has(p):
						valid = false
						break
					if (cells[p] as Cell).is_void:
						score += 1.0 - (cells[p] as Cell).land_val + 0.3
				if not valid:
					continue
				if score < best_score:
					best_score = score
					best_path = path

		for p: Vector2i in best_path:
			var pcell: Cell = cells[p]
			if pcell.is_void:
				pcell.terrain = Terrain.PLAIN
				pcell.is_void = false
				pcell.land_val = LAND_THRESHOLD + 0.01

		main_comp = _flood_fill(center)

func _hex_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var n: int = hex_distance(a.x, a.y, b.x, b.y)
	for i in range(n + 1):
		var t: float = float(i) / float(max(n, 1))
		var a_q := float(a.x)
		var a_r := float(a.y)
		var a_s := -a_q - a_r
		var b_q := float(b.x)
		var b_r := float(b.y)
		var b_s := -b_q - b_r
		var cq := a_q + (b_q - a_q) * t
		var cr := a_r + (b_r - a_r) * t
		var cs := a_s + (b_s - a_s) * t
		var rq := roundi(cq)
		var rr := roundi(cr)
		var rs := roundi(cs)
		var q_diff: float = abs(rq - cq)
		var r_diff: float = abs(rr - cr)
		var s_diff: float = abs(rs - cs)
		if q_diff > r_diff and q_diff > s_diff:
			rq = -rr - rs
		elif r_diff > s_diff:
			rr = -rq - rs
		result.append(Vector2i(rq, rr))
	return result

# ── Terrain assignment ────────────────────────────────────────────────────────

func _smooth_field(field_name: String, iterations: int = 2) -> void:
	for _iter in range(iterations):
		var new_vals: Dictionary = {}
		for pos: Vector2i in cells:
			var cell: Cell = cells[pos]
			if cell.is_void:
				continue
			var s := 0.0
			var n := 0
			for nb: Vector2i in hex_neighbors(cell.q, cell.r):
				if cells.has(nb) and not (cells[nb] as Cell).is_void:
					s += (cells[nb] as Cell).get(field_name)
					n += 1
			if n > 0:
				new_vals[pos] = cell.get(field_name) * 0.55 + (s / float(n)) * 0.45
			else:
				new_vals[pos] = cell.get(field_name)
		for pos: Vector2i in new_vals:
			(cells[pos] as Cell).set(field_name, new_vals[pos])

func _classify_biome(elevation: float, moisture: float, temperature: float) -> int:
	var temp_bias: float = (temperature - 0.5) * 0.12
	var eff_elev: float = elevation - temp_bias

	if eff_elev >= ELEVATION_HIGH:
		return Terrain.SNOW if temperature < 0.50 else Terrain.MOUNTAIN

	if eff_elev >= ELEVATION_MID:
		if temperature < 0.35:
			return Terrain.SNOW
		return Terrain.HIGHLAND

	if eff_elev >= ELEVATION_LOW:
		if temperature > 0.65 and moisture < 0.45:
			return Terrain.DESERT
		if moisture > MOISTURE_FOREST:
			return Terrain.FOREST
		return Terrain.PLAIN

	if temperature > 0.70 and moisture < 0.38:
		return Terrain.DESERT
	if temperature < 0.28:
		return Terrain.SNOW
	if moisture > MOISTURE_FOREST:
		return Terrain.FOREST
	return Terrain.PLAIN

func _cellular_automaton_cleanup() -> void:
	var exempt: Array[int] = [Terrain.FORTRESS, Terrain.GRAIL]
	for _pass in range(CA_PASSES):
		var changes: Dictionary = {}
		for pos: Vector2i in cells:
			var cell: Cell = cells[pos]
			if cell.is_void or cell.terrain in exempt:
				continue
			var type_counts: Dictionary = {}
			for nb: Vector2i in hex_neighbors(cell.q, cell.r):
				if cells.has(nb) and not (cells[nb] as Cell).is_void:
					var nt: int = (cells[nb] as Cell).terrain
					type_counts[nt] = type_counts.get(nt, 0) + 1
			var my_count: int = type_counts.get(cell.terrain, 0)
			if my_count == 0:
				var best_t: int = cell.terrain
				var best_c: int = 0
				for t: int in type_counts:
					if type_counts[t] > best_c:
						best_c = type_counts[t]
						best_t = t
				if best_c > my_count:
					changes[pos] = best_t
		for pos: Vector2i in changes:
			(cells[pos] as Cell).terrain = changes[pos]

func _place_fortresses() -> void:
	var candidates: Array[Vector2i] = []
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void:
			continue
		# Fortresses appear on highlands/mountains, distributed across the map
		if cell.elevation > 0.60 and cell.terrain in [Terrain.HIGHLAND, Terrain.MOUNTAIN]:
			candidates.append(pos)

	if candidates.is_empty():
		return

	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (cells[a] as Cell).elevation > (cells[b] as Cell).elevation)

	# Min spacing scales with map radius so fortresses spread out on larger maps
	var min_spacing: int = max(3, game_radius / 4)
	var placed: Array[Vector2i] = []
	for pos: Vector2i in candidates:
		if placed.size() >= FORTRESS_COUNT:
			break
		var too_close := false
		for p: Vector2i in placed:
			if hex_distance(pos.x, pos.y, p.x, p.y) < min_spacing:
				too_close = true
				break
		if not too_close:
			placed.append(pos)
			(cells[pos] as Cell).terrain = Terrain.FORTRESS

func _fill_small_void_pockets() -> void:
	# Convert tiny isolated void pockets (≤2 cells) surrounded by land into plain
	var void_set: Array[Vector2i] = []
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void and cell.terrain == Terrain.VOID:
			void_set.append(pos)

	var visited: Dictionary = {}
	for pos: Vector2i in void_set:
		if visited.has(pos):
			continue
		var cluster: Array[Vector2i] = []
		var stack: Array[Vector2i] = [pos]
		visited[pos] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			cluster.append(cur)
			for nb: Vector2i in hex_neighbors(cur.x, cur.y):
				if cells.has(nb) and not visited.has(nb):
					var nb_cell: Cell = cells[nb]
					if nb_cell.is_void and nb_cell.terrain == Terrain.VOID:
						visited[nb] = true
						stack.append(nb)
		if cluster.size() <= 2:
			for p: Vector2i in cluster:
				var c: Cell = cells[p]
				c.terrain = Terrain.PLAIN
				c.is_void = false
				c.land_val = LAND_THRESHOLD + 0.01


func _add_beach_fringe() -> void:
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void or cell.terrain == Terrain.GRAIL:
			continue
		var has_void_nb := false
		for nb: Vector2i in hex_neighbors(cell.q, cell.r):
			if not cells.has(nb) or (cells[nb] as Cell).is_void:
				has_void_nb = true
				break
		if has_void_nb and cell.terrain in [Terrain.PLAIN, Terrain.HIGHLAND]:
			cell.terrain = Terrain.DESERT

func assign_terrain(seed_val: int) -> void:
	noise_elevation.seed   = seed_val + 55555
	noise_moisture.seed    = seed_val + 77777
	noise_temperature.seed = seed_val + 99999

	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void:
			continue
		cell.elevation   = (noise_elevation.get_noise_2d(cell.q, cell.r)   + 1.0) / 2.0
		# Distance bias: interior higher, coast lower — simulates real island topography
		var d_norm: float = clampf(float(hex_distance(cell.q, cell.r, 0, 0)) / float(game_radius), 0.0, 1.0)
		cell.elevation = cell.elevation * (1.0 - d_norm * 0.5)
		cell.moisture    = (noise_moisture.get_noise_2d(cell.q, cell.r)    + 1.0) / 2.0
		cell.temperature = (noise_temperature.get_noise_2d(cell.q, cell.r) + 1.0) / 2.0

	# More smoothing passes on larger maps for better biome coherence
	_smooth_field("elevation", 2)
	_smooth_field("moisture", 1)
	_smooth_field("temperature", 1)

	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.is_void:
			continue
		cell.terrain = _classify_biome(cell.elevation, cell.moisture, cell.temperature)

	_fill_small_void_pockets()
	_place_fortresses()
	_add_beach_fringe()
	_cellular_automaton_cleanup()

# ── Spawn placement ───────────────────────────────────────────────────────────

func _passable_or_mild(pos: Vector2i) -> bool:
	if not cells.has(pos):
		return false
	var cell: Cell = cells[pos]
	return not cell.is_void and cell.terrain != Terrain.MOUNTAIN

func _is_passable(pos: Vector2i) -> bool:
	if not cells.has(pos):
		return false
	var t: int = (cells[pos] as Cell).terrain
	return t != Terrain.VOID and t != Terrain.MOUNTAIN

func _sector_of(pos: Vector2i) -> int:
	var angle: float = atan2(float(pos.y) * 0.86602540378, float(pos.x) + float(pos.y) * 0.5)
	if angle < 0.0:
		angle += 2.0 * PI
	return int(angle / (2.0 * PI) * num_players) % num_players

func place_spawns() -> void:
	# Spawn ring: between 65% and 85% of game_radius from center
	var inner_min: float = float(game_radius) * 0.65
	var inner_max: float = float(game_radius) * 0.85

	var sectors: Array[Array] = []
	for _i in range(num_players):
		sectors.append([])

	for pos: Vector2i in cells:
		if not _passable_or_mild(pos):
			continue
		var d: int = hex_distance(pos.x, pos.y, 0, 0)
		if float(d) < inner_min or float(d) > inner_max:
			continue
		sectors[_sector_of(pos)].append(pos)

	spawns.clear()

	var _score: Callable = func(pos: Vector2i) -> float:
		# Passable neighbors
		var pass_nb := 0
		for nb: Vector2i in hex_neighbors(pos.x, pos.y):
			if cells.has(nb) and _passable_or_mild(nb):
				pass_nb += 1
		# Nearby resource terrain
		var res_nb := 0
		for nb: Vector2i in hex_neighbors(pos.x, pos.y):
			if cells.has(nb):
				var t: int = (cells[nb] as Cell).terrain
				if t == Terrain.FOREST or t == Terrain.HIGHLAND or t == Terrain.PLAIN:
					res_nb += 1
		# Prefer mid-range of the spawn band
		var ideal: float = float(game_radius) * 0.72
		var d_center: float = float(hex_distance(pos.x, pos.y, 0, 0))
		var dist_score: float = max(0.0, 1.0 - abs(d_center - ideal) / (ideal * 0.3))
		return (pass_nb / 6.0) * 0.4 + min(res_nb / 4.0, 1.0) * 0.3 + dist_score * 0.3

	for sector: Array in sectors:
		if sector.is_empty():
			continue
		var best: Vector2i = sector[0]
		var best_score := -1.0
		for pos: Vector2i in sector:
			var s: float = _score.call(pos)
			if s > best_score:
				best_score = s
				best = pos
		(cells[best] as Cell).is_city = true
		spawns.append(best)

# ── Fix: spawn count ──────────────────────────────────────────────────────────

func _fix_spawn_count() -> void:
	if spawns.size() >= num_players:
		return

	var occupied_sectors: Array[int] = []
	for sp: Vector2i in spawns:
		occupied_sectors.append(_sector_of(sp))

	for si in range(num_players):
		if spawns.size() >= num_players:
			break
		if si in occupied_sectors:
			continue
		# Pick deepest passable cell in the missing sector
		var best: Vector2i = Vector2i(0, 0)
		var best_d: int = -1
		for pos: Vector2i in cells:
			if not _passable_or_mild(pos):
				continue
			if _sector_of(pos) != si:
				continue
			var d: int = hex_distance(pos.x, pos.y, 0, 0)
			if d > best_d:
				best_d = d
				best = pos
		if best_d >= 0:
			(cells[best] as Cell).is_city = true
			spawns.append(best)

# ── Fix: spawn radius balance ─────────────────────────────────────────────────

func _fix_spawn_radius() -> void:
	# Tolerance scales with map size
	var tolerance: int = max(2, game_radius / 6)

	for _iter in range(4):
		var dists: Array[int] = []
		for sp: Vector2i in spawns:
			dists.append(hex_distance(sp.x, sp.y, 0, 0))

		if (dists.max() as int) - (dists.min() as int) <= tolerance:
			return

		var avg := 0.0
		for d: int in dists:
			avg += float(d)
		avg /= float(dists.size())

		# Find most deviant spawn
		var worst_idx: int = 0
		var worst_dev: float = 0.0
		for i: int in range(spawns.size()):
			var dev: float = abs(float(dists[i] as int) - avg)
			if dev > worst_dev:
				worst_dev = dev
				worst_idx = i

		var old_sp: Vector2i = spawns[worst_idx]
		var sector: int = _sector_of(old_sp)

		# Find best replacement in same sector closer to avg distance
		var best: Vector2i = old_sp
		var best_dev: float = worst_dev
		for pos: Vector2i in cells:
			if not _passable_or_mild(pos):
				continue
			if _sector_of(pos) != sector:
				continue
			var d: int = hex_distance(pos.x, pos.y, 0, 0)
			if float(d) < float(game_radius) * 0.50:
				continue
			var dev: float = abs(float(d) - avg)
			if dev < best_dev:
				best_dev = dev
				best = pos

		if best != old_sp:
			(cells[old_sp] as Cell).is_city = false
			(cells[best] as Cell).is_city = true
			spawns[worst_idx] = best

# ── Spawn connectivity ────────────────────────────────────────────────────────

func _bfs_spawn_reachable(spawn: Vector2i) -> bool:
	var center := Vector2i(0, 0)
	var visited: Dictionary = {spawn: true}
	var queue: Array[Vector2i] = [spawn]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == center:
			return true
		for nb: Vector2i in hex_neighbors(cur.x, cur.y):
			if cells.has(nb) and not visited.has(nb) and _is_passable(nb):
				visited[nb] = true
				queue.append(nb)
	return false

func _carve_path_to_center(start: Vector2i) -> void:
	var center := Vector2i(0, 0)
	var dist: Dictionary = {start: 0.0}
	var prev: Dictionary = {}
	var heap := _MinHeap.new()
	heap.push(start, 0.0)
	while not heap.is_empty():
		var cost: float = heap.min_priority()
		var pos: Vector2i = heap.pop()
		if cost > dist.get(pos, 1e9):
			continue
		if pos == center:
			break
		for nb: Vector2i in hex_neighbors(pos.x, pos.y):
			if not cells.has(nb):
				continue
			var move_cost: float = 0.0 if _is_passable(nb) else 3.0
			var nc: float = cost + move_cost
			if nc < dist.get(nb, 1e9):
				dist[nb] = nc
				prev[nb] = pos
				heap.push(nb, nc)

	var cur: Vector2i = center
	while prev.has(cur):
		var cell: Cell = cells[cur]
		if cell.terrain in [Terrain.MOUNTAIN, Terrain.VOID]:
			cell.terrain = Terrain.PLAIN
			cell.is_void = false
		cur = prev[cur]

func _fix_spawn_connectivity() -> void:
	for spawn: Vector2i in spawns:
		if not _bfs_spawn_reachable(spawn):
			_carve_path_to_center(spawn)

# ── Resource placement ────────────────────────────────────────────────────────

func place_resources() -> void:
	var local_radius: int = max(3, game_radius / 5)

	var all_pass: Array[Vector2i] = []
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if _passable_or_mild(pos) and not cell.is_grail and not cell.is_city:
			all_pass.append(pos)

	# Common resources: 3 per player near their spawn, in outer ring
	var sectors: Array[Array] = []
	for _i in range(num_players):
		sectors.append([])
	for pos: Vector2i in all_pass:
		sectors[_sector_of(pos)].append(pos)

	for si in range(sectors.size()):
		var sector: Array = sectors[si]
		var outer: Array[Vector2i] = []
		for p: Vector2i in sector:
			if float(hex_distance(p.x, p.y, 0, 0)) > float(game_radius) * 0.4 and not (cells[p] as Cell).is_resource:
				outer.append(p)
		var sp: Vector2i = spawns[si] if si < spawns.size() else Vector2i(0, 0)
		outer.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return hex_distance(a.x, a.y, sp.x, sp.y) < hex_distance(b.x, b.y, sp.x, sp.y))
		for i in range(min(3, outer.size())):
			var cell: Cell = cells[outer[i]]
			cell.is_resource = true
			cell.res_tier = "common"

	# Rare resources: mid-ring, one per player
	var mid: Array[Vector2i] = []
	for p: Vector2i in all_pass:
		if (cells[p] as Cell).is_resource:
			continue
		var d: int = hex_distance(p.x, p.y, 0, 0)
		if float(d) >= float(game_radius) * 0.3 and float(d) <= float(game_radius) * 0.60:
			mid.append(p)
	_shuffle_vec2i(mid)
	for i in range(min(num_players, mid.size())):
		var cell: Cell = cells[mid[i]]
		cell.is_resource = true
		cell.res_tier = "rare"

	# Core resources: inner ring near center, contested during endgame
	var inner: Array[Vector2i] = []
	for p: Vector2i in all_pass:
		if (cells[p] as Cell).is_resource:
			continue
		if float(hex_distance(p.x, p.y, 0, 0)) <= float(game_radius) * 0.28:
			inner.append(p)
	_shuffle_vec2i(inner)
	for i in range(min(num_players, inner.size())):
		var cell: Cell = cells[inner[i]]
		cell.is_resource = true
		cell.res_tier = "core"

	# Reward pools in forest/highland
	var reward: Array[Vector2i] = []
	for pos: Vector2i in cells:
		var cell: Cell = cells[pos]
		if cell.terrain in [Terrain.FOREST, Terrain.HIGHLAND] and not cell.is_resource and not cell.is_city:
			reward.append(pos)
	_shuffle_vec2i(reward)
	var reward_count: int = rng.randi_range(num_players / 2, num_players)
	for i in range(min(reward_count, reward.size())):
		(cells[reward[i]] as Cell).is_reward = true

	# Keys scattered across passable land
	var keys: Array[Vector2i] = []
	for p: Vector2i in all_pass:
		if (cells[p] as Cell).is_resource or (cells[p] as Cell).is_city:
			continue
		if hex_distance(p.x, p.y, 0, 0) >= 2:
			keys.append(p)
	_shuffle_vec2i(keys)
	var key_count: int = max(3, num_players / 2)
	for i in range(min(key_count, keys.size())):
		(cells[keys[i]] as Cell).is_key = true

# ── Fix: resource balance ─────────────────────────────────────────────────────

func _fix_resource_balance() -> void:
	var local_radius: int = max(3, game_radius / 5)

	for _iter in range(5):
		var local: Array[int] = []
		for sp: Vector2i in spawns:
			var cnt: int = 0
			for pos: Vector2i in cells:
				if (cells[pos] as Cell).is_resource and hex_distance(pos.x, pos.y, sp.x, sp.y) <= local_radius:
					cnt += 1
			local.append(cnt)

		if (local.max() as int) - (local.min() as int) <= 2:
			return

		var rich_idx: int = 0
		var poor_idx: int = 0
		for i: int in range(local.size()):
			if (local[i] as int) > (local[rich_idx] as int):
				rich_idx = i
			if (local[i] as int) < (local[poor_idx] as int):
				poor_idx = i

		var rich_sp: Vector2i = spawns[rich_idx]
		var poor_sp: Vector2i = spawns[poor_idx]

		# Move the resource furthest from the rich spawn
		var move_from: Vector2i = Vector2i(-999, -999)
		var max_dist: int = -1
		for pos: Vector2i in cells:
			if not (cells[pos] as Cell).is_resource:
				continue
			var d: int = hex_distance(pos.x, pos.y, rich_sp.x, rich_sp.y)
			if d <= local_radius and d > max_dist:
				max_dist = d
				move_from = pos

		if move_from == Vector2i(-999, -999):
			return

		# Place in the nearest empty slot near the poor spawn
		var move_to: Vector2i = Vector2i(-999, -999)
		var min_dist: int = 999
		for pos: Vector2i in cells:
			var cell: Cell = cells[pos]
			if cell.is_resource or cell.is_city or cell.is_grail or not _passable_or_mild(pos):
				continue
			var d: int = hex_distance(pos.x, pos.y, poor_sp.x, poor_sp.y)
			if d <= local_radius and d < min_dist:
				min_dist = d
				move_to = pos

		if move_to == Vector2i(-999, -999):
			return

		var from_cell: Cell = cells[move_from]
		var to_cell: Cell = cells[move_to]
		to_cell.is_resource = true
		to_cell.res_tier = from_cell.res_tier
		from_cell.is_resource = false
		from_cell.res_tier = ""

# ── Chokepoints ───────────────────────────────────────────────────────────────

func find_chokepoints() -> void:
	var _cost: Callable = func(t: int) -> float:
		match t:
			Terrain.VOID:
				return 999.0
			Terrain.MOUNTAIN:
				return 5.0
			Terrain.FOREST:
				return 2.0
			Terrain.HIGHLAND:
				return 3.0
			_:
				return 1.0

	var usage: Dictionary = {}
	for spawn: Vector2i in spawns:
		var dist: Dictionary = {spawn: 0.0}
		var prev: Dictionary = {}
		var heap := _MinHeap.new()
		heap.push(spawn, 0.0)
		while not heap.is_empty():
			var d: float = heap.min_priority()
			var pos: Vector2i = heap.pop()
			if d > dist.get(pos, 1e9):
				continue
			if pos == Vector2i(0, 0):
				break
			for nb: Vector2i in hex_neighbors(pos.x, pos.y):
				if not cells.has(nb):
					continue
				var nd: float = d + _cost.call((cells[nb] as Cell).terrain)
				if nd < dist.get(nb, 1e9):
					dist[nb] = nd
					prev[nb] = pos
					heap.push(nb, nd)
		var cur: Vector2i = Vector2i(0, 0)
		while prev.has(cur):
			usage[cur] = usage.get(cur, 0) + 1
			cur = prev[cur]

	# On larger maps with more players, more paths converge so raise threshold
	var choke_threshold: int = max(2, num_players / 3)
	for pos: Vector2i in usage:
		if (usage[pos] as int) >= choke_threshold and cells.has(pos):
			(cells[pos] as Cell).is_choke = true

# ── Validation (record only, fixes already applied) ───────────────────────────

func validate() -> void:
	var issues: Array[String] = []

	if spawns.size() < num_players:
		issues.append("spawn_count=%d < %d" % [spawns.size(), num_players])

	var center_dists: Array[int] = []
	for sp: Vector2i in spawns:
		center_dists.append(hex_distance(sp.x, sp.y, 0, 0))
	if center_dists.size() > 0:
		var mx: int = center_dists.max() as int
		var mn: int = center_dists.min() as int
		var tolerance: int = max(2, game_radius / 6)
		if mx - mn > tolerance:
			issues.append("spawn_radius_var=%d (tolerance=%d)" % [mx - mn, tolerance])

	var local_radius: int = max(3, game_radius / 5)
	var local: Array[int] = []
	for sp: Vector2i in spawns:
		var cnt: int = 0
		for pos: Vector2i in cells:
			if (cells[pos] as Cell).is_resource and hex_distance(pos.x, pos.y, sp.x, sp.y) <= local_radius:
				cnt += 1
		local.append(cnt)
	if local.size() > 0 and (local.max() as int) - (local.min() as int) > 2:
		issues.append("resource_imbalance=%s" % str(local))

	stats["fair"] = issues.is_empty()
	stats["issues"] = issues

# ── Helpers ───────────────────────────────────────────────────────────────────

func _shuffle_vec2i(arr: Array[Vector2i]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector2i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ── Main generate ─────────────────────────────────────────────────────────────

func generate() -> Dictionary:
	var seed_val: int = base_seed
	rng.seed = seed_val

	make_grid()
	generate_land_shape(seed_val)
	_repair_connectivity()
	assign_terrain(seed_val)

	# Grail at center
	var center := Vector2i(0, 0)
	if cells.has(center):
		var cc: Cell = cells[center]
		cc.is_grail = true
		cc.terrain = Terrain.GRAIL
		cc.is_void = false

	place_spawns()
	_fix_spawn_count()
	_fix_spawn_radius()
	_fix_spawn_connectivity()
	place_resources()
	_fix_resource_balance()
	find_chokepoints()

	var land_count: int = 0
	var void_count: int = 0
	for cell: Cell in cells.values():
		if cell.is_void:
			void_count += 1
		else:
			land_count += 1

	stats = {
		"seed": seed_val,
		"radius": game_radius,
		"players": num_players,
		"land": land_count,
		"void": void_count,
		"total": cells.size(),
		"spawns": spawns,
	}

	validate()
	return cells

# ── Terrain color lookup ──────────────────────────────────────────────────────

static func terrain_color(t: int) -> Color:
	match t:
		Terrain.VOID:
			return Color(0.03, 0.04, 0.14)
		Terrain.PLAIN:
			return Color(0.40, 0.70, 0.15)
		Terrain.FOREST:
			return Color(0.06, 0.28, 0.06)
		Terrain.HIGHLAND:
			return Color(0.70, 0.55, 0.28)
		Terrain.MOUNTAIN:
			return Color(0.58, 0.56, 0.62)
		Terrain.FORTRESS:
			return Color(0.50, 0.22, 0.72)
		Terrain.GRAIL:
			return Color(1.00, 0.84, 0.18)
		Terrain.DESERT:
			return Color(0.88, 0.75, 0.38)
		Terrain.SNOW:
			return Color(0.86, 0.92, 0.98)
	return Color.GRAY

# ── MinHeap ───────────────────────────────────────────────────────────────────

class _MinHeap:
	var _data: Array[Dictionary] = []

	func is_empty() -> bool:
		return _data.is_empty()

	func push(pos: Vector2i, priority: float) -> void:
		_data.append({"pos": pos, "p": priority})
		var i: int = _data.size() - 1
		while i > 0:
			var parent: int = (i - 1) / 2
			if _data[parent]["p"] <= _data[i]["p"]:
				break
			var tmp: Dictionary = _data[parent]
			_data[parent] = _data[i]
			_data[i] = tmp
			i = parent

	func pop() -> Vector2i:
		var result: Vector2i = _data[0]["pos"]
		_data[0] = _data[_data.size() - 1]
		_data.pop_back()
		if _data.size() > 0:
			var i: int = 0
			while true:
				var left: int = 2 * i + 1
				var right: int = 2 * i + 2
				var smallest: int = i
				if left < _data.size() and _data[left]["p"] < _data[smallest]["p"]:
					smallest = left
				if right < _data.size() and _data[right]["p"] < _data[smallest]["p"]:
					smallest = right
				if smallest == i:
					break
				var tmp: Dictionary = _data[i]
				_data[i] = _data[smallest]
				_data[smallest] = tmp
				i = smallest
		return result

	func min_priority() -> float:
		return _data[0]["p"] if _data.size() > 0 else 1e9
