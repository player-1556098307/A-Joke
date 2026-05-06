## TerrainEffect — terrain lookup tables and effect application
class_name TerrainEffect
extends RefCounted

# Matches HGWMapGenerator.Terrain enum:
# VOID=0, PLAIN=1, FOREST=2, HIGHLAND=3, MOUNTAIN=4, FORTRESS=5, GRAIL=6, DESERT=7, SNOW=8

static func get_enter_bonus_range(terrain: int) -> int:
	return 1 if terrain == 3 else 0  # HIGHLAND → +1 attack range

static func get_defense_reduction(terrain: int) -> int:
	return 1 if terrain == 4 else 0  # MOUNTAIN → -1 damage

static func is_stealthy(terrain: int) -> bool:
	return terrain == 2  # FOREST

static func apply_enter_effect(player: HGWPlayerState, terrain: int, energy_mgr: EnergyManager) -> Dictionary:
	match terrain:
		5:  # FORTRESS — first occupation +3 energy (tracked by caller)
			return {"fortress_entry": true}
		7:  # DESERT — caller handles d100 event
			return {"desert_event": true}
		8:  # SNOW — caller handles slide
			return {"snow_slide": true}
		6:  # GRAIL_THRONE — caller tracks occupation
			return {"grail_zone": true}
	return {}

static func apply_damage_with_terrain(base_damage: int, defender: HGWPlayerState, terrain: int) -> int:
	var dmg := base_damage
	# Mountain -1 first
	if terrain == 4:
		dmg = maxi(0, dmg - 1)
	# Fortress halved second (ceil)
	if terrain == 5:
		dmg = ceili(float(dmg) / 2.0)
	return maxi(0, dmg)
