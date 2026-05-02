class_name RoundSnapshot
extends RefCounted

var round_number: int
var is_tiebreak: bool = false
var tiebreak_candidates: Array[int] = []
var gestures: Dictionary = {}
var winners: Array[int] = []
var losers: Array[int] = []
var is_draw: bool = false
var actions: Array[ActionLog] = []
var player_states_after: Array[PlayerStateSnapshot] = []
var events: Array[String] = []
