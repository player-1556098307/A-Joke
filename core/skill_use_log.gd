class_name SkillUseLog
extends RefCounted

var round_number: int
var actor_id: int
var actor_name: String
var skill_name: String
var target_names: Array[String] = []
var total_damage: int = 0
var effects_summary: String = ""
