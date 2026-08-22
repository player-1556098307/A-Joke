## TowerSelect — 慈悲尖塔选人场景（房间式队伍）
## 1号槽位=玩家（真人，默认）；2/3号槽位可填充 AI 队友，空槽位不参战（单人/双人/三人由填充决定）
## ⇄ 按钮可交换站位（角色+模式一起换，影响战斗中座位顺序与距离）
## 样式与 PvE 选人一致：角色卡 + 等级筛选 + 详情预览 + 技能卡
extends Control

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
const GRADE_ORDER := { "S": 0, "A": 1, "B": 2, "C": 3 }

## 槽位模式：0=真人（仅1号玩家槽固定），1=AI（托管队友），-1=空（不参战）
## 2/3号槽位仅支持 空/AI（本地单机无第二真人输入；真人队友留待联机部署开放）
const MODE_HUMAN := 0
const MODE_AI := 1
const MODE_EMPTY := -1

var _chars: Array[CharacterData] = []
var _active_slot: int = 0
var _selections: Array[int] = [-1, -1, -1]
var _slot_modes: Array[int] = [MODE_HUMAN, MODE_EMPTY, MODE_EMPTY]
var _grade_filter: String = ""

var _list_vbox: VBoxContainer
var _card_buttons: Array[Button] = []
var _card_chars: Array[CharacterData] = []
var _card_name_lbls: Array[Label] = []
var _card_sel_badges: Array[Panel] = []
var _grade_buttons: Array[Button] = []
var _slot_buttons: Array[Button] = []
var _slot_name_lbls: Array[Label] = []
var _slot_mode_buttons: Array[Button] = []
var _avatar_box: Panel
var _avatar_label: Label
var _name_label: Label
var _stats_panel: Panel
var _skills_container: VBoxContainer
var _start_btn: Button
var _swap_pending: int = -1  # 换位模式：-1=未激活，>=0=源槽位索引
var _swap_buttons: Array[Button] = []

func _ready() -> void:
	for data in Characters.LIST:
		var res := load(data.get("res_path", "")) as CharacterData
		if res != null:
			_chars.append(res)
	_build_ui()
	_selections[0] = 0  # 玩家槽位默认选第一个角色
	_refresh_all()

func _get_cls(char_data: CharacterData) -> String:
	return char_data.tags[0] if char_data.tags.size() > 0 else "战士"

func _make_flat(bg: Color, bdr: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = bdr
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

# ── 界面构建 ───────────────────────────────────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#FFFDF5")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

	var border := Panel.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bf := StyleBoxFlat.new()
	bf.draw_center = false
	bf.border_color = Color("#2C2C2A")
	bf.set_border_width_all(3)
	bf.set_corner_radius_all(6)
	border.add_theme_stylebox_override("panel", bf)
	add_child(border)

	# 顶部：返回 + 标题 + 开始
	var back := Button.new()
	back.text = "← 返回"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(90, 32)
	back.anchor_left = 0.0; back.anchor_top = 0.0
	back.offset_left = 18.0; back.offset_top = 10.0
	back.offset_right = 108.0; back.offset_bottom = 42.0
	back.add_theme_stylebox_override("normal", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 6))
	back.add_theme_stylebox_override("hover",  _make_flat(Color("#3A3A37"), Color("#2C2C2A"), 0, 6))
	back.add_theme_stylebox_override("pressed",_make_flat(Color("#1F1F1D"), Color("#2C2C2A"), 0, 6))
	back.add_theme_color_override("font_color", Color("#FFFDF5"))
	back.add_theme_color_override("font_hover_color", Color("#FFFDF5"))
	back.add_theme_font_size_override("font_size", 12)
	back.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
	back.z_index = 100  # 始终置顶，不被任何后续元素覆盖
	add_child(back)

	var title := Label.new()
	title.text = "慈悲尖塔 — 队伍房间"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#2C2C2A"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 1.0
	title.offset_top = 10.0; title.offset_bottom = 44.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	_start_btn = Button.new()
	_start_btn.text = ""
	_start_btn.focus_mode = Control.FOCUS_NONE
	_start_btn.custom_minimum_size = Vector2(150, 34)
	# 靠右对齐（anchor_left=1.0 必须设置，否则 offset_left=-178 会让按钮横跨整个屏幕）
	_start_btn.anchor_left = 1.0; _start_btn.anchor_right = 1.0; _start_btn.anchor_top = 0.0
	_start_btn.offset_left = -178.0; _start_btn.offset_right = -18.0
	_start_btn.offset_top = 9.0; _start_btn.offset_bottom = 43.0
	_start_btn.add_theme_stylebox_override("normal", _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 3, 8))
	_start_btn.add_theme_stylebox_override("hover",  _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 3, 8))
	_start_btn.add_theme_stylebox_override("pressed",_make_flat(Color("#27500A"), Color("#2C2C2A"), 3, 8))
	_start_btn.add_theme_color_override("font_color", Color("#EAF3DE"))
	_start_btn.add_theme_font_size_override("font_size", 14)
	_start_btn.pressed.connect(_on_start)
	add_child(_start_btn)
	var start_lbl := Label.new()
	start_lbl.text = "开始闯关"
	start_lbl.add_theme_font_size_override("font_size", 14)
	start_lbl.add_theme_color_override("font_color", Color("#EAF3DE"))
	start_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_lbl.anchor_right = 1.0; start_lbl.anchor_bottom = 1.0
	_start_btn.add_child(start_lbl)

	# 房间说明
	var room_hint := Label.new()
	room_hint.text = "1号 = 你（玩家）；2/3号可添加 AI 队友，⇄可交换站位，空槽位不参战（真人联机后续开放）"
	room_hint.add_theme_font_size_override("font_size", 11)
	room_hint.add_theme_color_override("font_color", Color("#888780"))
	room_hint.anchor_left = 0.0; room_hint.anchor_top = 0.0
	room_hint.offset_left = 120.0; room_hint.offset_top = 44.0
	room_hint.offset_right = 560.0; room_hint.offset_bottom = 62.0
	room_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room_hint)

	# 左侧面板
	var left_bg := Panel.new()
	left_bg.anchor_left = 0.0; left_bg.anchor_top = 0.0
	left_bg.offset_left = 10.0; left_bg.offset_top = 64.0
	left_bg.offset_right = 340.0; left_bg.offset_bottom = 482.0
	var ls := StyleBoxFlat.new()
	ls.bg_color = Color("#FFFDF5"); ls.border_color = Color("#2C2C2A")
	ls.set_border_width_all(2); ls.set_corner_radius_all(4)
	left_bg.add_theme_stylebox_override("panel", ls)
	add_child(left_bg)

	var filter_bar := HBoxContainer.new()
	filter_bar.anchor_left = 0.0; filter_bar.anchor_top = 0.0
	filter_bar.offset_left = 18.0; filter_bar.offset_top = 70.0
	filter_bar.offset_right = 340.0; filter_bar.offset_bottom = 100.0
	filter_bar.add_theme_constant_override("separation", 6)
	add_child(filter_bar)
	_build_grade_filter(filter_bar)

	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_top = 0.0; scroll.anchor_right = 1.0; scroll.anchor_bottom = 1.0
	scroll.offset_left = 18.0; scroll.offset_top = 104.0
	scroll.offset_right = -12.0; scroll.offset_bottom = -58.0
	add_child(scroll)
	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_vbox)
	_build_character_cards()

	# 右侧面板
	var right_bg := Panel.new()
	right_bg.anchor_left = 0.0; right_bg.anchor_top = 0.0
	right_bg.offset_left = 348.0; right_bg.offset_top = 64.0
	right_bg.offset_right = 950.0; right_bg.offset_bottom = 482.0
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color("#FFFDF5"); rs.border_color = Color("#2C2C2A")
	rs.set_border_width_all(2); rs.set_corner_radius_all(4)
	right_bg.add_theme_stylebox_override("panel", rs)
	add_child(right_bg)

	_avatar_box = Panel.new()
	_avatar_box.anchor_left = 0.0; _avatar_box.anchor_top = 0.0
	_avatar_box.offset_left = 366.0; _avatar_box.offset_top = 78.0
	_avatar_box.offset_right = 526.0; _avatar_box.offset_bottom = 238.0
	add_child(_avatar_box)
	_avatar_label = Label.new()
	_avatar_label.add_theme_font_size_override("font_size", 72)
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_label.anchor_right = 1.0; _avatar_label.anchor_bottom = 1.0
	_avatar_box.add_child(_avatar_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color("#2C2C2A"))
	_name_label.anchor_left = 0.0; _name_label.anchor_top = 0.0
	_name_label.offset_left = 540.0; _name_label.offset_top = 78.0
	_name_label.offset_right = 760.0; _name_label.offset_bottom = 110.0
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	var info_lbl := Label.new()
	info_lbl.text = "角色详情预览 — 点击左侧角色分配给当前成员"
	info_lbl.add_theme_font_size_override("font_size", 11)
	info_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	info_lbl.anchor_left = 0.0; info_lbl.anchor_top = 0.0
	info_lbl.offset_left = 540.0; info_lbl.offset_top = 110.0
	info_lbl.offset_right = 930.0; info_lbl.offset_bottom = 128.0
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_lbl)

	_stats_panel = Panel.new()
	_stats_panel.anchor_left = 0.0; _stats_panel.anchor_top = 0.0
	_stats_panel.offset_left = 540.0; _stats_panel.offset_top = 134.0
	_stats_panel.offset_right = 934.0; _stats_panel.offset_bottom = 238.0
	add_child(_stats_panel)

	var sk_header := Label.new()
	sk_header.text = "技能"
	sk_header.add_theme_font_size_override("font_size", 12)
	sk_header.add_theme_color_override("font_color", Color("#2C2C2A"))
	sk_header.anchor_left = 0.0; sk_header.anchor_top = 0.0
	sk_header.offset_left = 540.0; sk_header.offset_top = 246.0
	sk_header.offset_right = 700.0; sk_header.offset_bottom = 266.0
	sk_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sk_header)
	_skills_container = VBoxContainer.new()
	_skills_container.anchor_left = 0.0; _skills_container.anchor_top = 0.0
	_skills_container.anchor_right = 1.0; _skills_container.anchor_bottom = 1.0
	_skills_container.offset_left = 540.0; _skills_container.offset_top = 270.0
	_skills_container.offset_right = -12.0; _skills_container.offset_bottom = -58.0
	_skills_container.add_theme_constant_override("separation", 6)
	add_child(_skills_container)

	# 底部成员槽位条（房间式：空/AI/真人）
	var slot_bg := Panel.new()
	slot_bg.anchor_left = 0.0; slot_bg.anchor_top = 0.0; slot_bg.anchor_right = 1.0
	slot_bg.offset_left = 10.0; slot_bg.offset_top = 488.0
	slot_bg.offset_right = -10.0; slot_bg.offset_bottom = 532.0
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color("#F1EFE8"); ss.border_color = Color("#2C2C2A")
	ss.set_border_width_all(2); ss.set_corner_radius_all(4)
	slot_bg.add_theme_stylebox_override("panel", ss)
	add_child(slot_bg)
	var slots := HBoxContainer.new()
	slots.anchor_left = 0.0; slots.anchor_top = 0.0; slots.anchor_right = 1.0
	slots.offset_left = 14.0; slots.offset_top = 5.0; slots.offset_right = -14.0; slots.offset_bottom = 39.0
	slots.add_theme_constant_override("separation", 12)
	slot_bg.add_child(slots)
	for i in 3:
		var slot_box := HBoxContainer.new()
		slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot_box.add_theme_constant_override("separation", 6)
		slots.add_child(slot_box)
		var btn := Button.new()
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_active_slot.bind(i))
		slot_box.add_child(btn)
		_slot_buttons.append(btn)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
		lbl.offset_left = 10.0; lbl.offset_right = -4.0
		btn.add_child(lbl)
		_slot_name_lbls.append(lbl)
		var mode_btn := Button.new()
		mode_btn.text = ""
		mode_btn.focus_mode = Control.FOCUS_NONE
		mode_btn.custom_minimum_size = Vector2(64, 30)
		mode_btn.add_theme_font_size_override("font_size", 10)
		mode_btn.pressed.connect(_toggle_slot_mode.bind(i))
		slot_box.add_child(mode_btn)
		_slot_mode_buttons.append(mode_btn)
		var swap_btn := Button.new()
		swap_btn.text = "⇄"
		swap_btn.focus_mode = Control.FOCUS_NONE
		swap_btn.custom_minimum_size = Vector2(36, 30)
		swap_btn.add_theme_font_size_override("font_size", 12)
		swap_btn.pressed.connect(_on_swap_pressed.bind(i))
		slot_box.add_child(swap_btn)
		_swap_buttons.append(swap_btn)

# ── 等级筛选 ───────────────────────────────────────────────────────

func _build_grade_filter(bar: HBoxContainer) -> void:
	var all_btn := Button.new()
	all_btn.text = "全部"
	all_btn.focus_mode = Control.FOCUS_NONE
	all_btn.custom_minimum_size = Vector2(52, 26)
	all_btn.add_theme_font_size_override("font_size", 11)
	all_btn.pressed.connect(func(): _set_grade_filter(""))
	bar.add_child(all_btn)
	_grade_buttons.append(all_btn)
	for g in ["S", "A", "B", "C"]:
		var btn := Button.new()
		btn.text = "%s级" % g
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(52, 26)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_set_grade_filter.bind(g))
		bar.add_child(btn)
		_grade_buttons.append(btn)
	_refresh_grade_filter_style()

func _set_grade_filter(grade: String) -> void:
	_grade_filter = grade
	_refresh_grade_filter_style()
	_update_list_visibility()

func _refresh_grade_filter_style() -> void:
	for i in _grade_buttons.size():
		var btn: Button = _grade_buttons[i]
		var label: String = btn.text
		var grade: String = label.replace("级", "") if label != "全部" else ""
		var is_active := (grade == _grade_filter) or (label == "全部" and _grade_filter == "")
		if is_active:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 2, 4))
			btn.add_theme_color_override("font_color", Color("#EAF3DE"))
		else:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 1, 4))
			btn.add_theme_color_override("font_color", Color("#2C2C2A"))

func _matches_filter(char_data: CharacterData) -> bool:
	return _grade_filter == "" or char_data.grade == _grade_filter

func _sorted_characters() -> Array[CharacterData]:
	var sorted: Array[CharacterData] = []
	for c in _chars:
		sorted.append(c)
	sorted.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		var ga: int = GRADE_ORDER.get(a.grade, 9)
		var gb: int = GRADE_ORDER.get(b.grade, 9)
		if ga != gb:
			return ga < gb
		return false)
	return sorted

# ── 角色卡列表 ─────────────────────────────────────────────────────

func _build_character_cards() -> void:
	for c in _list_vbox.get_children():
		c.queue_free()
	_card_buttons.clear()
	_card_chars.clear()
	_card_name_lbls.clear()
	_card_sel_badges.clear()
	for char_data in _sorted_characters():
		var card := _make_character_card(char_data)
		_list_vbox.add_child(card)
		_card_buttons.append(card)
		_card_chars.append(char_data)
		card.pressed.connect(_select_for_active.bind(char_data))
	_update_list_visibility()

func _update_list_visibility() -> void:
	for i in _card_buttons.size():
		_card_buttons[i].visible = _matches_filter(_card_chars[i])

func _make_character_card(char_data: CharacterData) -> Button:
	var cls := _get_cls(char_data)
	var bar_col: Color  = CLASS_BAR_COLOR.get(cls,   Color("#639922"))
	var av_bg: Color    = CLASS_AVATAR_BG.get(cls,   Color("#B5D4F4"))
	var av_bdr: Color   = CLASS_AVATAR_BORDER.get(cls, Color("#185FA5"))
	var badge_bg: Color = CLASS_BADGE_BG.get(cls,   Color("#185FA5"))
	var badge_txt: Color= CLASS_BADGE_TEXT.get(cls,  Color("#E6F1FB"))

	var card := Button.new()
	card.custom_minimum_size = Vector2(304, 88)
	card.text = ""
	card.focus_mode = Control.FOCUS_NONE
	card.add_theme_stylebox_override("normal", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
	card.add_theme_stylebox_override("hover",  _make_flat(Color("#F5F3EC"), Color("#B4B2A9"), 2, 6))
	card.add_theme_stylebox_override("pressed",_make_flat(Color("#EAF3DE"), Color("#3B6D11"), 3, 6))

	var bar := ColorRect.new()
	bar.color = bar_col
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_top = 0.0; bar.anchor_bottom = 1.0
	bar.offset_right = 6.0
	card.add_child(bar)

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
		av_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
		av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_lbl.anchor_right = 1.0; av_lbl.anchor_bottom = 1.0
		av.add_child(av_lbl)

	var name_lbl := Label.new()
	name_lbl.layout_mode = 0
	name_lbl.offset_left = 84.0; name_lbl.offset_top = 8.0
	name_lbl.offset_right = 268.0; name_lbl.offset_bottom = 28.0
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)
	_card_name_lbls.append(name_lbl)

	var cb := _make_inline_badge(cls, badge_bg, badge_txt, 36, 14, 84, 30)
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cb)
	var lb := _make_inline_badge("%s级" % char_data.grade, Color("#444441"), Color("#D3D1C7"), 24, 14, 126, 30)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lb)

	var hp_lbl := Label.new()
	hp_lbl.layout_mode = 0
	hp_lbl.offset_left = 84.0; hp_lbl.offset_top = 50.0
	hp_lbl.offset_right = 268.0; hp_lbl.offset_bottom = 64.0
	hp_lbl.text = "HP %.1f" % char_data.max_hp
	hp_lbl.add_theme_font_size_override("font_size", 10)
	hp_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hp_lbl)

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

	var sel_panel := Panel.new()
	sel_panel.layout_mode = 0
	sel_panel.offset_left = 244.0; sel_panel.offset_top = 8.0
	sel_panel.offset_right = 296.0; sel_panel.offset_bottom = 24.0
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

# ── 交互 ───────────────────────────────────────────────────────────

func _set_active_slot(slot: int) -> void:
	if _swap_pending >= 0:
		if slot != _swap_pending:
			_swap_slots(_swap_pending, slot)
		else:
			_swap_pending = -1
			_refresh_all()
		return
	_active_slot = slot
	_refresh_all()

## 切换槽位模式（2/3号）：空 ↔ AI（本地单机不支持填真人；真人队友留待联机部署）
func _toggle_slot_mode(slot: int) -> void:
	if _slot_modes[slot] == MODE_HUMAN:
		return  # 真人槽位不可切换
	if _slot_modes[slot] == MODE_EMPTY:
		_slot_modes[slot] = MODE_AI
		# 填充时若未选角色，默认给一个
		if _selections[slot] < 0:
			_selections[slot] = slot % _chars.size()
	else:
		_slot_modes[slot] = MODE_EMPTY
	_refresh_all()

## 换位按钮：点击进入换位模式，再点另一个槽位完成交换
func _on_swap_pressed(slot: int) -> void:
	if _swap_pending == slot:
		_swap_pending = -1  # 再次点击取消
	elif _swap_pending >= 0:
		_swap_slots(_swap_pending, slot)
	else:
		_swap_pending = slot
	_refresh_all()

## 交换两个槽位的角色和模式
func _swap_slots(a: int, b: int) -> void:
	var tmp_sel: int = _selections[a]
	_selections[a] = _selections[b]
	_selections[b] = tmp_sel
	var tmp_mode: int = _slot_modes[a]
	_slot_modes[a] = _slot_modes[b]
	_slot_modes[b] = tmp_mode
	_swap_pending = -1
	_active_slot = a
	_refresh_all()

## 获取真人玩家所在槽位
func _get_human_slot() -> int:
	for i in 3:
		if _slot_modes[i] == MODE_HUMAN:
			return i
	return 0  # fallback（不应发生）

func _select_for_active(char_data: CharacterData) -> void:
	var idx := _chars.find(char_data)
	if idx >= 0:
		_selections[_active_slot] = idx
		# 空槽位选角色后自动填充为 AI（可再切真人）
		if _active_slot > 0 and _slot_modes[_active_slot] == MODE_EMPTY:
			_slot_modes[_active_slot] = MODE_AI
	_refresh_all()

func _refresh_all() -> void:
	_refresh_list_highlight()
	_refresh_slots()
	_refresh_detail()
	_update_start_label()

func _refresh_list_highlight() -> void:
	var selected_idx: int = _selections[_active_slot]
	for i in _card_buttons.size():
		var is_sel: bool = i == selected_idx and _matches_filter(_card_chars[i])
		if is_sel:
			_card_buttons[i].add_theme_stylebox_override("normal", _make_flat(Color("#EAF3DE"), Color("#3B6D11"), 3, 6))
			_card_name_lbls[i].add_theme_color_override("font_color", Color("#27500A"))
		else:
			_card_buttons[i].add_theme_stylebox_override("normal", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
			_card_name_lbls[i].add_theme_color_override("font_color", Color("#2C2C2A"))
		_card_sel_badges[i].visible = is_sel

func _refresh_slots() -> void:
	for i in 3:
		var btn: Button = _slot_buttons[i]
		var lbl: Label = _slot_name_lbls[i]
		var mode_btn: Button = _slot_mode_buttons[i]
		var swap_btn: Button = _swap_buttons[i]
		var is_active: bool = i == _active_slot
		var mode: int = _slot_modes[i]
		var is_human: bool = mode == MODE_HUMAN
		var filled: bool = mode >= 0
		var is_swap_src: bool = _swap_pending == i
		var is_swap_mode: bool = _swap_pending >= 0
		if is_swap_src:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#FCE4E4"), Color("#E24B4A"), 3, 6))
		elif is_active and not is_swap_mode:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#EAF3DE"), Color("#3B6D11"), 3, 6))
		elif filled:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
		else:
			btn.add_theme_stylebox_override("normal", _make_flat(Color("#F7F5F0"), Color("#D3D1C7"), 1, 6))
		var sel: int = _selections[i]
		if is_human:
			lbl.text = "玩家 · %s%s" % [_chars[sel].character_name if sel >= 0 else "未选择", " ◈" if is_active else ""]
			lbl.add_theme_color_override("font_color", Color("#27500A") if is_active else Color("#2C2C2A"))
		elif mode == MODE_EMPTY:
			lbl.text = "＋ 空槽位%s" % (" ◈" if is_active else "")
			lbl.add_theme_color_override("font_color", Color("#888780"))
		else:
			var role: String = "AI" if mode == MODE_AI else "真人"
			lbl.text = "%s成员 · %s%s" % [role, _chars[sel].character_name if sel >= 0 else "未选择", " ◈" if is_active else ""]
			lbl.add_theme_color_override("font_color", Color("#27500A") if is_active else Color("#2C2C2A"))
		# 模式按钮
		if is_human:
			mode_btn.text = "👤 玩家"
			mode_btn.add_theme_stylebox_override("normal", _make_flat(Color("#FFF6E0"), Color("#C9A84C"), 1, 4))
			mode_btn.add_theme_color_override("font_color", Color("#8B6514"))
		else:
			# 非真人槽位：空 ↔ AI（真人留待联机）
			if mode == MODE_EMPTY:
				mode_btn.text = "＋ 空"
				mode_btn.add_theme_stylebox_override("normal", _make_flat(Color("#F1EFE8"), Color("#B4B2A9"), 1, 4))
				mode_btn.add_theme_color_override("font_color", Color("#5F5E5A"))
			else:
				mode_btn.text = "🤖 AI"
				mode_btn.add_theme_stylebox_override("normal", _make_flat(Color("#EEF4FB"), Color("#2A6AB0"), 1, 4))
				mode_btn.add_theme_color_override("font_color", Color("#2A6AB0"))
		# 换位按钮
		if is_swap_src:
			swap_btn.text = "取消"
			swap_btn.add_theme_stylebox_override("normal", _make_flat(Color("#E24B4A"), Color("#2C2C2A"), 1, 4))
			swap_btn.add_theme_color_override("font_color", Color("#FFFDF5"))
		elif is_swap_mode:
			swap_btn.text = "⇄"
			swap_btn.add_theme_stylebox_override("normal", _make_flat(Color("#FFF6E0"), Color("#C9A84C"), 1, 4))
			swap_btn.add_theme_color_override("font_color", Color("#8B6514"))
		else:
			swap_btn.text = "⇄"
			swap_btn.add_theme_stylebox_override("normal", _make_flat(Color("#F1EFE8"), Color("#B4B2A9"), 1, 4))
			swap_btn.add_theme_color_override("font_color", Color("#5F5E5A"))

func _refresh_detail() -> void:
	var sel: int = _selections[_active_slot]
	if sel < 0 or sel >= _chars.size():
		_name_label.text = "未选择"
		_avatar_label.text = "?"
		return
	var c: CharacterData = _chars[sel]
	var cls := _get_cls(c)
	_name_label.text = c.character_name
	_avatar_label.text = c.character_name.left(1)
	_avatar_label.add_theme_color_override("font_color", Color("#2C2C2A"))
	var av_s := StyleBoxFlat.new()
	av_s.bg_color = CLASS_AVATAR_BG.get(cls, Color("#B5D4F4"))
	av_s.border_color = CLASS_AVATAR_BORDER.get(cls, Color("#185FA5"))
	av_s.set_border_width_all(3); av_s.set_corner_radius_all(8)
	_avatar_box.add_theme_stylebox_override("panel", av_s)
	var portrait_rect := _avatar_box.get_node_or_null("PortraitRect") as TextureRect
	if portrait_rect == null:
		portrait_rect = TextureRect.new()
		portrait_rect.name = "PortraitRect"
		portrait_rect.anchor_right = 1.0; portrait_rect.anchor_bottom = 1.0
		portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_avatar_box.add_child(portrait_rect)
	if c.portrait != null:
		portrait_rect.texture = c.portrait
		portrait_rect.visible = true
		_avatar_label.visible = false
	else:
		portrait_rect.visible = false
		_avatar_label.visible = true
	_build_stats_panel(c)
	_build_skill_cards(c)

func _build_stats_panel(char_data: CharacterData) -> void:
	for child in _stats_panel.get_children():
		child.queue_free()
	var sp_s := StyleBoxFlat.new()
	sp_s.bg_color = Color("#F1EFE8")
	sp_s.border_color = Color("#D3D1C7")
	sp_s.set_border_width_all(1); sp_s.set_corner_radius_all(6)
	_stats_panel.add_theme_stylebox_override("panel", sp_s)
	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left = 12.0; vbox.offset_top = 10.0
	vbox.offset_right = -12.0; vbox.offset_bottom = -10.0
	_stats_panel.add_child(vbox)
	var cls := _get_cls(char_data)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	vbox.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	name_row.add_child(name_lbl)
	var cls_bg: Color = CLASS_BADGE_BG.get(cls, Color("#185FA5"))
	var cls_txt: Color = CLASS_BADGE_TEXT.get(cls, Color("#E6F1FB"))
	name_row.add_child(_make_inline_badge(cls, cls_bg, cls_txt, 36, 14, 0, 0))
	name_row.add_child(_make_inline_badge("%s级" % char_data.grade, Color("#444441"), Color("#D3D1C7"), 24, 14, 0, 0))
	var base_energy := char_data.basic_attack_cost
	var base_range := char_data.skills[0].max_range if char_data.skills.size() > 0 else 1
	if base_range >= 999:
		base_range = 1
	var stat_vals := [
		str(char_data.max_hp), str(base_energy), "1", str(base_range), str(char_data.skills.size()),
	]
	var cells_row := HBoxContainer.new()
	cells_row.add_theme_constant_override("separation", 6)
	cells_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(cells_row)
	for i in STAT_DEFS.size():
		cells_row.add_child(_make_stat_cell(STAT_DEFS[i][0], stat_vals[i], STAT_DEFS[i][1]))

func _make_stat_cell(key: String, value: String, val_color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(70, 36)
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

func _build_skill_cards(char_data: CharacterData) -> void:
	for child in _skills_container.get_children():
		child.queue_free()
	var unlockable: Array[SkillData] = []
	for sk in char_data.skills:
		for eff in sk.effects:
			if eff.effect_type == SkillEffect.EffectType.UNLOCK_SKILL and eff.unlock_skill != null:
				unlockable.append(eff.unlock_skill)
	for i in char_data.skills.size():
		_skills_container.add_child(_make_skill_row(char_data.skills[i], i, false))
	for sk in unlockable:
		_skills_container.add_child(_make_skill_row(sk, -1, true))

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
		bg = Color("#F5F3EC"); accent = Color("#D3D1C7")
		name_col = Color("#B4B2A9"); detail_col = Color("#D3D1C7")
	else:
		var c: Array = SKILL_COLORS[idx % SKILL_COLORS.size()]
		bg = c[0]; accent = c[1]; name_col = c[3]; detail_col = c[3].lightened(0.25)
	var row_s := StyleBoxFlat.new()
	row_s.bg_color = bg; row_s.border_color = accent
	row_s.set_border_width_all(1); row_s.set_corner_radius_all(4)
	row.add_theme_stylebox_override("panel", row_s)
	var bar := ColorRect.new()
	bar.color = accent
	bar.anchor_top = 0.0; bar.anchor_bottom = 1.0
	bar.offset_right = 4.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
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

func _update_start_label() -> void:
	var lbl := _start_btn.get_child(0) as Label
	if lbl == null:
		return
	var hs: int = _get_human_slot()
	if _selections[hs] < 0:
		lbl.text = "请先选择玩家角色"
		return
	var count := 0
	for i in 3:
		if _slot_modes[i] >= 0 and _selections[i] >= 0:
			count += 1
	lbl.text = "开始闯关（%d人队伍）" % count

## 构建队伍配置（纯函数）：只收已填充槽位，空槽位不参战
## 返回 Array[Dictionary]：{ character, is_human }
func _build_tower_config() -> Array:
	var party: Array = []
	for i in 3:
		if _slot_modes[i] < 0:
			continue  # 空槽位不参战
		var sel: int = _selections[i]
		if sel < 0 or sel >= _chars.size():
			return []  # 已填充但未选角色（异常）
		party.append({
			"character": _chars[sel],
			"is_human": _slot_modes[i] == MODE_HUMAN,
		})
	return party

func _on_start() -> void:
	# 真人玩家必须已选角色
	var hs: int = _get_human_slot()
	if _selections[hs] < 0 or _selections[hs] >= _chars.size():
		return
	var party := _build_tower_config()
	if party.is_empty():
		return
	SceneManager.last_tower_config = { "players": party }
	# 先过塔门对话（开场白/死亡对话），再进入战斗
	SceneManager.go_to("res://scenes/tower/tower_gate.tscn")
