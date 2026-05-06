## ShrinkRing — post-grail shrinking ring management
class_name ShrinkRing
extends RefCounted

signal ring_shrunk(new_radius: int)
signal player_in_danger(player_id: int)

var active: bool = false
var current_radius: int = 0
var turns_since_activation: int = 0
const SHRINK_INTERVAL := 3

func activate(initial_radius: int) -> void:
	active = true
	current_radius = initial_radius

func on_round_end() -> void:
	if not active:
		return
	turns_since_activation += 1
	if turns_since_activation % SHRINK_INTERVAL == 0:
		current_radius -= 1
		ring_shrunk.emit(current_radius)

func is_inside(q: int, r: int) -> bool:
	var dist := maxi(abs(q), maxi(abs(r), abs(q + r)))
	return dist <= current_radius

func apply_ring_damage(players: Array[HGWPlayerState], damage_resolver: DamageResolver) -> void:
	for player in players:
		if not player.is_alive:
			continue
		if not is_inside(player.hex_q, player.hex_r):
			damage_resolver.apply(player, 1)
