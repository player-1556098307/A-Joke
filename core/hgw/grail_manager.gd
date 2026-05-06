## GrailManager — grail throne occupation tracking & victory condition
class_name GrailManager
extends RefCounted

signal grail_opened()
signal occupation_started(player_id: int)
signal occupation_progress(player_id: int, turns: int)
signal occupation_interrupted(player_id: int)
signal victory_grail(player_id: int)

const REQUIRED_TURNS := 3
var is_open: bool = false
var grail_q: int = 0
var grail_r: int = 0

var occupying_player_id: int = -1
var occupation_turns: int = 0

func open_grail() -> void:
	is_open = true
	grail_opened.emit()

func on_player_turn_end(player: HGWPlayerState) -> void:
	if not is_open:
		return
	var on_throne := (player.hex_q == grail_q and player.hex_r == grail_r)
	if on_throne:
		if occupying_player_id != player.player_id:
			occupying_player_id = player.player_id
			occupation_turns = 1
			occupation_started.emit(player.player_id)
		else:
			occupation_turns += 1
			occupation_progress.emit(player.player_id, occupation_turns)
			if occupation_turns >= REQUIRED_TURNS:
				victory_grail.emit(player.player_id)
	else:
		if occupying_player_id == player.player_id:
			occupation_turns = 0
			occupation_interrupted.emit(player.player_id)

func interrupt_if_occupying(player_id: int) -> void:
	if occupying_player_id == player_id and occupation_turns > 0:
		occupation_turns = 0
		occupation_interrupted.emit(player_id)
