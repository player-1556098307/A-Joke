## UI 弹窗冒烟测试：新止水（天劫）三个新弹窗
## 覆盖：幻影闪避决策、别天神回溯决策、日影舞4段目标选择
## 验证：弹窗创建、按钮存在、点击后调用 GameManager 提交方法、闭包捕获正确
extends Node

var _pass_count: int = 0
var _fail_count: int = 0
var _ui: Control = null
var _applied_targets: Array = []

func _ready() -> void:
	print("=== UI弹窗冒烟测试（新止水） ===")
	await get_tree().process_frame

	var new_shisui_char := load("res://resources/characters/宇智波止水（天劫）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	if new_shisui_char == null or naruto_char == null or sasuke_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	# 初始化 GameManager（3人局，新止水为人类玩家）
	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "新止水", "character": new_shisui_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
		]
	})
	await get_tree().process_frame

	# 加载 game_ui 场景
	_ui = (load("res://scenes/game_ui.tscn") as PackedScene).instantiate()
	add_child(_ui)
	await get_tree().process_frame

	# _human_player_id 在 _refresh_all_cards 时设置，确认
	var ns: PlayerState = gm.get_player(0)
	_assert(ns != null and ns.phantom_count == 0, "U1: 新止水初始化（幻影0）")
	# 模拟新止水是人类玩家
	_ui._human_player_id = 0

	# ══ 测试1：幻影闪避弹窗 ══
	gm.phantom_dodge_required.emit(0, 1)
	await get_tree().process_frame
	_assert(_ui._phantom_dodge_dialog != null, "U2a: 幻影闪避弹窗已创建")
	if _ui._phantom_dodge_dialog:
		var btn_texts: Array[String] = []
		_for_each_button(_ui._phantom_dodge_dialog, func(b: Button): btn_texts.append(b.text))
		_assert(btn_texts.any(func(t: String): return t.contains("闪避")), "U2b: 闪避按钮存在（%s）" % str(btn_texts))
		_assert(btn_texts.any(func(t: String): return t.contains("硬抗")), "U2c: 硬抗按钮存在（%s）" % str(btn_texts))
	# 点击"闪避"按钮（消耗1气+1幻影）
	var dodge_clicked := _click_button(_ui._phantom_dodge_dialog, "闪避")
	_assert(dodge_clicked, "U2d: 点击闪避按钮")
	await get_tree().process_frame
	_assert(_ui._phantom_dodge_dialog == null, "U2e: 弹窗已关闭")

	# ══ 测试2：回溯弹窗 ══
	gm.backtrack_required.emit(0)
	await get_tree().process_frame
	_assert(_ui._backtrack_dialog != null, "U3a: 回溯弹窗已创建")
	if _ui._backtrack_dialog:
		var btn_texts2: Array[String] = []
		_for_each_button(_ui._backtrack_dialog, func(b: Button): btn_texts2.append(b.text))
		_assert(btn_texts2.any(func(t: String): return t.contains("发动回溯")), "U3b: 发动按钮存在（%s）" % str(btn_texts2))
		_assert(btn_texts2.any(func(t: String): return t.contains("跳过")), "U3c: 跳过按钮存在（%s）" % str(btn_texts2))
	# 点击"跳过"
	var skip_clicked := _click_button(_ui._backtrack_dialog, "跳过")
	_assert(skip_clicked, "U3d: 点击跳过按钮")
	await get_tree().process_frame
	_assert(_ui._backtrack_dialog == null, "U3e: 弹窗已关闭")

	# ══ 测试3：日影舞目标选择弹窗（4段） ══
	var targets: Array[int] = [1, 2]  # 目标：鸣人(1)、佐助(2)
	gm.hiroari_targets_required.emit(0, targets)
	await get_tree().process_frame
	_assert(_ui._hiroari_dialog != null, "U4a: 日影舞弹窗已创建（第1段）")
	if _ui._hiroari_dialog:
		var btn_texts3: Array[String] = []
		_for_each_button(_ui._hiroari_dialog, func(b: Button): btn_texts3.append(b.text))
		_assert(btn_texts3.any(func(t: String): return t.contains("鸣人")), "U4b: 鸣人按钮存在（%s）" % str(btn_texts3))
		_assert(btn_texts3.any(func(t: String): return t.contains("佐助")), "U4c: 佐助按钮存在（%s）" % str(btn_texts3))
		_assert(btn_texts3.any(func(t: String): return t.contains("跳过")), "U4d: 跳过按钮存在（%s）" % str(btn_texts3))

	# 依次点击：鸣人、鸣人、跳过、佐助（验证闭包捕获与段推进）
	# 点击第1段"鸣人"按钮 → 应追加 target=1
	_click_button(_ui._hiroari_dialog, "鸣人")
	await get_tree().process_frame
	_assert(_ui._hiroari_ctx.get("picks", []).size() == 1 and _ui._hiroari_ctx["picks"][0] == 1, "U5a: 第1段点击鸣人 → picks=[1]（实际=%s）" % str(_ui._hiroari_ctx.get("picks", [])))
	# 点击第2段"鸣人"按钮（弹窗已重建）
	_assert(_ui._hiroari_dialog != null, "U5b: 第2段弹窗已重建")
	_click_button(_ui._hiroari_dialog, "鸣人")
	await get_tree().process_frame
	_assert(_ui._hiroari_ctx.get("picks", []).size() == 2 and _ui._hiroari_ctx["picks"][1] == 1, "U5c: 第2段点击鸣人 → picks=[1,1]（实际=%s）" % str(_ui._hiroari_ctx.get("picks", [])))
	# 点击第3段"跳过"
	_click_button(_ui._hiroari_dialog, "跳过")
	await get_tree().process_frame
	_assert(_ui._hiroari_ctx.get("picks", []).size() == 3 and _ui._hiroari_ctx["picks"][2] == -1, "U5d: 第3段跳过 → picks=[1,1,-1]（实际=%s）" % str(_ui._hiroari_ctx.get("picks", [])))
	# 第4段点击"佐助"（真实点击：验证捕获与提交链路）
	# 点击前 picks=[1,1,-1]，点击后 picks=[1,1,-1,2] 达4个 → _submit_hiroari() 提交
	# 用成员变量捕获信号闭包（GDScript 闭包对局部变量重新赋值不生效）
	_applied_targets = []
	var on_made := func(pid: int, t: Array[int]): _applied_targets = t.duplicate()
	gm.hiroari_targets_made.connect(on_made)
	var clicked := _click_button(_ui._hiroari_dialog, "佐助")
	_assert(clicked, "U5e1: 第4段点击佐助成功")
	await get_tree().process_frame
	gm.hiroari_targets_made.disconnect(on_made)
	var applied: Array = _applied_targets
	_assert(applied.size() == 4 and applied[3] == 2, "U5e: 提交目标=[1,1,-1,2]（实际=%s）" % str(applied))
	_assert(_ui._hiroari_dialog == null, "U5f: 4段选择完毕弹窗已关闭")

	print("=== UI弹窗冒烟测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _for_each_button(node: Node, cb: Callable) -> void:
	for c in node.get_children():
		if c is Button:
			cb.call(c)
		_for_each_button(c, cb)

func _click_button(root: Node, text_part: String) -> bool:
	var btn := _find_button(root, text_part)
	if btn == null:
		return false
	btn.pressed.emit()
	return true

func _find_button(node: Node, text_part: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text.contains(text_part):
			return c
		var found := _find_button(c, text_part)
		if found != null:
			return found
	return null

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)