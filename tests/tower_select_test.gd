## 塔选人界面冒烟测试（房间式）
## 验证：角色卡、默认1真人玩家+2空槽位、填充AI/真人、空槽位不参战、角色分配
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔选人房间冒烟测试 ===")
	await get_tree().process_frame

	var sel = (load("res://scenes/tower/tower_select.tscn") as PackedScene).instantiate()
	add_child(sel)
	await get_tree().process_frame

	# 1. 角色卡（含波风水门）
	_assert(sel._card_buttons.size() == sel._chars.size(), "1a: 角色卡数量=%d（实际=%d）" % [sel._chars.size(), sel._card_buttons.size()])
	_assert(sel._chars.size() > 0, "1b: 角色池非空（实际=%d）" % sel._chars.size())
	var has_minato: bool = false
	for c in sel._chars:
		if c.character_name.contains("波风水门"):
			has_minato = true
			break
	_assert(has_minato, "1c: 角色池包含波风水门（实际=%d个角色）" % sel._chars.size())

	# 2. 房间默认：1号真人玩家，2/3空
	_assert(sel._slot_modes[0] == 0, "2a: 槽位1=真人玩家（实际=%d）" % sel._slot_modes[0])
	_assert(sel._slot_modes[1] == -1 and sel._slot_modes[2] == -1, "2b: 槽位2/3为空（实际=%s）" % str(sel._slot_modes))
	_assert(sel._selections[0] >= 0, "2c: 玩家已选角色")

	# 3. 默认单人队伍（空槽位不参战）
	var cfg: Array = sel._build_tower_config()
	_assert(cfg.size() == 1, "3a: 默认1人队伍（实际=%d）" % cfg.size())
	_assert(cfg.size() > 0 and cfg[0]["is_human"] == true, "3b: 玩家真人")

	# 4. 填充槽位2为AI（空→AI）
	sel._toggle_slot_mode(1)
	_assert(sel._slot_modes[1] == 1, "4a: 槽位2→AI（实际=%d）" % sel._slot_modes[1])
	_assert(sel._selections[1] >= 0, "4b: AI自动分配角色")
	cfg = sel._build_tower_config()
	_assert(cfg.size() == 2, "4c: 队伍2人（实际=%d）" % cfg.size())
	_assert(cfg.size() > 1 and cfg[1]["is_human"] == false, "4d: 成员2为AI")

	# 5. 槽位2切回空（AI→空，不参战；本地单机不支持填真人）
	sel._toggle_slot_mode(1)
	_assert(sel._slot_modes[1] == -1, "5a: 槽位2 AI→空（实际=%d）" % sel._slot_modes[1])
	cfg = sel._build_tower_config()
	_assert(cfg.size() == 1, "5b: 空槽位不参战（实际=%d）" % cfg.size())

	# 6. 槽位2再填充AI → 队伍2人且成员2为AI
	sel._toggle_slot_mode(1)
	_assert(sel._slot_modes[1] == 1, "6a: 槽位2 空→AI（实际=%d）" % sel._slot_modes[1])
	cfg = sel._build_tower_config()
	_assert(cfg.size() == 2 and cfg[1]["is_human"] == false, "6b: 2人队伍成员2为AI（实际=%s）" % str(cfg.size()))

	# 7. 角色分配（激活槽位0）
	sel._set_active_slot(0)
	sel._select_for_active(sel._chars[1])
	_assert(sel._selections[0] == 1, "7a: 玩家角色更新（实际=%d）" % sel._selections[0])
	_assert(sel._name_label.text == sel._chars[1].character_name, "7b: 详情刷新（实际=%s）" % sel._name_label.text)

	# 8. 空槽位激活后选角色 → 自动填充AI（此时槽位1已AI，槽位2再填 → 3人）
	sel._set_active_slot(2)
	sel._select_for_active(sel._chars[0])
	_assert(sel._slot_modes[2] == 1, "8a: 空槽位选角色自动填充AI（实际=%d）" % sel._slot_modes[2])
	cfg = sel._build_tower_config()
	_assert(cfg.size() == 3, "8b: 队伍3人（玩家+2AI，实际=%d）" % cfg.size())
	_assert(cfg[2]["is_human"] == false, "8c: 槽位3为AI（实际=%s）" % str(cfg[2]["is_human"]))

	print("=== 塔选人冒烟测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
