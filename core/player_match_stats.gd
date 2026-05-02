class_name PlayerMatchStats
extends RefCounted

var player_id: int
var player_name: String
var character: CharacterData
var is_human: bool

var final_hp: int
var max_hp: int
var total_damage_dealt: int = 0
var total_damage_taken: int = 0
var total_healing: int = 0
var skill_use_count: int = 0
var charge_count: int = 0
var win_count: int = 0
var tiebreak_win_count: int = 0
var shield_blocked_count: int = 0
var paralyze_applied_count: int = 0
var paralyze_suffered_count: int = 0
var elimination_round: int = -1
var elimination_reason: String = ""
var unlocked_skills: Array[String] = []
