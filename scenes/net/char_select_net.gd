extends Node

## 当前 match 中所有玩家的武将选择
## key = nakama user_id, value = char_resource_path
var selections: Dictionary = {}
var locked: Dictionary = {}   # user_id → true 表示已锁定
var my_user_id: String = ""
var match_id: String = ""

const OP_SELECT  := 100  # 选择武将（未锁定）
const OP_LOCK    := 101  # 锁定武将
const OP_ALL_LOCKED := 102  # 全员锁定，准备开始

func _ready() -> void:
	my_user_id = NetworkManager._session.user_id
	match_id = NetworkManager.current_room_id
	NetworkManager.game_message_received.connect(_on_message)

func select_character(char_path: String) -> void:
	selections[my_user_id] = char_path
	_send(OP_SELECT, {"char": char_path})

func lock_character() -> void:
	if not selections.has(my_user_id):
		return
	locked[my_user_id] = true
	_send(OP_LOCK, {"char": selections[my_user_id]})
	_check_all_locked()

func _on_message(op: int, data: Dictionary) -> void:
	var uid: String = data.get("uid", "")
	match op:
		OP_SELECT:
			selections[uid] = data.get("char", "")
			# 更新 UI：显示对方选的武将
		OP_LOCK:
			selections[uid] = data.get("char", "")
			locked[uid] = true
			_check_all_locked()

func _check_all_locked() -> void:
	# 所有已加入玩家都锁定后，房主广播 ALL_LOCKED
	# 此处简化：判断 locked 数量 == match 人数
	pass

func _send(op: int, payload: Dictionary) -> void:
	payload["uid"] = my_user_id
	NetworkManager._socket.send_match_state_async(match_id, op,
		JSON.stringify(payload))
