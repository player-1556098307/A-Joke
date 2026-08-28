## TowerResult — 慈悲尖塔通关/失败结算界面
## 从 SceneManager.pending_game_result 读取结果，展示结算信息
## 内容超出屏幕时自动滚动（确保按钮始终可达）
extends Control

## ---- 配色 ----
const C_BG       := Color("#12100D")
const C_PANEL_BG := Color("#1C1915")
const C_BORDER   := Color("#3A342A")
const C_GOLD     := Color("#FAC775")
const C_TEXT     := Color("#E8E2D5")
const C_TEXT_DIM := Color("#9A9182")
const C_RED      := Color("#E24B4A")
const C_GREEN    := Color("#3B6D11")

var _result: Dictionary = {}
## 滚动内容容器：所有 UI 元素挂在此节点下，内容超高时自动滚动
var _content: Control

func _ready() -> void:
	_result = SceneManager.pending_game_result
	_build_ui()

func _build_ui() -> void:
	# 全屏暗色背景
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

	# 滚动容器：内容超过屏幕高度时自动滚动
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)

	# 内容容器：承载所有 UI 元素，宽度固定 960，高度随内容增长
	_content = Control.new()
	_content.custom_minimum_size = Vector2(960, 0)
	_content.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.add_child(_content)

	var is_victory: bool = _result.get("tower_victory", false)
	var is_defeat: bool = _result.get("tower_defeat", false)

	if is_victory:
		_build_victory_ui()
	elif is_defeat:
		_build_defeat_ui()
	else:
		# 未知状态，回主菜单
		SceneManager.go_to("res://scenes/main_menu.tscn")

## 添加顶层元素到内容容器（替代直接 add_child）
func _add(node: Control) -> void:
	_content.add_child(node)

## 构建完成后设置内容容器高度（确保滚动区域正确）
func _finalize_content_height(last_y: float) -> void:
	_content.custom_minimum_size = Vector2(960, last_y + 10.0)

## ============== 通关结算 ==============
func _build_victory_ui() -> void:
	var floors_cleared: int = _result.get("floors_cleared", 3)
	var death_count: int = SceneManager.tower_death_count

	# 标题：尖塔征服
	var title := Label.new()
	title.text = "尖 塔 征 服"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.offset_top = 60.0; title.offset_bottom = 100.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = "你是第一百零七人中，第一个走出来的人"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0; subtitle.anchor_right = 1.0
	subtitle.offset_top = 108.0; subtitle.offset_bottom = 130.0
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(subtitle)

	# 分割线装饰
	_add_divider(145.0)

	# 层级清单面板
	var panel := Panel.new()
	panel.anchor_left = 0.15; panel.anchor_right = 0.85
	panel.offset_top = 160.0; panel.offset_bottom = 340.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL_BG; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	_add(panel)

	var enemy_names := ["破败王者（怒）", "漩涡鸣人（仙人模式）", "司马懿（狂）"]
	var y_offset := 20.0
	for i in range(min(floors_cleared, 3)):
		var line := HBoxContainer.new()
		line.anchor_left = 0.05; line.anchor_right = 0.95
		line.offset_top = y_offset; line.offset_bottom = y_offset + 40.0
		line.add_theme_constant_override("separation", 12)
		panel.add_child(line)

		# 勾选标记
		var check := Label.new()
		check.text = "✓"
		check.add_theme_font_size_override("font_size", 18)
		check.add_theme_color_override("font_color", C_GREEN)
		check.custom_minimum_size = Vector2(30, 0)
		check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(check)

		# 层号
		var fl := Label.new()
		fl.text = "第%d层" % (i + 1)
		fl.add_theme_font_size_override("font_size", 14)
		fl.add_theme_color_override("font_color", C_TEXT_DIM)
		fl.custom_minimum_size = Vector2(80, 0)
		fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(fl)

		# 敌人名
		var en := Label.new()
		en.text = enemy_names[i] if i < enemy_names.size() else "???"
		en.add_theme_font_size_override("font_size", 14)
		en.add_theme_color_override("font_color", C_TEXT)
		en.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(en)

		y_offset += 52.0

	# 统计信息
	var stats_y := 360.0
	_add_stat_line("通关层数", "%d / %d" % [floors_cleared, 3], stats_y)
	_add_stat_line("累计死亡", "%d 次" % death_count, stats_y + 32.0)

	# 战报统计面板
	var after_stats := _build_tower_stats_panel(stats_y + 70.0)

	# 按钮
	var btn_bottom := _add_buttons(true, after_stats + 15.0)

	# 设置内容高度（确保滚动区域覆盖所有元素+按钮）
	_finalize_content_height(btn_bottom)

## ============== 失败结算 ==============
func _build_defeat_ui() -> void:
	var failed_floor: int = _result.get("failed_floor", 1)
	var enemy_name: String = _result.get("enemy_name", "???")
	var death_count: int = SceneManager.tower_death_count

	# 标题：坠落
	var title := Label.new()
	title.text = "坠  落"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", C_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.offset_top = 80.0; title.offset_bottom = 130.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(title)

	# 失败信息
	var info := Label.new()
	info.text = "你在第 %d 层倒下" % failed_floor
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", C_TEXT)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.anchor_left = 0.0; info.anchor_right = 1.0
	info.offset_top = 150.0; info.offset_bottom = 175.0
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(info)

	# 敌人信息面板
	var panel := Panel.new()
	panel.anchor_left = 0.2; panel.anchor_right = 0.8
	panel.offset_top = 200.0; panel.offset_bottom = 300.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL_BG; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	_add(panel)

	var enemy_lbl := Label.new()
	enemy_lbl.text = "守层者：%s" % enemy_name
	enemy_lbl.add_theme_font_size_override("font_size", 14)
	enemy_lbl.add_theme_color_override("font_color", C_GOLD)
	enemy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	enemy_lbl.anchor_left = 0.0; enemy_lbl.anchor_right = 1.0
	enemy_lbl.anchor_top = 0.0; enemy_lbl.anchor_bottom = 1.0
	enemy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(enemy_lbl)

	# 统计
	_add_stat_line("累计死亡", "%d 次" % death_count, 320.0)

	# 战报统计面板
	var after_stats := _build_tower_stats_panel(350.0)

	# 梅塔特隆的话
	var quote := Label.new()
	var quotes := [
		"塔会记住你怕什么。你越怕，它越往下长。",
		"每个死人都说下次能行。",
		"你欠这塔的次数，还没还清。",
	]
	quote.text = quotes[death_count % quotes.size()]
	quote.add_theme_font_size_override("font_size", 12)
	quote.add_theme_color_override("font_color", C_TEXT_DIM)
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.anchor_left = 0.1; quote.anchor_right = 0.9
	quote.offset_top = after_stats + 5.0; quote.offset_bottom = after_stats + 30.0
	quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(quote)

	# 按钮
	var btn_bottom := _add_buttons(false, after_stats + 45.0)

	_finalize_content_height(btn_bottom)

## ============== 通用组件 ==============

func _add_divider(y: float) -> void:
	var line := HSeparator.new()
	line.anchor_left = 0.3; line.anchor_right = 0.7
	line.offset_top = y; line.offset_bottom = y + 2.0
	_add(line)

func _add_stat_line(label_text: String, value_text: String, y: float) -> void:
	var hbox := HBoxContainer.new()
	hbox.anchor_left = 0.3; hbox.anchor_right = 0.7
	hbox.offset_top = y; hbox.offset_bottom = y + 28.0
	hbox.add_theme_constant_override("separation", 16)
	_add(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", C_TEXT)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val)

## 添加按钮，返回按钮底部的 Y 坐标（用于计算内容高度）
func _add_buttons(is_victory: bool, btn_y: float = 440.0) -> float:

	# 再战按钮（失败）或 返回主菜单（通关）
	if is_victory:
		var main_btn := Button.new()
		main_btn.text = "返回主菜单"
		main_btn.focus_mode = Control.FOCUS_NONE
		main_btn.custom_minimum_size = Vector2(160, 40)
		main_btn.add_theme_font_size_override("font_size", 14)
		main_btn.anchor_left = 0.5; main_btn.anchor_right = 0.5
		main_btn.offset_left = -80.0; main_btn.offset_right = 80.0
		main_btn.offset_top = btn_y; main_btn.offset_bottom = btn_y + 40.0
		main_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A5A3A"), C_BORDER, 2, 8))
		main_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3B6D11"), C_BORDER, 2, 8))
		main_btn.add_theme_color_override("font_color", C_TEXT)
		main_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
		_add(main_btn)
	else:
		# 再战按钮
		var retry_btn := Button.new()
		retry_btn.text = "再  战"
		retry_btn.focus_mode = Control.FOCUS_NONE
		retry_btn.custom_minimum_size = Vector2(140, 40)
		retry_btn.add_theme_font_size_override("font_size", 14)
		retry_btn.anchor_left = 0.5; retry_btn.anchor_right = 0.5
		retry_btn.offset_left = -150.0; retry_btn.offset_right = -10.0
		retry_btn.offset_top = btn_y; retry_btn.offset_bottom = btn_y + 40.0
		retry_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A5A3A"), C_BORDER, 2, 8))
		retry_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3B6D11"), C_BORDER, 2, 8))
		retry_btn.add_theme_color_override("font_color", C_TEXT)
		retry_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/tower/tower_select.tscn"))
		_add(retry_btn)

		# 主菜单按钮
		var main_btn := Button.new()
		main_btn.text = "主菜单"
		main_btn.focus_mode = Control.FOCUS_NONE
		main_btn.custom_minimum_size = Vector2(140, 40)
		main_btn.add_theme_font_size_override("font_size", 14)
		main_btn.anchor_left = 0.5; main_btn.anchor_right = 0.5
		main_btn.offset_left = 10.0; main_btn.offset_right = 150.0
		main_btn.offset_top = btn_y; main_btn.offset_bottom = btn_y + 40.0
		main_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A2A28"), C_BORDER, 2, 8))
		main_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3A342A"), C_BORDER, 2, 8))
		main_btn.add_theme_color_override("font_color", C_TEXT_DIM)
		main_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
		_add(main_btn)

	return btn_y + 40.0

func _make_flat(bg: Color, bdr: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = bdr
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s

## ============== 战报统计面板 ==============

## 构建战报统计面板：展示我方每个角色的跨层累积统计
## 返回面板底部的 y 坐标
func _build_tower_stats_panel(y_start: float) -> float:
	var stats: Array = _result.get("tower_stats", [])
	if stats.is_empty():
		return y_start

	# 面板高度：标题(28) + 表头(24) + 每角色行(24) + 内边距(20)
	var row_h: float = 24.0
	var panel_h: float = 28.0 + 24.0 + stats.size() * row_h + 20.0

	var panel := Panel.new()
	panel.anchor_left = 0.1; panel.anchor_right = 0.9
	panel.offset_top = y_start; panel.offset_bottom = y_start + panel_h
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL_BG; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(panel)

	# 标题
	var title := Label.new()
	title.text = "战 报"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.offset_top = 6.0; title.offset_bottom = 26.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	# 列定义：角色名 | 猜拳胜 | 造成伤害 | 承受伤害 | 抵挡伤害 | 恢复血量
	var col_labels := ["角色", "猜拳胜", "造成伤害", "承受伤害", "抵挡伤害", "恢复血量"]
	var col_weights := [3.0, 2.0, 2.5, 2.5, 2.5, 2.5]
	var total_weight: float = 0.0
	for w in col_weights:
		total_weight += w

	var panel_w: float = 960.0 * 0.8  # anchor 0.1~0.9 = 80% of 960
	var col_widths: Array[float] = []
	for w in col_weights:
		col_widths.append(panel_w * w / total_weight)

	# 表头行
	var header_y: float = 30.0
	var x_cursor: float = 0.0
	for i in range(col_labels.size()):
		var hdr := Label.new()
		hdr.text = col_labels[i]
		hdr.add_theme_font_size_override("font_size", 11)
		hdr.add_theme_color_override("font_color", C_TEXT_DIM)
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hdr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hdr.anchor_left = x_cursor / panel_w
		hdr.anchor_right = (x_cursor + col_widths[i]) / panel_w
		hdr.offset_top = header_y; hdr.offset_bottom = header_y + row_h
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(hdr)
		x_cursor += col_widths[i]

	# 分隔线
	var sep := ColorRect.new()
	sep.color = Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.5)
	sep.anchor_left = 0.05; sep.anchor_right = 0.95
	sep.offset_top = header_y + row_h; sep.offset_bottom = header_y + row_h + 1.0
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sep)

	# 每个角色一行
	for row_idx in range(stats.size()):
		var s: Dictionary = stats[row_idx]
		var row_y: float = header_y + row_h + 3.0 + row_idx * row_h
		x_cursor = 0.0
		var values := [
			s.get("char_name", "???"),
			"%d" % int(s.get("win_count", 0)),
			"%.0f" % float(s.get("damage_dealt", 0)),
			"%.0f" % float(s.get("damage_taken", 0)),
			"%.0f" % float(s.get("damage_blocked", 0)),
			"%.0f" % float(s.get("healing", 0)),
		]
		for i in range(values.size()):
			var cell := Label.new()
			cell.text = str(values[i])
			cell.add_theme_font_size_override("font_size", 11)
			# 角色名列用金色，数值列用白色
			if i == 0:
				cell.add_theme_color_override("font_color", C_GOLD)
			else:
				cell.add_theme_color_override("font_color", C_TEXT)
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.anchor_left = x_cursor / panel_w
			cell.anchor_right = (x_cursor + col_widths[i]) / panel_w
			cell.offset_top = row_y; cell.offset_bottom = row_y + row_h
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(cell)
			x_cursor += col_widths[i]

	return y_start + panel_h
