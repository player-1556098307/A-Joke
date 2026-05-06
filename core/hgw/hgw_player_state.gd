## HGWPlayerState — HGW mode per-player runtime state
## Extends the concept of PlayerState with hex-map coordinates, terrain awareness,
## seal reward buffs, and per-turn flags.
class_name HGWPlayerState
extends RefCounted

var player_id: int
var player_name: String
var character: CharacterData
var is_human: bool
var is_alive: bool = true

# ── HP & energy ──────────────────────────────────────────────────────────────────
var hp: int
var max_hp: int
var energy: int = 0

# ── Map position ─────────────────────────────────────────────────────────────────
var hex_q: int = 0
var hex_r: int = 0

# ── Defence chain (shared with existing damage model) ────────────────────────────
var clone_count: int = 0
var shield: int = 0  # 0=none, -1=infinite (one-hit), N=value

# ── Movement & attack range ──────────────────────────────────────────────────────
var base_movement: int = 3
var bonus_movement: int = 0
func get_movement() -> int: return base_movement + bonus_movement

var base_attack_range: int = 1
var bonus_attack_range: int = 0
var on_highland: bool = false
func get_attack_range() -> int:
	var r := base_attack_range + bonus_attack_range
	if on_highland: r += 1
	return r

# ── Permanent seal buffs ─────────────────────────────────────────────────────────
var has_energy_per_turn_buff: bool = false
var has_movement_bonus: bool = false
var has_range_bonus: bool = false

# ── Per-turn flags (reset every turn) ────────────────────────────────────────────
var moved_this_turn: bool = false
var acted_this_turn: bool = false
var attacked_this_turn: bool = false
var gathered_this_turn: bool = false

# ── Delayed damage (Rasengan) ────────────────────────────────────────────────────
var delayed_damages: Array[Dictionary] = []

# ── Desert event pending ─────────────────────────────────────────────────────────
var skip_next_action: bool = false

func reset_turn_data() -> void:
	moved_this_turn = false
	acted_this_turn = false
	attacked_this_turn = false
	gathered_this_turn = false
