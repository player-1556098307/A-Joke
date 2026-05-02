class_name ActionLog
extends RefCounted

var actor_id: int
var action_type: int  # PlayerState.ActionType
var skill_name: String = ""
var target_ids: Array[int] = []
var effect_results: Array[Dictionary] = []
