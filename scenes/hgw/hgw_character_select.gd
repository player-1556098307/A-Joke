## HGWCharacterSelect — HGW mode character & game setup screen
extends Control

const C_BG := Color("#FFFDF5")
const C_PANEL_BG := Color("#F1EFE8")
const C_PANEL_BDR := Color("#D3D1C7")
const C_GOLD := Color("#8B6514")
const C_GOLD_BRT := Color("#BA7517")
const C_TEXT := Color("#2C2C2A")
const C_TEXT_DIM := Color("#5F5E5A")

const CHARACTER_PRELOADS := [
	preload("res://resources/characters/漩涡鸣人.tres"),
	preload("res://resources/characters/宇智波佐助.tres"),
	preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
	preload("res://resources/characters/春野樱.tres"),
]

var _selected_char_index: int = 0
var _ai_count: int = 2
var _seed_val: int = 0
var _char_buttons: Array[Button] = []
var _ai_count_label: Label
var _start_btn: Button

func _ready() -> void:
	_build_ui()
	_select_character(0)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

	# Top bar
	var top_bar := PanelContainer.new()
	top_bar.layout_mode = 1
	top_bar.anchor_left = 0.0; top_bar.anchor_top = 0.0; top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 44.0
	top_bar.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	add_child(top_bar)

	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top_bar.add_child(th)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.add_theme_font_size_override("font_size", 13)
	back_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	back_btn.add_theme_color_override("font_hover_color", C_TEXT)
	back_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
	_style_small_btn(back_btn)
	th.add_child(back_btn)

	var title := Label.new()
	title.text = "圣杯战争 · 选择你的从者"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_GOLD_BRT)
	th.add_child(title)

	# Main area — character cards on the left
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 1
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0
	scroll.anchor_right = 0.55; scroll.anchor_bottom = 1.0
	scroll.offset_top = 50.0; scroll.offset_bottom = -60.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var card_list := VBoxContainer.new()
	card_list.add_theme_constant_override("separation", 8)
	scroll.add_child(card_list)

	for i in range(CHARACTER_PRELOADS.size()):
		var card := _build_character_card(CHARACTER_PRELOADS[i], i)
		card_list.add_child(card)

	# Right panel — settings
	var right_panel := PanelContainer.new()
	right_panel.layout_mode = 1
	right_panel.anchor_left = 0.57; right_panel.anchor_top = 0.0
	right_panel.anchor_right = 1.0; right_panel.anchor_bottom = 1.0
	right_panel.offset_top = 50.0; right_panel.offset_bottom = -60.0
	right_panel.offset_right = -12.0
	right_panel.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG * Color(1, 1, 1, 0.9), C_PANEL_BDR * Color(1, 1, 1, 0.5), 1, 10))
	right_panel.custom_minimum_size = Vector2(320, 0)
	add_child(right_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right_panel.add_child(rv)

	var section_title := Label.new()
	section_title.text = "游戏设置"
	section_title.add_theme_font_size_override("font_size", 16)
	section_title.add_theme_color_override("font_color", C_GOLD)
	rv.add_child(section_title)

	# AI count selector
	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 10)
	rv.add_child(ai_row)

	var ai_label := Label.new()
	ai_label.text = "AI 对手数量:"
	ai_label.add_theme_font_size_override("font_size", 14)
	ai_label.add_theme_color_override("font_color", C_TEXT)
	ai_row.add_child(ai_label)

	var ai_minus := Button.new()
	ai_minus.text = "−"
	ai_minus.custom_minimum_size = Vector2(36, 36)
	ai_minus.add_theme_font_size_override("font_size", 18)
	ai_minus.add_theme_color_override("font_color", C_TEXT)
	_style_btn(ai_minus)
	ai_minus.pressed.connect(func(): _adjust_ai_count(-1))
	ai_row.add_child(ai_minus)

	_ai_count_label = Label.new()
	_ai_count_label.text = str(_ai_count)
	_ai_count_label.custom_minimum_size = Vector2(40, 0)
	_ai_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ai_count_label.add_theme_font_size_override("font_size", 18)
	_ai_count_label.add_theme_color_override("font_color", C_GOLD_BRT)
	ai_row.add_child(_ai_count_label)

	var ai_plus := Button.new()
	ai_plus.text = "+"
	ai_plus.custom_minimum_size = Vector2(36, 36)
	ai_plus.add_theme_font_size_override("font_size", 18)
	ai_plus.add_theme_color_override("font_color", C_TEXT)
	_style_btn(ai_plus)
	ai_plus.pressed.connect(func(): _adjust_ai_count(1))
	ai_row.add_child(ai_plus)

	# Seed input
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	rv.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = "地图种子:"
	seed_label.add_theme_font_size_override("font_size", 14)
	seed_label.add_theme_color_override("font_color", C_TEXT)
	seed_row.add_child(seed_label)

	var seed_btn := Button.new()
	seed_btn.text = "随机"
	seed_btn.custom_minimum_size = Vector2(60, 32)
	seed_btn.add_theme_font_size_override("font_size", 13)
	seed_btn.add_theme_color_override("font_color", C_GOLD)
	_style_btn(seed_btn)
	seed_btn.pressed.connect(func(): _seed_val = 0)
	seed_row.add_child(seed_btn)

	# Preview section
	var preview_title := Label.new()
	preview_title.text = "已选择"
	preview_title.add_theme_font_size_override("font_size", 14)
	preview_title.add_theme_color_override("font_color", C_GOLD)
	rv.add_child(preview_title)

	# AI character list
	var ai_chars_title := Label.new()
	ai_chars_title.text = "AI 将从剩余角色中随机选择"
	ai_chars_title.add_theme_font_size_override("font_size", 11)
	ai_chars_title.add_theme_color_override("font_color", C_TEXT_DIM)
	rv.add_child(ai_chars_title)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(spacer)

	# Start button
	_start_btn = Button.new()
	_start_btn.text = "开始圣杯战争"
	_start_btn.custom_minimum_size = Vector2(0, 48)
	_start_btn.add_theme_font_size_override("font_size", 18)
	_start_btn.add_theme_color_override("font_color", C_GOLD_BRT)
	_start_btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var s_normal := StyleBoxFlat.new()
	s_normal.bg_color = Color("#8B6514")
	s_normal.border_color = C_GOLD * Color(1, 1, 1, 0.5)
	s_normal.set_border_width_all(2)
	s_normal.set_corner_radius_all(10)
	_start_btn.add_theme_stylebox_override("normal", s_normal)

	var s_hover: StyleBoxFlat = s_normal.duplicate()
	s_hover.bg_color = Color("#BA7517")
	s_hover.border_color = C_GOLD
	_start_btn.add_theme_stylebox_override("hover", s_hover)

	_start_btn.pressed.connect(_on_start_pressed)
	rv.add_child(_start_btn)

	# Bottom bar
	var bot_bar := PanelContainer.new()
	bot_bar.layout_mode = 1
	bot_bar.anchor_left = 0.0; bot_bar.anchor_top = 1.0; bot_bar.anchor_right = 1.0; bot_bar.anchor_bottom = 1.0
	bot_bar.offset_top = -48.0
	bot_bar.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	add_child(bot_bar)

	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	bot_bar.add_child(bh)

	var info := Label.new()
	info.text = "选择一名角色作为你的从者，AI 将操控其余角色"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", C_TEXT_DIM)
	bh.add_child(info)

func _build_character_card(char_data: CharacterData, idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 90)
	panel.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG * Color(1, 1, 1, 0.8), C_PANEL_BDR * Color(1, 1, 1, 0.3), 1, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)

	# Avatar
	var av_panel := PanelContainer.new()
	av_panel.custom_minimum_size = Vector2(72, 72)
	var av_style := StyleBoxFlat.new()
	av_style.bg_color = Color("#F1EFE8")
	av_style.border_color = C_PANEL_BDR
	av_style.set_border_width_all(1)
	av_style.set_corner_radius_all(6)
	av_panel.add_theme_stylebox_override("panel", av_style)
	hb.add_child(av_panel)

	var av_lbl := Label.new()
	av_lbl.text = char_data.character_name.left(1)
	av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av_lbl.add_theme_font_size_override("font_size", 28)
	av_lbl.add_theme_color_override("font_color", C_GOLD)
	av_panel.add_child(av_lbl)

	# Info
	var info_vb := VBoxContainer.new()
	info_vb.add_theme_constant_override("separation", 4)
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info_vb)

	var name_lbl := Label.new()
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", C_GOLD_BRT)
	info_vb.add_child(name_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP: %d" % char_data.max_hp
	hp_lbl.add_theme_font_size_override("font_size", 12)
	hp_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	info_vb.add_child(hp_lbl)

	var tag_str: String = " · ".join(PackedStringArray(char_data.tags)) if char_data.tags.size() > 0 else ""
	if tag_str != "":
		var tag_lbl := Label.new()
		tag_lbl.text = tag_str
		tag_lbl.add_theme_font_size_override("font_size", 11)
		tag_lbl.add_theme_color_override("font_color", C_GOLD)
		info_vb.add_child(tag_lbl)

	var skill_names: Array[String] = []
	for sk in char_data.skills:
		skill_names.append(sk.skill_name)
	var skills_str := " · ".join(PackedStringArray(skill_names)) if skill_names.size() > 0 else ""
	if skills_str != "":
		var sk_lbl := Label.new()
		sk_lbl.text = "技能: %s" % skills_str
		sk_lbl.add_theme_font_size_override("font_size", 10)
		sk_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		info_vb.add_child(sk_lbl)

	# Select button
	var btn := Button.new()
	btn.text = "选择"
	btn.custom_minimum_size = Vector2(80, 36)
	btn.add_theme_font_size_override("font_size", 14)
	_style_btn(btn)
	var bidx := idx
	btn.pressed.connect(func(): _select_character(bidx))
	hb.add_child(btn)
	_char_buttons.append(btn)

	return panel

func _select_character(idx: int) -> void:
	_selected_char_index = idx
	for i in range(_char_buttons.size()):
		var btn := _char_buttons[i]
		if i == idx:
			btn.text = "已选 ✓"
			btn.add_theme_color_override("font_color", C_GOLD_BRT)
		else:
			btn.text = "选择"
			btn.add_theme_color_override("font_color", C_TEXT)

func _adjust_ai_count(delta: int) -> void:
	_ai_count = clampi(_ai_count + delta, 1, 7)
	_ai_count_label.text = str(_ai_count)

func _on_start_pressed() -> void:
	var config := _build_config()
	SceneManager.last_hgw_config = config
	SceneManager.go_to("res://scenes/hgw/hgw_battle.tscn")

func _build_config() -> Dictionary:
	var players: Array = []
	var chosen_char: CharacterData = CHARACTER_PRELOADS[_selected_char_index]

	# Human player
	players.append({
		"name": "玩家",
		"is_human": true,
		"character": chosen_char,
	})

	# AI players — pick from remaining characters
	var available: Array = []
	for i in range(CHARACTER_PRELOADS.size()):
		if i != _selected_char_index:
			available.append(CHARACTER_PRELOADS[i])
	available.shuffle()

	var ai_names := ["鸣人", "佐助", "佐助·疾风传", "樱", "卡卡西", "我爱罗", "雏田"]
	for i in range(mini(_ai_count, available.size())):
		players.append({
			"name": "AI-%s" % ai_names[i % ai_names.size()],
			"is_human": false,
			"character": available[i],
		})

	return {
		"num_players": players.size(),
		"seed": _seed_val if _seed_val > 0 else randi() % 99999 + 1,
		"players": players,
	}

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

func _style_btn(btn: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color("#F1EFE8")
	n.border_color = C_GOLD * Color(1, 1, 1, 0.3)
	n.set_border_width_all(1)
	n.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color("#E6E2D4")
	h.border_color = C_GOLD
	btn.add_theme_stylebox_override("hover", h)

func _style_small_btn(btn: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color.TRANSPARENT
	n.border_color = C_PANEL_BDR * Color(1, 1, 1, 0.3)
	n.set_border_width_all(1)
	n.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", n)
	var h: StyleBoxFlat = n.duplicate()
	h.border_color = C_GOLD * Color(1, 1, 1, 0.5)
	btn.add_theme_stylebox_override("hover", h)
