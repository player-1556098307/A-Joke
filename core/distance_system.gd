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

## 生成无方向的键："min_id:max_id"
func _make_key(a: int, b: int) -> String:
	if a < b:
		return "%d:%d" % [a, b]
	return "%d:%d" % [b, a]
