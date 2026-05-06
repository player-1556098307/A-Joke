## 设置场景 — 完全由代码构建UI，管理出拳倒计时/AI速度/动画速度/全屏等设置
## 通过 SettingsManager 自动加载持久化存储为 user://settings.cfg
extends Control

# ── Node refs ─────────────────────────────────────────────────────────────────
var _btn30:        Button
var _btn60:        Button
var _btn90:        Button
var _btn_infinite: Button
var _btn_custom:   Button
var _custom_input: HBoxContainer
var _spinbox:      SpinBox
var _btn_fast:     Button
var _btn_medium:   Button
var _btn_slow:     Button
var _anim_slider:       HSlider
var _anim_value_label:  Label
var _btn_fullscreen:    Button

var _timeout_btns: Array[Button] = []
var _speed_btns:   Array[Button] = []

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_ui()
	_load_ui_from_settings()

# ── UI Construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color("#FFFDF5")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Top bar background
	var topbar_bg := ColorRect.new()
	topbar_bg.color = Color("#2C2C2A")
	topbar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	topbar_bg.anchor_right = 1.0
	topbar_bg.offset_bottom = 44.0
	add_child(topbar_bg)

	# Top bar row
	var topbar := HBoxContainer.new()
	topbar.anchor_right = 1.0
	topbar.offset_bottom = 44.0
	topbar.add_theme_constant_override("separation", 0)
	add_child(topbar)

	var btn_back := Button.new()
	btn_back.text = "← 返回"
	btn_back.focus_mode = Control.FOCUS_NONE
	btn_back.custom_minimum_size = Vector2(100, 44)
	btn_back.add_theme_font_size_override("font_size", 13)
	btn_back.add_theme_color_override("font_color",       Color("#FAC775"))
	btn_back.add_theme_color_override("font_hover_color", Color("#FFFDF5"))
	btn_back.add_theme_stylebox_override("normal",  _make_flat(Color(0,0,0,0),    Color(0,0,0,0), 0, 0))
	btn_back.add_theme_stylebox_override("hover",   _make_flat(Color(1,1,1,0.08), Color(0,0,0,0), 0, 0))
	btn_back.add_theme_stylebox_override("pressed", _make_flat(Color(1,1,1,0.05), Color(0,0,0,0), 0, 0))
	btn_back.pressed.connect(_on_back_pressed)
	topbar.add_child(btn_back)

	var title_lbl := Label.new()
	title_lbl.text = "⚙ 设置"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color("#FAC775"))
	topbar.add_child(title_lbl)

	# Spacer mirrors back button for symmetric centering
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(100, 44)
	topbar.add_child(spacer)

	# Scrollable content area (640px centered)
	var scroll := ScrollContainer.new()
	scroll.offset_left   = 160.0
	scroll.offset_top    = 52.0
	scroll.offset_right  = 800.0
	scroll.offset_bottom = 532.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	# ── Gameplay ──────────────────────────────────────────────────────────────
	content.add_child(_make_section_title("游戏玩法"))
	content.add_child(_make_spacer(4))

	# Row: timeout
	var row_timeout := _make_row("出拳倒计时")
	var preset_right := VBoxContainer.new()
	preset_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_right.add_theme_constant_override("separation", 6)

	var preset_box := HBoxContainer.new()
	preset_box.add_theme_constant_override("separation", 6)

	_btn30        = _make_preset_btn("30s")
	_btn60        = _make_preset_btn("60s")
	_btn90        = _make_preset_btn("90s")
	_btn_infinite = _make_preset_btn("无限")
	_btn_custom   = _make_preset_btn("自定义")
	_timeout_btns = [_btn30, _btn60, _btn90, _btn_infinite, _btn_custom]

	_btn30.pressed.connect(       func(): _on_preset_timeout(30, _btn30))
	_btn60.pressed.connect(       func(): _on_preset_timeout(60, _btn60))
	_btn90.pressed.connect(       func(): _on_preset_timeout(90, _btn90))
	_btn_infinite.pressed.connect(func(): _on_preset_timeout(0,  _btn_infinite))
	_btn_custom.pressed.connect(  _on_custom_timeout_pressed)

	for b in _timeout_btns:
		preset_box.add_child(b)

	_custom_input = HBoxContainer.new()
	_custom_input.add_theme_constant_override("separation", 4)
	_custom_input.visible = false

	_spinbox = SpinBox.new()
	_spinbox.min_value = 0
	_spinbox.max_value = 999
	_spinbox.step = 1
	_spinbox.value = 60
	_spinbox.custom_minimum_size = Vector2(88, 34)
	_spinbox.value_changed.connect(_on_spinbox_value_changed)

	var unit_lbl := Label.new()
	unit_lbl.text = "秒"
	unit_lbl.add_theme_font_size_override("font_size", 13)
	unit_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	unit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_custom_input.add_child(_spinbox)
	_custom_input.add_child(unit_lbl)

	preset_right.add_child(preset_box)
	preset_right.add_child(_custom_input)
	row_timeout.add_child(preset_right)
	content.add_child(row_timeout)

	# Row: AI speed
	var row_ai := _make_row("AI 决策速度")
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 6)
	_btn_fast   = _make_preset_btn("快")
	_btn_medium = _make_preset_btn("中")
	_btn_slow   = _make_preset_btn("慢")
	_speed_btns = [_btn_fast, _btn_medium, _btn_slow]
	_btn_fast.pressed.connect(  func(): _on_ai_speed("fast",   _btn_fast))
	_btn_medium.pressed.connect(func(): _on_ai_speed("medium", _btn_medium))
	_btn_slow.pressed.connect(  func(): _on_ai_speed("slow",   _btn_slow))
	for b in _speed_btns:
		speed_box.add_child(b)
	row_ai.add_child(speed_box)
	content.add_child(row_ai)

	# Row: animation speed
	var row_anim := _make_row("动画速度")
	_anim_slider = HSlider.new()
	_anim_slider.min_value = 0.1
	_anim_slider.max_value = 10.0
	_anim_slider.step = 0.1
	_anim_slider.value = 1.0
	_anim_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_slider.custom_minimum_size = Vector2(0, 28)
	_style_slider(_anim_slider)
	_anim_slider.value_changed.connect(_on_anim_slider_changed)

	_anim_value_label = Label.new()
	_anim_value_label.text = "1.0×"
	_anim_value_label.custom_minimum_size = Vector2(48, 0)
	_anim_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_anim_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_anim_value_label.add_theme_font_size_override("font_size", 13)
	_anim_value_label.add_theme_color_override("font_color", Color("#FAC775"))
	row_anim.add_child(_anim_slider)
	row_anim.add_child(_anim_value_label)
	content.add_child(row_anim)

	# ── Display ───────────────────────────────────────────────────────────────
	content.add_child(_make_spacer(8))
	content.add_child(_make_divider())
	content.add_child(_make_spacer(8))
	content.add_child(_make_section_title("显示"))
	content.add_child(_make_spacer(4))

	var row_fs := _make_row("全屏模式")
	_btn_fullscreen = Button.new()
	_btn_fullscreen.focus_mode = Control.FOCUS_NONE
	_btn_fullscreen.custom_minimum_size = Vector2(160, 36)
	_btn_fullscreen.add_theme_font_size_override("font_size", 13)
	_btn_fullscreen.pressed.connect(_on_fullscreen_pressed)
	row_fs.add_child(_btn_fullscreen)
	content.add_child(row_fs)

	# ── Audio (disabled placeholder) ──────────────────────────────────────────
	content.add_child(_make_spacer(8))
	content.add_child(_make_divider())
	content.add_child(_make_spacer(8))

	var audio_box := VBoxContainer.new()
	audio_box.modulate = Color(1, 1, 1, 0.4)
	audio_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	audio_box.add_theme_constant_override("separation", 4)
	audio_box.add_child(_make_section_title("音效（即将推出）"))
	audio_box.add_child(_make_spacer(4))

	var row_sfx := _make_row("音效")
	row_sfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sfx_btn := _make_preset_btn("开")
	sfx_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sfx_btn.disabled = true
	row_sfx.add_child(sfx_btn)
	audio_box.add_child(row_sfx)

	var row_bgm := _make_row("音乐")
	row_bgm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bgm_btn := _make_preset_btn("开")
	bgm_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgm_btn.disabled = true
	row_bgm.add_child(bgm_btn)
	audio_box.add_child(row_bgm)

	content.add_child(audio_box)

	# ── Reset button ──────────────────────────────────────────────────────────
	content.add_child(_make_spacer(16))

	var reset_row := HBoxContainer.new()
	reset_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn_reset := Button.new()
	btn_reset.text = "恢复默认设置"
	btn_reset.focus_mode = Control.FOCUS_NONE
	btn_reset.custom_minimum_size = Vector2(160, 36)
	btn_reset.add_theme_font_size_override("font_size", 13)
	btn_reset.add_theme_stylebox_override("normal",  _make_flat(Color("#F1EFE8"), Color("#D3D1C7"), 1, 6))
	btn_reset.add_theme_stylebox_override("hover",   _make_flat(Color("#E8E6DF"), Color("#D3D1C7"), 1, 6))
	btn_reset.add_theme_stylebox_override("pressed", _make_flat(Color("#DDD9D0"), Color("#D3D1C7"), 1, 6))
	btn_reset.add_theme_color_override("font_color", Color("#5F5E5A"))
	btn_reset.pressed.connect(_on_reset_pressed)
	reset_row.add_child(btn_reset)
	content.add_child(reset_row)
	content.add_child(_make_spacer(16))

# ── Load current settings into UI ─────────────────────────────────────────────
func _load_ui_from_settings() -> void:
	var t := SettingsManager.gesture_timeout
	match t:
		30: _select_timeout_preset(_btn30)
		60: _select_timeout_preset(_btn60)
		90: _select_timeout_preset(_btn90)
		0:  _select_timeout_preset(_btn_infinite)
		_:
			_select_timeout_preset(_btn_custom)
			_custom_input.visible = true
			_spinbox.value = t

	match SettingsManager.ai_speed:
		"fast":   _select_speed(_btn_fast)
		"medium": _select_speed(_btn_medium)
		"slow":   _select_speed(_btn_slow)

	_anim_slider.value = SettingsManager.anim_speed
	_anim_value_label.text = "%.1f×" % SettingsManager.anim_speed

	_update_fullscreen_button()

# ── Handlers ──────────────────────────────────────────────────────────────────
func _on_preset_timeout(value: int, btn: Button) -> void:
	SettingsManager.gesture_timeout = value
	_custom_input.visible = false
	_select_timeout_preset(btn)
	SettingsManager.save_settings()

func _on_custom_timeout_pressed() -> void:
	_custom_input.visible = true
	_select_timeout_preset(_btn_custom)

func _on_spinbox_value_changed(value: float) -> void:
	SettingsManager.gesture_timeout = int(value)
	SettingsManager.save_settings()

func _on_ai_speed(speed: String, btn: Button) -> void:
	SettingsManager.ai_speed = speed
	_select_speed(btn)
	SettingsManager.save_settings()

func _on_anim_slider_changed(value: float) -> void:
	SettingsManager.anim_speed = value
	_anim_value_label.text = "%.1f×" % value
	Engine.time_scale = value
	SettingsManager.save_settings()

func _on_fullscreen_pressed() -> void:
	SettingsManager.fullscreen = not SettingsManager.fullscreen
	SettingsManager.apply_fullscreen()
	_update_fullscreen_button()
	SettingsManager.save_settings()

func _on_reset_pressed() -> void:
	SettingsManager.gesture_timeout = SettingsManager.DEFAULT_GESTURE_TIMEOUT
	SettingsManager.ai_speed        = SettingsManager.DEFAULT_AI_SPEED
	SettingsManager.anim_speed      = SettingsManager.DEFAULT_ANIM_SPEED
	SettingsManager.fullscreen      = SettingsManager.DEFAULT_FULLSCREEN
	SettingsManager.apply_fullscreen()
	SettingsManager.save_settings()
	Engine.time_scale = 1.0
	_load_ui_from_settings()

func _on_back_pressed() -> void:
	SceneManager.go_to("res://scenes/main_menu.tscn")

# ── Helpers ───────────────────────────────────────────────────────────────────
func _update_fullscreen_button() -> void:
	if SettingsManager.fullscreen:
		_btn_fullscreen.text = "✓ 全屏模式"
		_btn_fullscreen.add_theme_stylebox_override("normal",  _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 2, 6))
		_btn_fullscreen.add_theme_stylebox_override("hover",   _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 2, 6))
		_btn_fullscreen.add_theme_stylebox_override("pressed", _make_flat(Color("#27500A"), Color("#2C2C2A"), 2, 6))
		_btn_fullscreen.add_theme_color_override("font_color", Color("#EAF3DE"))
	else:
		_btn_fullscreen.text = "窗口模式"
		_btn_fullscreen.add_theme_stylebox_override("normal",  _make_flat(Color("#E6F1FB"), Color("#185FA5"), 2, 6))
		_btn_fullscreen.add_theme_stylebox_override("hover",   _make_flat(Color("#CCE4F9"), Color("#185FA5"), 2, 6))
		_btn_fullscreen.add_theme_stylebox_override("pressed", _make_flat(Color("#B5D4F4"), Color("#185FA5"), 2, 6))
		_btn_fullscreen.add_theme_color_override("font_color", Color("#0C447C"))

func _select_timeout_preset(btn: Button) -> void:
	for b in _timeout_btns:
		_apply_unselected(b)
	_apply_selected(btn)

func _select_speed(btn: Button) -> void:
	for b in _speed_btns:
		_apply_unselected(b)
	_apply_selected(btn)

func _apply_selected(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",  _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 2, 6))
	btn.add_theme_stylebox_override("hover",   _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 2, 6))
	btn.add_theme_stylebox_override("pressed", _make_flat(Color("#27500A"), Color("#2C2C2A"), 2, 6))
	btn.add_theme_color_override("font_color", Color("#EAF3DE"))

func _apply_unselected(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal",  _make_flat(Color("#F1EFE8"), Color("#D3D1C7"), 2, 6))
	btn.add_theme_stylebox_override("hover",   _make_flat(Color("#E8E6DF"), Color("#D3D1C7"), 2, 6))
	btn.add_theme_stylebox_override("pressed", _make_flat(Color("#DDD9D0"), Color("#D3D1C7"), 2, 6))
	btn.add_theme_color_override("font_color", Color("#5F5E5A"))

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

func _make_section_title(text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.add_theme_constant_override("separation", 0)

	var bar := ColorRect.new()
	bar.color = Color("#FAC775")
	bar.custom_minimum_size = Vector2(4, 0)
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color("#888780"))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(lbl)
	row.add_child(margin)
	return row

func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 44)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(112, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	return row

func _make_preset_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(72, 36)
	btn.add_theme_font_size_override("font_size", 13)
	_apply_unselected(btn)
	return btn

func _make_divider() -> HSeparator:
	return HSeparator.new()

func _make_spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _style_slider(slider: HSlider) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#D3D1C7")
	bg.set_corner_radius_all(3)
	bg.content_margin_top    = 3
	bg.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#3B6D11")
	fill.set_corner_radius_all(3)
	fill.content_margin_top    = 3
	fill.content_margin_bottom = 3
	slider.add_theme_stylebox_override("grabber_area",           fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
