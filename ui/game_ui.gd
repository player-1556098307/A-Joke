## GameUI — 主游戏界面，监听 GameManager 全部20个信号
## 负责渲染环形排列的玩家卡片、手势/行动/目标选择面板、战斗日志、回合倒计时、
## 思考动画、手势揭示弹窗、加赛高亮、技能效果动画等所有战斗UI交互
class_name GameUI
extends Control

@onready var round_label: Label              = $RoundLabel
@onready var phase_label: Label              = $PhaseLabel
@onready var log_scroll: ScrollContainer     = $LogScroll
@onready var log_vbox: VBoxContainer         = $LogScroll/LogVBox
@onready var gesture_panel: VBoxContainer    = $GesturePanel
@onready var btn_rock: Button                = $GesturePanel/BtnRock
@onready var btn_scissors: Button            = $GesturePanel/BtnScissors
@onready var btn_paper: Button               = $GesturePanel/BtnPaper
@onready var action_panel: VBoxContainer     = $ActionPanel
@onready var btn_charge: Button              = $ActionPanel/BtnCharge
@onready var skills_container: VBoxContainer = $ActionPanel/SkillsContainer
@onready var target_panel: VBoxContainer     = $TargetPanel
@onready var players_container: Control      = $PlayersContainer
@onready var right_header_label: Label       = $RightHeaderLabel
@onready var timer_label: Label              = $TimerLabel
@onready var timer_badge: ColorRect          = $TimerBadge

var _human_player_id: int = -1
var _current_action_player_id: int = -1
var _player_cards: Dictionary = {}
var _in_tiebreak: bool = false
var _tiebreak_candidate_ids: Array[int] = []
var _current_round: int = 0
var _elimination_log: Array[Dictionary] = []
var _elim_order: int = 0
var _is_draw_reentry: bool = false
## 联机模式客户端引用（非 null 时走网络通道）
var net_client: NetworkGameClient = null
var is_spectating: bool = false
var _spectator_view_idx: int = 0

const ARENA_CENTER := Vector2(480.0, 295.0)
const ARENA_RADIUS := 155.0
# Countdown duration is read from SettingsManager at runtime

const CLASS_AVATAR_BG := {
	"战士": Color("#B5D4F4"), "法师": Color("#EEEDFE"),
	"坦克": Color("#F4C0D1"), "刺客": Color("#F5C4B3"),
}
const CLASS_AVATAR_BORDER := {
	"战士": Color("#185FA5"), "法师": Color("#534AB7"),
	"坦克": Color("#993556"), "刺客": Color("#993C1D"),
}

const LT_PHASE  := 0
const LT_WIN    := 1
const LT_DAMAGE := 2
const LT_STATUS := 3
const MAX_LOG_ENTRIES := 200

const LOG_COLORS := [  # [bg, border, title, detail]
	[Color("#E6F1FB"), Color("#B5D4F4"), Color("#185FA5"), Color("#0C447C")],
	[Color("#EAF3DE"), Color("#C0DD97"), Color("#27500A"), Color("#3B6D11")],
	[Color("#FCEBEB"), Color("#F7C1C1"), Color("#791F1F"), Color("#A32D2D")],
	[Color("#FAEEDA"), Color("#FAC775"), Color("#412402"), Color("#BA7517")],
]

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s

var _distance_labels: Array[Label] = []
var _turn_timer: Timer
var _turn_seconds_left: float = 0.0
var _timer_start_msec: int = 0
var _timer_total_seconds: float = 0.0

var _log_entries: Array[Dictionary] = []
var _log_rows: Array[PanelContainer] = []
var _log_filter_pid: int = -1
var _log_filter_buttons: HBoxContainer

func _ready() -> void:
	_style_panels()
	_style_gesture_buttons()
	_style_charge_button()
	_setup_turn_timer()
	_setup_menu_button()

	btn_rock.pressed.connect(_on_gesture_pressed.bind(PlayerState.Gesture.ROCK))
	btn_scissors.pressed.connect(_on_gesture_pressed.bind(PlayerState.Gesture.SCISSORS))
	btn_paper.pressed.connect(_on_gesture_pressed.bind(PlayerState.Gesture.PAPER))
	btn_charge.pressed.connect(_on_charge_pressed)

	_setup_log_filter_ui()
	log_scroll.follow_focus = true
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gesture_panel.hide()
	action_panel.hide()
	target_panel.hide()

	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.gesture_submitted.connect(_on_gesture_submitted)
	GameManager.round_resolved.connect(_on_round_resolved)
	GameManager.action_required.connect(_on_action_required)
	GameManager.skill_applied.connect(_on_skill_applied)
	GameManager.player_charged.connect(_on_player_charged)
	GameManager.player_eliminated.connect(_on_player_eliminated)
	GameManager.game_over.connect(_on_game_over)
	GameManager.tiebreak_started.connect(_on_tiebreak_started)
	GameManager.tiebreak_resolved.connect(_on_tiebreak_resolved)
	GameManager.player_shielded.connect(_on_player_shielded)
	GameManager.player_paralyzed.connect(_on_player_paralyzed)
	GameManager.distance_changed.connect(_on_distance_changed)
	GameManager.player_skipped.connect(_on_player_skipped)
	GameManager.delayed_damage_triggered.connect(_on_delayed_damage_triggered)
	GameManager.clone_destroyed.connect(_on_clone_destroyed)
	GameManager.skill_unlocked.connect(_on_skill_unlocked)

func _style_panels() -> void:
	# LogPanelBg — white background, dark border (matching SVG)
	var log_panel: Panel = $LogPanelBg
	log_panel.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#2C2C2A"), 2, 4))

	# RightPanelBg — white background, dark border
	var right_panel: Panel = $RightPanelBg
	right_panel.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#2C2C2A"), 2, 4))

	# BorderFrame — transparent fill, stroke only (Bug 1: was default dark panel)
	var border_panel: Panel = $BorderFrame
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(1, 1, 1, 0)
	border_style.border_color = Color("#2C2C2A")
	border_style.set_border_width_all(3)
	border_style.set_corner_radius_all(6)
	border_panel.add_theme_stylebox_override("panel", border_style)

	# Dot pattern overlay (Bug 1: add dot texture per SVG reference)
	var dot_img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	dot_img.fill(Color(0, 0, 0, 0))
	dot_img.set_pixel(6, 6, Color(0.910, 0.894, 0.816, 0.23))
	var dot_tex := ImageTexture.create_from_image(dot_img)
	var dot_rect := TextureRect.new()
	dot_rect.texture = dot_tex
	dot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot_rect.stretch_mode = TextureRect.STRETCH_TILE
	dot_rect.anchor_right = 1.0
	dot_rect.anchor_bottom = 1.0
	dot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot_rect)
	move_child(dot_rect, 1)

func _setup_turn_timer() -> void:
	_turn_timer = Timer.new()
	_turn_timer.one_shot = false
	_turn_timer.wait_time = 1.0
	_turn_timer.timeout.connect(_on_turn_timer_tick)
	add_child(_turn_timer)

func _setup_menu_button() -> void:
	var menu_btn := Button.new()
	menu_btn.text = "← 菜单"
	menu_btn.add_theme_font_size_override("font_size", 10)
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.custom_minimum_size = Vector2(56, 24)
	menu_btn.position = Vector2(772, 8)
	menu_btn.size = Vector2(52, 22)
	menu_btn.add_theme_stylebox_override("normal",   _make_flat(Color("#3A3A38"), Color("#5A5A57"), 1, 3))
	menu_btn.add_theme_stylebox_override("hover",    _make_flat(Color("#4A4A47"), Color("#888780"), 1, 3))
	menu_btn.add_theme_stylebox_override("pressed",  _make_flat(Color("#2C2C2A"), Color("#FAC775"), 1, 3))
	menu_btn.add_theme_color_override("font_color",         Color("#D3D1C7"))
	menu_btn.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
	menu_btn.add_theme_color_override("font_pressed_color", Color("#FAC775"))
	menu_btn.pressed.connect(_on_menu_pressed)
	add_child(menu_btn)

func _on_menu_pressed() -> void:
	# Backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.35)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Panel
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.custom_minimum_size = Vector2(300, 0)

	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color("#FFFDF5")
	pstyle.border_color = Color("#2C2C2A")
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(8)
	pstyle.content_margin_left = 20.0
	pstyle.content_margin_top = 20.0
	pstyle.content_margin_right = 20.0
	pstyle.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", pstyle)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "返回菜单"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color("#2C2C2A"))
	vbox.add_child(title_lbl)

	var body_lbl := Label.new()
	body_lbl.text = "确定要返回主菜单吗？\n当前对战进度将会丢失。"
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_lbl.add_theme_font_size_override("font_size", 12)
	body_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	vbox.add_child(body_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	# "继续游戏" button
	var stay_btn := Button.new()
	stay_btn.text = "继续游戏"
	stay_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stay_btn.add_theme_font_size_override("font_size", 12)
	stay_btn.add_theme_color_override("font_color", Color("#2C2C2A"))
	stay_btn.add_theme_stylebox_override("normal", _make_flat(Color("#F1EFE8"), Color("#5A5A57"), 1, 4))
	stay_btn.add_theme_stylebox_override("hover", _make_flat(Color("#E6E2D4"), Color("#2C2C2A"), 1, 4))
	stay_btn.pressed.connect(func():
		backdrop.queue_free()
		panel.queue_free()
	)
	btn_row.add_child(stay_btn)

	# "确定返回" button
	var leave_btn := Button.new()
	leave_btn.text = "确定返回"
	leave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_btn.add_theme_font_size_override("font_size", 12)
	leave_btn.add_theme_color_override("font_color", Color("#FFFDF5"))
	leave_btn.add_theme_stylebox_override("normal", _make_flat(Color("#E24B4A"), Color("#C03838"), 1, 4))
	leave_btn.add_theme_stylebox_override("hover", _make_flat(Color("#C03838"), Color("#A02020"), 1, 4))
	leave_btn.pressed.connect(func():
		backdrop.queue_free()
		panel.queue_free()
		var config = SceneManager.last_game_config
		if config.get("is_network", false):
			if config.get("is_host", false):
				NetworkManager.stop_game_server()
			else:
				NetworkManager.disconnect_from_game()
			SceneManager.go_to("res://scenes/net/lobby.tscn")
		else:
			SceneManager.go_to("res://scenes/main_menu.tscn")
	)
	btn_row.add_child(leave_btn)

	# Center panel after layout
	await get_tree().process_frame
	var sz := panel.get_combined_minimum_size()
	panel.offset_left = -sz.x / 2.0
	panel.offset_right = sz.x / 2.0
	panel.offset_top = -sz.y / 2.0
	panel.offset_bottom = sz.y / 2.0

# ── Action effects ────────────────────────────────────────────────────────────

func _play_charge_effect(player_id: int) -> void:
	var card: Control = _player_cards.get(player_id)
	if card == null:
		return

	var glow := ColorRect.new()
	glow.color = Color("#FAC775")
	glow.self_modulate = Color(1, 1, 1, 0)
	glow.position = Vector2(-4, -4)
	glow.size = card.custom_minimum_size + Vector2(8, 8)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(glow)
	card.move_child(glow, 0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(glow, "self_modulate", Color(1, 1, 1, 0.55), 0.2)
	tween.tween_property(glow, "scale", Vector2(1.06, 1.06), 0.2)
	tween.tween_property(glow, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(0.4)
	tween.tween_property(glow, "scale", Vector2(1.0, 1.0), 0.5).set_delay(0.4)
	tween.chain().tween_callback(func(): glow.queue_free())

	var popup := Label.new()
	popup.text = "⚡"
	popup.add_theme_font_size_override("font_size", 22)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.position = Vector2(34, -20)
	popup.size = Vector2(36, 28)
	popup.self_modulate = Color(1, 1, 1, 0)
	card.add_child(popup)

	var t2 := create_tween()
	t2.tween_property(popup, "position", Vector2(34, -50), 0.7)
	t2.set_parallel(true)
	t2.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.2)
	t2.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.4).set_delay(0.4)
	t2.chain().tween_callback(func(): popup.queue_free())

func _play_attack_effect(target_id: int) -> void:
	var card: Control = _player_cards.get(target_id)
	if card == null:
		return

	var flash := ColorRect.new()
	flash.color = Color("#E24B4A")
	flash.self_modulate = Color(1, 1, 1, 0.7)
	flash.position = Vector2(0, 0)
	flash.size = card.custom_minimum_size
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(flash)
	card.move_child(flash, 0)

	var tween := create_tween()
	tween.tween_property(flash, "self_modulate", Color(1, 1, 1, 0), 0.35)
	tween.tween_callback(func(): flash.queue_free()).set_delay(0.4)

	var orig_pos := card.position
	var shake := create_tween()
	shake.tween_property(card, "position", orig_pos + Vector2(6, 0), 0.04)
	shake.tween_property(card, "position", orig_pos - Vector2(6, 0), 0.08)
	shake.tween_property(card, "position", orig_pos + Vector2(2, 0), 0.06)
	shake.tween_property(card, "position", orig_pos, 0.04)

func _play_skill_effect(target_id: int, effect_type: int) -> void:
	var card: Control = _player_cards.get(target_id)
	if card == null:
		return

	var colors := {
		SkillEffect.EffectType.DAMAGE:       Color("#E24B4A"),
		SkillEffect.EffectType.SHIELD:       Color("#534AB7"),
		SkillEffect.EffectType.CLONE_SHIELD: Color("#185FA5"),
		SkillEffect.EffectType.PARALYZE:     Color("#BA7517"),
		SkillEffect.EffectType.HEAL:         Color("#639922"),
		SkillEffect.EffectType.DELAYED_DAMAGE: Color("#A32D2D"),
	}
	var c: Color = colors.get(effect_type, Color("#FAC775"))

	var ring := ColorRect.new()
	ring.color = c
	ring.self_modulate = Color(1, 1, 1, 0.8)
	ring.position = Vector2(-3, -3)
	ring.size = card.custom_minimum_size + Vector2(6, 6)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ring)
	card.move_child(ring, 0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "self_modulate", Color(1, 1, 1, 0), 0.6)
	tween.tween_property(ring, "scale", Vector2(1.08, 1.08), 0.6)
	tween.chain().tween_callback(func(): ring.queue_free())

func _style_gesture_buttons() -> void:
	var data := [
		[btn_rock,     "✊  石头"],
		[btn_scissors, "✌  剪刀"],
		[btn_paper,    "✋  布"],
	]
	for entry in data:
		var btn: Button = entry[0]
		btn.text = entry[1]
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_stylebox_override("normal",  _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
		btn.add_theme_stylebox_override("hover",   _make_flat(Color("#EAF3DE"), Color("#3B6D11"), 2, 6))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#D8ECC5"), Color("#27500A"), 3, 6))
		btn.add_theme_color_override("font_color",         Color("#2C2C2A"))
		btn.add_theme_color_override("font_hover_color",   Color("#27500A"))
		btn.add_theme_color_override("font_pressed_color", Color("#27500A"))

func _style_charge_button() -> void:
	btn_charge.text = "聚气 +1 (⚡)"
	btn_charge.add_theme_font_size_override("font_size", 13)
	btn_charge.add_theme_stylebox_override("normal",  _make_flat(Color("#FAEEDA"), Color("#BA7517"), 2, 6))
	btn_charge.add_theme_stylebox_override("hover",   _make_flat(Color("#F5E4C0"), Color("#9A5E0A"), 2, 6))
	btn_charge.add_theme_stylebox_override("pressed", _make_flat(Color("#EEDBA5"), Color("#6B4008"), 2, 6))
	btn_charge.add_theme_color_override("font_color",         Color("#412402"))
	btn_charge.add_theme_color_override("font_hover_color",   Color("#412402"))
	btn_charge.add_theme_color_override("font_pressed_color", Color("#412402"))

# ── Player cards ─────────────────────────────────────────────────────────────

func setup_players(players: Array[PlayerState]) -> void:
	for child in players_container.get_children():
		child.queue_free()
	_player_cards.clear()
	_human_player_id = -1
	_current_round = 0
	_elimination_log.clear()
	_elim_order = 0

	for player in players:
		if player.is_human and _human_player_id == -1:
			_human_player_id = player.player_id

	var count := players.size()
	for i in count:
		var player := players[i]
		var angle  := -PI / 2.0 + i * (TAU / count)
		var cx     := ARENA_CENTER.x + ARENA_RADIUS * cos(angle)
		var cy     := ARENA_CENTER.y + ARENA_RADIUS * sin(angle)
		var card   := _build_player_card(player)
		card.position = Vector2(cx - 52.0, cy - 55.0)
		players_container.add_child(card)
		_player_cards[player.player_id] = card

	_refresh_all_distances()
	_rebuild_distance_labels()

	for p in players:
		_add_filter_button(p.character.character_name, p.player_id)

func _get_cls(player: PlayerState) -> String:
	return player.character.tags[0] if player.character.tags.size() > 0 else "战士"

func _hp_color(hp: int, max_hp: int) -> Color:
	var pct := float(hp) / float(max_hp)
	if pct > 0.5:  return Color("#639922")
	if pct > 0.25: return Color("#D85A30")
	return Color("#E24B4A")

func _build_player_card(player: PlayerState) -> Control:
	var cls    := _get_cls(player)
	var av_bg  : Color = CLASS_AVATAR_BG.get(cls,     Color("#B5D4F4"))
	var av_bdr : Color = CLASS_AVATAR_BORDER.get(cls, Color("#185FA5"))

	var wrap := Control.new()
	wrap.name = "Player_%d" % player.player_id
	wrap.custom_minimum_size = Vector2(104.0, 128.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# HP text (above bar)
	var hp_lbl := Label.new()
	hp_lbl.name = "HpText"
	hp_lbl.text = "HP %d/%d" % [player.hp, player.character.max_hp]
	hp_lbl.add_theme_font_size_override("font_size", 8)
	hp_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	hp_lbl.position = Vector2(4.0, 0.0)
	hp_lbl.size = Vector2(96.0, 10.0)
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hp_lbl)

	# HP bar background
	var hp_bg := ColorRect.new()
	hp_bg.name = "HpBarBg"
	hp_bg.color = Color("#D3D1C7")
	hp_bg.position = Vector2(4.0, 11.0)
	hp_bg.size = Vector2(96.0, 8.0)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hp_bg)

	# HP bar fill
	var hp_fill := ColorRect.new()
	hp_fill.name = "HpBarFill"
	hp_fill.color = _hp_color(player.hp, player.character.max_hp)
	hp_fill.position = Vector2(4.0, 11.0)
	hp_fill.size = Vector2(96.0 * float(player.hp) / float(player.character.max_hp), 8.0)
	hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(hp_fill)

	# Card body
	var body := Panel.new()
	body.name = "CardBody"
	body.position = Vector2(0.0, 21.0)
	body.size = Vector2(104.0, 76.0)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bdr_col := Color("#185FA5") if player.is_human else Color("#2C2C2A")
	var bdr_w   := 2 if player.is_human else 2
	body.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), bdr_col, bdr_w, 4))
	wrap.add_child(body)

	# Avatar box (56×56, centered horizontally, top 6px)
	var av := Panel.new()
	av.name = "AvatarBox"
	av.position = Vector2(24.0, 4.0)
	av.size = Vector2(56.0, 56.0)
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av_s := StyleBoxFlat.new()
	av_s.bg_color = av_bg; av_s.border_color = av_bdr
	av_s.set_border_width_all(1); av_s.set_corner_radius_all(4)
	av.add_theme_stylebox_override("panel", av_s)
	body.add_child(av)

	if player.character.portrait != null:
		var av_tex := TextureRect.new()
		av_tex.texture = player.character.portrait
		av_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_tex.anchor_right = 1.0; av_tex.anchor_bottom = 1.0
		av.add_child(av_tex)
	else:
		var av_lbl := Label.new()
		av_lbl.text = player.character.character_name.left(1)
		av_lbl.add_theme_font_size_override("font_size", 22)
		av_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_lbl.anchor_right = 1.0; av_lbl.anchor_bottom = 1.0
		av.add_child(av_lbl)

	# Name bar (bottom of body)
	var name_bar := Panel.new()
	name_bar.position = Vector2(4.0, 58.0)
	name_bar.size = Vector2(96.0, 16.0)
	name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bar.add_theme_stylebox_override("panel", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 2))
	body.add_child(name_bar)

	var name_lbl := Label.new()
	name_lbl.name = "NameLabel"
	var is_me := player.player_id == _human_player_id and _human_player_id >= 0
	var suffix: String = "（你）" if is_me else ("" if player.is_human else " AI")
	name_lbl.text = player.player_name + suffix
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color("#FFFDF5"))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.anchor_right = 1.0; name_lbl.anchor_bottom = 1.0
	name_bar.add_child(name_lbl)

	# Energy (top-right of body)
	var energy_lbl := Label.new()
	energy_lbl.name = "EnergyLabel"
	energy_lbl.text = "⚡%d" % player.energy
	energy_lbl.add_theme_font_size_override("font_size", 9)
	energy_lbl.add_theme_color_override("font_color", Color("#BA7517"))
	energy_lbl.position = Vector2(72.0, 2.0)
	energy_lbl.size = Vector2(28.0, 14.0)
	energy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(energy_lbl)

	# Distance (non-human, top-left of body)
	if not player.is_human:
		var dist_lbl := Label.new()
		dist_lbl.name = "DistLabel"
		dist_lbl.text = "↔-"
		dist_lbl.add_theme_font_size_override("font_size", 8)
		dist_lbl.add_theme_color_override("font_color", Color("#888780"))
		dist_lbl.position = Vector2(2.0, 2.0)
		dist_lbl.size = Vector2(22.0, 12.0)
		dist_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(dist_lbl)

	# Status row (below body) — buff/debuff badges
	var status_bg := ColorRect.new()
	status_bg.name = "StatusBg"
	status_bg.color = Color("#F1EFE8")
	status_bg.position = Vector2(4.0, 99.0)
	status_bg.size = Vector2(96.0, 14.0)
	status_bg.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(status_bg)

	var status_row := HBoxContainer.new()
	status_row.name = "StatusRow"
	status_row.position = Vector2(6.0, 99.0)
	status_row.size = Vector2(92.0, 14.0)
	status_row.add_theme_constant_override("separation", 2)
	status_row.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(status_row)

	var think_bar := Panel.new()
	think_bar.name = "ThinkBar"
	think_bar.position = Vector2(4.0, 115.0)
	think_bar.size = Vector2(96.0, 10.0)
	think_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tbs := StyleBoxFlat.new()
	tbs.bg_color = Color("#F1EFE8"); tbs.set_corner_radius_all(2)
	think_bar.add_theme_stylebox_override("panel", tbs)
	wrap.add_child(think_bar)

	var think_fill := ColorRect.new()
	think_fill.name = "ThinkFill"
	think_fill.color = Color("#888780")
	think_fill.position = Vector2(5.0, 116.0)
	think_fill.size = Vector2(0.0, 8.0)
	think_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(think_fill)

	var think_lbl := Label.new()
	think_lbl.name = "ThinkLabel"
	think_lbl.text = "思考中..."
	think_lbl.add_theme_font_size_override("font_size", 7)
	think_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
	think_lbl.position = Vector2(4.0, 115.0)
	think_lbl.size = Vector2(96.0, 10.0)
	think_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	think_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	think_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(think_lbl)
	think_bar.hide(); think_fill.hide(); think_lbl.hide()

	return wrap

func _make_status_badge(text: String, bg: Color, fg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0.0, 14.0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_left = 4.0; s.content_margin_right = 4.0
	s.set_corner_radius_all(3)
	p.add_theme_stylebox_override("panel", s)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", fg)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	return p

func _refresh_player_card(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	var card: Control = _player_cards.get(player_id)
	if player == null or card == null:
		return

	var max_hp := player.character.max_hp

	var hp_fill: ColorRect = card.get_node_or_null("HpBarFill")
	if hp_fill:
		hp_fill.color = _hp_color(player.hp, max_hp)
		hp_fill.size.x = 96.0 * maxf(0.0, float(player.hp)) / float(max_hp)

	var hp_text: Label = card.get_node_or_null("HpText")
	if hp_text:
		hp_text.text = "HP %d/%d" % [player.hp, max_hp]

	var body := card.get_node_or_null("CardBody")
	if body:
		var energy_lbl: Label = body.get_node_or_null("EnergyLabel")
		if energy_lbl:
			energy_lbl.text = "⚡%d" % player.energy
		var dist_lbl: Label = body.get_node_or_null("DistLabel")
		if dist_lbl and _human_player_id >= 0 and player_id != _human_player_id:
			dist_lbl.text = "↔%d" % GameManager.get_distance(_human_player_id, player_id)

	var status_row: HBoxContainer = card.get_node_or_null("StatusRow")
	if status_row:
		for child in status_row.get_children():
			child.queue_free()
		if player.clone_count > 0:
			var badge := _make_status_badge("影分身×%d" % player.clone_count, Color("#0C447C"), Color("#E6F1FB"))
			badge.tooltip_text = "影分身：每存在一个影分身可以抵挡一次伤害，影分身可以帮助玩家聚气"
			status_row.add_child(badge)
		if player.paralyze_turns > 0:
			var badge := _make_status_badge("麻痹 %d回合" % player.paralyze_turns, Color("#BA7517"), Color("#FAEEDA"))
			badge.tooltip_text = "麻痹：无法出拳，跳过本回合"
			status_row.add_child(badge)
		if player.shield > 0:
			var badge := _make_status_badge("护盾 %d" % player.shield, Color("#534AB7"), Color("#EEEDFE"))
			badge.tooltip_text = "护盾：抵消 %d 点伤害" % player.shield
			status_row.add_child(badge)
		if player.delayed_damages.size() > 0:
			var total := 0
			for entry in player.delayed_damages:
				total += int(entry.get("damage", 0))
			var badge := _make_status_badge("⏱ %d伤" % total, Color("#A32D2D"), Color("#FCEBEB"))
			badge.tooltip_text = "延迟伤害：将在回合结束时触发 %d 点伤害" % total
			status_row.add_child(badge)

func _refresh_all_distances() -> void:
	if _human_player_id < 0:
		return
	for pid in _player_cards:
		if pid != _human_player_id:
			_refresh_player_card(pid)

func _refresh_all_cards() -> void:
	for pid in _player_cards:
		_refresh_player_card(pid)

func _rebuild_distance_labels() -> void:
	for lbl in _distance_labels:
		lbl.queue_free()
	_distance_labels.clear()

	var alive_ids: Array[int] = []
	for player in GameManager.get_alive_players():
		alive_ids.append(player.player_id)

	if alive_ids.size() < 2:
		return

	for i in range(alive_ids.size()):
		var pid_a := alive_ids[i]
		var pid_b := alive_ids[(i + 1) % alive_ids.size()]
		var card_a: Control = _player_cards.get(pid_a)
		var card_b: Control = _player_cards.get(pid_b)
		if card_a == null or card_b == null:
			continue

		var center_a := card_a.position + card_a.custom_minimum_size * 0.5
		var center_b := card_b.position + card_b.custom_minimum_size * 0.5
		var midpoint := (center_a + center_b) * 0.5
		var dist := GameManager.get_distance(pid_a, pid_b)

		var lbl := Label.new()
		lbl.text = "距离 %d" % dist
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color("#888780"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.position = midpoint - Vector2(20, 7)
		lbl.size = Vector2(40, 14)
		players_container.add_child(lbl)
		_distance_labels.append(lbl)

# ── Thinking indicator ───────────────────────────────────────────────────────

var _think_tweens: Dictionary = {}

func _set_thinking(player_id: int, active: bool) -> void:
	var card: Control = _player_cards.get(player_id)
	if card == null:
		return
	var bar: Panel = card.get_node_or_null("ThinkBar")
	var fill: ColorRect = card.get_node_or_null("ThinkFill")
	var lbl: Label = card.get_node_or_null("ThinkLabel")
	if bar == null or fill == null or lbl == null:
		return

	if active:
		bar.show(); fill.show(); lbl.show()
		var total := maxf(1.0, _timer_total_seconds)
		var pct := clampf(_turn_seconds_left / total, 0.0, 1.0)
		fill.size.x = pct * 94.0
		fill.color = Color("#FAC775") if pct > 0.33 else Color("#E24B4A")
		if player_id == _human_player_id:
			lbl.text = "决定中..."
		else:
			lbl.text = "思考中..."
	else:
		var old_tw: Tween = _think_tweens.get(player_id)
		if old_tw != null:
			old_tw.kill()
			_think_tweens.erase(player_id)
		bar.hide(); fill.hide(); lbl.hide()

func _show_all_thinking() -> void:
	for pid in _player_cards:
		var player := GameManager.get_player(pid)
		if player == null or not player.is_alive:
			continue
		if _in_tiebreak and not _tiebreak_candidate_ids.has(pid):
			continue
		if player.current_gesture == PlayerState.Gesture.SKIP:
			continue
		_set_thinking(pid, true)

func _hide_all_thinking() -> void:
	for pid in _player_cards:
		_set_thinking(pid, false)
		var fill: ColorRect = _player_cards[pid].get_node_or_null("ThinkFill") if _player_cards.has(pid) else null
		if fill:
			fill.color = Color("#888780")

func _mark_decided(player_id: int) -> void:
	var card: Control = _player_cards.get(player_id)
	if card == null:
		return
	var bar: Panel = card.get_node_or_null("ThinkBar")
	var fill: ColorRect = card.get_node_or_null("ThinkFill")
	var lbl: Label = card.get_node_or_null("ThinkLabel")
	if bar == null or fill == null or lbl == null:
		return

	var old_tw: Tween = _think_tweens.get(player_id)
	if old_tw != null:
		old_tw.kill()
		_think_tweens.erase(player_id)

	fill.size.x = 94.0
	fill.color = Color("#3B6D11")
	lbl.text = "✓ 已决定"
	lbl.add_theme_color_override("font_color", Color("#27500A"))
	bar.show(); fill.show(); lbl.show()

	var tw := create_tween()
	tw.tween_callback(func():
		bar.hide(); fill.hide(); lbl.hide()
		lbl.text = "思考中..."
		lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
		fill.color = Color("#888780")
		fill.size.x = 0.0
	).set_delay(0.8)

# ── Log ──────────────────────────────────────────────────────────────────────

func _setup_log_filter_ui() -> void:
	# Dark background strip behind the tab bar
	var tab_bg := ColorRect.new()
	tab_bg.name = "LogFilterBg"
	tab_bg.color = Color("#2C2C2A")
	tab_bg.position = Vector2(14, 80)
	tab_bg.size = Vector2(176, 22)
	tab_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab_bg)

	var filter_row := HBoxContainer.new()
	filter_row.name = "LogFilterRow"
	filter_row.add_theme_constant_override("separation", 0)
	filter_row.position = Vector2(14, 81)
	filter_row.size = Vector2(176, 20)
	filter_row.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(filter_row)
	_log_filter_buttons = filter_row

	_add_filter_button("全部", -1)

func _make_filter_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(0)
	s.content_margin_left = 4; s.content_margin_right = 4
	return s

func _player_filter_color(pid: int) -> Color:
	if pid == -1:
		return Color("#444441")
	var player := GameManager.get_player(pid)
	if player == null:
		return Color("#444441")
	var cls := _get_cls(player)
	return CLASS_AVATAR_BORDER.get(cls, Color("#444441"))

func _add_filter_button(label: String, pid: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 9)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 20)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	btn.pressed.connect(_on_filter_button_pressed.bind(pid))

	var pc := _player_filter_color(pid)
	var is_active := (pid == _log_filter_pid)
	if is_active:
		btn.add_theme_stylebox_override("normal",   _make_filter_style(pc))
		btn.add_theme_stylebox_override("hover",    _make_filter_style(pc))
		btn.add_theme_stylebox_override("pressed",  _make_filter_style(pc))
		btn.add_theme_color_override("font_color",         Color("#FFFDF5"))
		btn.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
		btn.add_theme_color_override("font_pressed_color", Color("#FFFDF5"))
	else:
		btn.add_theme_stylebox_override("normal",   _make_filter_style(Color("#2C2C2A")))
		btn.add_theme_stylebox_override("hover",    _make_filter_style(Color("#3A3A38")))
		btn.add_theme_stylebox_override("pressed",  _make_filter_style(pc))
		btn.add_theme_color_override("font_color",         Color("#888780"))
		btn.add_theme_color_override("font_hover_color",   Color("#D3D1C7"))
		btn.add_theme_color_override("font_pressed_color", Color("#FFFDF5"))

	_log_filter_buttons.add_child(btn)

func _on_filter_button_pressed(pid: int) -> void:
	_log_filter_pid = pid
	for child in _log_filter_buttons.get_children():
		child.queue_free()
	_add_filter_button("全部", -1)
	for player in GameManager.get_alive_players():
		_add_filter_button(player.character.character_name, player.player_id)
	for entry in _elimination_log:
		var p_name: String = entry.get("player_name", "")
		if p_name != "":
			# Check if already has a button (avoid duplicates for dead players)
			var already := false
			for child in _log_filter_buttons.get_children():
				if child is Button and child.text == p_name:
					already = true
					break
			if not already:
				_add_filter_button(p_name, int(entry.get("player_id", -1)))
	_rebuild_log_display()

func _rebuild_log_display() -> void:
	for row in _log_rows:
		row.queue_free()
	_log_rows.clear()
	for entry in _log_entries:
		var ep: int = entry.get("pid", -1)
		if _log_filter_pid != -1 and ep != -1 and ep != _log_filter_pid:
			continue
		_add_log_row(entry["text"], entry["type"], entry.get("details", []))
	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value

func _add_log_row(text: String, log_type: int, details: Array) -> PanelContainer:
	var colors: Array = LOG_COLORS[log_type]
	var row := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = colors[0]; s.border_color = colors[1]
	s.set_border_width_all(1); s.set_corner_radius_all(0)
	s.content_margin_left = 8.0; s.content_margin_right = 8.0
	s.content_margin_top  = 4.0; s.content_margin_bottom = 4.0
	row.add_theme_stylebox_override("panel", s)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	row.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = text
	title_lbl.add_theme_font_size_override("font_size", 10)
	title_lbl.add_theme_color_override("font_color", colors[2])
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	for det in details:
		var d_lbl := Label.new()
		d_lbl.text = "  " + str(det)
		d_lbl.add_theme_font_size_override("font_size", 10)
		d_lbl.add_theme_color_override("font_color", colors[3])
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(d_lbl)

	log_vbox.add_child(row)
	_log_rows.append(row)
	return row

func _append_log(text: String, log_type: int = LT_PHASE, pid: int = -1, details: Array[String] = []) -> void:
	_log_entries.append({"text": text, "type": log_type, "pid": pid, "details": details.duplicate()})
	while _log_entries.size() > MAX_LOG_ENTRIES:
		_log_entries.pop_front()
		if _log_rows.size() > 0:
			_log_rows[0].queue_free()
			_log_rows.pop_front()
	if _log_filter_pid != -1 and pid != -1 and pid != _log_filter_pid:
		return
	_add_log_row(text, log_type, details)
	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value

func _append_log_detail(text: String) -> void:
	if _log_entries.is_empty():
		_append_log(text, LT_PHASE)
		return
	_log_entries[-1]["details"].append(text)
	var last_pid: int = _log_entries[-1].get("pid", -1)
	if _log_filter_pid != -1 and last_pid != -1 and last_pid != _log_filter_pid:
		return
	if not _log_rows.is_empty():
		var last_row: PanelContainer = _log_rows[-1]
		var vbox := last_row.get_child(0) as VBoxContainer
		if vbox:
			var colors: Array = LOG_COLORS[_log_entries[-1]["type"]]
			var d_lbl := Label.new()
			d_lbl.text = "  " + text
			d_lbl.add_theme_font_size_override("font_size", 10)
			d_lbl.add_theme_color_override("font_color", colors[3])
			d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			d_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(d_lbl)
	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value

# ── Skill availability ────────────────────────────────────────────────────────

func _can_use_skill_on_any(player: PlayerState, skill: SkillData) -> bool:
	if player.energy < skill.energy_cost:
		return false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.SELF:
			return true
	for other in GameManager.get_alive_players():
		if other.player_id == player.player_id:
			continue
		var dist := GameManager.get_distance(player.player_id, other.player_id)
		if dist >= skill.min_range and dist <= skill.max_range:
			return true
	return false

func _make_skill_button(skill: SkillData, idx: int, can_use: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(172, 48)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not can_use

	var bg  := Color("#B5D4F4") if can_use else Color("#F1EFE8")
	var bdr := Color("#185FA5") if can_use else Color("#B4B2A9")
	btn.add_theme_stylebox_override("normal",   _make_flat(bg,              bdr,          2 if can_use else 1, 6))
	btn.add_theme_stylebox_override("hover",    _make_flat(Color("#9FCAE9"),Color("#0C447C"), 2, 6))
	btn.add_theme_stylebox_override("pressed",  _make_flat(Color("#80B8DC"),Color("#0C447C"), 2, 6))
	btn.add_theme_stylebox_override("disabled", _make_flat(Color("#F1EFE8"),Color("#B4B2A9"), 1, 6))

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var range_str: String
	if skill.max_range >= 999:
		range_str = "自身"
	elif skill.min_range == skill.max_range:
		range_str = "范围%d" % skill.min_range
	else:
		range_str = "范围%d~%d" % [skill.min_range, skill.max_range]

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 4)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var name_lbl := Label.new()
	name_lbl.text = skill.skill_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color("#042C53") if can_use else Color("#888780"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(name_lbl)

	var cb_bg := Color("#185FA5") if can_use else Color("#B4B2A9")
	var cb := Panel.new()
	cb.custom_minimum_size = Vector2(40, 14)
	cb.add_theme_stylebox_override("panel", _make_flat(cb_bg, cb_bg, 0, 3))
	cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(cb)
	var cb_lbl := Label.new()
	cb_lbl.text = "⚡×%d" % skill.energy_cost
	cb_lbl.add_theme_font_size_override("font_size", 9)
	cb_lbl.add_theme_color_override("font_color", Color("#E6F1FB"))
	cb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cb_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cb_lbl.anchor_right = 1.0; cb_lbl.anchor_bottom = 1.0
	cb.add_child(cb_lbl)

	var desc_scroll := ScrollContainer.new()
	desc_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	desc_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	desc_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(desc_scroll)

	var sub_lbl := Label.new()
	sub_lbl.text = "%s · %s" % [range_str, skill.description if skill.description != "" else "—"]
	sub_lbl.add_theme_font_size_override("font_size", 9)
	sub_lbl.add_theme_color_override("font_color", Color("#185FA5") if can_use else Color("#B4B2A9"))
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.custom_minimum_size = Vector2(160, 0)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_scroll.add_child(sub_lbl)

	btn.tooltip_text = "%s\n%s\n气: %d · %s" % [skill.skill_name, skill.description, skill.energy_cost, range_str]
	btn.pressed.connect(_on_skill_button_pressed.bind(idx, skill))
	return btn

# ── Tiebreak overlay ──────────────────────────────────────────────────────────

func _apply_tiebreak_card_styles(candidate_ids: Array[int]) -> void:
	for pid in _player_cards:
		var card: Control = _player_cards[pid]
		var body: Panel = card.get_node_or_null("CardBody")
		if pid in candidate_ids:
			card.modulate = Color(1, 1, 1, 1)
			if body:
				var player := GameManager.get_player(pid)
				var bdr_col := Color("#185FA5") if (player != null and player.is_human) else Color("#2C2C2A")
				body.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), Color("#E24B4A"), 3, 4))
		else:
			card.modulate = Color(1, 1, 1, 0.35)

func _restore_card_styles() -> void:
	for pid in _player_cards:
		var card: Control = _player_cards[pid]
		var player := GameManager.get_player(pid)
		if player == null or not player.is_alive:
			card.modulate = Color(0.4, 0.4, 0.4, 0.7)
			continue
		card.modulate = Color(1, 1, 1, 1)
		var body: Panel = card.get_node_or_null("CardBody")
		if body:
			var cls := _get_cls(player)
			var bdr_col := Color("#185FA5") if player.is_human else Color("#2C2C2A")
			body.add_theme_stylebox_override("panel", _make_flat(Color("#FFFDF5"), bdr_col, 2, 4))

# ── Target panel ──────────────────────────────────────────────────────────────

func _show_target_panel(skill_index: int, skill: SkillData) -> void:
	print("[game_ui] _show_target_panel skill=%s idx=%d, _current_action_player_id=%d" % [skill.skill_name, skill_index, _current_action_player_id])
	for child in target_panel.get_children():
		child.queue_free()

	# Header
	var hdr := Panel.new()
	hdr.custom_minimum_size = Vector2(172, 28)
	hdr.add_theme_stylebox_override("panel", _make_flat(Color("#2C2C2A"), Color("#2C2C2A"), 0, 4))
	target_panel.add_child(hdr)
	var hdr_lbl := Label.new()
	hdr_lbl.text = "目标：%s" % skill.skill_name
	hdr_lbl.add_theme_font_size_override("font_size", 11)
	hdr_lbl.add_theme_color_override("font_color", Color("#FAC775"))
	hdr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_lbl.anchor_right = 1.0; hdr_lbl.anchor_bottom = 1.0
	hdr.add_child(hdr_lbl)

	# Skill description
	if skill.description != "":
		var desc_lbl := Label.new()
		desc_lbl.text = skill.description
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		target_panel.add_child(desc_lbl)

	# Target buttons
	for player in GameManager.get_alive_players():
		if player.player_id == _current_action_player_id:
			continue
		var dist     := GameManager.get_distance(_current_action_player_id, player.player_id)
		var in_range := dist >= skill.min_range and dist <= skill.max_range
		var btn      := Button.new()
		btn.custom_minimum_size = Vector2(172, 44)
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not in_range

		var bg  := Color("#FAEEDA") if in_range else Color("#F1EFE8")
		var bdr := Color("#D85A30") if in_range else Color("#B4B2A9")
		btn.add_theme_stylebox_override("normal",   _make_flat(bg,              bdr,              2, 6))
		btn.add_theme_stylebox_override("hover",    _make_flat(Color("#F5E4C0"),Color("#9A5E0A"), 2, 6))
		btn.add_theme_stylebox_override("pressed",  _make_flat(Color("#EDD8A0"),Color("#6B4008"), 2, 6))
		btn.add_theme_stylebox_override("disabled", _make_flat(Color("#F1EFE8"),Color("#B4B2A9"), 1, 6))

		var vbox := VBoxContainer.new()
		vbox.anchor_right = 1.0; vbox.anchor_bottom = 1.0
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(vbox)

		var n_lbl := Label.new()
		n_lbl.text = player.player_name
		n_lbl.add_theme_font_size_override("font_size", 11)
		n_lbl.add_theme_color_override("font_color", Color("#412402") if in_range else Color("#888780"))
		n_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(n_lbl)

		var info_lbl := Label.new()
		info_lbl.text = "HP %d/%d · 距离%d %s" % [
			player.hp, player.character.max_hp, dist,
			"✓" if in_range else "— 超出射程"
		]
		info_lbl.add_theme_font_size_override("font_size", 9)
		info_lbl.add_theme_color_override("font_color", Color("#9A5E0A") if in_range else Color("#B4B2A9"))
		info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(info_lbl)

		if in_range:
			btn.pressed.connect(_on_target_selected.bind(player.player_id, skill_index))
		target_panel.add_child(btn)

	# Cancel button
	var cancel := Button.new()
	cancel.text = "← 取消，重新选择"
	cancel.add_theme_font_size_override("font_size", 11)
	cancel.add_theme_stylebox_override("normal",  _make_flat(Color("#444441"), Color("#444441"), 0, 6))
	cancel.add_theme_stylebox_override("hover",   _make_flat(Color("#5A5A57"), Color("#5A5A57"), 0, 6))
	cancel.add_theme_stylebox_override("pressed", _make_flat(Color("#333331"), Color("#333331"), 0, 6))
	cancel.add_theme_color_override("font_color",       Color("#D3D1C7"))
	cancel.add_theme_color_override("font_hover_color", Color("#FFFDF5"))
	cancel.pressed.connect(func(): target_panel.hide(); action_panel.show())
	target_panel.add_child(cancel)

	action_panel.hide()
	target_panel.show()

# ── Turn timer ────────────────────────────────────────────────────────────────

func _start_turn_timer() -> void:
	var timeout := SettingsManager.gesture_timeout
	if timeout == 0:
		timer_badge.hide()
		timer_label.hide()
		return
	_timer_total_seconds = float(timeout)
	_turn_seconds_left = _timer_total_seconds
	_timer_start_msec = Time.get_ticks_msec()
	_update_timer_label()
	_turn_timer.start()

func _stop_turn_timer() -> void:
	_turn_timer.stop()
	timer_badge.hide()
	timer_label.hide()

func _update_timer_label() -> void:
	var secs := int(ceil(_turn_seconds_left))
	timer_label.text = "剩余时间 %02ds" % secs
	if _turn_seconds_left > 20:
		timer_label.add_theme_color_override("font_color", Color("#FFFDF5"))
		timer_badge.color = Color("#533AB7")
	elif _turn_seconds_left > 10:
		timer_label.add_theme_color_override("font_color", Color("#2C2C2A"))
		timer_badge.color = Color("#FAC775")
	else:
		timer_label.add_theme_color_override("font_color", Color("#FFFDF5"))
		timer_badge.color = Color("#E24B4A")
	timer_badge.show()
	timer_label.show()
	# Update all thinking bar fills
	for pid in _player_cards:
		var card: Control = _player_cards[pid]
		if card:
			var fill: ColorRect = card.get_node_or_null("ThinkFill")
			if fill and fill.visible:
				var total := maxf(1.0, _timer_total_seconds)
				var pct := clampf(_turn_seconds_left / total, 0.0, 1.0)
				fill.size.x = pct * 94.0
				fill.color = Color("#FAC775") if pct > 0.33 else Color("#E24B4A")

var _current_phase_for_timer: int = -1

func _on_turn_timer_tick() -> void:
	# Use real wall-clock time so Engine.time_scale doesn't affect the countdown
	var elapsed_real := float(Time.get_ticks_msec() - _timer_start_msec) / 1000.0
	_turn_seconds_left = maxf(0.0, _timer_total_seconds - elapsed_real)
	if _turn_seconds_left <= 0:
		_turn_seconds_left = 0
		_update_timer_label()
		_turn_timer.stop()
		if _human_player_id >= 0 and not is_spectating:
			var human := GameManager.get_player(_human_player_id)
			if human != null and human.is_alive:
				if net_client:
					if _current_phase_for_timer == GameManager.GamePhase.ACTION_INPUT and _human_player_id == _current_action_player_id:
						net_client.submit_action(PlayerState.ActionType.CHARGE, -1, -1)
					else:
						var gestures: Array[PlayerState.Gesture] = [PlayerState.Gesture.ROCK, PlayerState.Gesture.SCISSORS, PlayerState.Gesture.PAPER]
						var rng := RandomNumberGenerator.new()
						rng.randomize()
						var g: PlayerState.Gesture = gestures[rng.randi() % 3]
						net_client.submit_gesture(g)
				elif _current_phase_for_timer == GameManager.GamePhase.ACTION_INPUT and _human_player_id == _current_action_player_id:
					GameManager.submit_action(_human_player_id, PlayerState.ActionType.CHARGE, -1, -1)
				else:
					var gestures: Array[PlayerState.Gesture] = [PlayerState.Gesture.ROCK, PlayerState.Gesture.SCISSORS, PlayerState.Gesture.PAPER]
					var rng := RandomNumberGenerator.new()
					rng.randomize()
					var g: PlayerState.Gesture = gestures[rng.randi() % 3]
					if _in_tiebreak:
						GameManager.submit_tiebreak_gesture(_human_player_id, g)
					else:
						GameManager.submit_gesture(_human_player_id, g)
		return
	_update_timer_label()

# ── Phase changes ─────────────────────────────────────────────────────────────

func _on_phase_changed(phase: GameManager.GamePhase, data: Dictionary = {}) -> void:
	_current_phase_for_timer = phase
	match phase:
		GameManager.GamePhase.GESTURE_INPUT:
			_stop_turn_timer()
			_in_tiebreak = false
			if not _is_draw_reentry:
				_current_round += 1
			_is_draw_reentry = false
			_refresh_all_cards()
			round_label.text = "第 %d 回合" % _current_round
			phase_label.text = "出拳阶段 — 请选择手势"
			phase_label.add_theme_color_override("font_color", Color("#FFFDF5"))
			if is_spectating:
				right_header_label.text = "观战中"
			else:
				right_header_label.text = "选择手势"
			var human   := GameManager.get_player(_human_player_id)
			var alive   := human != null and human.is_alive
			var skipped := human != null and (human.current_gesture == PlayerState.Gesture.SKIP or human.paralyze_turns > 0)
			gesture_panel.visible = (_human_player_id >= 0 and alive and not skipped and not is_spectating)
			action_panel.hide()
			target_panel.hide()
			_pending_reveals.clear()
			_append_log("── 回合 %d 开始 ──" % _current_round, LT_PHASE)
			_start_turn_timer()
			_show_all_thinking()

		GameManager.GamePhase.RESOLVING:
			_stop_turn_timer()
			_hide_all_thinking()
			gesture_panel.hide()
			phase_label.text = "结算中..."
			_play_all_gesture_reveals()

		GameManager.GamePhase.TIEBREAK_INPUT:
			_stop_turn_timer()
			_pending_reveals.clear()
			right_header_label.text = "加赛出拳"
			phase_label.text = "⚔ 加赛 — 请出拳"
			phase_label.add_theme_color_override("font_color", Color("#E24B4A"))
			# 客户端通过 data["candidates"] 获取加赛候选人（主机由 _on_tiebreak_started 直接设置）
			if data.has("candidates") and not (data["candidates"] as Array).is_empty():
				var cands: Array[int] = []
				for c in data["candidates"]:
					cands.append(int(c))
				_in_tiebreak = true
				_tiebreak_candidate_ids = cands
				_apply_tiebreak_card_styles(cands)
			if _human_player_id in _tiebreak_candidate_ids and not is_spectating:
				gesture_panel.show()
			else:
				gesture_panel.hide()
			action_panel.hide()
			target_panel.hide()
			_start_turn_timer()
			_show_all_thinking()

		GameManager.GamePhase.TIEBREAK_RESOLVING:
			_stop_turn_timer()
			_hide_all_thinking()
			_play_all_gesture_reveals()
			gesture_panel.hide()

		GameManager.GamePhase.ACTION_INPUT:
			_stop_turn_timer()
			right_header_label.text = "选择行动"
			phase_label.text = "行动阶段"
			var wid = data.get("winner_id", -1)
			print("[game_ui] _on_phase_changed ACTION_INPUT wid=%d, _human_player_id=%d, _current_action_player_id=%d" % [wid, _human_player_id, _current_action_player_id])
			if wid >= 0:
				_current_action_player_id = -1
				_on_action_required(wid)

		GameManager.GamePhase.APPLYING:
			_stop_turn_timer()
			action_panel.hide()
			target_panel.hide()

		GameManager.GamePhase.ELIMINATION:
			_stop_turn_timer()
			action_panel.hide()
			target_panel.hide()
			var elim_id: int = data.get("player_id", -1)
			if elim_id >= 0 and net_client:
				_on_player_eliminated(elim_id)

		GameManager.GamePhase.ROUND_END:
			if net_client:
				ClientStateSync.tick_delayed_damages()

		_:
			pass

# ── Signal handlers ───────────────────────────────────────────────────────────

var _pending_reveals: Array[Dictionary] = []

func _on_gesture_submitted(player_id: int, gesture: PlayerState.Gesture) -> void:
	if player_id == _human_player_id:
		gesture_panel.hide()
	var gesture_names: PackedStringArray = ["无", "石头", "剪刀", "布", "跳过"]
	var player := GameManager.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)
	var gname: String = gesture_names[gesture] if gesture < gesture_names.size() else str(gesture)
	var prefix := "[加赛] " if _in_tiebreak else ""
	_pending_reveals.append({"player_id": player_id, "gesture": gesture, "p_name": p_name, "gname": gname, "prefix": prefix})
	_mark_decided(player_id)

func _play_all_gesture_reveals() -> void:
	# Print all deferred log messages first
	for entry in _pending_reveals:
		var log_pid: int = entry["player_id"]
		var log_prefix: String = entry.get("prefix", "")
		var log_name: String = entry.get("p_name", str(log_pid))
		var log_gname: String = entry.get("gname", "")
		_append_log("%s%s 出了 %s" % [log_prefix, log_name, log_gname], LT_PHASE, log_pid)

	var gesture_emojis: PackedStringArray = ["", "✊", "✌", "✋", "⏭"]
	var popups: Array[Label] = []

	for entry in _pending_reveals:
		var pid: int = entry["player_id"]
		var g: int = entry["gesture"]
		var emoji: String = gesture_emojis[g] if g < gesture_emojis.size() else ""
		if emoji == "":
			continue
		var card: Control = _player_cards.get(pid)
		if card == null:
			continue

		var popup := Label.new()
		popup.text = emoji
		popup.add_theme_font_size_override("font_size", 36)
		popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup.self_modulate = Color(1, 1, 1, 0)
		popup.scale = Vector2(0.3, 0.3)
		popup.pivot_offset = Vector2(52, 38)
		popup.position = Vector2(0, -12)
		popup.size = Vector2(104, 56)
		card.add_child(popup)
		popups.append(popup)

	if popups.is_empty():
		_pending_reveals.clear()
		return

	# Phase 1: pop in (0→0.3s)
	for popup in popups:
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.3)
		t.tween_property(popup, "scale", Vector2(1.3, 1.3), 0.3)

	# Phase 2: settle (0.3→1.0s)
	for popup in popups:
		var t := create_tween()
		t.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.7).set_delay(0.3)

	# Phase 3: hold (1.0→1.5s, natural)

	# Phase 4: fade out (1.5→2.0s)
	for popup in popups:
		var t := create_tween()
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(1.5)
		t.tween_callback(func(): popup.queue_free()).set_delay(2.1)

	_pending_reveals.clear()

func _on_round_resolved(result: Dictionary) -> void:
	if result["is_draw"]:
		_append_log("── 平局，重新出拳 ──", LT_PHASE)
		_is_draw_reentry = true
		return
	var winners: Array = result["winners"] as Array
	if winners.size() == 1:
		var p := GameManager.get_player(int(winners[0]))
		_append_log("获胜方：%s" % (p.player_name if p else str(winners[0])), LT_WIN, int(winners[0]))
	else:
		var names: Array[String] = []
		for wid in winners:
			var p := GameManager.get_player(int(wid))
			names.append(p.player_name if p else str(wid))
		_append_log("多人获胜（%s），进入加赛" % ", ".join(PackedStringArray(names)), LT_WIN)

func _on_action_required(player_id: int) -> void:
	print("[game_ui] _on_action_required called player_id=%d, _human_player_id=%d" % [player_id, _human_player_id])
	if player_id != _human_player_id:
		print("[game_ui] _on_action_required SKIP: player_id != _human_player_id")
		return
	_current_action_player_id = player_id
	print("[game_ui] _on_action_required OK: showing action panel for player %d" % player_id)
	var player := GameManager.get_player(player_id)
	if player == null:
		return

	var gain := 1 + player.clone_count
	if player.clone_count > 0:
		btn_charge.text = "聚气 +%d (⚡)（影分身×%d）" % [gain, player.clone_count]
	else:
		btn_charge.text = "聚气 +1 (⚡)"

	for child in skills_container.get_children():
		child.queue_free()

	var sep := Label.new()
	sep.text = "— 技能 —"
	sep.add_theme_font_size_override("font_size", 10)
	sep.add_theme_color_override("font_color", Color("#888780"))
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_container.add_child(sep)

	var all_skills := player.get_all_skills()
	for i in range(all_skills.size()):
		var skill: SkillData = all_skills[i]
		var can_use := _can_use_skill_on_any(player, skill)
		skills_container.add_child(_make_skill_button(skill, i, can_use))

	action_panel.show()
	_start_turn_timer()

func _on_gesture_pressed(gesture: PlayerState.Gesture) -> void:
	gesture_panel.hide()
	if net_client:
		net_client.submit_gesture(gesture)
		_mark_decided(_human_player_id)
		_stop_turn_timer()
		return
	if _in_tiebreak:
		GameManager.submit_tiebreak_gesture(_human_player_id, gesture)
	else:
		GameManager.submit_gesture(_human_player_id, gesture)

func _on_charge_pressed() -> void:
	action_panel.hide()
	target_panel.hide()
	print("[game_ui] _on_charge_pressed: net_client=%s" % (net_client != null))
	if net_client:
		net_client.submit_action(PlayerState.ActionType.CHARGE, -1, -1)
		return
	GameManager.submit_action(_current_action_player_id, PlayerState.ActionType.CHARGE, -1, -1)

func _on_skill_button_pressed(skill_index: int, skill: SkillData) -> void:
	print("[game_ui] _on_skill_button_pressed skill=%s idx=%d, net_client=%s, _current_action_player_id=%d" % [skill.skill_name, skill_index, net_client != null, _current_action_player_id])
	var needs_target := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE \
		or effect.target == SkillEffect.EffectTarget.ENEMY_SPLASH:
			needs_target = true
			break
	if needs_target:
		_show_target_panel(skill_index, skill)
	else:
		action_panel.hide()
		if net_client:
			net_client.submit_action(PlayerState.ActionType.USE_SKILL, skill_index, -1)
		else:
			GameManager.submit_action(_current_action_player_id, PlayerState.ActionType.USE_SKILL, skill_index, -1)

func _on_target_selected(target_id: int, skill_index: int) -> void:
	target_panel.hide()
	print("[game_ui] _on_target_selected target_id=%d skill_index=%d, net_client=%s" % [target_id, skill_index, net_client != null])
	if net_client:
		net_client.submit_action(PlayerState.ActionType.USE_SKILL, skill_index, target_id)
		return
	GameManager.submit_action(_current_action_player_id, PlayerState.ActionType.USE_SKILL, skill_index, target_id)

## 纯 UI 渲染：状态已由 RoundResolver（主机）或 ClientStateSync（客户端）更新
func _on_skill_applied(logs: Array[Dictionary]) -> void:
	for entry in logs:
		var target := GameManager.get_player(entry["target_id"])
		var t_name := target.player_name if target else str(entry["target_id"])
		var effect_type: int = entry.get("effect_type", -1)
		var res: Dictionary  = entry.get("result", {})
		match effect_type:
			SkillEffect.EffectType.DAMAGE:
				var dealt: int    = res.get("damage_dealt", 0)
				var absorbed: int = res.get("shield_absorbed", 0)
				var remain: int   = res.get("remaining_hp", 0)
				var msg := "%s 护盾吸收%d，受%d伤，剩余HP %d" % [t_name, absorbed, dealt, remain] \
							if absorbed > 0 \
							else "%s 受到 %d 伤害，剩余HP %d" % [t_name, dealt, remain]
				_append_log(msg, LT_DAMAGE, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_attack_effect(entry["target_id"])
			SkillEffect.EffectType.SHIELD:
				var sv: int = res.get("shield_value", 0)
				_append_log("%s 获得%s" % [t_name, "全挡护盾" if sv == -1 else ("护盾 %d" % sv)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.CLONE_SHIELD:
				_append_log("%s 召唤影分身（下次受击全挡，聚气+1）" % t_name, LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.PARALYZE:
				_append_log("%s 被麻痹 %d 回合" % [t_name, res.get("turns", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.CHANGE_DISTANCE:
				var attacker := GameManager.get_player(entry.get("attacker_id", -1))
				var a_name   := attacker.player_name if attacker else "?"
				var dir      := "拉近" if res.get("delta", 0) < 0 else "拉远"
				_append_log("%s 与 %s 距离%s，当前: %d" % [a_name, t_name, dir, res.get("new_distance", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_all_distances()
			SkillEffect.EffectType.HEAL:
				_append_log("%s 回复 %d HP，剩余HP %d" % [t_name, res.get("heal_amount", 0), res.get("remaining_hp", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.DELAYED_DAMAGE:
				_append_log("%s 挂载延迟伤害（%d回合后受 %d 伤）" % [t_name, res.get("delay", 1), res.get("damage", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.UNLOCK_SKILL:
				var sname: String = res.get("skill_name", "")
				if sname != "":
					_append_log("%s 解锁新技能【%s】" % [t_name, sname], LT_WIN, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)

func _on_player_charged(player_id: int, new_energy: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.energy = new_energy
	var hint   := "（影分身+%d）" % player.clone_count if (player != null and player.clone_count > 0) else ""
	_append_log("%s 聚气%s，气槽: %d" % [player.player_name if player else str(player_id), hint, new_energy], LT_STATUS, player_id)
	_refresh_player_card(player_id)
	_play_charge_effect(player_id)

func _on_player_eliminated(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.is_alive = false
	_elim_order += 1
	_elimination_log.append({
		"order":       _elim_order,
		"player_id":   player_id,
		"player_name": player.player_name if player else str(player_id),
		"round":       _current_round,
	})
	_append_log("★ %s 被淘汰！" % (player.player_name if player else str(player_id)), LT_WIN, player_id)
	var card: Control = _player_cards.get(player_id)
	if card:
		card.modulate = Color(0.4, 0.4, 0.4, 0.7)
	_refresh_all_distances()
	_rebuild_distance_labels()

func _on_game_over(winner_id: int, record: MatchRecord) -> void:
	gesture_panel.hide()
	action_panel.hide()
	target_panel.hide()
	SceneManager.pending_game_result = {
		"winner_id":       winner_id,
		"elimination_log": _elimination_log.duplicate(true),
		"match_record":    record,
		"round":           _current_round,
	}
	SceneManager.go_to("res://scenes/game_over.tscn")

func _on_tiebreak_started(candidate_ids: Array[int]) -> void:
	var already_in_tiebreak := _in_tiebreak
	_in_tiebreak = true
	_tiebreak_candidate_ids = candidate_ids.duplicate()
	_apply_tiebreak_card_styles(candidate_ids)
	if not already_in_tiebreak:
		var names: Array[String] = []
		for id in candidate_ids:
			var p := GameManager.get_player(id)
			names.append(p.player_name if p else str(id))
		_append_log("── 加赛开始（%s）──" % ", ".join(PackedStringArray(names)), LT_STATUS)

func _on_tiebreak_resolved(winner_id: int) -> void:
	_in_tiebreak = false
	_restore_card_styles()
	# restore phase label color
	phase_label.add_theme_color_override("font_color", Color("#FFFDF5"))
	var p := GameManager.get_player(winner_id)
	_append_log("── 加赛胜出：%s ──" % (p.player_name if p else str(winner_id)), LT_WIN)

func _on_player_shielded(player_id: int, shield_value: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.shield = shield_value
	_refresh_player_card(player_id)

func _on_player_paralyzed(player_id: int, turns: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.paralyze_turns = turns
	_refresh_player_card(player_id)

func _on_distance_changed(_from_id: int, _to_id: int, _new_distance: int) -> void:
	_refresh_all_distances()
	_rebuild_distance_labels()

func _on_player_skipped(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("%s 被麻痹，跳过本回合" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_delayed_damage_triggered(player_id: int, damage: int, remaining_hp: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.hp = remaining_hp
	var p_name := player.player_name if player else str(player_id)
	if damage > 0:
		_append_log("⏰ %s 延迟伤害触发，受 %d 伤，剩余HP %d" % [p_name, damage, remaining_hp], LT_DAMAGE, player_id)
		_play_attack_effect(player_id)
	else:
		_append_log("⏰ %s 延迟伤害被护盾完全抵挡" % p_name, LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_clone_destroyed(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("影分身：%s 的影分身被击破！" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_skill_unlocked(player_id: int, skill_name: String) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("✦ %s 永久解锁技能【%s】" % [player.player_name if player else str(player_id), skill_name], LT_WIN, player_id)
	_refresh_player_card(player_id)


# ── 联机信号处理 ────────────────────────────────────────────────────────────

func _on_gestures_revealed(gestures: Dictionary, result: Dictionary) -> void:
	# 客户端：从网络数据填充 _pending_reveals，确保出拳日志和动画正常显示
	var gesture_names: PackedStringArray = ["无", "石头", "剪刀", "布", "跳过"]
	for pid in gestures:
		var g: int = gestures[pid]
		var player := GameManager.get_player(pid)
		var p_name := player.player_name if player else str(pid)
		var gname: String = gesture_names[g] if g < gesture_names.size() else str(g)
		var prefix := "[加赛] " if _in_tiebreak else ""
		_pending_reveals.append({"player_id": pid, "gesture": g, "p_name": p_name, "gname": gname, "prefix": prefix})
	_play_all_gesture_reveals()
	_on_round_resolved(result)

func _on_action_result(data: Dictionary) -> void:
	print("[game_ui] _on_action_result type=%s" % data.get('type', '?'))
	# 客户端：先将状态写入 GameManager，再渲染 UI（主机端状态由 RoundResolver 直接更新）
	ClientStateSync.apply_action_result(data)
	var action_type: String = data.get('type', '')
	match action_type:
		'skill':
			var raw_logs: Array = data.get('logs', [])
			var typed_logs: Array[Dictionary] = []
			for l in raw_logs:
				typed_logs.append(l)
			_on_skill_applied(typed_logs)
		'charge':
			_on_player_charged(data.get('player_id', -1), data.get('energy', 0))
		'paralyze':
			var pid: int = data.get('player_id', -1)
			_on_player_paralyzed(pid, data.get('turns', 0))
		'shield':
			var pid: int = data.get('player_id', -1)
			_on_player_shielded(pid, data.get('value', 0))
		'clone_destroyed':
			_on_clone_destroyed(data.get('player_id', -1))
		'skill_unlocked':
			var pid: int = data.get('player_id', -1)
			_on_skill_unlocked(pid, data.get('skill', ''))
		'delayed_damage':
			var pid: int = data.get('player_id', -1)
			_on_delayed_damage_triggered(pid, data.get('damage', 0), data.get('hp', 0))
		'distance':
			_on_distance_changed(data.get('from', -1), data.get('to', -1), data.get('dist', 0))
		'tiebreak_winner':
			_in_tiebreak = false
			_tiebreak_candidate_ids.clear()
			_restore_card_styles()
			phase_label.add_theme_color_override("font_color", Color("#FFFDF5"))
			var pid: int = data.get('player_id', -1)
			var p := GameManager.get_player(pid)
			_append_log('── 加赛胜出：%s ──' % (p.player_name if p else str(pid)), LT_WIN)

func _on_full_state_sync(players: Array, phase: int, round: int) -> void:
	_current_round = round
	if _player_cards.is_empty():
		_setup_from_sync(players)
		# PHASE_ENTER 先于 FULL_STATE_SYNC 到达时 _human_player_id 尚未设置，
		# 导致手势面板未显示。此处补充更新 UI 状态。
		if _human_player_id >= 0 and not is_spectating:
			var human_alive := false
			for ps_data in players:
				if ps_data["id"] == _human_player_id and ps_data["alive"]:
					human_alive = true
					break
			if human_alive:
				gesture_panel.show()
		_show_all_thinking()
	else:
		ClientStateSync.apply_full_sync(players)
		for ps_data in players:
			_refresh_player_card(ps_data["id"])
		_refresh_all_distances()
		_rebuild_distance_labels()

func _on_state_hash_received(expected_hash: int) -> void:
	var local_hash := _compute_local_state_hash()
	if local_hash != expected_hash:
		push_warning("[GameUI] 状态不同步（本地: %d，服务器: %d），请求全量同步" % [local_hash, expected_hash])
		if net_client:
			net_client.rpc_id(1, "client_request_sync")

func _compute_local_state_hash() -> int:
	var parts: Array[String] = []
	for p in GameManager._players:
		parts.append("%d:%d:%d:%d:%d:%d" % [
			p.player_id, p.hp, p.energy, p.shield,
			p.clone_count, p.paralyze_turns
		])
	parts.sort()
	return hash(",".join(PackedStringArray(parts)))

func _setup_from_sync(players_data: Array) -> void:
	for child in players_container.get_children():
		child.queue_free()
	_player_cards.clear()
	_elimination_log.clear()
	_elim_order = 0

	var my_pid = net_client.my_player_id if net_client else -1
	var player_states: Array[PlayerState] = []
	for data in players_data:
		var char_res = load(data["char_id"]) as CharacterData
		if char_res == null:
			continue
		var ps = PlayerState.new(data["id"], data["name"], char_res, data.get("is_human", data["id"] == my_pid))
		ps.team_id = data.get("team", 0)
		ps.hp = data["hp"]
		ps.energy = data["energy"]
		ps.shield = data["shield"]
		ps.paralyze_turns = data["paralyze"]
		ps.clone_count = data["clone"]
		ps.is_alive = data["alive"]
		ps.delayed_damages = data.get("delayed_dmg", [])
		for path in data.get("unlocked_skills", []):
			var skill_res := load(path) as SkillData
			if skill_res and not ps.unlocked_skills.has(skill_res):
				ps.unlocked_skills.append(skill_res)
		player_states.append(ps)
		if data["id"] == my_pid:
			_human_player_id = my_pid

	# 客户端：将同步的玩家状态写入 GameManager，使 get_player() 可用
	GameManager._players.clear()
	for ps in player_states:
		GameManager._players.append(ps)

	# 客户端初始化 DistanceSystem，使 get_distance() / _refresh_player_card 可用
	GameManager._distance_system = DistanceSystem.new()
	var seat_order: Array[int] = []
	for ps2 in player_states:
		seat_order.append(ps2.player_id)
	GameManager._distance_system.setup(seat_order)

	var count := player_states.size()
	for i in count:
		var ps := player_states[i]
		var angle := -PI / 2.0 + i * (TAU / count)
		var cx := ARENA_CENTER.x + ARENA_RADIUS * cos(angle)
		var cy := ARENA_CENTER.y + ARENA_RADIUS * sin(angle)
		var card := _build_player_card(ps)
		card.position = Vector2(cx - 52.0, cy - 55.0)
		players_container.add_child(card)
		_player_cards[ps.player_id] = card

	_refresh_all_distances()
	_rebuild_distance_labels()

	for ps in player_states:
		_add_filter_button(ps.character.character_name, ps.player_id)

func _on_game_over_result(winner_id: int, match_data: Dictionary = {}) -> void:
	gesture_panel.hide()
	action_panel.hide()
	target_panel.hide()
	var record = MatchRecord.from_dict(match_data) if not match_data.is_empty() else null
	SceneManager.pending_game_result = {
		'winner_id': winner_id,
		'elimination_log': _elimination_log.duplicate(true),
		'match_record': record,
		'round': _current_round,
	}
	SceneManager.go_to('res://scenes/game_over.tscn')
