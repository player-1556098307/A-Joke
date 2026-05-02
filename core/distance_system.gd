class_name DistanceSystem

var _seat_order: Array[int] = []
var _distance_offsets: Dictionary = {}

func setup(seat_order: Array[int]) -> void:
	_seat_order = seat_order.duplicate()
	_distance_offsets.clear()

func get_distance(from_id: int, to_id: int) -> int:
	if from_id == to_id:
		return 0
	var idx_from := _seat_order.find(from_id)
	var idx_to   := _seat_order.find(to_id)
	if idx_from == -1 or idx_to == -1:
		return 999
	var n: int         = _seat_order.size()
	var clockwise: int = abs(idx_to - idx_from)
	var counter: int   = n - clockwise
	var base: int      = min(clockwise, counter)
	var key       := _make_key(from_id, to_id)
	var offset: int = _distance_offsets.get(key, 0)
	return max(1, base + offset)

func modify_distance(from_id: int, to_id: int, delta: int) -> void:
	var key := _make_key(from_id, to_id)
	var current: int = _distance_offsets.get(key, 0)
	_distance_offsets[key] = current + delta

func remove_player(player_id: int) -> void:
	_seat_order.erase(player_id)

func _make_key(a: int, b: int) -> String:
	if a < b:
		return "%d:%d" % [a, b]
	return "%d:%d" % [b, a]
