## 角色选择场景 — 左侧角色列表，右侧角色详情预览，底部AI数量配置
## 选中角色后构建游戏config存储到SceneManager，跳转到Main场景开始游戏
extends Control

@onready var btn_back: Button           = $BtnBack
@onready var character_list: VBoxContainer = $LeftList/CharacterList
@onready var avatar_box: Panel          = $AvatarBox
@onready var avatar_label: Label        = $AvatarBox/AvatarLabel
@onready var stats_panel: Panel         = $StatsPanel
@onready var skills_container: VBoxContainer = $SkillsScroll/SkillsContainer
@onready var right_header_label: Label  = $RightHeaderLabel
@onready var btn_minus: Button          = $AIConfigContent/AIConfigHBox/AIRightHBox/BtnMinus
@onready var count_label: Label         = $AIConfigContent/AIConfigHBox/AIRightHBox/CountBox/CountLabel
@onready var btn_plus: Button           = $AIConfigContent/AIConfigHBox/AIRightHBox/BtnPlus
@onready var btn_start: Button          = $BtnStart
@onready var left_panel_bg: Panel       = $LeftPanelBg
@onready var right_panel_bg: Panel      = $RightPanelBg
@onready var ai_config_content: Panel   = $AIConfigContent
@onready var border_frame: Panel        = $BorderFrame

var selected_character: CharacterData = null
var ai_count: int = 2
var debug_force_scissors: bool = false
var all_characters: Array[CharacterData] = []
var _card_buttons:    Array[Button] = []
var _card_name_lbls:  Array[Label]  = []
var _card_hp_lbls:    Array[Label]  = []
var _card_sel_badges: Array[Panel]  = []

# ── Class colour maps ─────────────────────────────────────────────────────────

const CLASS_BAR_COLOR := {
	"战士": Color("#639922"), "法师": Color("#534AB7"),
	"坦克": Color("#D4537E"), "刺客": Color("#D85A30"),
}
const CLASS_BADGE_BG := {
	"战士": Color("#185FA5"), "法师": Color("#534AB7"),
	"坦克": Color("#D4537E"), "刺客": Color("#D85A30"),
}
const CLASS_BADGE_TEXT := {
	"战士": Color("#E6F1FB"), "法师": Color("#EEEDFE"),
	"坦克": Color("#FFFDF5"), "刺客": Color("#FAECE7"),
}
const CLASS_AVATAR_BG := {
	"战士": Color("#B5D4F4"), "法师": Color("#EEEDFE"),
	"坦克": Color("#F4C0D1"), "刺客": Color("#F5C4B3"),
}
const CLASS_AVATAR_BORDER := {
	"战士": Color("#185FA5"), "法师": Color("#534AB7"),
	"坦克": Color("#993556"), "刺客": Color("#993C1D"),
}

const SKILL_COLORS := [
	[Color("#E6F1FB"), Color("#185FA5"), Color("#E6F1FB"), Color("#0C447C")],
	[Color("#EEEDFE"), Color("#534AB7"), Color("#EEEDFE"), Color("#3C3489")],
	[Color("#EAF3DE"), Color("#3B6D11"), Color("#EAF3DE"), Color("#27500A")],
]

const STAT_DEFS := [
	["生命值",   Color("#3B6D11")],
	["普攻耗气", Color("#BA7517")],
	["基础伤害", Color("#E24B4A")],
	["基础范围", Color("#534AB7")],
	["技能数量", Color("#2C2C2A")],
]

func _get_cls(char_data: CharacterData) -> String:
	return char_data.tags[0] if char_data.tags.size() > 0 else "战士"

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_apply_styling()
	btn_back.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
	btn_minus.pressed.connect(func(): _on_ai_count_changed(-1))
	btn_plus.pressed.connect(func(): _on_ai_count_changed(1))
	btn_start.pressed.connect(_on_start_pressed)
	_setup_debug_toggle()
	_load_all_characters()
	_build_character_list()
	if all_characters.size() > 0:
		_select_character(all_characters[0])

# ── Styling ───────────────────────────────────────────────────────────────────

func _apply_styling() -> void:
	# Outer border
	var bf := StyleBoxFlat.new()
	bf.draw_center = false
	bf.border_color = Color("#2C2C2A")
	bf.set_border_width_all(3)
	bf.set_corner_radius_all(6)
	border_frame.add_theme_stylebox_override("panel", bf)

	# Left / Right panel borders
	var panel_s := _make_flat(Color("#FFFDF5"), Color("#2C2C2A"), 2, 4)
	left_panel_bg.add_theme_stylebox_override("panel", panel_s)
	right_panel_bg.add_theme_stylebox_override("panel", panel_s.duplicate())

	# BtnBack
	btn_back.focus_mode = Control.FOCUS_NONE
	btn_back.add_theme_stylebox_override("normal",  _make_flat(Color("#444441"), Color("#444441"), 0, 4))
	btn_back.add_theme_stylebox_override("hover",   _make_flat(Color("#5A5A57"), Color("#5A5A57"), 0, 4))
	btn_back.add_theme_stylebox_override("pressed", _make_flat(Color("#333331"), Color("#333331"), 0, 4))
	btn_back.add_theme_color_override("font_color",          Color("#D3D1C7"))
	btn_back.add_theme_color_override("font_hover_color",    Color("#FFFDF5"))
	btn_back.add_theme_color_override("font_pressed_color",  Color("#D3D1C7"))
	btn_back.add_theme_font_size_override("font_size", 11)

	# AI config panel
	var ai_s := _make_flat(Color("#F1EFE8"), Color("#D3D1C7"), 1, 6)
	ai_config_content.add_theme_stylebox_override("panel", ai_s)

	# Minus/Plus buttons
	var step_s := _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 1, 4)
	for btn in [btn_minus, btn_plus]:
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal",  step_s)
		btn.add_theme_stylebox_override("hover",   _make_flat(Color("#F5F3EC"), Color("#B4B2A9"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#EAE8E1"), Color("#888780"), 1, 4))
		btn.add_theme_font_size_override("font_size", 14)

	# CountBox dark background
	var count_box: Panel = $AIConfigContent/AIConfigHBox/AIRightHBox/CountBox
	var cb_s := StyleBoxFlat.new()
	cb_s.bg_color = Color("#2C2C2A")
	cb_s.set_corner_radius_all(4)
	count_box.add_theme_stylebox_override("panel", cb_s)

	# Start button (styled after first character is selected; see _style_start_button)
	_style_start_button()

func _style_start_button() -> void:
	btn_start.text = ""
	btn_start.focus_mode = Control.FOCUS_NONE
	btn_start.add_theme_stylebox_override("normal",  _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 3, 8))
	btn_start.add_theme_stylebox_override("hover",   _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 3, 8))
	btn_start.add_theme_stylebox_override("pressed", _make_flat(Color("#27500A"), Color("#2C2C2A"), 3, 8))
	# Label child — only create once
	if btn_start.get_child_count() == 0:
		var lbl := Label.new()
		lbl.name = "StartLabel"
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color("#EAF3DE"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		btn_start.add_child(lbl)

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

# ── Load characters ───────────────────────────────────────────────────────────

const _CHARACTER_PRELOADS = [
	preload("res://resources/characters/漩涡鸣人.tres"),
	preload("res://resources/characters/宇智波佐助.tres"),
	preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
	preload("res://resources/characters/春野樱.tres"),
]

func _load_all_characters() -> void:
	for res in _CHARACTER_PRELOADS:
		if res is CharacterData:
			all_characters.append(res as CharacterData)

# ── Character list ────────────────────────────────────────────────────────────

func _build_character_list() -> void:
	for child in character_list.get_children():
		child.queue_free()
	_card_buttons.clear()
	_card_name_lbls.clear()
	_card_hp_lbls.clear()
	_card_sel_badges.clear()

	for char_data in all_characters:
		var card := _make_character_card(char_data)
		character_list.add_child(card)
		_card_buttons.append(card)
		card.pressed.connect(_select_character.bind(char_data))

func _make_character_card(char_data: CharacterData) -> Button:
	var cls := _get_cls(char_data)
	var bar_col: Color  = CLASS_BAR_COLOR.get(cls,   Color("#639922"))
	var av_bg: Color    = CLASS_AVATAR_BG.get(cls,   Color("#B5D4F4"))
	var av_bdr: Color   = CLASS_AVATAR_BORDER.get(cls, Color("#185FA5"))
	var badge_bg: Color = CLASS_BADGE_BG.get(cls,   Color("#185FA5"))
	var badge_txt: Color= CLASS_BADGE_TEXT.get(cls,  Color("#E6F1FB"))

	var card := Button.new()
	card.custom_minimum_size = Vector2(284, 88)
	card.text = ""
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
	card.add_theme_stylebox_override("hover",  _make_flat(Color("#F5F3EC"), Color("#B4B2A9"), 2, 6))
	card.add_theme_stylebox_override("pressed",_make_flat(Color("#EAF3DE"), Color("#3B6D11"), 3, 6))

	# 6 px left accent bar
	var bar := ColorRect.new()
	bar.color = bar_col
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_top = 0.0; bar.anchor_bottom = 1.0
	bar.offset_right = 6.0
	card.add_child(bar)

	# Avatar box (64×64 at x=12, y=12)
	var av := Panel.new()
	av.layout_mode = 0
	av.offset_left = 12.0; av.offset_top = 12.0
	av.offset_right = 76.0; av.offset_bottom = 76.0
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av_s := StyleBoxFlat.new()
	av_s.bg_color = av_bg; av_s.border_color = av_bdr
	av_s.set_border_width_all(2); av_s.set_corner_radius_all(6)
	av.add_theme_stylebox_override("panel", av_s)
	card.add_child(av)

	if char_data.portrait != null:
		var tr := TextureRect.new()
		tr.texture = char_data.portrait
		tr.anchor_right = 1.0; tr.anchor_bottom = 1.0
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av.add_child(tr)
	else:
		var av_lbl := Label.new()
		av_lbl.text = char_data.character_name.left(1)
		av_lbl.add_theme_font_size_override("font_size", 30)
		av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_lbl.anchor_right = 1.0; av_lbl.anchor_bottom = 1.0
		av.add_child(av_lbl)

	# Character name
	var name_lbl := Label.new()
	name_lbl.layout_mode = 0
	name_lbl.offset_left = 84.0; name_lbl.offset_top = 8.0
	name_lbl.offset_right = 248.0; name_lbl.offset_bottom = 28.0
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)
	_card_name_lbls.append(name_lbl)

	# Class badge (36×14 at x=84, y=30)
	var cb := _make_inline_badge(cls, badge_bg, badge_txt, 36, 14, 84, 30)
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cb)

	# Level badge (24×14 at x=126, y=30)
	var lb := _make_inline_badge("C级", Color("#444441"), Color("#D3D1C7"), 24, 14, 126, 30)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lb)

	# HP text
	var hp_lbl := Label.new()
	hp_lbl.layout_mode = 0
	hp_lbl.offset_left = 84.0; hp_lbl.offset_top = 50.0
	hp_lbl.offset_right = 268.0; hp_lbl.offset_bottom = 64.0
	hp_lbl.text = "HP %d" % char_data.max_hp
	hp_lbl.add_theme_font_size_override("font_size", 10)
	hp_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hp_lbl)
	_card_hp_lbls.append(hp_lbl)

	# Skill names
	var sk_names: Array[String] = []
	for sk in char_data.skills:
		sk_names.append(sk.skill_name)
	var sk_lbl := Label.new()
	sk_lbl.layout_mode = 0
	sk_lbl.offset_left = 84.0; sk_lbl.offset_top = 64.0
	sk_lbl.offset_right = 268.0; sk_lbl.offset_bottom = 78.0
	sk_lbl.text = " · ".join(PackedStringArray(sk_names))
	sk_lbl.add_theme_font_size_override("font_size", 10)
	sk_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	sk_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sk_lbl)

	# "已选" badge (hidden initially) at x=244, y=8, 32×16
	var sel_panel := Panel.new()
	sel_panel.layout_mode = 0
	sel_panel.offset_left = 244.0; sel_panel.offset_top = 8.0
	sel_panel.offset_right = 276.0; sel_panel.offset_bottom = 24.0
	sel_panel.visible = false
	sel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sel_s := StyleBoxFlat.new()
	sel_s.bg_color = Color("#3B6D11"); sel_s.set_corner_radius_all(3)
	sel_panel.add_theme_stylebox_override("panel", sel_s)
	card.add_child(sel_panel)
	_card_sel_badges.append(sel_panel)

	var sel_lbl := Label.new()
	sel_lbl.text = "已选"
	sel_lbl.add_theme_font_size_override("font_size", 9)
	sel_lbl.add_theme_color_override("font_color", Color("#EAF3DE"))
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sel_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel_lbl.anchor_right = 1.0; sel_lbl.anchor_bottom = 1.0
	sel_panel.add_child(sel_lbl)

	return card

func _make_inline_badge(text: String, bg: Color, fg: Color,
		w: int, h: int, x: int, y: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if x > 0 or y > 0:
		p.layout_mode = 0
		p.offset_left = float(x); p.offset_top = float(y)
		p.offset_right = float(x + w); p.offset_bottom = float(y + h)
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", s)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", fg)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	p.add_child(lbl)
	return p

# ── Select character ──────────────────────────────────────────────────────────

func _select_character(char_data: CharacterData) -> void:
	selected_character = char_data
	_update_preview(char_data)
	_update_list_selection()
	_update_start_button_label()

func _update_list_selection() -> void:
	for i in _card_buttons.size():
		var is_sel := all_characters[i] == selected_character
		if is_sel:
			_card_buttons[i].add_theme_stylebox_override("normal",
				_make_flat(Color("#EAF3DE"), Color("#3B6D11"), 3, 6))
			_card_name_lbls[i].add_theme_color_override("font_color", Color("#27500A"))
			_card_hp_lbls[i].add_theme_color_override("font_color",   Color("#3B6D11"))
		else:
			_card_buttons[i].add_theme_stylebox_override("normal",
				_make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
			_card_name_lbls[i].add_theme_color_override("font_color", Color("#2C2C2A"))
			_card_hp_lbls[i].add_theme_color_override("font_color",   Color("#5F5E5A"))
		_card_sel_badges[i].visible = is_sel

# ── Right preview ─────────────────────────────────────────────────────────────

func _update_preview(char_data: CharacterData) -> void:
	var cls := _get_cls(char_data)
	right_header_label.text = "角色详情预览 — %s" % char_data.character_name

	# Avatar box colour
	var av_s := StyleBoxFlat.new()
	av_s.bg_color = CLASS_AVATAR_BG.get(cls, Color("#B5D4F4"))
	av_s.border_color = CLASS_AVATAR_BORDER.get(cls, Color("#185FA5"))
	av_s.set_border_width_all(2); av_s.set_corner_radius_all(8)
	avatar_box.add_theme_stylebox_override("panel", av_s)

	# Portrait or initial letter
	var portrait_rect := avatar_box.get_node_or_null("PortraitRect") as TextureRect
	if portrait_rect == null:
		portrait_rect = TextureRect.new()
		portrait_rect.name = "PortraitRect"
		portrait_rect.anchor_right = 1.0; portrait_rect.anchor_bottom = 1.0
		portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar_box.add_child(portrait_rect)
	if char_data.portrait != null:
		portrait_rect.texture = char_data.portrait
		portrait_rect.visible = true
		avatar_label.visible = false
	else:
		portrait_rect.visible = false
		avatar_label.visible = true
	avatar_label.text = char_data.character_name.left(1)

	_build_stats_panel(char_data)
	_build_skill_cards(char_data)

func _build_stats_panel(char_data: CharacterData) -> void:
	for child in stats_panel.get_children():
		child.queue_free()

	# Stats panel bg
	var sp_s := StyleBoxFlat.new()
	sp_s.bg_color = Color("#F1EFE8")
	sp_s.border_color = Color("#D3D1C7")
	sp_s.set_border_width_all(1); sp_s.set_corner_radius_all(6)
	stats_panel.add_theme_stylebox_override("panel", sp_s)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0; margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left",  16)
	margin.add_theme_constant_override("margin_top",   10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	stats_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Name + badges row
	var cls := _get_cls(char_data)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vbox.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	name_row.add_child(name_lbl)

	var cls_bg: Color  = CLASS_BADGE_BG.get(cls,   Color("#185FA5"))
	var cls_txt: Color = CLASS_BADGE_TEXT.get(cls,  Color("#E6F1FB"))
	name_row.add_child(_make_inline_badge(cls, cls_bg, cls_txt, 36, 14, 0, 0))
	name_row.add_child(_make_inline_badge("C级", Color("#444441"), Color("#D3D1C7"), 24, 14, 0, 0))

	# Stat cells
	var base_energy := char_data.basic_attack_cost
	var base_range  := char_data.skills[0].max_range   if char_data.skills.size() > 0 else 1
	if base_range >= 999:
		base_range = 1
	var stat_vals := [
		str(char_data.max_hp),
		str(base_energy),
		"1",
		str(base_range),
		str(char_data.skills.size()),
	]

	var cells_row := HBoxContainer.new()
	cells_row.add_theme_constant_override("separation", 6)
	cells_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(cells_row)

	for i in STAT_DEFS.size():
		cells_row.add_child(_make_stat_cell(STAT_DEFS[i][0], stat_vals[i], STAT_DEFS[i][1]))

func _make_stat_cell(key: String, value: String, val_color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(80, 36)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#FFFDF5"); s.border_color = Color("#D3D1C7")
	s.set_border_width_all(1); s.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", s)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	p.add_child(vbox)

	var k := Label.new()
	k.text = key
	k.add_theme_font_size_override("font_size", 9)
	k.add_theme_color_override("font_color", Color("#888780"))
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(k)

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 14)
	v.add_theme_color_override("font_color", val_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(v)
	return p

# ── Skill list ────────────────────────────────────────────────────────────────

func _build_skill_cards(char_data: CharacterData) -> void:
	for child in skills_container.get_children():
		child.queue_free()

	# Collect skills unlockable via UNLOCK_SKILL effects (shown as locked rows)
	var unlockable: Array[SkillData] = []
	for sk in char_data.skills:
		for eff in sk.effects:
			if eff.effect_type == SkillEffect.EffectType.UNLOCK_SKILL and eff.unlock_skill != null:
				unlockable.append(eff.unlock_skill)

	for i in char_data.skills.size():
		skills_container.add_child(_make_skill_row(char_data.skills[i], i, false))
	for sk in unlockable:
		skills_container.add_child(_make_skill_row(sk, -1, true))

func _make_skill_row(skill: SkillData, idx: int, locked: bool) -> Panel:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 38)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg: Color
	var accent: Color
	var name_col: Color
	var detail_col: Color
	if locked:
		bg        = Color("#F5F3EC")
		accent    = Color("#D3D1C7")
		name_col  = Color("#B4B2A9")
		detail_col = Color("#D3D1C7")
	else:
		var c: Array = SKILL_COLORS[idx % SKILL_COLORS.size()]
		bg        = c[0]
		accent    = c[1]
		name_col  = c[3]
		detail_col = c[3].lightened(0.25)

	var row_s := StyleBoxFlat.new()
	row_s.bg_color = bg; row_s.border_color = accent
	row_s.set_border_width_all(1); row_s.set_corner_radius_all(4)
	row.add_theme_stylebox_override("panel", row_s)

	# Left accent bar (4px)
	var bar := ColorRect.new()
	bar.color = accent
	bar.anchor_top = 0.0; bar.anchor_bottom = 1.0
	bar.offset_right = 4.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

	# Skill name: top-left when description exists, vertically centred otherwise
	var name_lbl := Label.new()
	name_lbl.text = ("🔒 " if locked else "") + skill.skill_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if skill.description != "":
		name_lbl.anchor_bottom = 0.0
		name_lbl.offset_left = 10.0; name_lbl.offset_top = 2.0
		name_lbl.offset_right = 350.0; name_lbl.offset_bottom = 21.0
	else:
		name_lbl.anchor_bottom = 1.0
		name_lbl.offset_left = 10.0; name_lbl.offset_right = 350.0
	row.add_child(name_lbl)

	# Description (bottom-left, only if non-empty)
	if skill.description != "":
		var desc_lbl := Label.new()
		desc_lbl.text = skill.description
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", detail_col)
		desc_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.anchor_bottom = 0.0
		desc_lbl.offset_left = 10.0; desc_lbl.offset_top = 21.0
		desc_lbl.offset_right = 350.0; desc_lbl.offset_bottom = 36.0
		row.add_child(desc_lbl)

	# Cost + range (right side)
	var range_str: String
	if skill.max_range >= 999:
		range_str = "自身"
	elif skill.min_range == skill.max_range:
		range_str = "范围%d" % skill.min_range
	else:
		range_str = "范围%d~%d" % [skill.min_range, skill.max_range]
	var info_lbl := Label.new()
	info_lbl.text = "⚡%d  %s" % [skill.energy_cost, range_str]
	info_lbl.add_theme_font_size_override("font_size", 9)
	info_lbl.add_theme_color_override("font_color", name_col)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_lbl.anchor_left = 1.0; info_lbl.anchor_right = 1.0
	info_lbl.anchor_bottom = 1.0
	info_lbl.offset_left = -96.0; info_lbl.offset_right = -6.0
	row.add_child(info_lbl)

	return row

# ── AI count ──────────────────────────────────────────────────────────────────

func _on_ai_count_changed(delta: int) -> void:
	ai_count = clampi(ai_count + delta, 1, mini(7, all_characters.size() - 1))
	count_label.text = str(ai_count)
	_update_start_button_label()

func _setup_debug_toggle() -> void:
	var cb := CheckBox.new()
	cb.text = "调试：AI固定出剪刀"
	cb.add_theme_font_size_override("font_size", 10)
	cb.add_theme_color_override("font_color", Color("#5F5E5A"))
	cb.button_pressed = debug_force_scissors
	cb.layout_mode = 0
	cb.offset_left   = 330.0
	cb.offset_top    = 476.0
	cb.offset_right  = 560.0
	cb.offset_bottom = 494.0
	cb.toggled.connect(func(pressed: bool): debug_force_scissors = pressed)
	add_child(cb)

func _update_start_button_label() -> void:
	var lbl := btn_start.get_node_or_null("StartLabel") as Label
	if lbl == null:
		return
	if selected_character == null:
		lbl.text = "请先选择角色"
	else:
		lbl.text = "开始游戏！（你：%s · AI ×%d 随机）" % [selected_character.character_name, ai_count]

# ── Start game ────────────────────────────────────────────────────────────────

func _on_start_pressed() -> void:
	if selected_character == null:
		return

	var remaining: Array[CharacterData] = []
	for c in all_characters:
		if c != selected_character:
			remaining.append(c)
	remaining.shuffle()
	var ai_pool := remaining.slice(0, ai_count)

	var config: Dictionary = {
		"players": [{ "name": "玩家", "is_human": true, "character": selected_character }],
		"debug_force_scissors": debug_force_scissors
	}
	for ai_char in ai_pool:
		config["players"].append({
			"name": "AI-%s" % ai_char.character_name,
			"is_human": false,
			"character": ai_char
		})

	SceneManager.last_game_config = config
	SceneManager.go_to("res://scenes/main.tscn")
