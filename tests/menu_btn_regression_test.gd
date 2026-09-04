## 对局菜单按钮 + 场景布局回归测试
## 验证：1) menu_btn 存在且可被点击（无遮挡）2) 点击后弹窗出现且按钮可点 3) 关键面板布局正常
extends Node

var _pass_count: int = 0
var _fail_count: int = 0
var _ui: Control = null
var _btn_found: Button = null

func _ready() -> void:
	print("=== menu_btn/layout regression test ===")
	await get_tree().process_frame

	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if sasuke_char == null or naruto_char == null:
		print("FATAL: character resources load failed")
		get_tree().quit(1)
		return

	GameManager.setup_game({
		"players": [
			{"name": "佐助", "character": sasuke_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": false},
		]
	})
	await get_tree().process_frame

	_ui = (load("res://scenes/game_ui.tscn") as PackedScene).instantiate()
	add_child(_ui)
	await get_tree().process_frame
	await get_tree().process_frame

	# ── T1: menu_btn 存在 ──
	var menu_btn := _ui.get_node_or_null("MenuButton") as Button
	_assert(menu_btn != null, "T1: menu_btn exists")
	if menu_btn == null:
		_finish(); return

	# ── T2: menu_btn 无遮挡（点击测试点能命中自己）──
	var btn_rect := menu_btn.get_global_rect()
	var test_pos := btn_rect.get_center()
	var hit := _ui.get_global_rect().encloses(btn_rect)
	_assert(hit, "T2a: menu_btn inside viewport, rect=%s" % [btn_rect])
	var topmost := _find_topmost_at(_ui, test_pos)
	_assert(topmost == menu_btn, "T2b: menu_btn is topmost at its center (got %s)" % [topmost.name if topmost else "null"])

	# ── T3: 点击 menu_btn 后弹窗出现且可交互 ──
	menu_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var confirm_btn := _find_button_by_text(_ui, "确定返回")
	_assert(confirm_btn != null, "T3a: confirm dialog shown after menu btn pressed")
	var stay_btn := _find_button_by_text(_ui, "继续游戏")
	_assert(stay_btn != null, "T3b: stay btn shown")
	if stay_btn:
		stay_btn.pressed.emit()
		await get_tree().process_frame
		confirm_btn = _find_button_by_text(_ui, "确定返回")
		_assert(confirm_btn == null, "T3c: dialog closed after stay btn")

	# ── T4: 弹窗面板在视口内（居中）──
	menu_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var dlg_panel := _find_last_panel_container(_ui)
	if dlg_panel:
		var pr := dlg_panel.get_global_rect()
		var vp := get_viewport().get_visible_rect()
		_assert(vp.encloses(pr), "T4: menu dialog inside viewport (%s in %s)" % [pr, vp])
	else:
		_assert(false, "T4: dialog panel not found")

	# ── T5: 右列三面板在视口内 ──
	for panel_name in ["GesturePanel", "ActionPanel", "TargetPanel"]:
		var p := _ui.get_node_or_null(panel_name) as Control
		if p == null:
			_assert(false, "T5: %s missing" % panel_name)
			continue
		var r := p.get_global_rect()
		var vp := get_viewport().get_visible_rect()
		_assert(vp.encloses(r), "T5: %s rect %s inside viewport %s" % [panel_name, r, vp])

	_finish()

## ── helpers ──

func _find_button_by_text(root: Node, txt: String) -> Button:
	_btn_found = null
	_walk_buttons_match(root, txt)
	return _btn_found

func _walk_buttons_match(node: Node, txt: String) -> void:
	if node is Button and (node as Button).text == txt and _btn_found == null:
		_btn_found = node
		return
	for child in node.get_children():
		_walk_buttons_match(child, txt)

func _find_last_panel_container(root: Node) -> PanelContainer:
	var found: PanelContainer = null
	for c in root.get_children():
		if c is PanelContainer:
			found = c
	return found

func _find_topmost_at(root: Control, pos: Vector2) -> Control:
	# 模拟 Godot 输入传递：后 add_child 的兄弟先命中（场景树逆序）
	var stack: Array = [root]
	var topmost: Control = null
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Control:
			var c := node as Control
			if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
				if topmost == null or node.get_index() > topmost.get_index() or node.get_path_to(topmost).get_name_count() > 0:
					topmost = c
		for child in node.get_children():
			stack.push_back(child)
	return topmost

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: %s" % msg)
	else:
		_fail_count += 1
		print("FAIL: %s" % msg)

func _finish() -> void:
	print("RESULT: PASS=%d FAIL=%d" % [_pass_count, _fail_count])
	get_tree().quit(1 if _fail_count > 0 else 0)
