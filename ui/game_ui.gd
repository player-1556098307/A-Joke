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
@onready var skills_container: VBoxContainer = $ActionPanel/SkillsScroll/SkillsContainer
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

const ARENA_RADIUS := 155.0
## 竞技场中心基准（960×540 设计分辨率下的值，运行时按实际尺寸缩放）
const ARENA_CENTER_DESIGN := Vector2(480.0, 295.0)
# Countdown duration is read from SettingsManager at runtime

## 获取竞技场中心（根据 PlayersContainer 实际大小按比例缩放，适配不同宽高比）
func _get_arena_center() -> Vector2:
	var container_size := players_container.size
	if container_size.x <= 0 or container_size.y <= 0:
		return ARENA_CENTER_DESIGN
	# 按 960×540 设计比例缩放竞技场中心位置
	return Vector2(
		container_size.x * (ARENA_CENTER_DESIGN.x / 960.0),
		container_size.y * (ARENA_CENTER_DESIGN.y / 540.0)
	)

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
	# ── 黑白配（手心手背）信号 ──
	GameManager.odd_even_started.connect(_on_odd_even_started)
	GameManager.odd_even_resolved.connect(_on_odd_even_resolved)
	GameManager.odd_even_finished.connect(_on_odd_even_finished)
	GameManager.player_shielded.connect(_on_player_shielded)
	GameManager.player_paralyzed.connect(_on_player_paralyzed)
	GameManager.player_knocked_down.connect(_on_player_knocked_down)
	GameManager.distance_changed.connect(_on_distance_changed)
	GameManager.player_skipped.connect(_on_player_skipped)
	GameManager.delayed_damage_triggered.connect(_on_delayed_damage_triggered)
	GameManager.clone_destroyed.connect(_on_clone_destroyed)
	GameManager.skill_unlocked.connect(_on_skill_unlocked)
	GameManager.bell_gained.connect(_on_bell_gained)
	GameManager.counter_stance_entered.connect(_on_counter_stance_entered)
	GameManager.counter_stance_triggered.connect(_on_counter_stance_triggered)
	GameManager.counter_stance_ended.connect(_on_counter_stance_ended)
	GameManager.skill_disabled.connect(_on_skill_disabled)
	GameManager.end_phase_bell_decision_required.connect(_on_end_phase_bell_decision_required)
	GameManager.player_invincible.connect(_on_player_invincible)
	GameManager.player_burning.connect(_on_player_burning)
	GameManager.player_berserker.connect(_on_player_berserker)
	GameManager.gate_changed.connect(_on_gate_changed)
	GameManager.eighth_gate_opened.connect(_on_eighth_gate_opened)
	GameManager.skill_lost.connect(_on_skill_lost)
	GameManager.burn_damage_triggered.connect(_on_burn_damage_triggered)
	GameManager.hp_payment_made.connect(_on_hp_payment_made)
	# ── 波风水门专属信号 ──
	GameManager.ftg_marks_changed.connect(_on_ftg_marks_changed)
	GameManager.ftg_mark_applied.connect(_on_ftg_mark_applied)
	GameManager.ftg_mark_removed.connect(_on_ftg_mark_removed)
	GameManager.ftg_swap_triggered.connect(_on_ftg_swap_triggered)
	GameManager.ftg_dodge_triggered.connect(_on_ftg_dodge_triggered)
	GameManager.nine_tails_stage_changed.connect(_on_nine_tails_stage_changed)
	GameManager.nine_tails_invincible_started.connect(_on_nine_tails_invincible_started)
	GameManager.nine_tails_invincible_ended.connect(_on_nine_tails_invincible_ended)
	GameManager.nine_tails_attack.connect(_on_nine_tails_attack)
	GameManager.ftg_intercept_required.connect(_on_ftg_intercept_required)
	GameManager.rasengan_counter_required.connect(_on_rasengan_counter_required)
	# ── 卫宫专属信号 ──
	GameManager.project_skill_required.connect(_on_project_skill_required)
	GameManager.project_skill_made.connect(_on_project_skill_made)
	GameManager.binding_field_started.connect(_on_binding_field_started)
	GameManager.binding_field_ended.connect(_on_binding_field_ended)
	GameManager.projected_skill_gained.connect(_on_projected_skill_gained)
	GameManager.projected_skill_lost.connect(_on_projected_skill_lost)
	# ── 宇智波泉奈专属信号 ──
	GameManager.glory_unlocked_changed.connect(_on_glory_unlocked_changed)
	GameManager.glory_takeover.connect(_on_glory_takeover)
	GameManager.glory_required.connect(_on_glory_required)
	GameManager.uchiha_stance_entered.connect(_on_uchiha_stance_entered)
	# ── 新止水（天劫）专属信号 ──
	GameManager.phantom_changed.connect(_on_phantom_changed)
	GameManager.phantom_dodge_required.connect(_on_phantom_dodge_required)
	GameManager.backtrack_required.connect(_on_backtrack_required)
	GameManager.backtrack_performed.connect(_on_backtrack_performed)
	GameManager.hiroari_targets_required.connect(_on_hiroari_targets_required)
	GameManager.hiroari_used.connect(_on_hiroari_used)
	GameManager.hiano_interrupt_required.connect(_on_hiano_interrupt_required)
	# ── 奥伯龙 / 卡斯特 专属信号 ──
	GameManager.dream_end_required.connect(_on_dream_end_required)
	GameManager.lake_blessing_required.connect(_on_lake_blessing_required)
	GameManager.sword_forge_required.connect(_on_sword_forge_required)
	GameManager.pilgrimage_shield_gained.connect(_on_pilgrimage_shield_gained)
	GameManager.sword_forge_unlocked_signal.connect(_on_sword_forge_unlocked)
	GameManager.sword_forge_used.connect(_on_sword_forge_used)
	GameManager.sword_forge_fallback.connect(_on_sword_forge_fallback)
	GameManager.lake_blessing_used.connect(_on_lake_blessing_used)
	GameManager.caliburn_used.connect(_on_caliburn_used)
	GameManager.dream_end_used.connect(_on_dream_end_used)

func _style_panels() -> void:
	# Background 锚定全屏（修正手机端 expand 模式下背景未铺满的问题）
	var bg: ColorRect = $Background
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# PlayersContainer 锚定全屏（让竞技场容器随视口缩放，_get_arena_center 据此居中）
	players_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	players_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# BorderFrame 锚定全屏（边框铺满视口）
	var border_frame: Panel = $BorderFrame
	border_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	_setup_auto_rps_button()
	_setup_odd_even_panel()

## 自动出拳开关按钮（战场区域左下角拐角）
var _auto_rps_btn: Button
func _setup_auto_rps_button() -> void:
	_auto_rps_btn = Button.new()
	_auto_rps_btn.text = "⚡自动"
	_auto_rps_btn.add_theme_font_size_override("font_size", 9)
	_auto_rps_btn.focus_mode = Control.FOCUS_NONE
	_auto_rps_btn.custom_minimum_size = Vector2(52, 18)
	_auto_rps_btn.position = Vector2(210, 514)
	_auto_rps_btn.size = Vector2(52, 18)
	_update_auto_rps_btn_style()
	_auto_rps_btn.pressed.connect(_on_auto_rps_toggled)
	add_child(_auto_rps_btn)

func _update_auto_rps_btn_style() -> void:
	if GameManager.auto_rps_enabled:
		_auto_rps_btn.add_theme_stylebox_override("normal",   _make_flat(Color("#27500A"), Color("#3B6D11"), 1, 3))
		_auto_rps_btn.add_theme_stylebox_override("hover",    _make_flat(Color("#3B6D11"), Color("#4A8A16"), 1, 3))
		_auto_rps_btn.add_theme_stylebox_override("pressed",  _make_flat(Color("#1E4727"), Color("#97C459"), 1, 3))
		_auto_rps_btn.add_theme_color_override("font_color",         Color("#EAF3DE"))
		_auto_rps_btn.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
		_auto_rps_btn.add_theme_color_override("font_pressed_color", Color("#97C459"))
	else:
		_auto_rps_btn.add_theme_stylebox_override("normal",   _make_flat(Color("#3A3A38"), Color("#5A5A57"), 1, 3))
		_auto_rps_btn.add_theme_stylebox_override("hover",    _make_flat(Color("#4A4A47"), Color("#888780"), 1, 3))
		_auto_rps_btn.add_theme_stylebox_override("pressed",  _make_flat(Color("#2C2C2A"), Color("#FAC775"), 1, 3))
		_auto_rps_btn.add_theme_color_override("font_color",         Color("#D3D1C7"))
		_auto_rps_btn.add_theme_color_override("font_hover_color",   Color("#FFFDF5"))
		_auto_rps_btn.add_theme_color_override("font_pressed_color", Color("#FAC775"))

func _on_auto_rps_toggled() -> void:
	GameManager.auto_rps_enabled = not GameManager.auto_rps_enabled
	_update_auto_rps_btn_style()
	if GameManager.auto_rps_enabled:
		_append_log("── 自动出拳已开启 ──", LT_STATUS)
		# 开启时立即触发自动出拳（若当前正处于出拳阶段且玩家未提交手势）
		GameManager.resume_auto_rps()

## 黑白配（手心手背）选择面板
var _odd_even_panel: VBoxContainer
var _btn_palm: Button   # 手心
var _btn_back: Button   # 手背
func _setup_odd_even_panel() -> void:
	_odd_even_panel = VBoxContainer.new()
	_odd_even_panel.position = Vector2(774, 88)
	_odd_even_panel.size = Vector2(172, 0)
	_odd_even_panel.add_theme_constant_override("separation", 8)
	_odd_even_panel.visible = false
	add_child(_odd_even_panel)

	var title := Label.new()
	title.text = "手心手背"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("#FFFDF5"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_odd_even_panel.add_child(title)

	_btn_palm = Button.new()
	_btn_palm.text = "🖐  手心"
	_btn_palm.add_theme_font_size_override("font_size", 15)
	_btn_palm.custom_minimum_size = Vector2(172, 52)
	_btn_palm.add_theme_stylebox_override("normal",  _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
	_btn_palm.add_theme_stylebox_override("hover",   _make_flat(Color("#EAF3DE"), Color("#3B6D11"), 2, 6))
	_btn_palm.add_theme_stylebox_override("pressed", _make_flat(Color("#D8ECC5"), Color("#27500A"), 3, 6))
	_btn_palm.add_theme_color_override("font_color",         Color("#2C2C2A"))
	_btn_palm.add_theme_color_override("font_hover_color",   Color("#27500A"))
	_btn_palm.add_theme_color_override("font_pressed_color", Color("#27500A"))
	_btn_palm.pressed.connect(_on_odd_even_pressed.bind(true))
	_odd_even_panel.add_child(_btn_palm)

	_btn_back = Button.new()
	_btn_back.text = "✊  手背"
	_btn_back.add_theme_font_size_override("font_size", 15)
	_btn_back.custom_minimum_size = Vector2(172, 52)
	_btn_back.add_theme_stylebox_override("normal",  _make_flat(Color("#FFFDF5"), Color("#D3D1C7"), 2, 6))
	_btn_back.add_theme_stylebox_override("hover",   _make_flat(Color("#FCEBEB"), Color("#E24B4A"), 2, 6))
	_btn_back.add_theme_stylebox_override("pressed", _make_flat(Color("#FADDDD"), Color("#791F1F"), 3, 6))
	_btn_back.add_theme_color_override("font_color",         Color("#2C2C2A"))
	_btn_back.add_theme_color_override("font_hover_color",   Color("#E24B4A"))
	_btn_back.add_theme_color_override("font_pressed_color", Color("#791F1F"))
	_btn_back.pressed.connect(_on_odd_even_pressed.bind(false))
	_odd_even_panel.add_child(_btn_back)

func _on_odd_even_pressed(choice: bool) -> void:
	_odd_even_panel.hide()
	GameManager.submit_odd_even(_human_player_id, choice)

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

	# bind_node(glow)：层切换释放旧卡片时 Tween 自动终止，回调不再访问已释放节点
	var tween := create_tween().bind_node(glow)
	tween.set_parallel(true)
	tween.tween_property(glow, "self_modulate", Color(1, 1, 1, 0.55), 0.2)
	tween.tween_property(glow, "scale", Vector2(1.06, 1.06), 0.2)
	tween.tween_property(glow, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(0.4)
	tween.tween_property(glow, "scale", Vector2(1.0, 1.0), 0.5).set_delay(0.4)
	tween.chain().tween_callback(func():
		if is_instance_valid(glow):
			glow.queue_free()
	)

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

	var t2 := create_tween().bind_node(popup)
	t2.tween_property(popup, "position", Vector2(34, -50), 0.7)
	t2.set_parallel(true)
	t2.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.2)
	t2.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.4).set_delay(0.4)
	t2.chain().tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

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

	var tween := create_tween().bind_node(flash)
	tween.tween_property(flash, "self_modulate", Color(1, 1, 1, 0), 0.35)
	tween.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free()
	).set_delay(0.4)

	var orig_pos := card.position
	var shake := create_tween().bind_node(card)
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

	var tween := create_tween().bind_node(ring)
	tween.set_parallel(true)
	tween.tween_property(ring, "self_modulate", Color(1, 1, 1, 0), 0.6)
	tween.tween_property(ring, "scale", Vector2(1.08, 1.08), 0.6)
	tween.chain().tween_callback(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)

## 伤害/治疗飘字
## kind: "normal"(红) / "true"(紫) / "pierce"(橙) / "crit"(大红暴击) / "heal"(绿)
func _show_damage_popup(target_id: int, amount: float, kind: String = "normal") -> void:
	if amount == 0.0:
		return
	var card: Control = _player_cards.get(target_id)
	if card == null:
		return

	var is_heal := kind == "heal"
	var sign_str := "+" if is_heal else "-"
	var text := "%s%.1f" % [sign_str, amount]
	if kind == "crit":
		text = "暴击！%s%.1f" % [sign_str, amount]

	var colors := {
		"normal": Color("#E24B4A"),
		"true":   Color("#9B59B6"),
		"pierce": Color("#E67E22"),
		"crit":   Color("#FF4444"),
		"heal":   Color("#639922"),
	}
	var col: Color = colors.get(kind, Color("#E24B4A"))
	var font_size := 20 if kind == "crit" else 16

	var popup := Label.new()
	popup.text = text
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_color_override("font_color", col)
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	popup.add_theme_constant_override("outline_size", 3)
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 卡片上方居中
	popup.position = Vector2(22.0, -8.0)
	popup.size = Vector2(60.0, 24.0)
	popup.z_index = 50
	card.add_child(popup)

	var tw := create_tween().bind_node(popup)
	tw.set_parallel(true)
	# 向上飘 36px + 淡出
	tw.tween_property(popup, "position", Vector2(22.0, -44.0), 0.8).set_trans(Tween.TRANS_QUART)
	tw.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.15)
	tw.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(0.3)
	# 暴击额外弹跳缩放
	if kind == "crit":
		popup.scale = Vector2(0.3, 0.3)
		tw.tween_property(popup, "scale", Vector2(1.3, 1.3), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(popup, "scale", Vector2(1.0, 1.0), 0.15)
	tw.chain().tween_callback(func():
		if is_instance_valid(popup):
			popup.queue_free()
	)

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
	var center := _get_arena_center()
	for i in count:
		var player := players[i]
		var angle  := -PI / 2.0 + i * (TAU / count)
		var cx     := center.x + ARENA_RADIUS * cos(angle)
		var cy     := center.y + ARENA_RADIUS * sin(angle)
		var card   := _build_player_card(player)
		card.position = Vector2(cx - 52.0, cy - 55.0)
		# 宙斯Boss卡片放大（更有Boss压迫感）：绕卡片中心缩放，位置不变
		if player.is_zeus_boss:
			card.pivot_offset = Vector2(52.0, 64.0)
			card.scale = Vector2(1.6, 1.6)
		players_container.add_child(card)
		_player_cards[player.player_id] = card

	_refresh_all_distances()
	_rebuild_distance_labels()

	# 重建日志过滤按钮：清空旧按钮，避免塔模式每层 setup_players 累积
	for child in _log_filter_buttons.get_children():
		child.queue_free()
	_log_filter_pid = -1
	_add_filter_button("全部", -1)
	for p in players:
		_add_filter_button(p.character.character_name, p.player_id)
	_rebuild_log_display()

func _get_cls(player: PlayerState) -> String:
	return player.character.tags[0] if player.character.tags.size() > 0 else "战士"

func _hp_color(hp: float, max_hp: float) -> Color:
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
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.mouse_entered.connect(_on_player_card_hovered.bind(player.player_id))
	wrap.mouse_exited.connect(_on_player_card_unhovered.bind(player.player_id))

	# HP text (above bar)
	var hp_lbl := Label.new()
	hp_lbl.name = "HpText"
	hp_lbl.text = "HP %.1f/%.1f" % [player.hp, player.get_max_hp()]
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
	hp_fill.color = _hp_color(player.hp, player.get_max_hp())
	hp_fill.position = Vector2(4.0, 11.0)
	hp_fill.size = Vector2(96.0 * float(player.hp) / float(player.get_max_hp()), 8.0)
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
	var card_bg := Color("#FFFDF5")
	if _tower_theme_active:
		card_bg = Color("#222018")
		bdr_col = Color("#5A4E38") if player.is_human else Color("#3A342A")
	body.add_theme_stylebox_override("panel", _make_flat(card_bg, bdr_col, bdr_w, 4))
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
		av_tex.name = "AvatarTexture"
		av_tex.texture = _get_player_portrait(player)
		av_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		av_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av_tex.anchor_right = 1.0; av_tex.anchor_bottom = 1.0
		av.add_child(av_tex)
	else:
		var av_lbl := Label.new()
		av_lbl.name = "AvatarLabel"
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
	var name_bar_bg := Color("#2C2C2A")
	if _tower_theme_active:
		name_bar_bg = Color("#3A342A")
	name_bar.add_theme_stylebox_override("panel", _make_flat(name_bar_bg, name_bar_bg, 0, 2))
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

	# Energy — 右上角菱形蓝色方片 + 白色黑体数字
	# pivot_offset 设为 size/2，使旋转围绕几何中心进行；菱形向右突出卡片边缘
	var _dia_size := 18.0
	var _dia_pos := Vector2(91.0, 5.0)   # body 坐标系，中心=(100,14)
	var energy_diamond := ColorRect.new()
	energy_diamond.name = "EnergyDiamond"
	energy_diamond.color = Color("#185FA5")
	energy_diamond.size = Vector2(_dia_size, _dia_size)
	energy_diamond.position = _dia_pos
	energy_diamond.pivot_offset = Vector2(_dia_size / 2.0, _dia_size / 2.0)  # 围绕中心旋转
	energy_diamond.rotation = PI / 4.0  # 旋转45°成菱形
	energy_diamond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_diamond.z_index = 1  # 低于对话/奖励弹窗(2/3)，弹窗弹出时气标被覆盖
	body.add_child(energy_diamond)

	var energy_lbl := Label.new()
	energy_lbl.name = "EnergyLabel"
	energy_lbl.text = "%d" % player.energy
	energy_lbl.add_theme_font_size_override("font_size", 13)
	energy_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
	energy_lbl.add_theme_color_override("font_outline_color", Color("#0A2A50"))
	energy_lbl.add_theme_constant_override("outline_size", 1)
	energy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	energy_lbl.size = Vector2(_dia_size, _dia_size)
	energy_lbl.position = _dia_pos  # 与菱形同位，文字在 size 框内居中 = 菱形中心
	energy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	energy_lbl.z_index = 1  # 与菱形同级，弹窗弹出时一起被覆盖
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

# ── 技能详情悬浮面板 ──────────────────────────────────────────────────────────

var _skill_tooltip: PanelContainer = null
var _tooltip_hovered_pid: int = -1

func _on_player_card_hovered(player_id: int) -> void:
	_tooltip_hovered_pid = player_id
	_show_skill_tooltip(player_id)

func _on_player_card_unhovered(player_id: int) -> void:
	if _tooltip_hovered_pid != player_id:
		return
	_tooltip_hovered_pid = -1
	_hide_skill_tooltip()

## 构建技能详情悬浮面板：角色名 + 全量技能列表（含被动技）
func _show_skill_tooltip(player_id: int) -> void:
	_hide_skill_tooltip()
	var player := GameManager.get_player(player_id)
	if player == null:
		return

	# 收集全量技能（含被动技、限定技），用于"查看"而非"操作"
	var all_skills: Array[SkillData] = []
	for skill in player.character.skills:
		all_skills.append(skill)
	for skill in player.unlocked_skills:
		if not _has_skill_in_list(all_skills, skill.skill_name):
			all_skills.append(skill)
	if player.projected_skill != null and not _has_skill_in_list(all_skills, player.projected_skill.skill_name):
		all_skills.append(player.projected_skill)
	for bs in player.binding_field_skills:
		if not _has_skill_in_list(all_skills, bs.skill_name):
			all_skills.append(bs)
	if all_skills.is_empty():
		return

	var card: Control = _player_cards.get(player_id)
	if card == null:
		return

	# 面板配色
	var panel_bg := Color("#FFFDF5")
	var panel_bdr := Color("#185FA5")
	var title_bg  := Color("#185FA5")
	var skill_bg  := Color("#F1EFE8")
	var skill_bdr := Color("#B4B2A9")
	var name_fg   := Color("#042C53")
	var desc_fg   := Color("#3A3A38")
	var cost_fg   := Color("#185FA5")
	var tag_passive_fg := Color("#9A9182")
	var tag_limited_fg := Color("#993556")
	if _tower_theme_active:
		panel_bg = Color("#222018")
		panel_bdr = Color("#5A4E38")
		title_bg  = Color("#3A342A")
		skill_bg  = Color("#2A2620")
		skill_bdr = Color("#5A4E38")
		name_fg   = Color("#FAC775")
		desc_fg   = Color("#E8E2D5")
		cost_fg   = Color("#FAC775")
		tag_passive_fg = Color("#9A9182")
		tag_limited_fg = Color("#C49A6A")

	var panel := PanelContainer.new()
	panel.name = "SkillTooltip"
	panel.custom_minimum_size = Vector2(230.0, 0.0)
	panel.z_index = 100
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_flat(panel_bg, panel_bdr, 2, 6))

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 4)
	outer_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(outer_vbox)

	# 标题栏：角色名
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0.0, 22.0)
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_theme_stylebox_override("panel", _make_flat(title_bg, title_bg, 0, 4))
	outer_vbox.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = player.player_name
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color("#FFFFFF"))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_lbl.anchor_right = 1.0; title_lbl.anchor_bottom = 1.0
	title_bar.add_child(title_lbl)

	# 技能条目
	for skill in all_skills:
		var entry := PanelContainer.new()
		entry.custom_minimum_size = Vector2(0.0, 0.0)
		entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_theme_stylebox_override("panel", _make_flat(skill_bg, skill_bdr, 1, 4))
		outer_vbox.add_child(entry)

		var evbox := VBoxContainer.new()
		evbox.add_theme_constant_override("separation", 2)
		evbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(evbox)

		# 第一行：技能名 + 耗气标签
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 4)
		top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		evbox.add_child(top_row)

		var sname := Label.new()
		sname.text = skill.skill_name
		sname.add_theme_font_size_override("font_size", 11)
		sname.add_theme_color_override("font_color", name_fg)
		sname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sname.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_row.add_child(sname)

		# 被动/限定标记
		if skill.is_passive:
			var tag := Label.new()
			tag.text = "[被动]"
			tag.add_theme_font_size_override("font_size", 8)
			tag.add_theme_color_override("font_color", tag_passive_fg)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top_row.add_child(tag)
		if skill.is_limited:
			var tag2 := Label.new()
			tag2.text = "[限定]"
			tag2.add_theme_font_size_override("font_size", 8)
			tag2.add_theme_color_override("font_color", tag_limited_fg)
			tag2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top_row.add_child(tag2)

		# 耗气标签
		var cost_str := "⚡%d" % skill.energy_cost
		if skill.bell_cost > 0:
			cost_str += " 钟%d" % skill.bell_cost
		if skill.ftg_cost > 0:
			cost_str += " 标%d" % skill.ftg_cost
		if skill.can_pay_with_hp:
			cost_str += "/HP"
		var cost_lbl := Label.new()
		cost_lbl.text = cost_str
		cost_lbl.add_theme_font_size_override("font_size", 9)
		cost_lbl.add_theme_color_override("font_color", cost_fg)
		cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_row.add_child(cost_lbl)

		# 第二行：范围 + 描述
		var range_str := _skill_range_str(skill)
		var desc_text := skill.description if skill.description != "" else "—"
		var desc_lbl := Label.new()
		desc_lbl.text = "%s · %s" % [range_str, desc_text]
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", desc_fg)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.custom_minimum_size = Vector2(200.0, 0)
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		evbox.add_child(desc_lbl)

	# 定位：放在卡片右侧，空间不够则放左侧
	add_child(panel)
	# 强制布局以获取实际尺寸
	panel.update_minimum_size()
	var panel_size := panel.get_combined_minimum_size()
	if panel_size.x <= 0:
		panel_size.x = 230.0
	if panel_size.y <= 0:
		panel_size.y = 200.0
	panel.size = panel_size
	panel.position = _calc_tooltip_pos(card, panel_size)

	_skill_tooltip = panel

func _hide_skill_tooltip() -> void:
	if _skill_tooltip != null and is_instance_valid(_skill_tooltip):
		_skill_tooltip.queue_free()
	_skill_tooltip = null

func _has_skill_in_list(skills: Array[SkillData], skill_name: String) -> bool:
	for s in skills:
		if s.skill_name == skill_name:
			return true
	return false

func _skill_range_str(skill: SkillData) -> String:
	if skill.max_range >= 999:
		return "自身"
	elif skill.min_range == skill.max_range:
		return "范围%d" % skill.min_range
	else:
		return "范围%d~%d" % [skill.min_range, skill.max_range]

func _calc_tooltip_pos(card: Control, panel_size: Vector2) -> Vector2:
	var card_pos := card.global_position
	var card_size := card.size
	var view_width := 960.0
	var view_height := 540.0
	var gap := 8.0
	# 优先放卡片右侧
	var x := card_pos.x + card_size.x + gap
	if x + panel_size.x > view_width:
		# 放左侧
		x = card_pos.x - panel_size.x - gap
	if x < 0:
		x = gap
	# 垂直居中对齐卡片
	var y := card_pos.y - (panel_size.y - card_size.y) / 2.0
	if y < 4.0:
		y = 4.0
	if y + panel_size.y > view_height:
		y = view_height - panel_size.y - 4.0
	return Vector2(x, y)

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

	var max_hp := player.get_max_hp()

	# 头像刷新：八门全开时切换到死门形态
	_refresh_player_avatar(card, player)

	var hp_fill: ColorRect = card.get_node_or_null("HpBarFill")
	if hp_fill:
		hp_fill.color = _hp_color(player.hp, max_hp)
		hp_fill.size.x = 96.0 * maxf(0.0, float(player.hp)) / float(max_hp)

	var hp_text: Label = card.get_node_or_null("HpText")
	if hp_text:
		hp_text.text = "HP %.1f/%.1f" % [player.hp, max_hp]

	var body := card.get_node_or_null("CardBody")
	if body:
		var energy_lbl: Label = body.get_node_or_null("EnergyLabel")
		if energy_lbl:
			energy_lbl.text = "%d" % player.energy
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
		if player.knockdown_turns > 0:
			var badge2 := _make_status_badge("击飞 %d回合" % player.knockdown_turns, Color("#7B4BA0"), Color("#F3ECFA"))
			badge2.tooltip_text = "击飞：可正常猜拳获得回合，但行动阶段只能聚气"
			status_row.add_child(badge2)
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
		if player.bell_count > 0:
			var badge := _make_status_badge("钟×%d" % player.bell_count, Color("#6B3A2A"), Color("#FBF0EB"))
			badge.tooltip_text = "钟：造成伤害时获得，可用于砸钟或招架"
			status_row.add_child(badge)
		if player.counter_stance:
			var badge := _make_status_badge("防反", Color("#185FA5"), Color("#E6F1FB"))
			badge.tooltip_text = "防反：受伤减半+免疫控制+获得1气+反击1伤"
			status_row.add_child(badge)
		if player.skill_disabled_turns > 0:
			var badge := _make_status_badge("封技 %d回合" % player.skill_disabled_turns, Color("#993C1D"), Color("#FAECE7"))
			badge.tooltip_text = "封技：无法使用技能（仅保留普攻）"
			status_row.add_child(badge)
		if player.invincible_turns > 0:
			var badge := _make_status_badge("无敌 %d回合" % player.invincible_turns, Color("#27500A"), Color("#EAF3DE"))
			badge.tooltip_text = "无敌：无视所有伤害和控制效果"
			status_row.add_child(badge)
		if player.burning:
			var badge := _make_status_badge("燃烧", Color("#A32D2D"), Color("#FCEBEB"))
			badge.tooltip_text = "燃烧：每回合结束失去1HP（HP>1保护）"
			status_row.add_child(badge)
		if player.berserker:
			var badge := _make_status_badge("狂战士", Color("#791F1F"), Color("#FCEBEB"))
			badge.tooltip_text = "狂战士：受伤回合结束额外失去1HP（可致死）"
			status_row.add_child(badge)
		if player.gate_count > 0:
			var badge := _make_status_badge("八门×%d" % player.gate_count, Color("#6B3A2A"), Color("#FBF0EB"))
			badge.tooltip_text = "八门遁甲：聚气时自动开门，第8门全开后获得新技能"
			status_row.add_child(badge)
		# ── 波风水门专属状态徽章 ──
		if player.ftg_marks > 0:
			var badge := _make_status_badge("飞雷神×%d" % player.ftg_marks, Color("#1A4B7A"), Color("#E1EFF8"))
			badge.tooltip_text = "飞雷神标记：可用于释放飞雷神技能"
			status_row.add_child(badge)
		if player.ftg_marked_by.size() > 0:
			var badge := _make_status_badge("被标记×%d" % player.ftg_marked_by.size(), Color("#A32D2D"), Color("#FCEBEB"))
			badge.tooltip_text = "被飞雷神标记：可能被波风水门换位或闪避"
			status_row.add_child(badge)
		if player.nine_tails_invincible:
			var stage_names: Array = ["", "咆哮", "大爪", "尾兽玉"]
			var stage_text: String = stage_names[player.nine_tails_stage] if player.nine_tails_stage < stage_names.size() else "?"
			var badge := _make_status_badge("九尾·%s" % stage_text, Color("#791F1F"), Color("#FCEBEB"))
			badge.tooltip_text = "漂泊九尾：无敌状态中，三段攻击进行中"
			status_row.add_child(badge)
		# ── 秽土柱间专属状态徽章 ──
		if player.stomp_active > 0:
			var badge := _make_status_badge("跺脚 %d回合" % player.stomp_active, Color("#2A5A3A"), Color("#EAF5ED"))
			badge.tooltip_text = "跺脚：受击时获得1气并下回合强制判胜"
			status_row.add_child(badge)
		# ── 卫宫专属状态徽章 ──
		if player.projected_skill != null:
			var badge := _make_status_badge("投影·%s" % player.projected_skill.skill_name, Color("#3B5BA5"), Color("#E8F0FB"))
			badge.tooltip_text = "投影：本回合可用投影复制的技能（使用后消失）"
			status_row.add_child(badge)
		if player.binding_field_turns > 0:
			var badge := _make_status_badge("无限剑制 %d回合" % player.binding_field_turns, Color("#185FA5"), Color("#E6F1FB"))
			badge.tooltip_text = "无限剑制：结界持续 %d 回合，结界内敌人的技能已被复制" % player.binding_field_turns
			status_row.add_child(badge)
		# ── 宇智波泉奈专属状态徽章 ──
		if player.uchiha_stance:
			var badge := _make_status_badge("宇智波流", Color("#3B2D5A"), Color("#EFEAFB"))
			badge.tooltip_text = "宇智波流：受击时伤害减半+进入无法选择+反击1伤并使攻击者本回合失去技能"
			status_row.add_child(badge)
		if player.untargetable_turns > 0:
			var badge := _make_status_badge("不可选 %d回合" % player.untargetable_turns, Color("#5A2D2D"), Color("#FBEAEA"))
			badge.tooltip_text = "无法选择：任何技能无法指定该玩家为目标"
			status_row.add_child(badge)
		if player.glory_unlocked:
			var badge := _make_status_badge("荣耀·可用", Color("#7A5A00"), Color("#FDF3DD"))
			badge.tooltip_text = "宇智波的荣耀：已解锁，持有4气时可在他人回合准备阶段夺取行动权"
			status_row.add_child(badge)
		# ── 新止水（天劫）专属状态徽章：幻影瞬身 ──
		if player.phantom_count > 0:
			var badge := _make_status_badge("幻影×%d" % player.phantom_count, Color("#2A5A7A"), Color("#E4F1F8"))
			badge.tooltip_text = "幻影瞬身：普攻命中+1幻影；每幻影普攻增伤0.5；可消耗1气+1幻影闪避一次攻击；3幻影可释放日影舞"
			status_row.add_child(badge)

## 获取玩家当前应显示的头像：八门全开（gate_count>=8）时使用死门形态图
func _get_player_portrait(player: PlayerState) -> Texture2D:
	if player.character.alternate_portrait != null and player.gate_count >= 8:
		return player.character.alternate_portrait
	return player.character.portrait

## 刷新玩家卡片头像（含八门全开形态切换）
func _refresh_player_avatar(card: Control, player: PlayerState) -> void:
	var av := card.get_node_or_null("CardBody/AvatarBox") as Panel
	if av == null:
		return
	var av_tex := av.get_node_or_null("AvatarTexture") as TextureRect
	if av_tex:
		av_tex.texture = _get_player_portrait(player)

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

	# bind_node(card)：层切换释放旧卡时 Tween 自动终止，不再访问已释放的子节点
	var tw := create_tween().bind_node(card)
	tw.tween_callback(func():
		if is_instance_valid(bar):
			bar.hide()
		if is_instance_valid(fill):
			fill.hide()
			fill.color = Color("#888780")
			fill.size.x = 0.0
		if is_instance_valid(lbl):
			lbl.hide()
			lbl.text = "思考中..."
			lbl.add_theme_color_override("font_color", Color("#5F5E5A"))
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
	title_lbl.add_theme_font_size_override("font_size", 8)
	title_lbl.add_theme_color_override("font_color", colors[2])
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	for det in details:
		var d_lbl := Label.new()
		d_lbl.text = "  " + str(det)
		d_lbl.add_theme_font_size_override("font_size", 8)
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
			d_lbl.add_theme_font_size_override("font_size", 8)
			d_lbl.add_theme_color_override("font_color", colors[3])
			d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			d_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(d_lbl)
	await get_tree().process_frame
	log_scroll.scroll_vertical = log_scroll.get_v_scroll_bar().max_value

# ── Skill availability ────────────────────────────────────────────────────────

func _can_use_skill_on_any(player: PlayerState, skill: SkillData) -> bool:
	# 可血付技能在气不足时也可用（用HP代替气支付）
	if player.energy < skill.energy_cost and not skill.can_pay_with_hp:
		return false
	# 血付需要保留至少1血
	if player.energy < skill.energy_cost and player.hp <= 1:
		return false
	# 钟消耗校验：无钟不可使用需钟的技能（如砸钟）
	if player.bell_count < skill.bell_cost:
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
		# 组队/塔模式：队友不可选为目标
		var me := GameManager.get_player(_current_action_player_id)
		if me != null and me.team_id != 0 and player.team_id == me.team_id:
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
		info_lbl.text = "HP %.1f/%.1f · 距离%d %s" % [
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
				# 黑白配超时 → 随机选手心/手背
				if _current_phase_for_timer == GameManager.GamePhase.ODD_EVEN_INPUT:
					var rng_oe := RandomNumberGenerator.new()
					rng_oe.randomize()
					GameManager.submit_odd_even(_human_player_id, rng_oe.randf() < 0.5)
				elif net_client:
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
	# 每次阶段变化同步自动出拳按钮样式（跨层 setup_game 重置状态后自动纠正显示）
	_update_auto_rps_btn_style()
	match phase:
		GameManager.GamePhase.ODD_EVEN_INPUT:
			_stop_turn_timer()
			_hide_all_thinking()
			gesture_panel.hide()
			action_panel.hide()
			target_panel.hide()
			_odd_even_panel.hide()
			phase_label.text = "手心手背 — 自动进行中" if GameManager.odd_even_auto else "手心手背 — 请选择"
			phase_label.add_theme_color_override("font_color", Color("#FAC775"))
			right_header_label.text = "黑白配"
			var oe_human := GameManager.get_player(_human_player_id)
			var oe_human_can_play := oe_human != null and oe_human.is_alive and oe_human.paralyze_turns <= 0 and not is_spectating
			# 自动模式下无需手动点击；手动模式才显示选择面板
			_odd_even_panel.visible = oe_human_can_play and not GameManager.odd_even_auto
			_append_log("── 手心手背（黑白配）──" , LT_PHASE)
			_start_turn_timer()
			_show_all_thinking()

		GameManager.GamePhase.ODD_EVEN_RESOLVING:
			_stop_turn_timer()
			_hide_all_thinking()
			_odd_even_panel.hide()
			phase_label.text = "黑白配结算中..."
			_play_odd_even_reveals()

		GameManager.GamePhase.GESTURE_INPUT:
			_stop_turn_timer()
			_in_tiebreak = false
			_odd_even_panel.hide()
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
			_odd_even_panel.hide()
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

		GameManager.GamePhase.PREPARATION:
			# 准备阶段：有准备技能（投影）的玩家按逆时针轮询释放
			# 无准备技能时 GameManager 会立即进入 ACTION_INPUT，此处仅更新提示
			_stop_turn_timer()
			action_panel.hide()
			target_panel.hide()
			gesture_panel.hide()
			phase_label.text = "准备阶段"
			phase_label.add_theme_color_override("font_color", Color("#185FA5"))
			right_header_label.text = "投影·准备"
			_append_log("── 准备阶段 ──", LT_STATUS)

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

		GameManager.GamePhase.END_PHASE:
			phase_label.text = "结束阶段"
			phase_label.add_theme_color_override("font_color", Color("#6B3A2A"))
			_refresh_all_cards()
			_append_log("── 结束阶段 ──", LT_STATUS)

		GameManager.GamePhase.ROUND_END:
			if net_client:
				ClientStateSync.tick_delayed_damages()

		_:
			pass

# ── Signal handlers ───────────────────────────────────────────────────────────

var _pending_reveals: Array[Dictionary] = []
var _pending_odd_even_reveals: Array[Dictionary] = []
var _odd_even_reveal_results: Dictionary = {}  # pid → {is_winner: bool, choice: bool}

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
	# 战斗日志不再显示猜拳过程（"XX 出了 石头"），仅由 _on_round_resolved 显示获胜方
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

	# Phase 1: pop in (0→0.3s) —— bind_node(popup)：层切换释放旧卡时 Tween 自动终止
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.set_parallel(true)
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.3)
		t.tween_property(popup, "scale", Vector2(1.3, 1.3), 0.3)

	# Phase 2: settle (0.3→1.0s)
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.7).set_delay(0.3)

	# Phase 3: hold (1.0→1.5s, natural)

	# Phase 4: fade out (1.5→2.0s)
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(1.5)
		t.tween_callback(func():
			if is_instance_valid(popup):
				popup.queue_free()
		).set_delay(2.1)

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

	# 击飞状态：只能聚气，隐藏所有技能按钮
	if player.knockdown_turns > 0:
		var kd_hint := Label.new()
		kd_hint.text = "— 击飞中，只能聚气 —"
		kd_hint.add_theme_font_size_override("font_size", 11)
		kd_hint.add_theme_color_override("font_color", Color("#7B4BA0"))
		kd_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skills_container.add_child(kd_hint)
		action_panel.show()
		_start_turn_timer()
		return

	var sep := Label.new()
	sep.text = "— 技能 —"
	sep.add_theme_font_size_override("font_size", 10)
	sep.add_theme_color_override("font_color", Color("#888780"))
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_container.add_child(sep)

	var all_skills := player.get_all_skills()
	for i in range(all_skills.size()):
		var skill: SkillData = all_skills[i]
		# 飞雷神拔除：仅当自身被飞雷神标记时才显示（水门不会被自己标记）
		if skill.skill_name == "飞雷神拔除" and player.ftg_marked_by.is_empty():
			continue
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
		_submit_skill_action(skill_index, skill, -1)

func _on_target_selected(target_id: int, skill_index: int) -> void:
	target_panel.hide()
	print("[game_ui] _on_target_selected target_id=%d skill_index=%d, net_client=%s" % [target_id, skill_index, net_client != null])
	# 需要找到对应的技能，走统一血付提交流程
	var player := GameManager.get_player(_current_action_player_id)
	if player == null:
		return
	var all_skills := player.get_all_skills()
	if skill_index < 0 or skill_index >= all_skills.size():
		return
	_submit_skill_action(skill_index, all_skills[skill_index], target_id)

## 统一技能提交流程：先检查血付需求，再提交行动
## 气不足且可血付时弹出血付选择框，确认后携带 hp_paid 提交
func _submit_skill_action(skill_index: int, skill: SkillData, target_id: int) -> void:
	var player := GameManager.get_player(_current_action_player_id)
	if player == null:
		return
	var hp_paid: float = 0.0
	if skill.can_pay_with_hp and player.energy < skill.energy_cost and player.hp > 1:
		# 需要血付：弹出血付选择框，确认后提交
		action_panel.hide()
		_show_hp_payment_dialog_with_callback(skill_index, skill, target_id)
		return
	# 无需血付，直接提交
	action_panel.hide()
	if net_client:
		net_client.submit_action(PlayerState.ActionType.USE_SKILL, skill_index, target_id, hp_paid)
	else:
		GameManager.submit_action(_current_action_player_id, PlayerState.ActionType.USE_SKILL, skill_index, target_id, hp_paid)

## 纯 UI 渲染：状态已由 RoundResolver（主机）或 ClientStateSync（客户端）更新
func _on_skill_applied(logs: Array[Dictionary]) -> void:
	for entry in logs:
		var target := GameManager.get_player(entry["target_id"])
		var t_name := target.player_name if target else str(entry["target_id"])
		var attacker := GameManager.get_player(entry.get("attacker_id", -1))
		var a_name := attacker.player_name if attacker else "?"
		var s_name: String = entry.get("skill_name", "")
		var skill_tag := "【%s】" % s_name if s_name != "" else ""
		var effect_type: int = entry.get("effect_type", -1)
		var res: Dictionary  = entry.get("result", {})
		match effect_type:
			SkillEffect.EffectType.DAMAGE:
				var dealt: float    = res.get("damage_dealt", 0.0)
				var absorbed: float = res.get("shield_absorbed", 0.0)
				var remain: float   = res.get("remaining_hp", 0.0)
				var msg := "%s%s 攻击 %s：护盾吸收%.1f，造成%.1f伤，剩余HP %.1f" % [a_name, skill_tag, t_name, absorbed, dealt, remain] \
							if absorbed > 0 \
							else "%s%s 攻击 %s：造成 %.1f 伤害，剩余HP %.1f" % [a_name, skill_tag, t_name, dealt, remain]
				_append_log(msg, LT_DAMAGE, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_attack_effect(entry["target_id"])
				_show_damage_popup(entry["target_id"], dealt, "normal")
			SkillEffect.EffectType.SHIELD:
				var sv: float = res.get("shield_value", 0.0)
				_append_log("%s%s 给 %s 施加%s" % [a_name, skill_tag, t_name, "全挡护盾" if sv == -1 else ("护盾 %.1f" % sv)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.CLONE_SHIELD:
				_append_log("%s%s 召唤影分身保护 %s（下次受击全挡，聚气+1）" % [a_name, skill_tag, t_name], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.PARALYZE:
				_append_log("%s%s 麻痹 %s %d 回合" % [a_name, skill_tag, t_name, res.get("turns", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.CHANGE_DISTANCE:
				var dir := "拉近" if res.get("delta", 0) < 0 else "拉远"
				_append_log("%s%s 与 %s 距离%s，当前: %d" % [a_name, skill_tag, t_name, dir, res.get("new_distance", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_all_distances()
			SkillEffect.EffectType.HEAL:
				_append_log("%s%s 治疗 %s：回复 %.1f HP，剩余HP %.1f" % [a_name, skill_tag, t_name, res.get("heal_amount", 0.0), res.get("remaining_hp", 0.0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
				_show_damage_popup(entry["target_id"], res.get("heal_amount", 0.0), "heal")
			SkillEffect.EffectType.DELAYED_DAMAGE:
				_append_log("%s%s 对 %s 挂载延迟伤害（%d回合后受 %.1f 伤）" % [a_name, skill_tag, t_name, res.get("delay", 1), res.get("damage", 0.0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.UNLOCK_SKILL:
				var sname: String = res.get("skill_name", "")
				if sname != "":
					_append_log("%s%s 解锁 %s 的新技能【%s】" % [a_name, skill_tag, t_name, sname], LT_WIN, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
			SkillEffect.EffectType.FTG_MARK:
				var dealt: float = res.get("damage_dealt", 0.0)
				_append_log("🌀 %s%s 飞雷神标记 %s！受 %.1f 伤，剩余HP %.1f" % [a_name, skill_tag, t_name, dealt, res.get("remaining_hp", 0.0)], LT_DAMAGE, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_skill_effect(entry["target_id"], effect_type)
				_show_damage_popup(entry["target_id"], dealt, "normal")
			SkillEffect.EffectType.FTG_CHARGE:
				_append_log("🌀 %s%s 为 %s 聚飞雷神标记（共%d个）" % [a_name, skill_tag, t_name, res.get("ftg_marks", 0)], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
			SkillEffect.EffectType.FTG_REMOVE:
				_append_log("🌀 %s%s 拔除 %s 的飞雷神标记" % [a_name, skill_tag, t_name], LT_STATUS, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
			SkillEffect.EffectType.NINE_TAILS:
				_append_log("🦊 %s%s 对 %s 释放漂泊九尾！" % [a_name, skill_tag, t_name], LT_WIN, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
			SkillEffect.EffectType.TRUE_DAMAGE:
				var tdealt: float = res.get("damage_dealt", 0.0)
				var tremain: float = res.get("remaining_hp", 0.0)
				_append_log("💫 %s%s 对 %s 造成 %.1f 真实伤害，剩余HP %.1f" % [a_name, skill_tag, t_name, tdealt, tremain], LT_DAMAGE, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_attack_effect(entry["target_id"])
				_show_damage_popup(entry["target_id"], tdealt, "true")
			SkillEffect.EffectType.PIERCE_DAMAGE:
				var pdealt: float = res.get("damage_dealt", 0.0)
				var premain: float = res.get("remaining_hp", 0.0)
				var pcrit: bool   = res.get("crit", false)
				var pmsg := "⚔️ %s%s 断头台穿透 %s！%s造成 %.1f 伤，剩余HP %.1f" % [a_name, skill_tag, t_name, "暴击!" if pcrit else "", pdealt, premain]
				_append_log(pmsg, LT_DAMAGE, entry.get("attacker_id", -1))
				_refresh_player_card(entry["target_id"])
				_play_attack_effect(entry["target_id"])
				_show_damage_popup(entry["target_id"], pdealt, "crit" if pcrit else "pierce")
			SkillEffect.EffectType.DEATH_SENTENCE:
				var rounds: Array = res.get("rounds", [])
				var wc: int = res.get("win_count", 0)
				var ik: bool = res.get("instant_kill", false)
				var dmg: float = res.get("damage_dealt", 0.0)
				var heal: float = res.get("total_heal", 0.0)
				var rem: float = res.get("remaining_hp", 0.0)
				# 7次猜拳结果：逐条清晰展示（每次猜拳独立成行，延迟滚动显示）
				_append_log("⚖️ %s%s 对 %s 发动断罪死！7次猜拳开始——" % [a_name, skill_tag, t_name], LT_PHASE, entry.get("attacker_id", -1))
				for i in range(rounds.size()):
					var r: Dictionary = rounds[i]
					var rwin: bool = r.get("win", false)
					var rcrit: bool = r.get("crit", false)
					var line: String
					if rwin:
						line = "  第%d次 ✊ 赢！%s%s" % [i + 1, "暴击×2 " if rcrit else "", "对 %s 造成 %.1f 伤" % [t_name, r.get("dmg", 0.0)]]
					else:
						line = "  第%d次 ✋ 输 — %s 回复 %.1f HP" % [i + 1, a_name, r.get("heal", 0.0)]
					_append_log(line, LT_STATUS if rwin else LT_DAMAGE, entry.get("attacker_id", -1))
					await get_tree().create_timer(0.18).timeout
				var summary := "⚖️ 断罪死结算：赢%d次" % wc
				if ik:
					summary += "，%s 被即死淘汰！" % t_name
				else:
					summary += "，%s 受 %.1f 伤，剩余HP %.1f" % [t_name, dmg, rem]
				if heal > 0:
					summary += "，%s 回复 %.1f HP" % [a_name, heal]
				_append_log(summary, LT_WIN, entry.get("attacker_id", -1))
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
		_play_elimination_effect(card)
	_refresh_all_distances()
	_rebuild_distance_labels()

## 淘汰特效：闪烁→缩放碎裂→旋转→淡出
func _play_elimination_effect(card: Control) -> void:
	var original_pos := card.position
	var original_scale := card.scale
	var original_mod := card.modulate
	var original_rot := card.rotation
	# 阶段1：红色闪烁警告（0→0.3s）
	var tw := create_tween().bind_node(card)
	tw.tween_method(
		func(t: float): card.modulate = original_mod.lerp(Color(1.0, 0.2, 0.2, 1.0), abs(sin(t * PI * 4))),
		0.0, 0.3, 0.3
	)
	# 阶段2：缩放碎裂（0.3→0.5s）—快速放大再骤缩
	tw.chain().tween_property(card, "scale", original_scale * 1.25, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(card, "scale", original_scale * 0.6, 0.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	# 阶段3：旋转坠落（0.5→0.85s）—顺时针旋转45度并下沉
	tw.chain().set_parallel(true)
	tw.tween_property(card, "rotation", original_rot + deg_to_rad(45.0), 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "position", original_pos + Vector2(0, 12), 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	# 阶段4：变灰淡出 + 回正姿态（0.85→1.4s）—转为灰色半透明，旋转和位移归位
	tw.chain().set_parallel(true)
	tw.tween_property(card, "modulate", Color(0.35, 0.35, 0.35, 0.55), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "rotation", original_rot, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position", original_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_game_over(winner_id: int, record: MatchRecord) -> void:
	gesture_panel.hide()
	action_panel.hide()
	target_panel.hide()
	# 慈悲尖塔模式：每层结束都触发 game_over，层推进由 TowerManager 处理，
	# 不跳转结算场景（否则与塔流程冲突导致崩溃）
	if GameManager.get("_is_tower_mode"):
		return
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

# ── 黑白配（手心手背）UI 回调 ──────────────────────────────────
func _on_odd_even_started(participant_ids: Array[int]) -> void:
	_pending_odd_even_reveals.clear()
	_odd_even_reveal_results.clear()
	var names: Array[String] = []
	for id in participant_ids:
		var p := GameManager.get_player(id)
		names.append(p.player_name if p else str(id))
	_append_log("── 黑白配开始（%d人）──" % participant_ids.size(), LT_STATUS)

func _on_odd_even_resolved(choices: Dictionary, winners: Array[int], is_tie: bool) -> void:
	# 记录每个玩家的选择和是否胜出，供动画使用
	for pid in choices:
		_odd_even_reveal_results[int(pid)] = {
			"choice": choices[pid],
			"is_winner": winners.has(int(pid))
		}

func _on_odd_even_finished(rps_participants: Array[int]) -> void:
	var names: Array[String] = []
	for id in rps_participants:
		var p := GameManager.get_player(id)
		names.append(p.player_name if p else str(id))
	_append_log("── 黑白配结束，%d人进入石头剪刀布：%s ──" % [rps_participants.size(), ", ".join(PackedStringArray(names))], LT_WIN)

## 黑白配揭示动画：在每张玩家卡上显示手心🖐或手背✊，胜出者高亮
func _play_odd_even_reveals() -> void:
	var popups: Array = []
	for pid in _odd_even_reveal_results:
		var info: Dictionary = _odd_even_reveal_results[pid]
		var choice: bool = info["choice"]
		var is_winner: bool = info["is_winner"]
		var emoji: String = "🖐" if choice else "✊"
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
		if is_winner:
			popup.add_theme_color_override("font_color", Color("#3B6D11"))
		else:
			popup.add_theme_color_override("font_color", Color("#E24B4A"))
		card.add_child(popup)
		popups.append(popup)

	if popups.is_empty():
		return

	# Phase 1: pop in (0→0.3s)
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.set_parallel(true)
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 1), 0.3)
		t.tween_property(popup, "scale", Vector2(1.3, 1.3), 0.3)

	# Phase 2: settle (0.3→0.8s)
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.tween_property(popup, "scale", Vector2(1.0, 1.0), 0.5).set_delay(0.3)

	# Phase 3: fade out (1.3→1.8s)
	for popup in popups:
		var t := create_tween().bind_node(popup)
		t.tween_property(popup, "self_modulate", Color(1, 1, 1, 0), 0.5).set_delay(1.3)
		t.tween_callback(func():
			if is_instance_valid(popup):
				popup.queue_free()
		).set_delay(1.9)

	# 日志记录结果
	var palm_names: Array[String] = []
	var back_names: Array[String] = []
	for pid in _odd_even_reveal_results:
		var p := GameManager.get_player(pid)
		var pname: String = p.player_name if p else str(pid)
		if _odd_even_reveal_results[pid]["choice"]:
			palm_names.append(pname)
		else:
			back_names.append(pname)
	var total_tie := _odd_even_reveal_results.size() > 0
	for pid in _odd_even_reveal_results:
		if _odd_even_reveal_results[pid]["is_winner"]:
			total_tie = false
			break
	if total_tie:
		_append_log("── 全部相同，重新配 ──", LT_STATUS)
	else:
		_append_log("手心(%d)：%s | 手背(%d)：%s" % [palm_names.size(), ", ".join(PackedStringArray(palm_names)), back_names.size(), ", ".join(PackedStringArray(back_names))], LT_PHASE)

	_odd_even_reveal_results.clear()

func _on_player_shielded(player_id: int, shield_value: float) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.shield = shield_value
	_refresh_player_card(player_id)

func _on_player_paralyzed(player_id: int, turns: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.paralyze_turns = turns
	_refresh_player_card(player_id)

func _on_player_knocked_down(player_id: int, turns: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.knockdown_turns = turns
	_refresh_player_card(player_id)

func _on_distance_changed(_from_id: int, _to_id: int, _new_distance: int) -> void:
	_refresh_all_distances()
	_rebuild_distance_labels()

func _on_player_skipped(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("%s 被麻痹，跳过本回合" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_delayed_damage_triggered(player_id: int, damage: float, remaining_hp: float) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.hp = remaining_hp
	var p_name := player.player_name if player else str(player_id)
	if damage > 0:
		_append_log("⏰ %s 延迟伤害触发，受 %.1f 伤，剩余HP %.1f" % [p_name, damage, remaining_hp], LT_DAMAGE, player_id)
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

func _on_bell_gained(player_id: int, bell_count: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("🔔 %s 获得一个钟（共%d个）" % [player.player_name if player else str(player_id), bell_count], LT_WIN, player_id)
	_refresh_player_card(player_id)

# ── 宇智波泉奈专属日志处理 ──
func _on_glory_unlocked_changed(player_id: int, unlocked: bool) -> void:
	var player := GameManager.get_player(player_id)
	if unlocked:
		_append_log("🏮 %s 的【宇智波的荣耀】已解锁！持有4气时可在他人回合夺取行动权" % (player.player_name if player else str(player_id)), LT_WIN, player_id)
	else:
		_append_log("🏮 %s 的【宇智波的荣耀】已消耗，需重新聚满4气解锁" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_glory_takeover(caster_id: int, target_id: int, damage: float, absorbed: float, clone_broken: bool) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("🏮 %s 触发【宇智波的荣耀】！%s 本回合失去所有技能并受到 %d 伤，本回合行动权归 %s！" % [c_name, t_name, int(damage), c_name], LT_WIN, caster_id)
	_refresh_player_card(caster_id)
	if target:
		_refresh_player_card(target_id)

var _glory_decision_dialog: PanelContainer = null

func _on_glory_required(player_id: int, target_id: int) -> void:
	if player_id != _human_player_id:
		return
	_show_glory_decision_dialog(player_id, target_id)

func _show_glory_decision_dialog(player_id: int, target_id: int) -> void:
	if _glory_decision_dialog != null:
		_glory_decision_dialog.queue_free()
	_glory_decision_dialog = PanelContainer.new()
	_glory_decision_dialog.position = Vector2(300, 180)
	_glory_decision_dialog.size = Vector2(380, 160)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#6B3A2A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_glory_decision_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_glory_decision_dialog.add_child(vbox)

	var target := GameManager.get_player(target_id)
	var t_name := target.player_name if target else str(target_id)
	var label := Label.new()
	label.text = "是否释放【宇智波的荣耀】？\n将夺取 %s 的本回合行动权并造成 2 伤" % t_name
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var btn_yes := Button.new()
	btn_yes.text = "释放荣耀"
	btn_yes.add_theme_font_size_override("font_size", 14)
	btn_yes.pressed.connect(func():
		if net_client:
			net_client.rpc("submit_glory_decision", player_id, true)
		else:
			GameManager.submit_glory_decision(player_id, true)
		if _glory_decision_dialog:
			_glory_decision_dialog.queue_free()
			_glory_decision_dialog = null
	)
	hbox.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.text = "跳过"
	btn_no.add_theme_font_size_override("font_size", 14)
	btn_no.pressed.connect(func():
		if net_client:
			net_client.rpc("submit_glory_decision", player_id, false)
		else:
			GameManager.submit_glory_decision(player_id, false)
		if _glory_decision_dialog:
			_glory_decision_dialog.queue_free()
			_glory_decision_dialog = null
	)
	hbox.add_child(btn_no)

	add_child(_glory_decision_dialog)

func _on_uchiha_stance_entered(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("🌀 %s 进入宇智波流招架状态" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_counter_stance_entered(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("🛡 %s 进入防反状态" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_counter_stance_triggered(target_id: int, attacker_id: int) -> void:
	var target := GameManager.get_player(target_id)
	var attacker := GameManager.get_player(attacker_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("⚔ %s 防反触发！减半伤害+获得1气+反击%s 1伤" % [t_name, attacker.player_name if attacker else str(attacker_id)], LT_DAMAGE, target_id)
	_refresh_player_card(target_id)
	if attacker:
		_refresh_player_card(attacker_id)

func _on_counter_stance_ended(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("🛡 %s 防反状态结束" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_skill_disabled(player_id: int, turns: int) -> void:
	var player := GameManager.get_player(player_id)
	if turns > 0:
		_append_log("🔒 %s 被封技 %d 回合" % [player.player_name if player else str(player_id), turns], LT_STATUS, player_id)
	else:
		_append_log("🔓 %s 封技解除" % (player.player_name if player else str(player_id)), LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_player_invincible(player_id: int, turns: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.invincible_turns = turns
	_append_log("✦ %s 进入无敌状态（%d回合）" % [player.player_name if player else str(player_id), turns], LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_player_burning(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.burning = true
	_append_log("🔥 %s 进入燃烧状态" % (player.player_name if player else str(player_id)), LT_DAMAGE, player_id)
	_refresh_player_card(player_id)

func _on_player_berserker(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.berserker = true
	_append_log("💥 %s 进入狂战士状态" % (player.player_name if player else str(player_id)), LT_DAMAGE, player_id)
	_refresh_player_card(player_id)

func _on_gate_changed(player_id: int, gate_count: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.gate_count = gate_count
	_append_log("🚪 %s 八门开到第%d门" % [player.player_name if player else str(player_id), gate_count], LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_eighth_gate_opened(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("★ %s 八门全开！回复10HP，获得【夜凯】【夕象】，进入燃烧+狂战士状态！" % (player.player_name if player else str(player_id)), LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_skill_lost(player_id: int, skill_name: String) -> void:
	var player := GameManager.get_player(player_id)
	if player and not player.lost_skills.has(skill_name):
		player.lost_skills.append(skill_name)
	_append_log("✖ %s 永久失去技能【%s】" % [player.player_name if player else str(player_id), skill_name], LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_burn_damage_triggered(player_id: int, damage: float, remaining_hp: float, reason: String) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.hp = remaining_hp
	_append_log("🔥 %s 因%s失去%.1fHP，剩余HP %.1f" % [player.player_name if player else str(player_id), reason, damage, remaining_hp], LT_DAMAGE, player_id)
	_refresh_player_card(player_id)
	_play_attack_effect(player_id)

# ── 波风水门专属信号处理 ────────────────────────────────────────────
func _on_ftg_marks_changed(player_id: int, marks: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.ftg_marks = marks
	_refresh_player_card(player_id)

func _on_ftg_mark_applied(target_id: int, attacker_id: int) -> void:
	var target := GameManager.get_player(target_id)
	var attacker := GameManager.get_player(attacker_id)
	if target:
		if not target.ftg_marked_by.has(attacker_id):
			target.ftg_marked_by.append(attacker_id)
	_refresh_player_card(target_id)

func _on_ftg_mark_removed(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.ftg_marked_by.clear()
	_append_log("🌀 %s 拔除了飞雷神标记" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_ftg_swap_triggered(swapper_id: int, swapped_id: int, original_target_id: int) -> void:
	var swapper := GameManager.get_player(swapper_id)
	var swapped := GameManager.get_player(swapped_id)
	_append_log("🌀 %s 与 %s 换位！%s 替代 %s 成为技能目标" % [
		swapper.player_name if swapper else str(swapper_id),
		swapped.player_name if swapped else str(swapped_id),
		swapped.player_name if swapped else str(swapped_id),
		"原目标"
	], LT_STATUS, swapper_id)
	_refresh_player_card(swapper_id)
	_refresh_player_card(swapped_id)
	_refresh_all_distances()

func _on_ftg_dodge_triggered(player_id: int, attacker_id: int) -> void:
	var player := GameManager.get_player(player_id)
	var attacker := GameManager.get_player(attacker_id)
	_append_log("🌀 %s 闪避 %s 的攻击！" % [
		player.player_name if player else str(player_id),
		attacker.player_name if attacker else str(attacker_id)
	], LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_nine_tails_stage_changed(player_id: int, stage: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.nine_tails_stage = stage
	_refresh_player_card(player_id)

func _on_nine_tails_invincible_started(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.nine_tails_invincible = true
	_append_log("🦊 %s 进入九尾无敌状态！" % (player.player_name if player else str(player_id)), LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_nine_tails_invincible_ended(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	if player:
		player.nine_tails_invincible = false
	_append_log("🦊 %s 九尾无敌结束" % (player.player_name if player else str(player_id)), LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_nine_tails_attack(player_id: int, stage: int, damage: float, target_ids: Array[int]) -> void:
	var player := GameManager.get_player(player_id)
	var stage_names: Array = ["", "咆哮", "大爪", "尾兽玉"]
	var stage_name: String = stage_names[stage] if stage < stage_names.size() else "?"
	var target_names: Array[String] = []
	for tid in target_ids:
		var tp := GameManager.get_player(tid)
		target_names.append(tp.player_name if tp else str(tid))
		_refresh_player_card(tid)
	_append_log("🦊 %s 九尾·%s 对 %s 造成 %.1f 伤害" % [
		player.player_name if player else str(player_id),
		stage_name,
		", ".join(target_names) if target_names.size() > 0 else "无目标",
		damage
	], LT_DAMAGE, player_id)

func _on_end_phase_bell_decision_required(player_id: int, bell_count: int) -> void:
	# 只有人类玩家才弹确认框
	if player_id != _human_player_id:
		return
	# 弹出招架确认对话框
	_show_bell_decision_dialog(player_id, bell_count)

var _bell_decision_dialog: PanelContainer = null

func _show_bell_decision_dialog(player_id: int, bell_count: int) -> void:
	if _bell_decision_dialog != null:
		_bell_decision_dialog.queue_free()
	_bell_decision_dialog = PanelContainer.new()
	_bell_decision_dialog.position = Vector2(300, 180)
	_bell_decision_dialog.size = Vector2(360, 140)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#6B3A2A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_bell_decision_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_bell_decision_dialog.add_child(vbox)

	var label := Label.new()
	label.text = "你是否消耗 1 个钟进入招架状态？\n（当前钟: %d）" % bell_count
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	var btn_yes := Button.new()
	btn_yes.text = "招架"
	btn_yes.add_theme_font_size_override("font_size", 14)
	btn_yes.pressed.connect(func():
		if net_client:
			net_client.submit_bell_decision(player_id, true)
		else:
			GameManager.submit_bell_decision(player_id, true)
		if _bell_decision_dialog:
			_bell_decision_dialog.queue_free()
			_bell_decision_dialog = null
	)
	hbox.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.text = "跳过"
	btn_no.add_theme_font_size_override("font_size", 14)
	btn_no.pressed.connect(func():
		if net_client:
			net_client.submit_bell_decision(player_id, false)
		else:
			GameManager.submit_bell_decision(player_id, false)
		if _bell_decision_dialog:
			_bell_decision_dialog.queue_free()
			_bell_decision_dialog = null
	)
	hbox.add_child(btn_no)

	add_child(_bell_decision_dialog)

## 血付弹窗（回调模式）：玩家选择用多少血支付，确认后携带 hp_paid 提交行动
var _hp_payment_dialog: PanelContainer = null

func _show_hp_payment_dialog_with_callback(skill_index: int, skill: SkillData, target_id: int) -> void:
	if _hp_payment_dialog != null:
		_hp_payment_dialog.queue_free()
	_hp_payment_dialog = PanelContainer.new()
	_hp_payment_dialog.position = Vector2(260, 160)
	_hp_payment_dialog.size = Vector2(440, 200)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#A32D2D")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_hp_payment_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_hp_payment_dialog.add_child(vbox)

	var player := GameManager.get_player(_current_action_player_id)
	if player == null:
		return
	var current_energy: int = player.energy
	var need: int = max(0, skill.energy_cost - current_energy)
	var max_hp_pay: int = max(0, player.hp - 1)

	var label := Label.new()
	label.text = "技能【%s】需要 %d 气，你当前有 %d 气，差 %d 气。\n可用生命值代替气支付（最多 %d HP，保留1血）。选择用多少血支付：" % [skill.skill_name, skill.energy_cost, current_energy, need, min(max_hp_pay, need)]
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)

	# 数值选择 SpinBox
	var spin_row := HBoxContainer.new()
	spin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spin_row.add_theme_constant_override("separation", 10)
	vbox.add_child(spin_row)

	var spin_lbl := Label.new()
	spin_lbl.text = "血付数量:"
	spin_lbl.add_theme_font_size_override("font_size", 13)
	spin_row.add_child(spin_lbl)

	var spin_box := SpinBox.new()
	spin_box.min_value = 0
	spin_box.max_value = mini(max_hp_pay, need)
	spin_box.value = mini(max_hp_pay, need)
	spin_box.step = 1
	spin_box.custom_minimum_size = Vector2(80, 0)
	spin_row.add_child(spin_box)

	# 按钮行
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var btn_confirm := Button.new()
	btn_confirm.text = "确认血付"
	btn_confirm.add_theme_font_size_override("font_size", 14)
	btn_confirm.pressed.connect(func():
		var hp_paid: float = float(spin_box.value)
		_dismiss_hp_payment_dialog()
		if net_client:
			net_client.submit_action(PlayerState.ActionType.USE_SKILL, skill_index, target_id, hp_paid)
		else:
			GameManager.submit_action(_current_action_player_id, PlayerState.ActionType.USE_SKILL, skill_index, target_id, hp_paid)
	)
	btn_row.add_child(btn_confirm)

	var btn_cancel := Button.new()
	btn_cancel.text = "取消"
	btn_cancel.add_theme_font_size_override("font_size", 14)
	btn_cancel.pressed.connect(func():
		_dismiss_hp_payment_dialog()
		action_panel.show()
	)
	btn_row.add_child(btn_cancel)

	add_child(_hp_payment_dialog)

func _dismiss_hp_payment_dialog() -> void:
	if _hp_payment_dialog:
		_hp_payment_dialog.queue_free()
		_hp_payment_dialog = null

## 血付完成：刷新玩家卡片并记录日志
func _on_hp_payment_made(player_id: int, hp_paid: float) -> void:
	if hp_paid <= 0:
		return
	var player := GameManager.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)
	_append_log("%s 用 %.1f 点生命值代替气支付" % [p_name, hp_paid], LT_STATUS, player_id)
	_refresh_player_card(player_id)


# ── 飞雷神拦截弹窗 ──────────────────────────────────────────────────

var _ftg_intercept_dialog: PanelContainer = null
## 暂存当前拦截上下文（供换位目标选择用）
var _ftg_intercept_ctx: Dictionary = {}

func _on_ftg_intercept_required(target_id: int, attacker_id: int, marked_player_ids: Array[int], attacker_is_marked: bool) -> void:
	# 只有人类玩家才弹窗
	if target_id != _human_player_id:
		return
	_ftg_intercept_ctx = {
		"target_id": target_id,
		"attacker_id": attacker_id,
		"marked_player_ids": marked_player_ids,
		"attacker_is_marked": attacker_is_marked,
	}
	_show_ftg_intercept_dialog(target_id, attacker_id, marked_player_ids, attacker_is_marked)

func _show_ftg_intercept_dialog(target_id: int, attacker_id: int, marked_player_ids: Array[int], attacker_is_marked: bool) -> void:
	if _ftg_intercept_dialog != null:
		_ftg_intercept_dialog.queue_free()
	_ftg_intercept_dialog = PanelContainer.new()
	_ftg_intercept_dialog.position = Vector2(240, 140)
	_ftg_intercept_dialog.size = Vector2(480, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#3B5BA5")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_ftg_intercept_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_ftg_intercept_dialog.add_child(vbox)

	var attacker := GameManager.get_player(attacker_id)
	var a_name := attacker.player_name if attacker else str(attacker_id)

	var label := Label.new()
	label.text = "🌀 %s 的技能命中了你！\n飞雷神术式激活——选择应对：" % a_name
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# ── 换位按钮 ──
	if not marked_player_ids.is_empty():
		# 如果只有一个被标记玩家，直接换位；多个则需要选择
		if marked_player_ids.size() == 1:
			var swap_target := GameManager.get_player(marked_player_ids[0])
			var s_name := swap_target.player_name if swap_target else str(marked_player_ids[0])
			var btn_swap := Button.new()
			btn_swap.text = "换位：与 %s 交换座位（替代你成为目标）" % s_name
			btn_swap.add_theme_font_size_override("font_size", 13)
			btn_swap.pressed.connect(func():
				_submit_ftg_intercept_choice(GameManager.FTGChoice.SWAP, marked_player_ids[0])
			)
			vbox.add_child(btn_swap)
		else:
			var swap_label := Label.new()
			swap_label.text = "选择换位目标："
			swap_label.add_theme_font_size_override("font_size", 13)
			vbox.add_child(swap_label)
			for pid in marked_player_ids:
				var swap_target := GameManager.get_player(pid)
				var s_name := swap_target.player_name if swap_target else str(pid)
				var btn := Button.new()
				btn.text = "换位：与 %s 交换" % s_name
				btn.add_theme_font_size_override("font_size", 13)
				btn.pressed.connect(func():
					_submit_ftg_intercept_choice(GameManager.FTGChoice.SWAP, pid)
				)
				vbox.add_child(btn)

	# ── 闪避按钮 ──
	if attacker_is_marked:
		var minato := GameManager.get_player(target_id)
		var can_dodge := minato != null and minato.energy >= 2
		var btn_dodge := Button.new()
		if can_dodge:
			btn_dodge.text = "闪避：免疫本次攻击，消耗2气对 %s 释放螺旋丸（3伤）" % a_name
		else:
			btn_dodge.text = "闪避：免疫本次攻击（气不足2，无法反击螺旋丸）"
		btn_dodge.add_theme_font_size_override("font_size", 13)
		btn_dodge.pressed.connect(func():
			_submit_ftg_intercept_choice(GameManager.FTGChoice.DODGE, -1)
		)
		vbox.add_child(btn_dodge)

	# ── 跳过按钮 ──
	var btn_skip := Button.new()
	btn_skip.text = "跳过（不使用飞雷神）"
	btn_skip.add_theme_font_size_override("font_size", 13)
	btn_skip.pressed.connect(func():
		_submit_ftg_intercept_choice(GameManager.FTGChoice.SKIP, -1)
	)
	vbox.add_child(btn_skip)

	add_child(_ftg_intercept_dialog)

func _submit_ftg_intercept_choice(choice: int, swap_target_id: int) -> void:
	var target_id: int = _ftg_intercept_ctx.get("target_id", -1)
	_dismiss_ftg_intercept_dialog()
	if target_id < 0:
		return
	if net_client:
		net_client.submit_ftg_intercept(target_id, choice, swap_target_id)
	else:
		GameManager.submit_ftg_intercept(target_id, choice, swap_target_id)

func _dismiss_ftg_intercept_dialog() -> void:
	if _ftg_intercept_dialog:
		_ftg_intercept_dialog.queue_free()
		_ftg_intercept_dialog = null
	_ftg_intercept_ctx.clear()


## ── 闪避后螺旋丸反击二次确认弹窗 ─────────────────────────────────

var _rasengan_counter_dialog: PanelContainer = null
var _rasengan_counter_ctx: Dictionary = {}

## 闪避成功后，征求玩家是否消耗2气释放螺旋丸反击
func _on_rasengan_counter_required(target_id: int, attacker_id: int, minato_energy: int) -> void:
	if target_id != _human_player_id:
		return
	_rasengan_counter_ctx = {
		"target_id": target_id,
		"attacker_id": attacker_id,
		"minato_energy": minato_energy,
	}
	_show_rasengan_counter_dialog(target_id, attacker_id, minato_energy)

func _show_rasengan_counter_dialog(target_id: int, attacker_id: int, minato_energy: int) -> void:
	if _rasengan_counter_dialog != null:
		_rasengan_counter_dialog.queue_free()
	_rasengan_counter_dialog = PanelContainer.new()
	_rasengan_counter_dialog.position = Vector2(240, 160)
	_rasengan_counter_dialog.size = Vector2(460, 200)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#E24B4A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_rasengan_counter_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_rasengan_counter_dialog.add_child(vbox)

	var attacker := GameManager.get_player(attacker_id)
	var a_name := attacker.player_name if attacker else str(attacker_id)

	var label := Label.new()
	label.text = "🌀 你闪避了 %s 的攻击！\n飞雷神术式逆转——是否消耗2气释放螺旋丸反击？" % a_name
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)

	var btn_yes := Button.new()
	btn_yes.text = "反击：对 %s 释放螺旋丸（3伤，消耗2气）" % a_name
	btn_yes.add_theme_font_size_override("font_size", 13)
	btn_yes.pressed.connect(func():
		_submit_rasengan_counter(true)
	)
	vbox.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.text = "放弃反击（保留能量）"
	btn_no.add_theme_font_size_override("font_size", 13)
	btn_no.pressed.connect(func():
		_submit_rasengan_counter(false)
	)
	vbox.add_child(btn_no)

	add_child(_rasengan_counter_dialog)

func _submit_rasengan_counter(use_counter: bool) -> void:
	var target_id: int = _rasengan_counter_ctx.get("target_id", -1)
	_dismiss_rasengan_counter_dialog()
	if target_id < 0:
		return
	if net_client:
		net_client.submit_rasengan_counter(target_id, use_counter)
	else:
		GameManager.submit_rasengan_counter(target_id, use_counter)

func _dismiss_rasengan_counter_dialog() -> void:
	if _rasengan_counter_dialog:
		_rasengan_counter_dialog.queue_free()
		_rasengan_counter_dialog = null
	_rasengan_counter_ctx.clear()


# ── 卫宫·投影弹窗 ──────────────────────────────────────────────────
## 投影：准备阶段选择目标玩家与技能（消耗1气，永久保留至用掉为止）
## 弹窗分两步：第一步选目标，第二步选技能（含被动技）
var _project_dialog: PanelContainer = null
var _project_ctx: Dictionary = {}

func _on_project_skill_required(player_id: int, target_ids: Array[int]) -> void:
	# 只有人类玩家才弹窗（AI 由 GameManager 自动决策）
	if player_id != _human_player_id:
		return
	_project_ctx = {"player_id": player_id, "target_ids": target_ids}
	_show_project_target_step(player_id, target_ids)

## 第一步：选择投影目标玩家
func _show_project_target_step(player_id: int, target_ids: Array[int]) -> void:
	_dismiss_project_dialog()
	_project_dialog = PanelContainer.new()
	_project_dialog.position = Vector2(240, 150)
	_project_dialog.size = Vector2(480, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#3B5BA5")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_project_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_project_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "⚔ 投影 — 选择目标玩家"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#185FA5"))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "消耗 1 气，复制目标玩家技能库中的一个技能（永久保留至用掉为止）"
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#5F5E5A"))
	vbox.add_child(hint)

	for tid in target_ids:
		var tp := GameManager.get_player(tid)
		var t_name := tp.player_name if tp else str(tid)
		var btn := Button.new()
		btn.text = "%s" % t_name
		btn.custom_minimum_size = Vector2(0, 34)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#E6F1FB"), Color("#185FA5"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#B5D4F4"), Color("#0C447C"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#9FCAE9"), Color("#0C447C"), 1, 4))
		btn.pressed.connect(func():
			_project_ctx["target_id"] = tid
			_show_project_skill_step(player_id, tid)
		)
		vbox.add_child(btn)

	var skip_btn := Button.new()
	skip_btn.text = "跳过（不使用投影）"
	skip_btn.add_theme_font_size_override("font_size", 12)
	skip_btn.add_theme_color_override("font_color", Color("#6F5E5A"))
	skip_btn.pressed.connect(func():
		_submit_project_choice(-1, "")
	)
	vbox.add_child(skip_btn)

	add_child(_project_dialog)

## 第二步：选择要投影的技能（含被动技）
func _show_project_skill_step(player_id: int, target_id: int) -> void:
	_dismiss_project_dialog()
	var target := GameManager.get_player(target_id)
	if target == null:
		_submit_project_choice(-1, "")
		return
	var all_skills := target.get_all_skills()

	_project_dialog = PanelContainer.new()
	_project_dialog.position = Vector2(240, 130)
	_project_dialog.size = Vector2(480, 300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#3B5BA5")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_project_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_project_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "⚔ 投影 — 选择 %s 的技能" % (target.player_name if target else str(target_id))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#185FA5"))
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for skill in all_skills:
		# 跳过卫宫自己的"投影"（防止套娃复制投影）
		if skill.skill_name == "投影":
			continue
		var btn := Button.new()
		var range_str: String
		if skill.max_range >= 999:
			range_str = "自身"
		elif skill.min_range == skill.max_range:
			range_str = "范围%d" % skill.min_range
		else:
			range_str = "范围%d~%d" % [skill.min_range, skill.max_range]
		btn.text = "%s（⚡%d · %s）" % [skill.skill_name, skill.energy_cost, range_str]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.tooltip_text = skill.description
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#EAF3DE"), Color("#639922"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#C0DD97"), Color("#27500A"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#A8CE7E"), Color("#27500A"), 1, 4))
		btn.pressed.connect(func():
			_submit_project_choice(target_id, skill.resource_path)
		)
		list.add_child(btn)

	if all_skills.is_empty():
		var empty := Label.new()
		empty.text = "（目标没有可用技能）"
		empty.add_theme_font_size_override("font_size", 12)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)

	var back_btn := Button.new()
	back_btn.text = "← 返回选择目标"
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.pressed.connect(func():
		_show_project_target_step(player_id, _project_ctx.get("target_ids", []))
	)
	vbox.add_child(back_btn)

	add_child(_project_dialog)

## 提交投影选择：-1 表示跳过
func _submit_project_choice(target_id: int, skill_path: String) -> void:
	var player_id: int = _project_ctx.get("player_id", -1)
	_dismiss_project_dialog()
	if player_id < 0:
		return
	# 网络对局：主机侧由 RPC client_submit_project_skill 转发到 GameManager；
	# 本地对局：直接 emit project_skill_made 信号（GameManager 已连接 _on_project_skill_made）
	if net_client:
		net_client.submit_project_skill(player_id, target_id, skill_path)
	else:
		GameManager.submit_project_skill(player_id, target_id, skill_path)

func _dismiss_project_dialog() -> void:
	if _project_dialog:
		_project_dialog.queue_free()
		_project_dialog = null

## 投影完成（本机回显或网络同步）：刷新卡片并记日志
func _on_project_skill_made(player_id: int, target_id: int, skill_path: String) -> void:
	var player := GameManager.get_player(player_id)
	var target := GameManager.get_player(target_id)
	if skill_path == "" or target_id < 0:
		var p_name := player.player_name if player else str(player_id)
		_append_log("%s 跳过了投影" % p_name, LT_STATUS, player_id)
		return
	var skill_res := load(skill_path) as SkillData
	if skill_res == null:
		return
	var p_name := player.player_name if player else str(player_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("⚔ %s 投影了 %s 的技能【%s】" % [p_name, t_name, skill_res.skill_name], LT_WIN, player_id)
	_refresh_player_card(player_id)

## 投影技能获得（投影成功）
func _on_projected_skill_gained(player_id: int, skill_name: String) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("⚔ %s 获得了投影技能【%s】（本回合可用，使用后消失）" % [
		player.player_name if player else str(player_id), skill_name
	], LT_WIN, player_id)
	_refresh_player_card(player_id)

## 投影技能使用后消失
func _on_projected_skill_lost(player_id: int, skill_name: String) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("⚔ %s 的投影技能【%s】已用完消失" % [
		player.player_name if player else str(player_id), skill_name
	], LT_STATUS, player_id)
	_refresh_player_card(player_id)

# ── 卫宫·无限剑制信号 ───────────────────────────────────────────────

func _on_binding_field_started(player_id: int, turns: int, target_ids: Array[int]) -> void:
	var player := GameManager.get_player(player_id)
	var target_names: Array[String] = []
	for tid in target_ids:
		var tp := GameManager.get_player(tid)
		target_names.append(tp.player_name if tp else str(tid))
		_refresh_player_card(tid)
	var p_name := player.player_name if player else str(player_id)
	_append_log("🗡 %s 展开无限剑制结界（%d回合），锁定敌人：%s" % [
		p_name, turns, ", ".join(target_names) if not target_names.is_empty() else "无"
	], LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_binding_field_ended(player_id: int) -> void:
	var player := GameManager.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)
	_append_log("🗑 %s 的无限剑制结界消散" % p_name, LT_STATUS, player_id)
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
		'knockdown':
			var pid: int = data.get('player_id', -1)
			_on_player_knocked_down(pid, data.get('turns', 0))
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
		'bell_gained':
			_on_bell_gained(data.get('player_id', -1), data.get('bell_count', 0))
		'counter_stance':
			_on_counter_stance_entered(data.get('player_id', -1))
		'counter_triggered':
			_on_counter_stance_triggered(data.get('target_id', -1), data.get('attacker_id', -1))
		'counter_ended':
			_on_counter_stance_ended(data.get('player_id', -1))
		'skill_disabled':
			_on_skill_disabled(data.get('player_id', -1), data.get('turns', 0))
		'invincible':
			_on_player_invincible(data.get('player_id', -1), data.get('turns', 0))
		'burning':
			_on_player_burning(data.get('player_id', -1))
		'berserker':
			_on_player_berserker(data.get('player_id', -1))
		'gate_changed':
			_on_gate_changed(data.get('player_id', -1), data.get('gate_count', 0))
		'eighth_gate':
			_on_eighth_gate_opened(data.get('player_id', -1))
		'skill_lost':
			_on_skill_lost(data.get('player_id', -1), data.get('skill_name', ''))
		'burn_damage':
			_on_burn_damage_triggered(data.get('player_id', -1), data.get('damage', 0.0), data.get('hp', 0.0), data.get('reason', ''))
		'hp_payment':
			var pid: int = data.get('player_id', -1)
			var hp_paid: float = data.get('hp_paid', 0.0)
			if hp_paid > 0:
				var player := GameManager.get_player(pid)
				var p_name := player.player_name if player else str(pid)
				_append_log("%s 用 %.1f 点生命值代替气支付" % [p_name, hp_paid], LT_STATUS, pid)
			_refresh_player_card(pid)
		'ftg_marks_changed':
			_on_ftg_marks_changed(data.get('player_id', -1), data.get('marks', 0))
		'ftg_mark_applied':
			_on_ftg_mark_applied(data.get('target_id', -1), data.get('attacker_id', -1))
		'ftg_mark_removed':
			_on_ftg_mark_removed(data.get('player_id', -1))
		'ftg_swap':
			_on_ftg_swap_triggered(data.get('swapper_id', -1), data.get('swapped_id', -1), data.get('original_target_id', -1))
		'ftg_dodge':
			_on_ftg_dodge_triggered(data.get('player_id', -1), data.get('attacker_id', -1))
		'nine_tails_stage':
			_on_nine_tails_stage_changed(data.get('player_id', -1), data.get('stage', 0))
		'nine_tails_invincible_started':
			_on_nine_tails_invincible_started(data.get('player_id', -1))
		'nine_tails_invincible_ended':
			_on_nine_tails_invincible_ended(data.get('player_id', -1))
		'nine_tails_attack':
			_on_nine_tails_attack(data.get('player_id', -1), data.get('stage', 0), data.get('damage', 0.0), data.get('target_ids', []))
		# ── 卫宫网络事件分发 ──
		'project_skill_made':
			_on_project_skill_made(data.get('player_id', -1), data.get('target_id', -1), data.get('skill_path', ''))
		'projected_skill_gained':
			_on_projected_skill_gained(data.get('player_id', -1), data.get('skill_name', ''))
		'projected_skill_lost':
			_on_projected_skill_lost(data.get('player_id', -1), data.get('skill_name', ''))
		'binding_field_started':
			_on_binding_field_started(data.get('player_id', -1), data.get('turns', 0), data.get('target_ids', []))
		'binding_field_ended':
			_on_binding_field_ended(data.get('player_id', -1))
		# ── 新止水（天劫）网络事件分发 ──
		'phantom_changed':
			_on_phantom_changed(data.get('player_id', -1), data.get('count', 0))
		'hiroari_used':
			_on_hiroari_used(data.get('player_id', -1), data.get('target_ids', []))
		'backtrack_performed':
			_on_backtrack_performed(data.get('player_id', -1), data.get('round', 0))
		# ── 奥伯龙 / 卡斯特 网络事件分发 ──
		'dream_end_used':
			_on_dream_end_used(data.get('caster_id', -1), data.get('target_id', -1))
		'lake_blessing_used':
			_on_lake_blessing_used(data.get('caster_id', -1), data.get('target_id', -1))
		'sword_forge_used':
			_on_sword_forge_used(data.get('caster_id', -1), data.get('target_id', -1), data.get('skill_name', ''))
		'sword_forge_fallback':
			_on_sword_forge_fallback(data.get('caster_id', -1), data.get('target_id', -1))
		'pilgrimage_shield_gained':
			_on_pilgrimage_shield_gained(data.get('player_id', -1))
		'sword_forge_unlocked':
			_on_sword_forge_unlocked(data.get('player_id', -1))
		'caliburn_used':
			_on_caliburn_used(data.get('caster_id', -1), data.get('target_id', -1))

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
		parts.append("%d:%.1f:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [
			p.player_id, p.hp, p.energy, p.shield,
			p.clone_count, p.paralyze_turns, p.bell_count,
			1 if p.counter_stance else 0, p.skill_disabled_turns,
			p.gate_count, p.invincible_turns,
			1 if p.burning else 0, 1 if p.berserker else 0,
			p.ftg_marks, p.nine_tails_stage,
			p.max_energy, p.stomp_active
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
		ps.knockdown_turns = data.get("knockdown", 0)
		ps.clone_count = data["clone"]
		ps.is_alive = data["alive"]
		ps.delayed_damages = data.get("delayed_dmg", [])
		ps.bell_count = data.get("bell_count", 0)
		ps.counter_stance = data.get("counter_stance", false)
		ps.skill_disabled_turns = data.get("skill_disabled", 0)
		ps.limited_skills_used = data.get("limited_used", [])
		ps.gate_count = data.get("gate_count", 0)
		ps.invincible_turns = data.get("invincible_turns", 0)
		ps.burning = data.get("burning", false)
		ps.berserker = data.get("berserker", false)
		ps.consecutive_rounds = data.get("consecutive_rounds", 0)
		ps.lost_skills = data.get("lost_skills", [])
		ps.ftg_marks = data.get("ftg_marks", 0)
		ps.ftg_marked_by = data.get("ftg_marked_by", [])
		ps.nine_tails_stage = data.get("nine_tails_stage", 0)
		ps.nine_tails_invincible = data.get("nine_tails_invincible", false)
		ps.max_energy = data.get("max_energy", 999)
		ps.stomp_active = data.get("stomp_active", 0)
		ps.force_win_next_round = data.get("force_win_next_round", 0) > 0
		ps.phantom_count = data.get("phantom_count", 0)
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
	var center := _get_arena_center()
	for i in count:
		var ps := player_states[i]
		var angle := -PI / 2.0 + i * (TAU / count)
		var cx := center.x + ARENA_RADIUS * cos(angle)
		var cy := center.y + ARENA_RADIUS * sin(angle)
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


# ══════════════════════════════════════════════════════════════════
# ── 新止水（天劫）专属 UI ──────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

var _phantom_dodge_dialog: PanelContainer = null
var _phantom_dodge_ctx: Dictionary = {}
var _backtrack_dialog: PanelContainer = null
var _hiroari_dialog: PanelContainer = null
var _hiroari_ctx: Dictionary = {}

## 幻影数量变化：刷新玩家卡片徽章
func _on_phantom_changed(player_id: int, _count: int) -> void:
	_refresh_player_card(player_id)

## 回溯完成：刷新全部卡片（全体状态可能已恢复）
func _on_backtrack_performed(_player_id: int, _round: int) -> void:
	_refresh_all_cards()
	_append_log("🕰 别天神·回溯发动！全体状态恢复到上一回合结束前", LT_WIN, _player_id)

## 日影舞释放完成：日志提示
func _on_hiroari_used(player_id: int, target_ids: Array[int]) -> void:
	var player := GameManager.get_player(player_id)
	_append_log("💨 %s 释放日影舞！4段连续打击：%s" % [
		player.player_name if player else str(player_id),
		str(target_ids)], LT_DAMAGE, player_id)
	_refresh_player_card(player_id)

## ── 幻影闪避决策弹窗（受击时：消耗1气+1幻影闪避） ──
func _on_phantom_dodge_required(player_id: int, attacker_id: int) -> void:
	if player_id != _human_player_id:
		return
	_phantom_dodge_ctx = {"player_id": player_id, "attacker_id": attacker_id}
	_show_phantom_dodge_dialog(player_id, attacker_id)

func _show_phantom_dodge_dialog(player_id: int, attacker_id: int) -> void:
	if _phantom_dodge_dialog != null:
		_phantom_dodge_dialog.queue_free()
	_phantom_dodge_dialog = PanelContainer.new()
	_phantom_dodge_dialog.position = Vector2(240, 170)
	_phantom_dodge_dialog.size = Vector2(460, 200)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#2A5A7A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_phantom_dodge_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_phantom_dodge_dialog.add_child(vbox)

	var attacker := GameManager.get_player(attacker_id)
	var a_name := attacker.player_name if attacker else str(attacker_id)
	var player := GameManager.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)

	var label := Label.new()
	label.text = "👻 %s 攻击了你！\n是否消耗 1气+1幻影 闪避这次攻击？" % a_name
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)

	var btn_yes := Button.new()
	btn_yes.text = "闪避（消耗1气+1幻影）"
	btn_yes.add_theme_font_size_override("font_size", 13)
	btn_yes.pressed.connect(func():
		_submit_phantom_dodge(true)
	)
	vbox.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.text = "硬抗（承受伤害）"
	btn_no.add_theme_font_size_override("font_size", 13)
	btn_no.pressed.connect(func():
		_submit_phantom_dodge(false)
	)
	vbox.add_child(btn_no)

	add_child(_phantom_dodge_dialog)

func _submit_phantom_dodge(dodge: bool) -> void:
	var player_id: int = _phantom_dodge_ctx.get("player_id", -1)
	if _phantom_dodge_dialog:
		_phantom_dodge_dialog.queue_free()
		_phantom_dodge_dialog = null
	_phantom_dodge_ctx.clear()
	if player_id < 0:
		return
	if net_client:
		net_client.submit_phantom_dodge(player_id, dodge)
	else:
		GameManager.submit_phantom_dodge(player_id, dodge)

## ── 别天神（回溯）决策弹窗：上回合不是自己时准备阶段触发 ──
func _on_backtrack_required(player_id: int) -> void:
	if player_id != _human_player_id:
		return
	_show_backtrack_dialog(player_id)

func _show_backtrack_dialog(player_id: int) -> void:
	if _backtrack_dialog != null:
		_backtrack_dialog.queue_free()
	_backtrack_dialog = PanelContainer.new()
	_backtrack_dialog.position = Vector2(240, 170)
	_backtrack_dialog.size = Vector2(460, 190)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#3B5BA5")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_backtrack_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_backtrack_dialog.add_child(vbox)

	var player := GameManager.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)

	var label := Label.new()
	label.text = "🕰 别天神·回溯\n是否消耗 1 气，将全体玩家状态回溯到上一回合？"
	label.add_theme_font_size_override("font_size", 14)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(label)

	var btn_yes := Button.new()
	btn_yes.text = "发动回溯（消耗1气）"
	btn_yes.add_theme_font_size_override("font_size", 13)
	btn_yes.pressed.connect(func():
		if _backtrack_dialog:
			_backtrack_dialog.queue_free()
			_backtrack_dialog = null
		if net_client:
			net_client.submit_backtrack_decision(player_id, true)
		else:
			GameManager.submit_backtrack_decision(player_id, true)
	)
	vbox.add_child(btn_yes)

	var btn_no := Button.new()
	btn_no.text = "跳过（不回溯）"
	btn_no.add_theme_font_size_override("font_size", 13)
	btn_no.pressed.connect(func():
		if _backtrack_dialog:
			_backtrack_dialog.queue_free()
			_backtrack_dialog = null
		if net_client:
			net_client.submit_backtrack_decision(player_id, false)
		else:
			GameManager.submit_backtrack_decision(player_id, false)
	)
	vbox.add_child(btn_no)

	add_child(_backtrack_dialog)

## ── 日影舞目标选择弹窗（4段，可重复选择目标） ──
func _on_hiroari_targets_required(player_id: int, target_ids: Array[int]) -> void:
	if player_id != _human_player_id:
		return
	_hiroari_ctx = {"player_id": player_id, "target_ids": target_ids, "picks": []}
	_show_hiroari_step()

func _show_hiroari_step() -> void:
	if _hiroari_dialog != null:
		_hiroari_dialog.queue_free()
	var ctx: Dictionary = _hiroari_ctx
	var picks: Array = ctx.get("picks", [])
	var target_ids: Array = ctx.get("target_ids", [])
	var player_id: int = ctx.get("player_id", -1)

	_hiroari_dialog = PanelContainer.new()
	_hiroari_dialog.position = Vector2(240, 150)
	_hiroari_dialog.size = Vector2(480, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#993C1D")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_hiroari_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_hiroari_dialog.add_child(vbox)

	var seg := picks.size() + 1
	var title := Label.new()
	title.text = "🌀 日影舞 — 第 %d/4 段，选择目标" % seg
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#993C1D"))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "每段造成 2 伤，可重复选择同一目标"
	hint.add_theme_font_size_override("font_size", 11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#5F5E5A"))
	vbox.add_child(hint)

	for tid in target_ids:
		var tp := GameManager.get_player(tid)
		var t_name := tp.player_name if tp else str(tid)
		var btn := Button.new()
		btn.text = "%s" % t_name
		btn.custom_minimum_size = Vector2(0, 34)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#FCEBEB"), Color("#993C1D"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#F7C1C1"), Color("#791F1F"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#F0A8A8"), Color("#791F1F"), 1, 4))
		btn.pressed.connect(func():
			picks.append(tid)
			if picks.size() >= 4:
				_submit_hiroari()
			else:
				_show_hiroari_step()
		)
		vbox.add_child(btn)

	var skip_btn := Button.new()
	skip_btn.text = "跳过本段（-1）"
	skip_btn.add_theme_font_size_override("font_size", 12)
	skip_btn.add_theme_color_override("font_color", Color("#6F5E5A"))
	skip_btn.pressed.connect(func():
		picks.append(-1)
		if picks.size() >= 4:
			_submit_hiroari()
		else:
			_show_hiroari_step()
	)
	vbox.add_child(skip_btn)

	add_child(_hiroari_dialog)

func _submit_hiroari() -> void:
	if _hiroari_dialog:
		_hiroari_dialog.queue_free()
		_hiroari_dialog = null
	var player_id: int = _hiroari_ctx.get("player_id", -1)
	var picks: Array = _hiroari_ctx.get("picks", [])
	_hiroari_ctx.clear()
	if player_id < 0:
		return
	var targets: Array[int] = []
	for p in picks:
		targets.append(int(p))
	if net_client:
		net_client.submit_hiroari_targets(player_id, targets)
	else:
		GameManager.submit_hiroari_targets(player_id, targets)


## ── 旧止水·日晕舞中断点决策弹窗（人类玩家） ──
var _hiano_dialog: PanelContainer = null

func _on_hiano_interrupt_required(player_id: int, target_id: int, _max_interrupt: int) -> void:
	# 只有人类玩家需要弹窗（AI 在 GameManager 内自动决策）
	if player_id != _human_player_id:
		return
	_show_hiano_dialog(player_id, target_id)

func _show_hiano_dialog(player_id: int, target_id: int) -> void:
	if _hiano_dialog != null:
		_hiano_dialog.queue_free()
	_hiano_dialog = PanelContainer.new()
	_hiano_dialog.position = Vector2(260, 170)
	_hiano_dialog.size = Vector2(440, 240)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#993C1D")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_hiano_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_hiano_dialog.add_child(vbox)

	var target := GameManager.get_player(target_id)
	var title := Label.new()
	title.text = "🌀 宇智波流·日晕舞 — 选择中断点"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#993C1D"))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "目标：%s（HP %.0f）\n共3段伤害（每段1伤），中断后可衔接【须佐能乎·九十九】" % [
		target.player_name if target else str(target_id),
		target.hp if target else 0.0]
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#5F5E5A"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	# 三个选项：不中断 / 1段后中断 / 2段后中断
	var options := [
		["打满3段（不中断）", 0],
		["1段后中断 → 接九十九", 1],
		["2段后中断 → 接九十九", 2],
	]
	for opt in options:
		var btn := Button.new()
		btn.text = opt[0]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#FCEBEB"), Color("#993C1D"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#F7C1C1"), Color("#791F1F"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#F0A8A8"), Color("#791F1F"), 1, 4))
		var interrupt_at: int = opt[1]
		btn.pressed.connect(func():
			_submit_hiano_interrupt(player_id, interrupt_at)
		)
		vbox.add_child(btn)

	add_child(_hiano_dialog)

func _submit_hiano_interrupt(player_id: int, interrupt_at: int) -> void:
	if _hiano_dialog:
		_hiano_dialog.queue_free()
		_hiano_dialog = null
	# 与日影舞提交方式一致：本地直接回调 GameManager，网络走 net_client
	if net_client:
		net_client.submit_hiano_interrupt(player_id, interrupt_at)
	else:
		GameManager.submit_hiano_interrupt(player_id, interrupt_at)


# ══════════════════════════════════════════════════════════════════
# ── 奥伯龙 / 卡斯特 专属 UI ─────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

# ── 通用目标选择弹窗（梦之终结 / 湖之加护 复用） ──
var _target_pick_dialog: PanelContainer = null
var _target_pick_ctx: Dictionary = {}  # {title, hint, player_id, target_ids, callback}

## 通用的目标选择弹窗。callback 形如 func(target_id: int) -> void
func _show_target_pick_dialog(title: String, hint: String, player_id: int,
		target_ids: Array[int], callback: Callable) -> void:
	if _target_pick_dialog != null:
		_target_pick_dialog.queue_free()
	_target_pick_ctx = {"callback": callback, "player_id": player_id}
	_target_pick_dialog = PanelContainer.new()
	_target_pick_dialog.position = Vector2(240, 150)
	_target_pick_dialog.size = Vector2(480, 300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#2A4A8C")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_target_pick_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_target_pick_dialog.add_child(vbox)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.add_theme_font_size_override("font_size", 15)
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_color_override("font_color", Color("#2A4A8C"))
	vbox.add_child(lbl_title)

	var lbl_hint := Label.new()
	lbl_hint.text = hint
	lbl_hint.add_theme_font_size_override("font_size", 12)
	lbl_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_hint.add_theme_color_override("font_color", Color("#5F5E5A"))
	lbl_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(lbl_hint)

	for tid in target_ids:
		var tp := GameManager.get_player(int(tid))
		var t_name := tp.player_name if tp else str(tid)
		var btn := Button.new()
		btn.text = "%s（HP %.0f）" % [t_name, tp.hp if tp else 0.0]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#EBF0FC"), Color("#2A4A8C"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#C1D2F7"), Color("#1A3A6F"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#A8C0F0"), Color("#1A3A6F"), 1, 4))
		var target_id: int = int(tid)
		btn.pressed.connect(func():
			_dismiss_target_pick_dialog()
			callback.call(target_id)
		)
		vbox.add_child(btn)

	add_child(_target_pick_dialog)

func _dismiss_target_pick_dialog() -> void:
	if _target_pick_dialog:
		_target_pick_dialog.queue_free()
		_target_pick_dialog = null
	_target_pick_ctx.clear()


# ── 梦之终结（奥伯龙） ──

func _on_dream_end_required(player_id: int, target_ids: Array[int]) -> void:
	if player_id != _human_player_id:
		return
	_show_target_pick_dialog(
		"🌙 梦之终结 — 选择目标",
		"目标下次受到的伤害翻倍（可标记自己）",
		player_id, target_ids,
		func(target_id: int):
			if net_client:
				net_client.submit_dream_end(player_id, target_id)
			else:
				GameManager.submit_dream_end(player_id, target_id))

func _on_dream_end_used(caster_id: int, target_id: int) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("🌙 %s 梦之终结：%s 下次伤害x2" % [c_name, t_name], LT_STATUS, caster_id)
	_refresh_player_card(caster_id)
	_refresh_player_card(target_id)


# ── 湖之加护（卡斯特） ──

func _on_lake_blessing_required(player_id: int, target_ids: Array[int]) -> void:
	if player_id != _human_player_id:
		return
	_show_target_pick_dialog(
		"💧 湖之加护 — 选择目标",
		"目标获得 1 气（可选自己）",
		player_id, target_ids,
		func(target_id: int):
			if net_client:
				net_client.submit_lake_blessing(player_id, target_id)
			else:
				GameManager.submit_lake_blessing(player_id, target_id))

func _on_lake_blessing_used(caster_id: int, target_id: int) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("💧 %s 湖之加护：%s 获得 1 气" % [c_name, t_name], LT_STATUS, caster_id)
	_refresh_player_card(target_id)


# ── 圣剑锻造（卡斯特）目标决策弹窗 ──

var _sword_forge_dialog: PanelContainer = null
var _sword_forge_dialog_step2: PanelContainer = null
var _sword_forge_ctx: Dictionary = {}  # {player_id, skill_names, attack_target_ids, chosen_index}

## 圣剑锻造弹窗：被锻造的目标人类玩家选择释放哪个技能+攻击谁
## player_id = 被锻造目标（自己选）
## skill_names = 可选技能名列表
## attack_target_ids = 可选攻击目标ID列表
func _on_sword_forge_required(player_id: int, skill_names: Array[String], attack_target_ids: Array[int]) -> void:
	if player_id != _human_player_id:
		return
	_sword_forge_ctx = {
		"player_id": player_id,
		"skill_names": skill_names,
		"attack_target_ids": attack_target_ids,
		"chosen_index": -1,
	}
	_show_sword_forge_skill_select()

## 第一步：选择释放哪个技能
func _show_sword_forge_skill_select() -> void:
	if _sword_forge_dialog != null:
		_sword_forge_dialog.queue_free()
	_sword_forge_dialog = PanelContainer.new()
	_sword_forge_dialog.position = Vector2(220, 130)
	_sword_forge_dialog.size = Vector2(520, 360)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF5")
	style.border_color = Color("#8C6A2A")
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	_sword_forge_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_sword_forge_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "⚔ 圣剑锻造 — 选择释放的技能"
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#8C6A2A"))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "卡斯特为你锻造了剑！你将无消耗释放一次以下技能"
	hint.add_theme_font_size_override("font_size", 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#5F5E5A"))
	vbox.add_child(hint)

	var skill_names: Array = _sword_forge_ctx.get("skill_names", [])
	for i in range(skill_names.size()):
		var sname: String = skill_names[i]
		var btn := Button.new()
		btn.text = sname
		btn.custom_minimum_size = Vector2(0, 34)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#FDF6E8"), Color("#8C6A2A"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#F7E4C1"), Color("#6A4F1A"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#F0D8A8"), Color("#6A4F1A"), 1, 4))
		var idx: int = i
		btn.pressed.connect(func():
			_sword_forge_ctx["chosen_index"] = idx
			_sword_forge_dialog.queue_free()
			_sword_forge_dialog = null
			_show_sword_forge_target_select()
		)
		vbox.add_child(btn)

	add_child(_sword_forge_dialog)

## 第二步：选择攻击目标（无敌方目标的技能才需要；纯自身技能跳过）
func _show_sword_forge_target_select() -> void:
	var attack_target_ids: Array = _sword_forge_ctx.get("attack_target_ids", [])
	# 若无可选攻击目标，直接提交（skill_index + attack_target_id=-1）
	if attack_target_ids.is_empty():
		_submit_sword_forge_choice()
		return
	if _sword_forge_dialog_step2 != null:
		_sword_forge_dialog_step2.queue_free()
	_sword_forge_dialog_step2 = PanelContainer.new()
	_sword_forge_dialog_step2.position = Vector2(240, 150)
	_sword_forge_dialog_step2.size = Vector2(480, 320)
	var style2 := StyleBoxFlat.new()
	style2.bg_color = Color("#FFFDF5")
	style2.border_color = Color("#8C6A2A")
	style2.set_border_width_all(3)
	style2.set_corner_radius_all(8)
	_sword_forge_dialog_step2.add_theme_stylebox_override("panel", style2)

	var vbox2 := VBoxContainer.new()
	vbox2.add_theme_constant_override("separation", 6)
	_sword_forge_dialog_step2.add_child(vbox2)

	var title2 := Label.new()
	title2.text = "⚔ 圣剑锻造 — 选择攻击目标"
	title2.add_theme_font_size_override("font_size", 15)
	title2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title2.add_theme_color_override("font_color", Color("#8C6A2A"))
	vbox2.add_child(title2)

	var player_id: int = _sword_forge_ctx.get("player_id", -1)
	for tid in attack_target_ids:
		var tp := GameManager.get_player(int(tid))
		var t_name := tp.player_name if tp else str(tid)
		var btn := Button.new()
		btn.text = "%s（HP %.0f，距离 %d）" % [
			t_name,
			tp.hp if tp else 0.0,
			GameManager._distance_system.get_distance(player_id, int(tid)) if GameManager._distance_system else 0]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", _make_flat(Color("#FDF6E8"), Color("#8C6A2A"), 1, 4))
		btn.add_theme_stylebox_override("hover", _make_flat(Color("#F7E4C1"), Color("#6A4F1A"), 1, 4))
		btn.add_theme_stylebox_override("pressed", _make_flat(Color("#F0D8A8"), Color("#6A4F1A"), 1, 4))
		var target_id: int = int(tid)
		btn.pressed.connect(func():
			_sword_forge_ctx["attack_target_id"] = target_id
			_sword_forge_dialog_step2.queue_free()
			_sword_forge_dialog_step2 = null
			_submit_sword_forge_choice()
		)
		vbox2.add_child(btn)

	add_child(_sword_forge_dialog_step2)

func _submit_sword_forge_choice() -> void:
	var player_id: int = _sword_forge_ctx.get("player_id", -1)
	var skill_index: int = _sword_forge_ctx.get("chosen_index", -1)
	var attack_target_id: int = _sword_forge_ctx.get("attack_target_id", -1)
	_sword_forge_ctx.clear()
	if player_id < 0 or skill_index < 0:
		return
	if net_client:
		net_client.submit_sword_forge(player_id, skill_index, attack_target_id)
	else:
		GameManager.submit_sword_forge(player_id, skill_index, attack_target_id)


# ── 卡斯特 完成事件日志 ──

func _on_sword_forge_used(caster_id: int, target_id: int, skill_name: String) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("⚔ %s 圣剑锻造：%s 无消耗释放了 %s" % [c_name, t_name, skill_name], LT_STATUS, caster_id)
	_refresh_player_card(caster_id)
	_refresh_player_card(target_id)

func _on_sword_forge_fallback(caster_id: int, target_id: int) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("⚔ %s 圣剑锻造：%s 无可用技能，获得 3 气" % [c_name, t_name], LT_STATUS, caster_id)
	_refresh_player_card(target_id)

func _on_pilgrimage_shield_gained(player_id: int) -> void:
	var p := GameManager.get_player(player_id)
	var p_name := p.player_name if p else str(player_id)
	_append_log("🛡 %s 巡礼触发，获得圣盾" % p_name, LT_STATUS, player_id)
	_refresh_player_card(player_id)

func _on_sword_forge_unlocked(player_id: int) -> void:
	var p := GameManager.get_player(player_id)
	var p_name := p.player_name if p else str(player_id)
	_append_log("⚔ %s 巡礼累计4次，解锁圣剑锻造！" % p_name, LT_WIN, player_id)
	_refresh_player_card(player_id)

func _on_caliburn_used(caster_id: int, target_id: int) -> void:
	var caster := GameManager.get_player(caster_id)
	var target := GameManager.get_player(target_id)
	var c_name := caster.player_name if caster else str(caster_id)
	var t_name := target.player_name if target else str(target_id)
	_append_log("⚔ %s Around Caliburn：%s 获得圣盾+下次伤害x2" % [c_name, t_name], LT_STATUS, caster_id)
	_refresh_player_card(caster_id)
	_refresh_player_card(target_id)


# ============================================================
#  慈悲尖塔暗色主题覆盖
# ============================================================
## 在塔模式启动时调用，将暖白纸面风格替换为暗黑塔门风格
func apply_tower_theme() -> void:
	var C_DARK_BG     := Color("#1A1714")
	var C_DARK_PANEL  := Color("#1C1915")
	var C_DARK_BORDER := Color("#3A342A")
	var C_DARK_CARD   := Color("#222018")
	var C_DARK_TEXT   := Color("#E8E2D5")

	# 日志面板
	var log_panel: Panel = $LogPanelBg
	log_panel.add_theme_stylebox_override("panel", _make_flat(C_DARK_PANEL, C_DARK_BORDER, 2, 4))

	# 右侧面板
	var right_panel: Panel = $RightPanelBg
	right_panel.add_theme_stylebox_override("panel", _make_flat(C_DARK_PANEL, C_DARK_BORDER, 2, 4))

	# 竞技场边框
	var border_panel: Panel = $BorderFrame
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(1, 1, 1, 0)
	border_style.border_color = C_DARK_BORDER
	border_style.set_border_width_all(3)
	border_style.set_corner_radius_all(6)
	border_panel.add_theme_stylebox_override("panel", border_style)

	# 全局暗色叠加（微调底色为暗色调）
	var dark_overlay := ColorRect.new()
	dark_overlay.color = Color(C_DARK_BG.r, C_DARK_BG.g, C_DARK_BG.b, 0.92)
	dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dark_overlay.show_behind_parent = true
	add_child(dark_overlay)
	move_child(dark_overlay, 0)

	# 刷新已有玩家卡为暗色（在 setup_players 之后的卡片也会被覆盖）
	# 标记标记：塔模式下的玩家卡在 _make_player_card 中检查
	_tower_theme_active = true

var _tower_theme_active: bool = false
