## 距离系统 — 环形座位距离计算器
## 玩家排成环形，距离 = min(顺时针步数, 逆时针步数) + 单对偏移量，最小为1
## 灵感来源于三国杀的座位距离机制
class_name DistanceSystem

## 座位顺序：按player_id排列的环形座位表
var _seat_order: Array[int] = []
## 距离偏移量字典，key格式 "min_id:max_id"，value为偏移值（可正可负）
var _distance_offsets: Dictionary = {}

## 初始化座位表，复制传入的座位顺序数组
func setup(seat_order: Array[int]) -> void:
	_seat_order = seat_order.duplicate()
	_distance_offsets.clear()

## 获取两个玩家之间的环形距离
## 同玩家返回0，不在座位表中返回999（表示不可达）
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

## 修改两个玩家之间的永久距离偏移（delta可正可负）
func modify_distance(from_id: int, to_id: int, delta: int) -> void:
	var key := _make_key(from_id, to_id)
	var current: int = _distance_offsets.get(key, 0)
	_distance_offsets[key] = current + delta

## 从座位表中移除一名玩家（死亡/淘汰时调用）
func remove_player(player_id: int) -> void:
	_seat_order.erase(player_id)

## 交换两名玩家在环形座位表中的位置（飞雷神换位用）
func swap_seats(player_a: int, player_b: int) -> void:
	var idx_a := _seat_order.find(player_a)
	var idx_b := _seat_order.find(player_b)
	if idx_a == -1 or idx_b == -1:
		return
	_seat_order[idx_a] = player_b
	_seat_order[idx_b] = player_a

## 生成无方向的键："min_id:max_id"
func _make_key(a: int, b: int) -> String:
	if a < b:
		return "%d:%d" % [a, b]
	return "%d:%d" % [b, a]

## 拍摄座位系统快照（用于新止水·别天神回溯）
func capture_snapshot() -> Dictionary:
	return {
		"seat_order": _seat_order.duplicate(),
		"distance_offsets": _distance_offsets.duplicate(),
	}

## 从快照恢复座位系统（用于新止水·别天神回溯）
## 注意：回溯时被恢复为存活的玩家需要重新加入座位表（由 GameManager 处理）
func restore_from_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	_seat_order = (snap.get("seat_order", []) as Array).duplicate()
	_distance_offsets.clear()
	var offsets: Dictionary = snap.get("distance_offsets", {})
	for key in offsets:
		_distance_offsets[key] = offsets[key]
