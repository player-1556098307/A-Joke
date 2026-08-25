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

	# 9. 换位功能：交换槽位0和槽位1（玩家↔AI）
	var pre_sel_0: int = sel._selections[0]
	var pre_sel_1: int = sel._selections[1]
	var pre_mode_0: int = sel._slot_modes[0]
	var pre_mode_1: int = sel._slot_modes[1]
	sel._swap_slots(0, 1)
	_assert(sel._selections[0] == pre_sel_1, "9a: 换位后槽位0角色=原槽位1角色（实际=%d）" % sel._selections[0])
	_assert(sel._selections[1] == pre_sel_0, "9b: 换位后槽位1角色=原槽位0角色（实际=%d）" % sel._selections[1])
	_assert(sel._slot_modes[0] == pre_mode_1, "9c: 换位后槽位0模式=原槽位1模式（实际=%d）" % sel._slot_modes[0])
	_assert(sel._slot_modes[1] == pre_mode_0, "9d: 换位后槽位1模式=原槽位0模式（实际=%d）" % sel._slot_modes[1])
	# 真人玩家换到槽位1后应能正确识别
	var hs: int = sel._get_human_slot()
	_assert(hs == 1, "9e: 换位后真人玩家在槽位1（实际=%d）" % hs)
	# _build_tower_config 中玩家变成第二个成员
	cfg = sel._build_tower_config()
	_assert(cfg.size() == 3, "9f: 换位后队伍仍3人（实际=%d）" % cfg.size())
	_assert(cfg[1]["is_human"] == true, "9g: 换位后玩家在队伍第2位（实际=%s）" % str(cfg[1]["is_human"]))
	_assert(cfg[0]["is_human"] == false, "9h: 换位后AI在队伍第1位（实际=%s）" % str(cfg[0]["is_human"]))

	# 10. 换回去（恢复正常顺序）
	sel._swap_slots(0, 1)
	hs = sel._get_human_slot()
	_assert(hs == 0, "10a: 换回后真人玩家在槽位0（实际=%d）" % hs)
	_assert(sel._slot_modes[0] == pre_mode_0 and sel._slot_modes[1] == pre_mode_1, "10b: 换回后模式恢复")
	cfg = sel._build_tower_config()
	_assert(cfg[0]["is_human"] == true, "10c: 换回后玩家在队伍第1位（实际=%s）" % str(cfg[0]["is_human"]))

	# 11. 换位按钮交互流程：点击⇄进入换位模式 → 再点槽位完成交换
	_assert(sel._swap_pending == -1, "11a: 初始无换位状态")
	sel._on_swap_pressed(0)
	_assert(sel._swap_pending == 0, "11b: 点击⇄进入换位模式（源=槽位0）")
	sel._on_swap_pressed(1)
	_assert(sel._swap_pending == -1, "11c: 再次点击目标完成交换后退出换位模式")
	# 交换应该已执行
	hs = sel._get_human_slot()
	_assert(hs == 1, "11d: 交互流程换位后玩家在槽位1（实际=%d）" % hs)

	# 12. 换位模式下再点源槽位取消
	sel._swap_slots(0, 1)  # 先换回去
	sel._on_swap_pressed(2)
	_assert(sel._swap_pending == 2, "12a: 点击槽位2⇄进入换位模式（源=槽位2）")
	sel._on_swap_pressed(2)
	_assert(sel._swap_pending == -1, "12b: 再次点击同一槽位取消换位")

	# 13. 高亮同步（回归：选中 _chars[0]（鸣人），列表按等级排序，高亮必须落在该角色卡片上）
	sel._set_active_slot(0)
	sel._select_for_active(sel._chars[0])  # 显式选中 _chars[0]，避免前序换位测试污染状态
	# 找到 _chars[0]（原始列表第一个角色）在排序后卡片列表中的位置
	var card_idx: int = -1
	for ci in sel._card_chars.size():
		if sel._card_chars[ci] == sel._chars[0]:
			card_idx = ci
			break
	_assert(card_idx >= 0, "13a: _chars[0] 在卡片列表中存在（实际索引=%d）" % card_idx)
	# 高亮卡片必须等于 _chars[0] 所在卡片（而非卡片0）
	for ci in sel._card_buttons.size():
		var expect_sel: bool = ci == card_idx
		var actual_sel: bool = sel._card_sel_badges[ci].visible
		if ci == card_idx:
			_assert(actual_sel, "13b: 卡片%d（%s）应显示已选徽章" % [ci, sel._card_chars[ci].character_name])
		else:
			_assert(not actual_sel, "13c: 卡片%d（%s）不应显示已选徽章" % [ci, sel._card_chars[ci].character_name])
	# 详情与高亮一致
	_assert(sel._name_label.text == sel._chars[0].character_name, "13d: 详情显示 _chars[0]（实际=%s）" % sel._name_label.text)

	# 14. 切到另一个角色后高亮跟随（选中 _chars[1]，高亮落在其卡片）
	sel._select_for_active(sel._chars[1])
	var sel_idx2: int = -1
	for ci in sel._card_chars.size():
		if sel._card_chars[ci] == sel._chars[1]:
			sel_idx2 = ci
			break
	_assert(sel_idx2 >= 0, "14a: _chars[1] 在卡片列表中存在（实际索引=%d）" % sel_idx2)
	for ci in sel._card_buttons.size():
		var expect: bool = ci == sel_idx2
		if ci == sel_idx2:
			_assert(sel._card_sel_badges[ci].visible, "14b: 卡片%d 应高亮（_chars[1]）" % ci)
		else:
			_assert(not sel._card_sel_badges[ci].visible, "14c: 卡片%d 不应高亮" % ci)
	_assert(sel._name_label.text == sel._chars[1].character_name, "14d: 详情跟随 _chars[1]（实际=%s）" % sel._name_label.text)

	# 15. 清理
	sel.queue_free()

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
