## 游戏结束场景 — 胜负展示 + 3-tab分析面板（统计/回放/技能记录）
## 从 SceneManager.pending_game_result 读取 MatchRecord 并构建完整结算UI
extends Control

var _record: MatchRecord
var _current_tab: String = "stats"
var _replay_mode: String = "log"
var _replay_index: int = 0
var _auto_playing: bool = false
var _replay_speed: float = 1.0
var _replay_timer: Timer
var _replay_auto_btn: Button
var _skill_log_mode: String = "timeline"

@onready var top_bar_label: Label = $TopBar/TopBarLabel
@onready var victory_label: Label = $WinnerPanel/VictoryBanner/VictoryLabel
@onready var victory_banner: PanelContainer = $WinnerPanel/VictoryBanner
@onready var crown_label: Label = $WinnerPanel/CrownLabel
@onready var winner_avatar: PanelContainer = $WinnerPanel/WinnerAvatar
@onready var winner_avatar_label: Label = $WinnerPanel/WinnerAvatar/WinnerAvatarLabel
@onready var winner_name_label: Label = $WinnerPanel/WinnerNameBar/WinnerNameLabel
@onready var winner_name_bar: PanelContainer = $WinnerPanel/WinnerNameBar
@onready var final_hp_label: Label = $WinnerPanel/FinalHPBox/FinalHPLabel
@onready var final_hp_box: PanelContainer = $WinnerPanel/FinalHPBox
@onready var unlocked_skill_label: Label = $WinnerPanel/UnlockedSkillLabel
@onready var elimination_list: VBoxContainer = $EliminationPanel/EliminationList
@onready var btn_replay: Button = $ActionPanel/BtnReplay
@onready var btn_reselect: Button = $ActionPanel/BtnReselect
@onready var btn_main_menu: Button = $ActionPanel/BtnMainMenu
@onready var btn_review: Button = $ActionPanel/BtnReview
@onready var btn_skill_log: Button = $ActionPanel/BtnSkillLog
@onready var winner_panel: VBoxContainer = $WinnerPanel
@onready var border_frame: Panel = $BorderFrame
@onready var left_panel_bg: Panel = $LeftPanelBg
@onready var right_panel_bg: Panel = $RightPanelBg

var _tab_bar: HBoxContainer
var _tab_content: PanelContainer
var _stats_panel: Control
var _replay_panel: Control
var _skill_log_panel: Control

var _log_mode_scroll: ScrollContainer
var _play_mode_panel: VBoxContainer
var _timeline_scroll: ScrollContainer
var _by_char_scroll: ScrollContainer
var _play_content: VBoxContainer

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s

func _ready() -> void:
	_setup_replay_timer()
	_apply_styling()
	_style_action_buttons()

	btn_replay.pressed.connect(_on_replay_pressed)
	btn_reselect.pressed.connect(_on_reselect_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)

	var result: Dictionary = SceneManager.pending_game_result
	var record: MatchRecord = result.get("match_record")
	if record:
		setup(record)
	else:
		top_bar_label.text = "⚔ 战斗结束"
		victory_label.text = "游戏结束"
		crown_label.hide()
		winner_avatar_label.text = "?"
		winner_name_label.text = "—"
		final_hp_label.text = ""
		btn_review.disabled = true
		btn_skill_log.disabled = true

func setup(record: MatchRecord) -> void:
	_record = record
	top_bar_label.text = "⚔ 战斗结束 — 第 %d 回合" % record.total_rounds
	_build_winner_section()
	_build_elimination_list()
	_build_tab_section()
	_switch_tab("stats")
	btn_review.disabled = false
	btn_review.modulate = Color(1, 1, 1, 1)
	btn_skill_log.disabled = false
	btn_skill_log.modulate = Color(1, 1, 1, 1)
	btn_review.pressed.connect(_on_review_pressed)
	btn_skill_log.pressed.connect(_on_skill_log_pressed)

# ── Styling ─────────────────────────────────────────────────────────────────

func _apply_styling() -> void:
	var bf := StyleBoxFlat.new()
	bf.draw_center = false
	bf.border_color = Color("#2C2C2A")
	bf.set_border_width_all(3)
	bf.set_corner_radius_all(6)
	border_frame.add_theme_stylebox_override("panel", bf)

	left_panel_bg.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#2C2C2A"), 2, 4))
	right_panel_bg.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#2C2C2A"), 2, 4))

func _style_action_buttons() -> void:
	btn_replay.add_theme_stylebox_override("normal",  _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 2, 8))
	btn_replay.add_theme_stylebox_override("hover",   _make_flat(Color("#4A8A16"), Color("#2C2C2A"), 2, 8))
	btn_replay.add_theme_stylebox_override("pressed", _make_flat(Color("#27500A"), Color("#2C2C2A"), 2, 8))
	btn_replay.add_theme_color_override("font_color",         Color("#EAF3DE"))
	btn_replay.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
	btn_replay.add_theme_color_override("font_pressed_color", Color("#C0DD97"))

	btn_reselect.add_theme_stylebox_override("normal",  _make_flat(Color("#185FA5"), Color("#2C2C2A"), 2, 8))
	btn_reselect.add_theme_stylebox_override("hover",   _make_flat(Color("#1E78CC"), Color("#2C2C2A"), 2, 8))
	btn_reselect.add_theme_stylebox_override("pressed", _make_flat(Color("#0C447C"), Color("#2C2C2A"), 2, 8))
	btn_reselect.add_theme_color_override("font_color",         Color("#E6F1FB"))
	btn_reselect.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
	btn_reselect.add_theme_color_override("font_pressed_color", Color("#B5D4F4"))

	btn_main_menu.add_theme_stylebox_override("normal",  _make_flat(Color("#F1EFE8"), Color("#B4B2A9"), 1, 6))
	btn_main_menu.add_theme_stylebox_override("hover",   _make_flat(Color("#E8E6DF"), Color("#888780"), 1, 6))
	btn_main_menu.add_theme_stylebox_override("pressed", _make_flat(Color("#DEDAD3"), Color("#666460"), 1, 6))
	btn_main_menu.add_theme_color_override("font_color",         Color("#5F5E5A"))
	btn_main_menu.add_theme_color_override("font_hover_color",   Color("#2C2C2A"))
	btn_main_menu.add_theme_color_override("font_pressed_color", Color("#2C2C2A"))

	btn_review.add_theme_stylebox_override("normal",  _make_flat(Color("#EAF3DE"), Color("#C0DD97"), 1, 6))
	btn_review.add_theme_stylebox_override("hover",   _make_flat(Color("#D8ECC5"), Color("#3B6D11"), 1, 6))
	btn_review.add_theme_color_override("font_color",         Color("#27500A"))
	btn_review.add_theme_color_override("font_hover_color",   Color("#1A3D07"))
	btn_skill_log.add_theme_stylebox_override("normal",  _make_flat(Color("#EEEDFE"), Color("#AFA9EC"), 1, 6))
	btn_skill_log.add_theme_stylebox_override("hover",   _make_flat(Color("#DDDBF8"), Color("#534AB7"), 1, 6))
	btn_skill_log.add_theme_color_override("font_color",         Color("#26215C"))
	btn_skill_log.add_theme_color_override("font_hover_color",   Color("#534AB7"))

# ── Winner section ──────────────────────────────────────────────────────────

func _build_winner_section() -> void:
	var stats: PlayerMatchStats = _record.player_stats.get(_record.winner_id)
	if stats == null:
		victory_label.text = "Draw！"
		victory_banner.add_theme_stylebox_override("panel", _make_flat(Color("#5F5E5A"), Color("#2C2C2A"), 2, 6))
		crown_label.text = "🤝"
		winner_avatar_label.text = "—"
		winner_name_label.text = "平局"
		winner_name_label.add_theme_color_override("font_color", Color("#FAC775"))
		final_hp_label.text = ""
		unlocked_skill_label.visible = false
		return

	victory_label.text = "Victory！"
	victory_banner.add_theme_stylebox_override("panel", _make_flat(Color("#BA7517"), Color("#2C2C2A"), 2, 6))
	crown_label.text = "👑"

	var portrait_rect := winner_avatar.get_node_or_null("WinnerPortraitRect") as TextureRect
	if portrait_rect == null:
		portrait_rect = TextureRect.new()
		portrait_rect.name = "WinnerPortraitRect"
		portrait_rect.anchor_right = 1.0
		portrait_rect.anchor_bottom = 1.0
		portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		winner_avatar.add_child(portrait_rect)

	if stats.character.portrait != null:
		portrait_rect.texture = stats.character.portrait
		portrait_rect.visible = true
		winner_avatar_label.visible = false
	else:
		portrait_rect.visible = false
		winner_avatar_label.visible = true
		winner_avatar_label.text = stats.character.character_name.left(1)
	var cls := _get_cls(stats)
	var av_bg: Color = Color("#B5D4F4")
	var av_bdr: Color = Color("#185FA5")
	if cls == "法师": av_bg = Color("#EEEDFE"); av_bdr = Color("#534AB7")
	elif cls == "坦克": av_bg = Color("#F4C0D1"); av_bdr = Color("#993556")
	elif cls == "刺客": av_bg = Color("#F5C4B3"); av_bdr = Color("#993C1D")
	winner_avatar.add_theme_stylebox_override("panel", _make_flat(av_bg, av_bdr, 2, 8))

	winner_name_bar.add_theme_stylebox_override("panel", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 4))
	winner_name_label.text = "%s（%s）" % [stats.player_name, stats.character.character_name]
	winner_name_label.add_theme_color_override("font_color", Color("#FAC775"))

	final_hp_box.add_theme_stylebox_override("panel", _make_flat(Color("#EAF3DE"), Color("#C0DD97"), 1, 4))
	final_hp_label.text = "最终 HP %d / %d" % [stats.final_hp, stats.max_hp]
	final_hp_label.add_theme_color_override("font_color", Color("#3B6D11"))

	if stats.unlocked_skills.size() > 0:
		var names: Array[String] = []
		for s in stats.unlocked_skills:
			names.append("【%s】" % s)
		unlocked_skill_label.text = "本局解锁：" + "、".join(names)
		unlocked_skill_label.visible = true
		unlocked_skill_label.add_theme_color_override("font_color", Color("#3C3489"))

func _get_cls(stats: PlayerMatchStats) -> String:
	return stats.character.tags[0] if stats.character.tags.size() > 0 else "战士"

# ── Elimination list ────────────────────────────────────────────────────────

func _build_elimination_list() -> void:
	for child in elimination_list.get_children():
		child.queue_free()

	var elim_order: Array[Dictionary] = []
	for pid in _record.player_stats:
		var ps: PlayerMatchStats = _record.player_stats[pid]
		if ps.elimination_round >= 0:
			elim_order.append({"pid": pid, "round": ps.elimination_round, "reason": ps.elimination_reason})
	elim_order.sort_custom(func(a, b): return a["round"] < b["round"])

	var elim_colors := [Color("#E24B4A"), Color("#EF9F27"), Color("#888780")]
	var bg_colors   := [Color("#FCEBEB"), Color("#FAEEDA"), Color("#F1EFE8")]
	var bdr_colors  := [Color("#F7C1C1"), Color("#FAC775"), Color("#D3D1C7")]
	var ord_colors  := [Color("#791F1F"), Color("#412402"), Color("#5F5E5A")]
	var nm_colors   := [Color("#A32D2D"), Color("#633806"), Color("#444441")]

	for i in range(elim_order.size()):
		var entry: Dictionary = elim_order[i]
		var ps: PlayerMatchStats = _record.player_stats[entry["pid"]]
		var ci := mini(i, 2)

		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row_s := StyleBoxFlat.new()
		row_s.bg_color = bg_colors[ci]; row_s.border_color = bdr_colors[ci]
		row_s.set_border_width_all(1); row_s.set_corner_radius_all(4)
		row.add_theme_stylebox_override("panel", row_s)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 0)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

		var strip := ColorRect.new()
		strip.color = elim_colors[ci]
		strip.custom_minimum_size = Vector2(4, 0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(strip)

		var mc := MarginContainer.new()
		mc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mc.add_theme_constant_override("margin_left", 12)
		mc.add_theme_constant_override("margin_top", 6)
		mc.add_theme_constant_override("margin_right", 8)
		mc.add_theme_constant_override("margin_bottom", 6)
		mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(mc)

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 2)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mc.add_child(vbox)

		var order_lbl := Label.new()
		order_lbl.text = "第 %d 淘汰 — 回合 %d" % [i + 1, entry["round"]]
		order_lbl.add_theme_font_size_override("font_size", 10)
		order_lbl.add_theme_color_override("font_color", ord_colors[ci])
		order_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(order_lbl)

		var name_lbl := Label.new()
		name_lbl.text = ps.player_name
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", nm_colors[ci])
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_lbl)

		if entry["reason"] != "":
			var reason_lbl := Label.new()
			reason_lbl.text = entry["reason"]
			reason_lbl.add_theme_font_size_override("font_size", 10)
			reason_lbl.add_theme_color_override("font_color", nm_colors[ci].darkened(0.2))
			reason_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(reason_lbl)

		var hp_lbl := Label.new()
		hp_lbl.text = "最终HP：%d/%d" % [ps.final_hp, ps.max_hp]
		hp_lbl.add_theme_font_size_override("font_size", 9)
		hp_lbl.add_theme_color_override("font_color", Color("#888780"))
		hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hp_lbl)

		elimination_list.add_child(row)

# ── Tab section ─────────────────────────────────────────────────────────────

func _build_tab_section() -> void:
	var section := VBoxContainer.new()
	section.name = "TabSection"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.add_theme_constant_override("separation", 0)
	section.add_child(_tab_bar)

	_add_tab_button("📊 局内统计", "stats")
	_add_tab_button("▶ 对局回放", "replay")
	_add_tab_button("⚔ 技能记录", "skill_log")

	_tab_content = PanelContainer.new()
	_tab_content.name = "TabContent"
	_tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_content.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 1, 0))
	section.add_child(_tab_content)

	_build_stats_panel()
	_build_replay_panel()
	_build_skill_log_panel()

	winner_panel.add_child(section)
	winner_panel.move_child(section, winner_panel.get_child_count() - 1)

func _add_tab_button(label: String, tab_id: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 11)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 28)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(_on_tab_pressed.bind(tab_id))
	btn.set_meta("tab_id", tab_id)
	_tab_bar.add_child(btn)

func _on_tab_pressed(tab_id: String) -> void:
	_switch_tab(tab_id)
	btn_review.visible = (tab_id != "replay")
	btn_skill_log.visible = (tab_id != "skill_log")

func _switch_tab(tab_id: String) -> void:
	_current_tab = tab_id
	if _stats_panel:
		_stats_panel.visible = (tab_id == "stats")
	if _replay_panel:
		_replay_panel.visible = (tab_id == "replay")
	if _skill_log_panel:
		_skill_log_panel.visible = (tab_id == "skill_log")
	_update_tab_styles()

func _update_tab_styles() -> void:
	for child in _tab_bar.get_children():
		if child is Button:
			var tid: String = child.get_meta("tab_id", "")
			if tid == _current_tab:
				child.add_theme_stylebox_override("normal", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 0))
				child.add_theme_color_override("font_color", Color("#FAC775"))
			else:
				child.add_theme_stylebox_override("normal", _make_flat(Color("#F1EFE8"), Color("#D3D1C7"), 1, 0))
				child.add_theme_color_override("font_color", Color("#888780"))

# ── Stats panel ─────────────────────────────────────────────────────────────

func _build_stats_panel() -> void:
	_stats_panel = Control.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_panel.visible = false

	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
	hbox.add_theme_constant_override("separation", 16)
	_stats_panel.add_child(hbox)

	var global := VBoxContainer.new()
	global.custom_minimum_size = Vector2(140, 0)
	global.add_theme_constant_override("separation", 8)
	hbox.add_child(global)

	var total_skills := 0
	var total_shields := 0
	for pid in _record.player_stats:
		var ps: PlayerMatchStats = _record.player_stats[pid]
		total_skills += ps.skill_use_count
		total_shields += ps.shield_blocked_count

	_add_stat_row(global, "总回合数", str(_record.total_rounds))
	_add_stat_row(global, "加赛次数", str(_record.tiebreak_count))
	_add_stat_row(global, "技能释放总数", str(total_skills))
	_add_stat_row(global, "护盾抵挡次数", str(total_shields))

	var compare_scroll := ScrollContainer.new()
	compare_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	compare_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hbox.add_child(compare_scroll)

	var compare := VBoxContainer.new()
	compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare.add_theme_constant_override("separation", 0)
	compare_scroll.add_child(compare)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	compare.add_child(header)

	var hdr_label := Label.new()
	hdr_label.text = "指标"
	hdr_label.custom_minimum_size = Vector2(64, 22)
	hdr_label.add_theme_font_size_override("font_size", 10)
	hdr_label.add_theme_color_override("font_color", Color("#FAC775"))
	hdr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hdr_style := _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 0)
	hdr_label.add_theme_stylebox_override("normal", hdr_style)
	header.add_child(hdr_label)

	var player_ids: Array[int] = []
	for pid in _record.player_stats:
		player_ids.append(pid)
	player_ids.sort()

	for pid in player_ids:
		var ps: PlayerMatchStats = _record.player_stats[pid]
		var ph := Label.new()
		ph.text = ps.player_name
		ph.custom_minimum_size = Vector2(0, 22)
		ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ph.add_theme_font_size_override("font_size", 10)
		ph.add_theme_color_override("font_color", Color("#FAC775"))
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_theme_stylebox_override("normal", hdr_style)
		header.add_child(ph)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	compare.add_child(rows)

	_add_compare_row(rows, "猜拳胜利", player_ids, func(ps): return ps.win_count)
	_add_compare_row(rows, "造成伤害", player_ids, func(ps): return ps.total_damage_dealt)
	_add_compare_row(rows, "承受伤害", player_ids, func(ps): return ps.total_damage_taken)
	_add_compare_row(rows, "技能释放", player_ids, func(ps): return ps.skill_use_count)
	_add_compare_row(rows, "聚气次数", player_ids, func(ps): return ps.charge_count)
	_add_compare_row(rows, "施加麻痹", player_ids, func(ps): return ps.paralyze_applied_count)
	_add_compare_row(rows, "被麻痹次数", player_ids, func(ps): return ps.paralyze_suffered_count)

	_tab_content.add_child(_stats_panel)

func _add_stat_row(parent: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 11)
	val.add_theme_color_override("font_color", Color("#2C2C2A"))
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)

func _add_compare_row(parent: VBoxContainer, label: String, player_ids: Array[int], getter: Callable) -> void:
	var row_idx := parent.get_child_count()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(64, 20)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var row_bg := _make_flat(Color("#FFFDF5") if row_idx % 2 == 0 else Color("#F5F3EC"), Color(0, 0, 0, 0), 0, 0)
	lbl.add_theme_stylebox_override("normal", row_bg)
	row.add_child(lbl)

	var max_val := -1
	for pid in player_ids:
		var v: int = getter.call(_record.player_stats[pid])
		if v > max_val: max_val = v

	for pid in player_ids:
		var ps: PlayerMatchStats = _record.player_stats[pid]
		var v: int = getter.call(ps)
		var cell := Label.new()
		cell.text = str(v)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_font_size_override("font_size", 9)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if v == max_val and max_val > 0:
			cell.add_theme_color_override("font_color", Color("#27500A"))
			cell.add_theme_stylebox_override("normal", _make_flat(Color("#EAF3DE"), Color(0, 0, 0, 0), 0, 0))
		else:
			cell.add_theme_color_override("font_color", Color("#5F5E5A"))
			cell.add_theme_stylebox_override("normal", row_bg)
		row.add_child(cell)

# ── Replay panel ────────────────────────────────────────────────────────────

func _build_replay_panel() -> void:
	_replay_panel = Control.new()
	_replay_panel.name = "ReplayPanel"
	_replay_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replay_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	_replay_panel.add_child(vbox)

	var mode_bar := HBoxContainer.new()
	mode_bar.add_theme_constant_override("separation", 0)
	vbox.add_child(mode_bar)

	var btn_log := Button.new()
	btn_log.text = "📋 日志模式"
	btn_log.add_theme_font_size_override("font_size", 10)
	btn_log.focus_mode = Control.FOCUS_NONE
	btn_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_log.custom_minimum_size = Vector2(0, 26)
	btn_log.pressed.connect(func(): _set_replay_mode("log"))
	mode_bar.add_child(btn_log)

	var btn_play := Button.new()
	btn_play.text = "▶ 播放模式"
	btn_play.add_theme_font_size_override("font_size", 10)
	btn_play.focus_mode = Control.FOCUS_NONE
	btn_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_play.custom_minimum_size = Vector2(0, 26)
	btn_play.pressed.connect(func(): _set_replay_mode("play"))
	mode_bar.add_child(btn_play)

	# Log scroll
	var log_scroll := ScrollContainer.new()
	log_scroll.name = "LogModeScroll"
	log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(log_scroll)
	_log_mode_scroll = log_scroll

	var log_list := VBoxContainer.new()
	log_list.name = "LogModeList"
	log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_list.add_theme_constant_override("separation", 4)
	log_scroll.add_child(log_list)

	for snap in _record.round_snapshots:
		_add_log_entry(log_list, snap)

	# Play panel
	var play_panel := VBoxContainer.new()
	play_panel.name = "PlayModePanel"
	play_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_panel.visible = false
	vbox.add_child(play_panel)
	_play_mode_panel = play_panel

	var rd := Label.new()
	rd.name = "RoundDisplay"
	rd.add_theme_font_size_override("font_size", 15)
	rd.add_theme_color_override("font_color", Color("#2C2C2A"))
	rd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_panel.add_child(rd)

	var ca_scroll := ScrollContainer.new()
	ca_scroll.name = "PlayContentScroll"
	ca_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ca_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ca_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	play_panel.add_child(ca_scroll)

	var ca := VBoxContainer.new()
	ca.name = "PlayContent"
	ca.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ca.add_theme_constant_override("separation", 6)
	ca_scroll.add_child(ca)
	_play_content = ca

	var prog := ProgressBar.new()
	prog.name = "ReplayProgress"
	prog.custom_minimum_size = Vector2(0, 6)
	prog.max_value = max(1, _record.round_snapshots.size() - 1)
	prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_panel.add_child(prog)

	var cbar := HBoxContainer.new()
	cbar.add_theme_constant_override("separation", 4)
	cbar.alignment = BoxContainer.ALIGNMENT_CENTER
	play_panel.add_child(cbar)

	for item in [["⏮", "_first"], ["◀", "_prev"], ["▶ 自动", "_auto"], ["▶", "_next"], ["⏭", "_last"]]:
		var b := Button.new()
		b.text = item[0]
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 26)
		match item[1]:
			"_first": b.pressed.connect(_on_replay_first)
			"_prev":  b.pressed.connect(_on_replay_prev)
			"_auto":
				b.pressed.connect(_on_replay_auto)
				_replay_auto_btn = b
			"_next":  b.pressed.connect(_on_replay_next)
			"_last":  b.pressed.connect(_on_replay_last)
		cbar.add_child(b)

	_tab_content.add_child(_replay_panel)

func _add_log_entry(parent: VBoxContainer, snap: RoundSnapshot) -> void:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 0)
	parent.add_child(entry)

	var hdr := Button.new()
	hdr.text = " 回合 %d%s" % [snap.round_number, " [加赛]" if snap.is_tiebreak else ""]
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color("#FAC775"))
	hdr.add_theme_stylebox_override("normal", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 3))
	hdr.focus_mode = Control.FOCUS_NONE
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.custom_minimum_size = Vector2(0, 24)

	var detail := VBoxContainer.new()
	detail.name = "RoundDetail"
	detail.add_theme_constant_override("separation", 2)

	var emojis := ["", "✊", "✌", "✋", "⏭"]
	var names  := ["无", "石头", "剪刀", "布", "跳过"]
	for pid in snap.gestures:
		var g: int = snap.gestures[pid]
		var ps: PlayerMatchStats = _record.player_stats.get(pid)
		var pname := ps.player_name if ps else str(pid)
		var gl := Label.new()
		gl.text = "%s  %s — %s" % [emojis[g] if g < emojis.size() else "?", pname, names[g] if g < names.size() else "?"]
		gl.add_theme_font_size_override("font_size", 10)
		gl.add_theme_color_override("font_color", Color("#2C2C2A"))
		gl.add_theme_stylebox_override("normal", _make_flat(Color("#F1EFE8"), Color("#F1EFE8"), 0, 0))
		detail.add_child(gl)

	if snap.is_draw:
		var rl := Label.new()
		rl.text = "— 平局 —"
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", Color("#BA7517"))
		detail.add_child(rl)
	else:
		for wid in snap.winners:
			var ps: PlayerMatchStats = _record.player_stats.get(int(wid))
			var rl := Label.new()
			rl.text = "获胜：%s" % (ps.player_name if ps else str(wid))
			rl.add_theme_font_size_override("font_size", 10)
			rl.add_theme_color_override("font_color", Color("#27500A"))
			rl.add_theme_stylebox_override("normal", _make_flat(Color("#EAF3DE"), Color("#EAF3DE"), 0, 0))
			detail.add_child(rl)

	for action in snap.actions:
		var ps: PlayerMatchStats = _record.player_stats.get(action.actor_id)
		var al := Label.new()
		al.text = "%s 使用 %s" % [ps.player_name if ps else "?", action.skill_name]
		al.add_theme_font_size_override("font_size", 10)
		al.add_theme_color_override("font_color", Color("#185FA5"))
		detail.add_child(al)

	for evt in snap.events:
		var el := Label.new()
		el.text = evt
		el.add_theme_font_size_override("font_size", 10)
		el.add_theme_color_override("font_color", Color("#BA7517"))
		detail.add_child(el)

	hdr.pressed.connect(func():
		detail.visible = not detail.visible
	)
	entry.add_child(hdr)
	entry.add_child(detail)

func _set_replay_mode(mode: String) -> void:
	_replay_mode = mode
	if _log_mode_scroll: _log_mode_scroll.visible = (mode == "log")
	if _play_mode_panel: _play_mode_panel.visible = (mode == "play")
	if mode == "play":
		await get_tree().process_frame
		_show_replay_round(0)

func _show_replay_round(index: int, _replay_reset: bool = false) -> void:
	if _record.round_snapshots.is_empty(): return
	_replay_index = clampi(index, 0, _record.round_snapshots.size() - 1)
	var snap: RoundSnapshot = _record.round_snapshots[_replay_index]
	if _play_mode_panel == null: return

	var rd: Label = _play_mode_panel.get_node_or_null("RoundDisplay")
	if rd: rd.text = "第 %d 回合 / 共 %d 回合" % [snap.round_number, _record.total_rounds]

	var ca: VBoxContainer = _play_content
	if ca:
		var to_free := ca.get_children()
		for child in to_free:
			child.queue_free()
		var emojis := ["", "✊", "✌", "✋", "⏭"]
		var names  := ["无", "石头", "剪刀", "布", "跳过"]
		for pid in snap.gestures:
			var g: int = snap.gestures[pid]
			var ps: PlayerMatchStats = _record.player_stats.get(pid)
			var gl := Label.new()
			gl.text = "%s  %s 出了 %s" % [emojis[g] if g < emojis.size() else "?", ps.player_name if ps else str(pid), names[g] if g < names.size() else "?"]
			gl.add_theme_font_size_override("font_size", 16)
			gl.add_theme_color_override("font_color", Color("#2C2C2A"))
			gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ca.add_child(gl)

		if snap.is_draw:
			var rl := Label.new()
			rl.text = "— 平局 —"; rl.add_theme_font_size_override("font_size", 18)
			rl.add_theme_color_override("font_color", Color("#BA7517"))
			rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ca.add_child(rl)
		else:
			for wid in snap.winners:
				var ps: PlayerMatchStats = _record.player_stats.get(int(wid))
				var rl := Label.new()
				rl.text = "获胜：%s" % (ps.player_name if ps else str(wid))
				rl.add_theme_font_size_override("font_size", 18)
				rl.add_theme_color_override("font_color", Color("#27500A"))
				rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ca.add_child(rl)

		for action in snap.actions:
			var ps_a: PlayerMatchStats = _record.player_stats.get(action.actor_id)
			var action_lbl := Label.new()
			action_lbl.text = "⚡ %s 使用了 %s" % [
				ps_a.player_name if ps_a else "?",
				action.skill_name
			]
			action_lbl.add_theme_font_size_override("font_size", 12)
			action_lbl.add_theme_color_override("font_color", Color("#185FA5"))
			action_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ca.add_child(action_lbl)

		for evt in snap.events:
			var evt_lbl := Label.new()
			evt_lbl.text = evt
			evt_lbl.add_theme_font_size_override("font_size", 12)
			evt_lbl.add_theme_color_override("font_color", Color("#BA7517"))
			evt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ca.add_child(evt_lbl)

	var prog: ProgressBar = _play_mode_panel.get_node_or_null("ReplayProgress")
	if prog: prog.value = _replay_index

func _on_replay_first() -> void: _show_replay_round(0)
func _on_replay_prev() -> void:
	if _replay_index > 0:
		_show_replay_round(_replay_index - 1)

func _on_replay_next() -> void:
	if _record.round_snapshots.size() > 0 and _replay_index < _record.round_snapshots.size() - 1:
		_show_replay_round(_replay_index + 1)
func _on_replay_last() -> void:  _show_replay_round(_record.round_snapshots.size() - 1)

func _setup_replay_timer() -> void:
	_replay_timer = Timer.new()
	_replay_timer.one_shot = false
	_replay_timer.timeout.connect(_on_replay_tick)
	add_child(_replay_timer)

func _on_replay_auto() -> void:
	if _auto_playing:
		_auto_playing = false; _replay_timer.stop()
		if _replay_auto_btn:
			_replay_auto_btn.text = "▶ 自动"
	else:
		_auto_playing = true
		_replay_timer.wait_time = 1.5 / _replay_speed
		if _replay_index >= _record.round_snapshots.size() - 1: _replay_index = 0
		_replay_timer.start()
		if _replay_auto_btn:
			_replay_auto_btn.text = "⏹ 停止"

func _on_replay_tick() -> void:
	if _replay_index < _record.round_snapshots.size() - 1:
		_replay_index += 1; _show_replay_round(_replay_index)
	else:
		_auto_playing = false; _replay_timer.stop()
		if _replay_auto_btn:
			_replay_auto_btn.text = "▶ 自动"

# ── Skill log panel ─────────────────────────────────────────────────────────

func _build_skill_log_panel() -> void:
	_skill_log_panel = Control.new()
	_skill_log_panel.name = "SkillLogPanel"
	_skill_log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skill_log_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	_skill_log_panel.add_child(vbox)

	var sub_bar := HBoxContainer.new()
	sub_bar.add_theme_constant_override("separation", 0)
	vbox.add_child(sub_bar)

	var btn_tl := Button.new()
	btn_tl.text = "时间线"
	btn_tl.add_theme_font_size_override("font_size", 10)
	btn_tl.focus_mode = Control.FOCUS_NONE
	btn_tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_tl.custom_minimum_size = Vector2(0, 24)
	btn_tl.pressed.connect(func(): _set_skill_mode("timeline"))
	sub_bar.add_child(btn_tl)

	var btn_bc := Button.new()
	btn_bc.text = "按角色"
	btn_bc.add_theme_font_size_override("font_size", 10)
	btn_bc.focus_mode = Control.FOCUS_NONE
	btn_bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_bc.custom_minimum_size = Vector2(0, 24)
	btn_bc.pressed.connect(func(): _set_skill_mode("by_char"))
	sub_bar.add_child(btn_bc)

	# Timeline
	var tl_scroll := ScrollContainer.new()
	tl_scroll.name = "TimelineScroll"
	tl_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tl_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(tl_scroll)
	_timeline_scroll = tl_scroll

	var tl_list := VBoxContainer.new()
	tl_list.name = "TimelineList"
	tl_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl_list.add_theme_constant_override("separation", 3)
	tl_scroll.add_child(tl_list)

	for slog in _record.skill_use_logs:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 1, 2))
		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		row.add_child(rh)

		var rl := Label.new()
		rl.text = "[%d]" % slog.round_number
		rl.add_theme_font_size_override("font_size", 10)
		rl.add_theme_color_override("font_color", Color("#888780"))
		rh.add_child(rl)

		var al := Label.new()
		al.text = slog.actor_name
		al.add_theme_font_size_override("font_size", 10)
		al.add_theme_color_override("font_color", Color("#2C2C2A"))
		rh.add_child(al)

		var sl := Label.new()
		sl.text = "→ %s" % slog.skill_name
		sl.add_theme_font_size_override("font_size", 10)
		sl.add_theme_color_override("font_color", Color("#185FA5"))
		rh.add_child(sl)

		if slog.target_names.size() > 0:
			var tl := Label.new()
			tl.text = "→ %s" % ", ".join(slog.target_names)
			tl.add_theme_font_size_override("font_size", 10)
			tl.add_theme_color_override("font_color", Color("#5F5E5A"))
			rh.add_child(tl)

		var sum_lbl := Label.new()
		sum_lbl.text = "(%s)" % slog.effects_summary
		sum_lbl.add_theme_font_size_override("font_size", 10)
		sum_lbl.add_theme_color_override("font_color", Color("#888780"))
		rh.add_child(sum_lbl)

		tl_list.add_child(row)

	# By-character
	var bc_scroll := ScrollContainer.new()
	bc_scroll.name = "ByCharScroll"
	bc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bc_scroll.visible = false
	vbox.add_child(bc_scroll)
	_by_char_scroll = bc_scroll

	var bc_vbox := VBoxContainer.new()
	bc_vbox.name = "ByCharList"
	bc_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bc_vbox.add_theme_constant_override("separation", 8)
	bc_scroll.add_child(bc_vbox)

	for pid in _record.player_stats:
		var ps: PlayerMatchStats = _record.player_stats[pid]
		var char_logs: Array[SkillUseLog] = []
		for slog in _record.skill_use_logs:
			if slog.actor_id == pid: char_logs.append(slog)
		if char_logs.is_empty(): continue

		var cs := VBoxContainer.new()
		cs.add_theme_constant_override("separation", 2)
		bc_vbox.add_child(cs)

		var ch := Label.new()
		ch.text = "%s — 技能使用 %d 次" % [ps.player_name, char_logs.size()]
		ch.add_theme_font_size_override("font_size", 11)
		ch.add_theme_color_override("font_color", Color("#FAC775"))
		ch.add_theme_stylebox_override("normal", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 2))
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cs.add_child(ch)

		for slog in char_logs:
			var cl := Label.new()
			cl.text = "  [回合%d] %s → %s (%s)" % [slog.round_number, slog.skill_name, ", ".join(slog.target_names), slog.effects_summary]
			cl.add_theme_font_size_override("font_size", 10)
			cl.add_theme_color_override("font_color", Color("#5F5E5A"))
			cs.add_child(cl)

	_tab_content.add_child(_skill_log_panel)

func _set_skill_mode(mode: String) -> void:
	_skill_log_mode = mode
	if _timeline_scroll: _timeline_scroll.visible = (mode == "timeline")
	if _by_char_scroll: _by_char_scroll.visible = (mode == "by_char")

# ── Navigation ──────────────────────────────────────────────────────────────

func _on_replay_pressed() -> void:
	SceneManager.go_to("res://scenes/main.tscn")

func _on_reselect_pressed() -> void:
	SceneManager.go_to("res://scenes/character_select.tscn")

func _on_main_menu_pressed() -> void:
	SceneManager.go_to("res://scenes/main_menu.tscn")

func _on_review_pressed() -> void:
	_on_tab_pressed("replay")

func _on_skill_log_pressed() -> void:
	_on_tab_pressed("skill_log")
