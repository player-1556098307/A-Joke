## BossAI — Seal 1 boss counterattack logic
class_name BossAI
extends RefCounted

func decide_counterattack(damage_log: Dictionary, all_players: Array[HGWPlayerState], boss_q: int, boss_r: int, map_cells: Dictionary) -> Dictionary:
	var has_damage_record := false
	for pid in damage_log:
		if damage_log[pid] > 0:
			has_damage_record = true
			break

	if has_damage_record:
		var top_id := _get_top_damage_dealer(damage_log)
		return {"skill": "single", "targets": [top_id]}
	else:
		var aoe_targets := _get_aoe_targets(all_players, boss_q, boss_r, 3)
		return {"skill": "aoe", "targets": aoe_targets}

func _get_top_damage_dealer(damage_log: Dictionary) -> int:
	var best_id := -1
	var best_dmg := -1
	for pid in damage_log:
		if damage_log[pid] > best_dmg:
			best_dmg = damage_log[pid]
			best_id = pid
	return best_id

func _get_aoe_targets(all_players: Array[HGWPlayerState], boss_q: int, boss_r: int, radius: int) -> Array[int]:
	var targets: Array[int] = []
	for player in all_players:
		if not player.is_alive:
			continue
		var dist := maxi(abs(player.hex_q - boss_q), maxi(abs(player.hex_r - boss_r), abs((player.hex_q + player.hex_r) - (boss_q + boss_r))))
		if dist <= radius:
			targets.append(player.player_id)
	return targets
