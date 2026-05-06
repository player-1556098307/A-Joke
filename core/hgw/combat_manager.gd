## CombatManager — attack initiation, RPS hit check, skill selection & resolution
class_name CombatManager
extends RefCounted

signal rps_required(attacker_id: int, defender_id: int)
signal rps_result(attacker_id: int, hit: bool)
signal skill_selection_required(attacker_id: int, available_skills: Array)
signal combat_resolved(log: Dictionary)

enum Gesture { ROCK = 0, SCISSORS = 1, PAPER = 2 }

var _damage_resolver: DamageResolver
var _energy_mgr: EnergyManager
var _terrain_effect: TerrainEffect

func _init(damage_resolver: DamageResolver, energy_mgr: EnergyManager, terrain_effect: TerrainEffect) -> void:
	_damage_resolver = damage_resolver
	_energy_mgr = energy_mgr
	_terrain_effect = terrain_effect

func initiate_attack(attacker: HGWPlayerState, defender: HGWPlayerState) -> void:
	assert(attacker.energy >= 1, "Attack requires at least 1 energy")
	assert(not attacker.gathered_this_turn, "Cannot attack after gathering this turn")
	_energy_mgr.spend(attacker, 1)
	rps_required.emit(attacker.player_id, defender.player_id)

func submit_rps(attacker_gesture: int, defender_gesture: int, attacker: HGWPlayerState, defender: HGWPlayerState) -> bool:
	var hit := _check_rps_hit(attacker_gesture, defender_gesture)
	rps_result.emit(attacker.player_id, hit)
	if hit:
		var available := _get_available_skills(attacker)
		skill_selection_required.emit(attacker.player_id, available)
	return hit

func resolve_skill(attacker: HGWPlayerState, defender: HGWPlayerState, skill: SkillData, terrain: int) -> Dictionary:
	_energy_mgr.spend(attacker, skill.energy_cost)
	var base_dmg := _calc_skill_damage(skill, attacker, defender)
	var final_dmg := _terrain_effect.apply_damage_with_terrain(base_dmg, defender, terrain)
	var result := _damage_resolver.apply(defender, final_dmg)

	# Register delayed damages (Rasengan)
	for effect: SkillEffect in skill.effects:
		if effect.effect_type == SkillEffect.EffectType.DELAYED_DAMAGE:
			defender.delayed_damages.append({
				"damage": effect.value,
				"trigger_in": effect.duration,
				"attacker_id": attacker.player_id,
			})

	result["attacker_id"] = attacker.player_id
	result["defender_id"] = defender.player_id
	result["skill_name"] = skill.skill_name
	combat_resolved.emit(result)
	return result

func _get_available_skills(attacker: HGWPlayerState) -> Array:
	var skills: Array = []
	for skill: SkillData in attacker.character.skills:
		skills.append(skill)
	return skills

func _check_rps_hit(atk: int, def: int) -> bool:
	if atk == def:
		return false
	return (atk - def + 3) % 3 == 1

func _calc_skill_damage(skill: SkillData, _attacker: HGWPlayerState, _defender: HGWPlayerState) -> int:
	var total := 0
	for effect: SkillEffect in skill.effects:
		if effect.effect_type == SkillEffect.EffectType.DAMAGE:
			total += effect.value
	return total
