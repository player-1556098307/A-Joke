## DamageResolver — damage absorption chain
## Clone → Infinite Shield → Value Shield → HP
class_name DamageResolver
extends RefCounted

static func apply(defender: HGWPlayerState, raw_damage: int) -> Dictionary:
	var dmg := raw_damage
	var result := {
		"final_damage": 0,
		"clone_broken": false,
		"shield_absorbed": 0,
		"hp_before": defender.hp,
		"hp_after": defender.hp,
		"killed": false,
	}

	# 1. Clone (Shadow Clone)
	if defender.clone_count > 0:
		defender.clone_count -= 1
		result["clone_broken"] = true
		result["hp_after"] = defender.hp
		return result

	# 2. Infinite shield (one-hit full absorb)
	if defender.shield == -1:
		defender.shield = 0
		result["hp_after"] = defender.hp
		return result

	# 3. Value shield
	if defender.shield > 0:
		var absorbed := mini(dmg, defender.shield)
		defender.shield -= absorbed
		dmg -= absorbed
		result["shield_absorbed"] = absorbed

	# 4. HP
	if dmg > 0:
		defender.hp = maxi(0, defender.hp - dmg)
		result["final_damage"] = dmg

	result["hp_after"] = defender.hp
	result["killed"] = (defender.hp <= 0)
	return result
