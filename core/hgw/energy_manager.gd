## EnergyManager — all energy (气) gain/spend/inherit logic
class_name EnergyManager
extends RefCounted

signal energy_changed(player_id: int, new_amount: int, delta: int, source: String)
signal auto_gain_triggered(player_id: int)

const SOURCE_RESOURCE_TILE := "resource_tile"
const SOURCE_FORTRESS_FIRST := "fortress_first"
const SOURCE_REWARD_POOL    := "reward_pool"
const SOURCE_GATHER         := "gather"
const SOURCE_DESERT_EVENT   := "desert_event"
const SOURCE_KILL_INHERIT   := "kill_inherit"
const SOURCE_SEAL1_BUFF     := "seal1_buff"

func gain(player: HGWPlayerState, amount: int, source: String) -> void:
	if amount <= 0:
		return
	player.energy += amount
	energy_changed.emit(player.player_id, player.energy, amount, source)

func spend(player: HGWPlayerState, amount: int) -> bool:
	if player.energy < amount:
		return false
	player.energy -= amount
	energy_changed.emit(player.player_id, player.energy, -amount, "spend")
	return true

func on_kill(killer: HGWPlayerState, victim: HGWPlayerState) -> void:
	if victim.energy > 0:
		var inherited := victim.energy
		victim.energy = 0
		energy_changed.emit(victim.player_id, 0, -inherited, "lost_on_death")
		killer.energy += inherited
		energy_changed.emit(killer.player_id, killer.energy, inherited, SOURCE_KILL_INHERIT)

func on_turn_start(player: HGWPlayerState) -> void:
	if player.has_energy_per_turn_buff:
		gain(player, 1, SOURCE_SEAL1_BUFF)
		auto_gain_triggered.emit(player.player_id)
