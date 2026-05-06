## 主菜单场景 — 标题画面，展示角色卡和导航按钮
## 所有 UI 样式通过代码中的 StyleBoxFlat 动态构建（无 theme 文件）
extends Control

@onready var btn_pve: Button = $BtnPvE
@onready var btn_pvp: Button = $BtnPvP
@onready var btn_hgw: Button = $BtnHGW
@onready var btn_settings: Button = $BtnSettings
@onready var btn_quit: Button = $BtnQuit
@onready var character_showcase: HBoxContainer = $CharacterShowcase
@onready var tips_panel: PanelContainer = $TipsPanel
@onready var border_frame: Panel = $BorderFrame

func _ready() -> void:
	_apply_border_frame()
	_style_pve_button()
	_style_pvp_button()
	_style_hgw_button()
	_style_settings_button()
	_style_quit_button()
	_style_tips_panel()
	btn_pve.pressed.connect(_on_pve_pressed)
	btn_hgw.pressed.connect(_on_hgw_pressed)
	btn_settings.pressed.connect(_on_settings_pressed)
	btn_quit.pressed.connect(get_tree().quit)
	_spawn_character_showcase()

func _apply_border_frame() -> void:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Color("#2C2C2A")
	s.set_border_width_all(3)
	s.set_corner_radius_all(6)
	border_frame.add_theme_stylebox_override("panel", s)

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

func _add_left_bar(btn: Button, color: Color) -> void:
	var bar := ColorRect.new()
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 0.0
	bar.anchor_bottom = 1.0
	bar.offset_right = 6.0
	btn.add_child(bar)

func _add_two_line_labels(btn: Button,
		main_text: String, main_color: Color, main_size: int,
		sub_text: String, sub_color: Color, sub_size: int) -> void:
	var h := btn.offset_bottom - btn.offset_top
	var split := h * 0.62

	var main_lbl := Label.new()
	main_lbl.text = main_text
	main_lbl.add_theme_font_size_override("font_size", main_size)
	main_lbl.add_theme_color_override("font_color", main_color)
	main_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_lbl.anchor_left = 0.0
	main_lbl.anchor_top = 0.0
	main_lbl.anchor_right = 1.0
	main_lbl.anchor_bottom = 0.0
	main_lbl.offset_top = 0.0
	main_lbl.offset_bottom = split
	btn.add_child(main_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_text
	sub_lbl.add_theme_font_size_override("font_size", sub_size)
	sub_lbl.add_theme_color_override("font_color", sub_color)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_lbl.anchor_left = 0.0
	sub_lbl.anchor_top = 0.0
	sub_lbl.anchor_right = 1.0
	sub_lbl.anchor_bottom = 0.0
	sub_lbl.offset_top = split + 2.0
	sub_lbl.offset_bottom = h
	btn.add_child(sub_lbl)

func _add_centered_label(btn: Button, text: String, color: Color, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_left = 0.0
	lbl.anchor_top = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	btn.add_child(lbl)

func _style_pve_button() -> void:
	btn_pve.text = ""
	btn_pve.focus_mode = Control.FOCUS_NONE
	btn_pve.add_theme_stylebox_override("normal", _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 3, 8))
	btn_pve.add_theme_stylebox_override("hover",  _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 3, 8))
	btn_pve.add_theme_stylebox_override("pressed",_make_flat(Color("#27500A"), Color("#2C2C2A"), 3, 8))
	_add_left_bar(btn_pve, Color("#97C459"))
	_add_two_line_labels(btn_pve,
		"PvE 对战", Color("#EAF3DE"), 18,
		"vs AI · 立即开始", Color("#C0DD97"), 11)

func _style_pvp_button() -> void:
	btn_pvp.text = ""
	btn_pvp.focus_mode = Control.FOCUS_NONE
	var s := _make_flat(Color("#F1EFE8"), Color("#D3D1C7"), 2, 8)
	btn_pvp.add_theme_stylebox_override("normal",   s)
	btn_pvp.add_theme_stylebox_override("hover",    s)
	btn_pvp.add_theme_stylebox_override("disabled", s)
	_add_left_bar(btn_pvp, Color("#D3D1C7"))
	_add_two_line_labels(btn_pvp,
		"PvP 联机", Color("#B4B2A9"), 18,
		"开发中，敬请期待...", Color("#D3D1C7"), 11)

	var lock := Label.new()
	lock.text = "🔒"
	lock.add_theme_font_size_override("font_size", 14)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.anchor_left = 1.0
	lock.anchor_top = 0.0
	lock.anchor_right = 1.0
	lock.anchor_bottom = 0.0
	lock.offset_left = -44.0
	lock.offset_top = 8.0
	lock.offset_right = -4.0
	lock.offset_bottom = 34.0
	btn_pvp.add_child(lock)

func _style_hgw_button() -> void:
	btn_hgw.text = ""
	btn_hgw.focus_mode = Control.FOCUS_NONE
	btn_hgw.add_theme_stylebox_override("normal", _make_flat(Color("#4A2C6E"), Color("#2C2C2A"), 3, 8))
	btn_hgw.add_theme_stylebox_override("hover",  _make_flat(Color("#5E3A8A"), Color("#2C2C2A"), 3, 8))
	btn_hgw.add_theme_stylebox_override("pressed",_make_flat(Color("#3A1F5C"), Color("#2C2C2A"), 3, 8))
	_add_left_bar(btn_hgw, Color("#C9A84C"))
	_add_two_line_labels(btn_hgw,
		"圣杯战争", Color("#F0E6D3"), 18,
		"测试 · 六边形地图", Color("#C9A84C"), 11)

func _style_settings_button() -> void:
	btn_settings.text = ""
	btn_settings.focus_mode = Control.FOCUS_NONE
	btn_settings.add_theme_stylebox_override("normal", _make_flat(Color("#E6F1FB"), Color("#185FA5"), 2, 8))
	btn_settings.add_theme_stylebox_override("hover",  _make_flat(Color("#CCE4F9"), Color("#185FA5"), 2, 8))
	btn_settings.add_theme_stylebox_override("pressed",_make_flat(Color("#B5D4F4"), Color("#185FA5"), 2, 8))
	_add_centered_label(btn_settings, "⚙ 设置", Color("#0C447C"), 14)

func _style_quit_button() -> void:
	btn_quit.text = ""
	btn_quit.focus_mode = Control.FOCUS_NONE
	btn_quit.add_theme_stylebox_override("normal", _make_flat(Color("#FCEBEB"), Color("#E24B4A"), 2, 8))
	btn_quit.add_theme_stylebox_override("hover",  _make_flat(Color("#FADDDD"), Color("#E24B4A"), 2, 8))
	btn_quit.add_theme_stylebox_override("pressed",_make_flat(Color("#F5C0C0"), Color("#E24B4A"), 2, 8))
	_add_centered_label(btn_quit, "✕ 退出", Color("#791F1F"), 14)

func _style_tips_panel() -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#F1EFE8")
	s.border_color = Color("#D3D1C7")
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	tips_panel.add_theme_stylebox_override("panel", s)

func _on_pve_pressed() -> void:
	SceneManager.go_to("res://scenes/character_select.tscn")

func _on_hgw_pressed() -> void:
	SceneManager.go_to("res://scenes/hgw/hgw_character_select.tscn")

func _on_settings_pressed() -> void:
	SceneManager.go_to("res://scenes/settings.tscn")

# ── Character showcase ───────────────────────────────────────────────────────

const _AVATAR_BG := {
	"战士": Color("#B5D4F4"), "法师": Color("#EEEDFE"),
	"坦克": Color("#F4C0D1"), "刺客": Color("#F5C4B3"),
}
const _AVATAR_BORDER := {
	"战士": Color("#185FA5"), "法师": Color("#534AB7"),
	"坦克": Color("#993556"), "刺客": Color("#993C1D"),
}
const _NAME_BAR := {
	"战士": Color("#2C2C2A"), "法师": Color("#534AB7"),
	"坦克": Color("#D4537E"), "刺客": Color("#993C1D"),
}
const _NAME_TEXT := {
	"战士": Color("#FAC775"), "法师": Color("#EEEDFE"),
	"坦克": Color("#FFFDF5"), "刺客": Color("#FFFDF5"),
}
const _INFO_COLOR := {
	"战士": Color("#3B6D11"), "法师": Color("#534AB7"),
	"坦克": Color("#D4537E"), "刺客": Color("#993C1D"),
}

func _get_cls(char_data: CharacterData) -> String:
	return char_data.tags[0] if char_data.tags.size() > 0 else "战士"

const _CHARACTER_PRELOADS = [
	preload("res://resources/characters/漩涡鸣人.tres"),
	preload("res://resources/characters/宇智波佐助.tres"),
	preload("res://resources/characters/宇智波佐助（疾风传）.tres"),
	preload("res://resources/characters/春野樱.tres"),
]

func _spawn_character_showcase() -> void:
	for res in _CHARACTER_PRELOADS:
		if res is CharacterData:
			_add_mini_card(res as CharacterData)

func _add_mini_card(char_data: CharacterData) -> void:
	var cls := _get_cls(char_data)
	var av_bg: Color     = _AVATAR_BG.get(cls,    Color("#B5D4F4"))
	var av_bdr: Color    = _AVATAR_BORDER.get(cls, Color("#185FA5"))
	var bar_col: Color   = _NAME_BAR.get(cls,      Color("#2C2C2A"))
	var name_col: Color  = _NAME_TEXT.get(cls,     Color("#FAC775"))
	var info_col: Color  = _INFO_COLOR.get(cls,    Color("#3B6D11"))

	# Outer container: 90 wide × 145 tall (card 120 + text below)
	var card := Control.new()
	card.custom_minimum_size = Vector2(90, 145)
	character_showcase.add_child(card)

	# Card border frame (90×120)
	var frame := Panel.new()
	frame.anchor_right = 1.0
	frame.offset_bottom = 120.0
	var frame_s := StyleBoxFlat.new()
	frame_s.bg_color = Color("#FFFDF5")
	frame_s.border_color = Color("#2C2C2A")
	frame_s.set_border_width_all(2)
	frame_s.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", frame_s)
	card.add_child(frame)

	# Avatar box: x=12, y=8, w=66, h=74
	var av_panel := Panel.new()
	av_panel.offset_left = 12.0
	av_panel.offset_top = 8.0
	av_panel.offset_right = 78.0
	av_panel.offset_bottom = 82.0
	var av_s := StyleBoxFlat.new()
	av_s.bg_color = av_bg
	av_s.border_color = av_bdr
	av_s.set_border_width_all(2)
	av_s.set_corner_radius_all(4)
	av_panel.add_theme_stylebox_override("panel", av_s)
	card.add_child(av_panel)

	if char_data.portrait != null:
		var tr := TextureRect.new()
		tr.texture = char_data.portrait
		tr.anchor_right = 1.0; tr.anchor_bottom = 1.0
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_panel.add_child(tr)
	else:
		var av_lbl := Label.new()
		av_lbl.text = char_data.character_name.left(1)
		av_lbl.add_theme_font_size_override("font_size", 28)
		av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_lbl.anchor_right = 1.0
		av_lbl.anchor_bottom = 1.0
		av_panel.add_child(av_lbl)

	# Name bar: y=98, h=18, inside card
	var name_bar := ColorRect.new()
	name_bar.offset_top = 98.0
	name_bar.offset_right = 90.0
	name_bar.offset_bottom = 116.0
	name_bar.color = bar_col
	card.add_child(name_bar)

	var name_lbl := Label.new()
	name_lbl.offset_top = 98.0
	name_lbl.offset_right = 90.0
	name_lbl.offset_bottom = 116.0
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	card.add_child(name_lbl)

	# HP + class (below card frame)
	var hp_lbl := Label.new()
	hp_lbl.offset_top = 120.0
	hp_lbl.offset_right = 90.0
	hp_lbl.offset_bottom = 133.0
	hp_lbl.text = "HP %d · %s" % [char_data.max_hp, cls]
	hp_lbl.add_theme_font_size_override("font_size", 10)
	hp_lbl.add_theme_color_override("font_color", info_col)
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(hp_lbl)

	# Skill names (below HP line)
	if char_data.skills.size() > 0:
		var names: Array[String] = []
		for sk in char_data.skills:
			names.append(sk.skill_name)
		var sk_lbl := Label.new()
		sk_lbl.offset_top = 133.0
		sk_lbl.offset_right = 90.0
		sk_lbl.offset_bottom = 145.0
		sk_lbl.text = " · ".join(PackedStringArray(names))
		sk_lbl.add_theme_font_size_override("font_size", 9)
		sk_lbl.add_theme_color_override("font_color", Color("#888780"))
		sk_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sk_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sk_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		card.add_child(sk_lbl)
