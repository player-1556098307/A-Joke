## 塔门对话冒烟测试（适配新版 DialogueBox 架构）
## 验证：开场白/死亡对话切换、多阶段死亡对话、进入按钮、中文数字
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 塔门对话冒烟测试 ===")
	await get_tree().process_frame

	# ---- 开场白（首次：death_count=0）----
	SceneManager.tower_death_count = 0
	SceneManager.last_tower_config.erase("failed_floor")
	var gate = (load("res://scenes/tower/tower_gate.tscn") as PackedScene).instantiate()
	add_child(gate)
	await get_tree().process_frame

	# DialogueBox 已开始对话，_lines 内部持有对话数据
	_assert(gate._dialogue_box != null, "1a: DialogueBox 已创建")
	_assert(gate._dialogue_box.is_active(), "1b: 开场白对话已激活")
	_assert(not gate._enter_btn.visible, "1c: 初始无进入按钮")
	var lines_open: Array = gate._dialogue_box._lines
	_assert(lines_open.size() == 5, "1d: 开场白5句（实际=%d）" % lines_open.size())
	# 第一句应含"停。"
	var first_text: String = lines_open[0].get("text", "")
	_assert(first_text.contains("停。"), "1e: 第一句含'停。'（实际=%s）" % first_text.left(30))

	# 逐句推进到最后（force_finish 触发 dialogue_finished → 显示进入按钮）
	gate._dialogue_box.force_finish()
	await get_tree().process_frame
	_assert(gate._enter_btn.visible, "2a: 对话结束后显示进入按钮")

	# 清理旧 gate
	gate.queue_free()
	await get_tree().process_frame

	# ---- 死亡对话（第11次死亡，死于第3层）----
	SceneManager.tower_death_count = 11
	SceneManager.last_tower_config["failed_floor"] = 3
	var gate2 = (load("res://scenes/tower/tower_gate.tscn") as PackedScene).instantiate()
	add_child(gate2)
	await get_tree().process_frame

	var lines_death: Array = gate2._dialogue_box._lines
	_assert(lines_death.size() >= 5, "3a: 死亡对话>=5句（实际=%d）" % lines_death.size())
	# 第10+次死亡=破例阶段，第一句应为"……"
	var d_first: String = lines_death[0].get("text", "")
	_assert(d_first.contains("……"), "3b: 第10+次死亡=破例阶段（实际=%s）" % d_first.left(30))
	# 第二句应含层数信息
	if lines_death.size() >= 2:
		var d_second: String = lines_death[1].get("text", "")
		_assert(d_second.contains("第一百零六") or d_second.contains("梅塔特隆"), "3c: 破例对话第二句含关键内容（实际=%s）" % d_second.left(40))

	gate2.queue_free()
	await get_tree().process_frame

	# ---- 第1次死亡：冷漠阶段 ----
	SceneManager.tower_death_count = 1
	SceneManager.last_tower_config["failed_floor"] = 1
	var gate3 = (load("res://scenes/tower/tower_gate.tscn") as PackedScene).instantiate()
	add_child(gate3)
	await get_tree().process_frame

	var lines_cold: Array = gate3._dialogue_box._lines
	_assert(lines_cold.size() == 5, "4a: 冷漠阶段5句（实际=%d）" % lines_cold.size())
	var cold_first: String = lines_cold[0].get("text", "")
	_assert(cold_first.contains("第一次"), "4b: 死亡次数=第一次（实际=%s）" % cold_first.left(40))
	# 第二句应含层数
	var cold_second: String = lines_cold[1].get("text", "")
	_assert(cold_second.contains("第一层"), "4c: 失败层=第一层（实际=%s）" % cold_second.left(50))

	gate3.queue_free()
	await get_tree().process_frame

	# ---- 第5次死亡：不耐阶段 ----
	SceneManager.tower_death_count = 5
	SceneManager.last_tower_config["failed_floor"] = 2
	var gate4 = (load("res://scenes/tower/tower_gate.tscn") as PackedScene).instantiate()
	add_child(gate4)
	await get_tree().process_frame

	var lines_impatient: Array = gate4._dialogue_box._lines
	_assert(lines_impatient.size() == 5, "5a: 不耐阶段5句（实际=%d）" % lines_impatient.size())
	var imp_first: String = lines_impatient[0].get("text", "")
	_assert(imp_first.contains("第五次"), "5b: 死亡次数=第五次（实际=%s）" % imp_first.left(40))

	gate4.queue_free()
	await get_tree().process_frame

	# ---- 第7次死亡：诡异阶段 ----
	SceneManager.tower_death_count = 7
	SceneManager.last_tower_config["failed_floor"] = 3
	var gate5 = (load("res://scenes/tower/tower_gate.tscn") as PackedScene).instantiate()
	add_child(gate5)
	await get_tree().process_frame

	var lines_eerie: Array = gate5._dialogue_box._lines
	_assert(lines_eerie.size() == 5, "6a: 诡异阶段5句（实际=%d）" % lines_eerie.size())
	var eerie_first: String = lines_eerie[0].get("text", "")
	_assert(eerie_first.contains("第七次"), "6b: 死亡次数=第七次（实际=%s）" % eerie_first.left(40))

	gate5.queue_free()

	print("=== 塔门冒烟测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
