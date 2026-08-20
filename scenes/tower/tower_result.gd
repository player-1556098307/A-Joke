## TowerResult — 慈悲尖塔通关/失败结算界面
## 从 SceneManager.pending_game_result 读取结果，展示结算信息
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

	var is_victory: bool = _result.get("tower_victory", false)
	var is_defeat: bool = _result.get("tower_defeat", false)

	if is_victory:
		_build_victory_ui()
	elif is_defeat:
		_build_defeat_ui()
	else:
		# 未知状态，回主菜单
		SceneManager.go_to("res://scenes/main_menu.tscn")

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
	add_child(title)

	# 副标题
	var subtitle := Label.new()
	subtitle.text = "你是第一百零七人中，第一个走出来的人"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.anchor_left = 0.0; subtitle.anchor_right = 1.0
	subtitle.offset_top = 108.0; subtitle.offset_bottom = 130.0
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)

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
	add_child(panel)

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

	# 按钮
	_add_buttons(true)

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
	add_child(title)

	# 失败信息
	var info := Label.new()
	info.text = "你在第 %d 层倒下" % failed_floor
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_color_override("font_color", C_TEXT)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.anchor_left = 0.0; info.anchor_right = 1.0
	info.offset_top = 150.0; info.offset_bottom = 175.0
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)

	# 敌人信息面板
	var panel := Panel.new()
	panel.anchor_left = 0.2; panel.anchor_right = 0.8
	panel.offset_top = 200.0; panel.offset_bottom = 300.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL_BG; ps.border_color = C_BORDER
	ps.set_border_width_all(2); ps.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)

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
	quote.offset_top = 370.0; quote.offset_bottom = 400.0
	quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quote)

	# 按钮
	_add_buttons(false)

## ============== 通用组件 ==============

func _add_divider(y: float) -> void:
	var line := HSeparator.new()
	line.anchor_left = 0.3; line.anchor_right = 0.7
	line.offset_top = y; line.offset_bottom = y + 2.0
	add_child(line)

func _add_stat_line(label_text: String, value_text: String, y: float) -> void:
	var hbox := HBoxContainer.new()
	hbox.anchor_left = 0.3; hbox.anchor_right = 0.7
	hbox.offset_top = y; hbox.offset_bottom = y + 28.0
	hbox.add_theme_constant_override("separation", 16)
	add_child(hbox)

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

func _add_buttons(is_victory: bool) -> void:
	var btn_y := 440.0

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
		add_child(main_btn)
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
		add_child(retry_btn)

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
		add_child(main_btn)

func _make_flat(bg: Color, bdr: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = bdr
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s
