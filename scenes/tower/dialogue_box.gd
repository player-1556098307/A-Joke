## DialogueBox — 通用剧情对话控件
## 可内嵌到任何场景中，支持：打字机效果、分支选项、多角色头像、旁白模式
## 用法：add_child(DialogueBox.new()) → start(dialogue_data) → 连接 dialogue_finished 信号
class_name DialogueBox
extends Control

signal dialogue_finished
signal line_shown(speaker: String, text: String, line_index: int)
signal choice_made(choice_index: int)

## ---- 配色（暗黑塔门风格） ----
const C_BG       := Color("#12100D")
const C_PANEL_BG := Color("#1C1915")
const C_BORDER   := Color("#3A342A")
const C_GOLD     := Color("#FAC775")
const C_TEXT     := Color("#E8E2D5")
const C_TEXT_DIM := Color("#9A9182")
const C_CHOICE_HOVER := Color("#3A342A")
const C_CHOICE_NORMAL := Color("#2A2A28")

## ---- 打字机配置 ----
var typewriter_speed: float = 0.04  ## 每字间隔秒数
var _typewriter_timer: float = 0.0
var _typewriter_char_index: int = 0
var _typewriter_full_text: String = ""
var _typewriter_active: bool = false

## ---- 对话数据 ----
var _lines: Array[Dictionary] = []  ## [{speaker, text, portrait, choices}]
var _index: int = -1
var _is_active: bool = false

## ---- UI引用 ----
var _bg: ColorRect
var _name_bar: Panel
var _name_label: Label
var _dialogue_panel: Panel
var _dialogue_label: RichTextLabel
var _hint_label: Label
var _portrait_rect: TextureRect
var _choices_container: VBoxContainer
var _skip_btn: Button

## ---- 选项回调 ----
var _choice_callback: Callable = Callable()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_hide_all()

func _process(delta: float) -> void:
	if not _typewriter_active:
		return
	_typewriter_timer += delta
	while _typewriter_timer >= typewriter_speed and _typewriter_char_index < _typewriter_full_text.length():
		_typewriter_timer -= typewriter_speed
		_typewriter_char_index += 1
		_dialogue_label.visible_characters = _typewriter_char_index
	if _typewriter_char_index >= _typewriter_full_text.length():
		_typewriter_active = false
		_dialogue_label.visible_characters = -1
		_on_line_complete()

# ============================================================
#  公开API
# ============================================================

## 开始对话，dialogue_data 格式：
## { "speaker": "名字", "lines": [
##     { "text": "台词", "speaker": "可选覆盖", "portrait": "可选路径" },
##     { "text": "带选项", "choices": [{ "label": "选项1" }, { "label": "选项2" }] },
##   ]
## }
func start(data: Dictionary) -> void:
	_lines.clear()
	var speaker_name: String = data.get("speaker", "")
	for line_data: Dictionary in data.get("lines", []):
		var entry: Dictionary = {
			"speaker": line_data.get("speaker", speaker_name),
			"text": line_data.get("text", ""),
			"portrait": line_data.get("portrait", ""),
			"choices": line_data.get("choices", []),
		}
		_lines.append(entry)
	if _lines.is_empty():
		dialogue_finished.emit()
		return
	_index = -1
	_is_active = true
	_show_all_ui()
	_advance()

## 带回调的选项选择
func set_choice_callback(cb: Callable) -> void:
	_choice_callback = cb

func is_active() -> bool:
	return _is_active

func force_finish() -> void:
	_typewriter_active = false
	_is_active = false
	_hide_all()
	dialogue_finished.emit()

# ============================================================
#  内部逻辑
# ============================================================

func _advance() -> void:
	if _typewriter_active:
		# 打字机进行中 → 立即显示全文
		_typewriter_active = false
		_dialogue_label.visible_characters = -1
		_on_line_complete()
		return

	_index += 1
	if _index >= _lines.size():
		_is_active = false
		_hide_all()
		dialogue_finished.emit()
		return

	var entry: Dictionary = _lines[_index]
	_show_entry(entry)
	line_shown.emit(entry.get("speaker", ""), entry.get("text", ""), _index)

func _show_entry(entry: Dictionary) -> void:
	var spk: String = entry.get("speaker", "")
	var txt: String = entry.get("text", "")
	var portrait_path: String = entry.get("portrait", "")

	# 名牌
	if spk.is_empty():
		_name_bar.visible = false
	else:
		_name_bar.visible = true
		_name_label.text = spk

	# 头像
	if portrait_path.is_empty():
		_portrait_rect.visible = false
		_dialogue_panel.anchor_left = 0.06
	else:
		var tex: Texture2D = load(portrait_path) as Texture2D
		if tex != null:
			_portrait_rect.texture = tex
			_portrait_rect.visible = true
			_dialogue_panel.anchor_left = 0.22
		else:
			_portrait_rect.visible = false
			_dialogue_panel.anchor_left = 0.06

	# 打字机效果
	_dialogue_label.visible_characters = 0
	_dialogue_label.text = txt
	_typewriter_full_text = txt
	_typewriter_char_index = 0
	_typewriter_timer = 0.0
	_typewriter_active = true

	# 清除旧选项
	_clear_choices()
	_hint_label.visible = true

func _on_line_complete() -> void:
	var entry: Dictionary = _lines[_index]
	var choices: Array = entry.get("choices", [])
	if choices.size() > 0:
		_hint_label.visible = false
		_show_choices(choices)
	else:
		_hint_label.visible = true

func _show_choices(choices: Array) -> void:
	_clear_choices()
	_choices_container.visible = true
	for i in range(choices.size()):
		var choice_data: Dictionary = choices[i]
		var label: String = choice_data.get("label", "...")
		var btn := Button.new()
		btn.text = label
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_GOLD)
		btn.add_theme_stylebox_override("normal", _make_flat(C_CHOICE_NORMAL, C_BORDER, 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(C_CHOICE_HOVER, C_GOLD, 1, 4))
		var idx := i
		btn.pressed.connect(func(): _on_choice_selected(idx, choices))
		_choices_container.add_child(btn)

func _on_choice_selected(idx: int, choices: Array) -> void:
	_clear_choices()
	choice_made.emit(idx)
	if _choice_callback.is_valid():
		_choice_callback.call(idx)
	# 选择后自动推进
	_advance()

func _clear_choices() -> void:
	for child in _choices_container.get_children():
		child.queue_free()
	_choices_container.visible = false

func _input(event: InputEvent) -> void:
	if not _is_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		_advance()
		accept_event()

# ============================================================
#  UI构建
# ============================================================

func _build_ui() -> void:
	# 全屏半透明背景
	_bg = ColorRect.new()
	_bg.color = C_BG
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.show_behind_parent = true
	add_child(_bg)

	# 头像区域（左侧，可选）
	_portrait_rect = TextureRect.new()
	_portrait_rect.visible = false
	_portrait_rect.anchor_left = 0.02; _portrait_rect.anchor_top = 0.15
	_portrait_rect.anchor_bottom = 0.85; _portrait_rect.anchor_right = 0.20
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_rect)

	# 神官名牌
	_name_bar = Panel.new()
	_name_bar.anchor_left = 0.06; _name_bar.anchor_top = 0.0
	_name_bar.anchor_right = 0.94; _name_bar.offset_top = 14.0; _name_bar.offset_bottom = 56.0
	var nb_s := StyleBoxFlat.new()
	nb_s.bg_color = C_PANEL_BG; nb_s.border_color = C_BORDER
	nb_s.set_border_width_all(2); nb_s.set_corner_radius_all(6)
	_name_bar.add_theme_stylebox_override("panel", nb_s)
	add_child(_name_bar)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.add_theme_color_override("font_color", C_GOLD)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.anchor_right = 1.0; _name_label.anchor_bottom = 1.0
	_name_bar.add_child(_name_label)

	# 对话面板
	_dialogue_panel = Panel.new()
	_dialogue_panel.anchor_left = 0.06; _dialogue_panel.anchor_top = 0.0
	_dialogue_panel.anchor_right = 0.94
	_dialogue_panel.offset_top = 70.0; _dialogue_panel.offset_bottom = 430.0
	var p_s := StyleBoxFlat.new()
	p_s.bg_color = C_PANEL_BG; p_s.border_color = C_BORDER
	p_s.set_border_width_all(2); p_s.set_corner_radius_all(8)
	_dialogue_panel.add_theme_stylebox_override("panel", p_s)
	add_child(_dialogue_panel)

	# 对话文本（用 RichTextLabel 支持 visible_characters 打字机）
	_dialogue_label = RichTextLabel.new()
	_dialogue_label.anchor_left = 0.04; _dialogue_label.anchor_top = 0.04
	_dialogue_label.anchor_right = 0.96; _dialogue_label.anchor_bottom = 0.96
	_dialogue_label.add_theme_font_size_override("normal_font_size", 15)
	_dialogue_label.add_theme_color_override("default_color", C_TEXT)
	_dialogue_label.bbcode_enabled = false
	_dialogue_label.scroll_following = false
	_dialogue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_panel.add_child(_dialogue_label)

	# 选项容器
	_choices_container = VBoxContainer.new()
	_choices_container.visible = false
	_choices_container.anchor_left = 0.08; _choices_container.anchor_top = 0.0
	_choices_container.anchor_right = 0.92; _choices_container.anchor_bottom = 0.0
	_choices_container.offset_top = 440.0; _choices_container.offset_bottom = 520.0
	_choices_container.add_theme_constant_override("separation", 6)
	add_child(_choices_container)

	# 底部提示
	_hint_label = Label.new()
	_hint_label.text = "点击继续 ▸"
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.anchor_left = 0.0; _hint_label.anchor_right = 1.0
	_hint_label.offset_top = 480.0; _hint_label.offset_bottom = 500.0
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint_label)

	# 跳过按钮
	_skip_btn = Button.new()
	_skip_btn.text = "跳过 ▸"
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.custom_minimum_size = Vector2(96, 32)
	_skip_btn.anchor_left = 0.0; _skip_btn.anchor_top = 0.0
	_skip_btn.offset_left = 20.0; _skip_btn.offset_top = 474.0
	_skip_btn.offset_right = 116.0; _skip_btn.offset_bottom = 506.0
	_skip_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A2A28"), Color("#3A342A"), 1, 6))
	_skip_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3A342A"), Color("#5A4E38"), 1, 6))
	_skip_btn.add_theme_color_override("font_color", Color("#9A9182"))
	_skip_btn.add_theme_font_size_override("font_size", 11)
	_skip_btn.pressed.connect(force_finish)
	add_child(_skip_btn)

func _hide_all() -> void:
	_bg.visible = false
	_name_bar.visible = false
	_dialogue_panel.visible = false
	_hint_label.visible = false
	_portrait_rect.visible = false
	_choices_container.visible = false
	_skip_btn.visible = false

func _show_all_ui() -> void:
	_bg.visible = true
	_name_bar.visible = true
	_dialogue_panel.visible = true
	_skip_btn.visible = true
	_hint_label.visible = true

func _make_flat(bg: Color, bdr: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = bdr
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s
