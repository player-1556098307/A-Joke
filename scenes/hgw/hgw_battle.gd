## HGWBattle — main HGW battle scene controller
## Renders hex map, player tokens, movement/attack ranges, UI overlays, event log
extends Control

# ── Color palette ────────────────────────────────────────────────────────────────
const C_BG       = Color("#FFFDF5")
const C_PANEL_BG = Color("#F1EFE8")
const C_PANEL_BDR= Color("#C8C4B8")
const C_GOLD     = Color("#8B6514")
const C_GOLD_BRT = Color("#C9A84C")
const C_TEXT     = Color("#2C2C2A")
const C_TEXT_DIM = Color("#6B6A65")
const C_RED      = Color("#B03030")
const C_GREEN    = Color("#2A7A2A")

# ── Scene references ─────────────────────────────────────────────────────────────
var _game_mgr: HGWGameManager
var _rps_modal: PanelContainer
var _skill_modal: PanelContainer
var _left_panel: VBoxContainer
var _right_panel: VBoxContainer
var _action_bar: HBoxContainer
var _move_bar: HBoxContainer
var _phase_label: Label
var _turn_label: Label
var _log_scroll: ScrollContainer
var _log_panel: VBoxContainer
var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _zoom_slider: HSlider
var _zoom_label: Label
var _last_mouse_pos: Vector2 = Vector2.ZERO

# ── Map rendering state ──────────────────────────────────────────────────────────
var _hex_size := 22.0
var _map_offset := Vector2.ZERO
var _map_zoom := 1.0
var _is_dragging := false
var _drag_start := Vector2.ZERO
var _drag_offset_start := Vector2.ZERO
var _show_movement_range: bool = false
var _show_attack_range: bool = false
var _reachable_cells: Array[Vector2i] = []
var _hovered_hex := Vector2i(-999, -999)
var _target_player_id: int = -1
var _current_enemies_in_range: Array[HGWPlayerState] = []
var _highlight_hex := Vector2i(-999, -999)
var _highlight_timer := 0.0
var _map_area_center := Vector2.ZERO
var _rps_pending_role: int = -1  # 0=attacker, 1=defender, -1=none
var _left_press_pos := Vector2.ZERO
var _left_pressed := false

func _ready() -> void:
	_setup_game_manager()
	_build_scene_tree()
	_build_tooltip()
	_setup_input()
	set_process(true)

	# Default map center before layout settles
	_map_area_center = get_viewport().get_visible_rect().size / 2.0

	# Compute accurate map center after one frame so layout is settled
	await get_tree().process_frame
	_update_map_area_center()

	var config: Dictionary = SceneManager.last_hgw_config
	if config.is_empty():
		config = _make_debug_config()
	_game_mgr.setup(config)

func _make_debug_config() -> Dictionary:
	return {
		"num_players": 3,
		"seed": randi() % 99999 + 1,
		"players": [
			{ "name": "玩家", "is_human": true,
			  "character": preload("res://resources/characters/漩涡鸣人.tres") },
			{ "name": "AI-佐助", "is_human": false,
			  "character": preload("res://resources/characters/宇智波佐助.tres") },
			{ "name": "AI-樱", "is_human": false,
			  "character": preload("res://resources/characters/春野樱.tres") },
		]
	}

func _setup_game_manager() -> void:
	_game_mgr = HGWGameManager.new()
	add_child(_game_mgr)
	_connect_game_signals()

func _connect_game_signals() -> void:
	_game_mgr.phase_changed.connect(_on_phase_changed)
	_game_mgr.player_turn_started.connect(_on_player_turn_started)
	_game_mgr.player_moved.connect(_on_player_moved)
	_game_mgr.energy_changed.connect(func(pid, amt): _refresh_right_panel(); queue_redraw())
	_game_mgr.rps_needed.connect(_on_rps_needed)
	_game_mgr.combat_hit.connect(_on_combat_hit)
	_game_mgr.combat_miss.connect(_on_combat_miss)
	_game_mgr.skill_needed.connect(_on_skill_needed)
	_game_mgr.player_eliminated.connect(_on_player_eliminated)
	_game_mgr.seal_event.connect(_on_seal_event)
	_game_mgr.grail_opened.connect(_on_grail_opened)
	_game_mgr.game_over.connect(_on_game_over)
	_game_mgr.terrain_effect_triggered.connect(_on_terrain_effect)

# ── Scene tree ───────────────────────────────────────────────────────────────────

func _build_scene_tree() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

	# Top bar
	var top_bar := PanelContainer.new()
	top_bar.layout_mode = 1
	top_bar.anchor_left = 0.0; top_bar.anchor_top = 0.0; top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 40.0
	top_bar.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 10)
	top_bar.add_child(top_hbox)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", 14)
	_phase_label.add_theme_color_override("font_color", C_GOLD_BRT)
	_phase_label.text = "准备中..."
	top_hbox.add_child(_phase_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)

	_turn_label = Label.new()
	_turn_label.add_theme_font_size_override("font_size", 12)
	_turn_label.add_theme_color_override("font_color", C_TEXT_DIM)
	top_hbox.add_child(_turn_label)

	# Left panel — current player info
	_left_panel = VBoxContainer.new()
	_left_panel.layout_mode = 1
	_left_panel.anchor_left = 0.0; _left_panel.anchor_top = 0.0
	_left_panel.anchor_right = 0.0; _left_panel.anchor_bottom = 1.0
	_left_panel.offset_left = 8.0; _left_panel.offset_top = 48.0
	_left_panel.offset_right = 220.0; _left_panel.offset_bottom = -55.0
	_left_panel.add_theme_constant_override("separation", 6)
	add_child(_left_panel)

	# Right panel — other players + seals
	_right_panel = VBoxContainer.new()
	_right_panel.layout_mode = 1
	_right_panel.anchor_left = 1.0; _right_panel.anchor_top = 0.0
	_right_panel.anchor_right = 1.0; _right_panel.anchor_bottom = 1.0
	_right_panel.offset_left = -210.0; _right_panel.offset_top = 48.0
	_right_panel.offset_right = -8.0; _right_panel.offset_bottom = -148.0
	_right_panel.add_theme_constant_override("separation", 6)
	add_child(_right_panel)

	# Event log panel (bottom, with scrollbar)
	var log_container := PanelContainer.new()
	log_container.layout_mode = 1
	log_container.anchor_left = 0.0; log_container.anchor_top = 1.0
	log_container.anchor_right = 1.0; log_container.anchor_bottom = 1.0
	log_container.offset_left = 8.0; log_container.offset_top = -140.0
	log_container.offset_right = -8.0; log_container.offset_bottom = -55.0
	var log_style := _make_flat(C_PANEL_BG * Color(1, 1, 1, 0.9), C_PANEL_BDR, 1, 4)
	log_style.content_margin_left = 6.0; log_style.content_margin_top = 4.0
	log_style.content_margin_right = 6.0; log_style.content_margin_bottom = 4.0
	log_container.add_theme_stylebox_override("panel", log_style)
	add_child(log_container)

	var log_vbox := VBoxContainer.new()
	log_vbox.add_theme_constant_override("separation", 2)
	log_container.add_child(log_vbox)

	var log_title := Label.new()
	log_title.text = "事件日志"
	log_title.add_theme_font_size_override("font_size", 9)
	log_title.add_theme_color_override("font_color", C_GOLD)
	log_vbox.add_child(log_title)

	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.follow_focus = true
	log_vbox.add_child(_log_scroll)

	_log_panel = VBoxContainer.new()
	_log_panel.add_theme_constant_override("separation", 1)
	_log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log_panel)

	# Bottom bars
	_build_bottom_bars()

	# Modals
	_rps_modal = load("res://scenes/hgw/rps_modal.gd").new()
	_rps_modal.visible = false
	_rps_modal.set_anchors_preset(Control.PRESET_CENTER)
	_rps_modal.gesture_selected.connect(_on_rps_gesture)
	add_child(_rps_modal)

	_skill_modal = load("res://scenes/hgw/skill_select_modal.gd").new()
	_skill_modal.visible = false
	_skill_modal.set_anchors_preset(Control.PRESET_CENTER)
	_skill_modal.skill_confirmed.connect(func(idx): _game_mgr.submit_skill(idx))
	_skill_modal.attack_cancelled.connect(func(): _game_mgr.cancel_skill())
	add_child(_skill_modal)

func _update_map_area_center() -> void:
	var vp := get_viewport().get_visible_rect()
	var left := 228.0
	var top := 44.0
	var right := vp.size.x - 218.0
	var bottom := vp.size.y - 150.0
	_map_area_center = Vector2((left + right) / 2.0, (top + bottom) / 2.0)

func _build_bottom_bars() -> void:
	# Background panel
	var bar_bg := PanelContainer.new()
	bar_bg.layout_mode = 1
	bar_bg.anchor_left = 0.0; bar_bg.anchor_right = 1.0
	bar_bg.anchor_top = 1.0; bar_bg.offset_top = -50.0
	bar_bg.anchor_bottom = 1.0
	bar_bg.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)

	# Bottom HBox: zoom controls | spacer | action buttons
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.layout_mode = 1
	bottom_hbox.anchor_left = 0.0; bottom_hbox.anchor_right = 1.0
	bottom_hbox.anchor_top = 1.0; bottom_hbox.offset_top = -50.0
	bottom_hbox.anchor_bottom = 1.0
	bottom_hbox.add_theme_constant_override("separation", 8)
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom_hbox)

	# Zoom controls
	var zoom_label := Label.new()
	zoom_label.text = "缩放:"
	zoom_label.add_theme_font_size_override("font_size", 11)
	zoom_label.add_theme_color_override("font_color", C_TEXT_DIM)
	bottom_hbox.add_child(zoom_label)

	var zoom_minus := Button.new()
	zoom_minus.text = "−"
	zoom_minus.custom_minimum_size = Vector2(28, 28)
	zoom_minus.add_theme_font_size_override("font_size", 14)
	zoom_minus.add_theme_color_override("font_color", C_TEXT)
	_style_small_btn(zoom_minus)
	zoom_minus.pressed.connect(func(): _adjust_zoom(-0.1))
	bottom_hbox.add_child(zoom_minus)

	_zoom_slider = HSlider.new()
	_zoom_slider.custom_minimum_size = Vector2(100, 0)
	_zoom_slider.min_value = 0.5
	_zoom_slider.max_value = 2.0
	_zoom_slider.step = 0.05
	_zoom_slider.value = 1.0
	_zoom_slider.value_changed.connect(_on_zoom_slider)
	bottom_hbox.add_child(_zoom_slider)

	var zoom_plus := Button.new()
	zoom_plus.text = "+"
	zoom_plus.custom_minimum_size = Vector2(28, 28)
	zoom_plus.add_theme_font_size_override("font_size", 14)
	zoom_plus.add_theme_color_override("font_color", C_TEXT)
	_style_small_btn(zoom_plus)
	zoom_plus.pressed.connect(func(): _adjust_zoom(0.1))
	bottom_hbox.add_child(zoom_plus)

	_zoom_label = Label.new()
	_zoom_label.text = "100%"
	_zoom_label.custom_minimum_size = Vector2(36, 0)
	_zoom_label.add_theme_font_size_override("font_size", 10)
	_zoom_label.add_theme_color_override("font_color", C_TEXT_DIM)
	bottom_hbox.add_child(_zoom_label)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.add_child(bottom_spacer)

	# Move bar (shown during MOVE_PHASE)
	_move_bar = HBoxContainer.new()
	_move_bar.add_theme_constant_override("separation", 10)
	_move_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_move_bar.visible = false
	bottom_hbox.add_child(_move_bar)

	var skip_move_btn := Button.new()
	skip_move_btn.text = "跳过移动"
	skip_move_btn.custom_minimum_size = Vector2(100, 34)
	skip_move_btn.add_theme_font_size_override("font_size", 14)
	skip_move_btn.add_theme_color_override("font_color", C_TEXT)
	skip_move_btn.add_theme_color_override("font_hover_color", C_GOLD)
	_style_action_btn(skip_move_btn)
	skip_move_btn.pressed.connect(func():
		var pid := _game_mgr.get_current_turn_player_id()
		_game_mgr.skip_move(pid))
	_move_bar.add_child(skip_move_btn)

	# Action bar (shown during ACTION_PHASE)
	_action_bar = HBoxContainer.new()
	_action_bar.add_theme_constant_override("separation", 10)
	_action_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_bar.visible = false
	bottom_hbox.add_child(_action_bar)

	var actions := [
		{"text": "聚气", "callable": func(): _on_action_gather()},
		{"text": "攻击", "callable": func(): _on_action_attack()},
		{"text": "跳过", "callable": func(): _on_action_skip()},
	]

	for a in actions:
		var btn := Button.new()
		btn.text = a["text"]
		btn.custom_minimum_size = Vector2(80, 34)
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_GOLD)
		_style_action_btn(btn)
		btn.pressed.connect(a["callable"])
		_action_bar.add_child(btn)

func _style_action_btn(btn: Button) -> void:
	var n_style := StyleBoxFlat.new()
	n_style.bg_color = Color("#F1EFE8")
	n_style.border_color = C_GOLD * Color(1, 1, 1, 0.4)
	n_style.set_border_width_all(1)
	n_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", n_style)
	var h_style: StyleBoxFlat = n_style.duplicate()
	h_style.bg_color = Color("#E6E2D4")
	h_style.border_color = C_GOLD
	btn.add_theme_stylebox_override("hover", h_style)

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

# ── Tooltip ──────────────────────────────────────────────────────────────────────

func _build_tooltip() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color("#FFFDF5")
	ts.border_color = C_GOLD * Color(1, 1, 1, 0.6)
	ts.set_border_width_all(1)
	ts.set_corner_radius_all(6)
	ts.content_margin_left = 8.0; ts.content_margin_top = 4.0
	ts.content_margin_right = 8.0; ts.content_margin_bottom = 4.0
	_tooltip_panel.add_theme_stylebox_override("panel", ts)
	add_child(_tooltip_panel)

	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 11)
	_tooltip_label.add_theme_color_override("font_color", C_TEXT)
	_tooltip_panel.add_child(_tooltip_label)

func _update_tooltip(screen_pos: Vector2, hex: Vector2i) -> void:
	var cell = _game_mgr.get_cell(hex.x, hex.y)
	if cell == null or cell.is_void:
		_tooltip_panel.visible = false
		return

	var lines: Array[String] = []
	var tname := _terrain_display_name(cell.terrain)
	lines.append("[%s] (%d, %d)" % [tname, hex.x, hex.y])

	var effect := _terrain_effect_description(cell.terrain)
	if effect != "":
		lines.append(effect)

	if cell.is_grail:
		lines.append("★ 圣杯")
	if cell.is_city:
		lines.append("◆ 城市（出生点）")
	if cell.is_resource:
		var tier_name := {"common": "普通资源", "rare": "稀有资源", "core": "核心资源"}
		lines.append("● %s" % tier_name.get(cell.res_tier, "资源"))
	if cell.is_reward:
		lines.append("◎ 悬赏池")
	if cell.is_key:
		lines.append("🔑 钥匙")
	if cell.is_choke:
		lines.append("▣ 咽喉点")

	_tooltip_label.text = "\n".join(PackedStringArray(lines))

	var tt_size := _tooltip_panel.get_combined_minimum_size()
	var vp := get_viewport().get_visible_rect()
	var tx := screen_pos.x + 16.0
	var ty := screen_pos.y - tt_size.y - 8.0
	if tx + tt_size.x > vp.size.x:
		tx = screen_pos.x - tt_size.x - 16.0
	if ty < 0:
		ty = screen_pos.y + 16.0
	_tooltip_panel.position = Vector2(tx, ty)
	_tooltip_panel.visible = true

# ── Input ────────────────────────────────────────────────────────────────────────

func _setup_input() -> void:
	set_process_input(true)

func _is_in_map_area(screen_pos: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect()
	if screen_pos.x < 224.0 or screen_pos.x > vp.size.x - 214.0:
		return false
	if screen_pos.y < 44.0 or screen_pos.y > vp.size.y - 150.0:
		return false
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		if not _is_in_map_area(event.position):
			return

	if event is InputEventMouseMotion:
		_last_mouse_pos = event.position
		if _left_pressed and not _is_dragging and event.position.distance_to(_left_press_pos) > 5.0:
			_is_dragging = true
			_drag_start = event.position
			_drag_offset_start = _map_offset
		if _is_dragging:
			_map_offset = _drag_offset_start + (event.position - _drag_start)
			queue_redraw()
		elif not _left_pressed:
			_update_hover(event.position)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_is_dragging = true
				_drag_start = event.position
				_drag_offset_start = _map_offset
			else:
				_is_dragging = false

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
				_left_press_pos = event.position
			else:
				if _is_dragging:
					_is_dragging = false
				else:
					_handle_click(event.position)
				_left_pressed = false

		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_adjust_zoom(0.1, event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_adjust_zoom(-0.1, event.position)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_show_attack_range = false
		_show_movement_range = false
		_target_player_id = -1
		_highlight_hex = Vector2i(-999, -999)
		_highlight_timer = 0.0
		queue_redraw()

func _adjust_zoom(delta: float, anchor_screen_pos: Vector2 = Vector2.ZERO) -> void:
	var old_zoom := _map_zoom
	_map_zoom = clampf(_map_zoom + delta, 0.5, 2.0)
	if abs(_map_zoom - old_zoom) < 0.001:
		return

	# Zoom toward anchor point
	if anchor_screen_pos != Vector2.ZERO:
		var world := (anchor_screen_pos - _map_offset - _map_area_center) / old_zoom
		_map_offset = anchor_screen_pos - world * _map_zoom - _map_area_center

	_zoom_slider.set_value_no_signal(_map_zoom)
	_zoom_label.text = "%d%%" % int(_map_zoom * 100)
	queue_redraw()

func _on_zoom_slider(value: float) -> void:
	var old_zoom := _map_zoom
	_map_zoom = value
	_zoom_label.text = "%d%%" % int(_map_zoom * 100)
	# Zoom toward center of map area
	var world := (_map_area_center - _map_offset - _map_area_center) / old_zoom
	_map_offset = _map_area_center - world * _map_zoom - _map_area_center
	queue_redraw()

func _update_hover(screen_pos: Vector2) -> void:
	var hex := _pixel_to_hex(screen_pos)
	if hex == _hovered_hex:
		return
	_hovered_hex = hex
	_update_tooltip(screen_pos, hex)
	queue_redraw()

func _handle_click(screen_pos: Vector2) -> void:
	var hex := _pixel_to_hex(screen_pos)
	var pid := _game_mgr.get_current_turn_player_id()
	if pid < 0:
		return

	match _game_mgr.get_phase():
		HGWGameManager.Phase.MOVE_PHASE:
			if _show_movement_range and _reachable_cells.has(hex):
				_game_mgr.submit_move(pid, hex.x, hex.y)
				_show_movement_range = false
				_reachable_cells.clear()
				queue_redraw()
			else:
				_show_movement_range = true
				var player := _game_mgr.get_player(pid)
				if player:
					_reachable_cells = _game_mgr.get_reachable_cells(player)
					queue_redraw()

		HGWGameManager.Phase.ACTION_PHASE:
			if _show_attack_range:
				var target_id := _find_player_at_cell(hex)
				if target_id >= 0 and target_id != pid:
					_game_mgr.submit_attack(pid, target_id)
					_show_attack_range = false
					_target_player_id = -1
					queue_redraw()

func _find_player_at_cell(hex: Vector2i) -> int:
	for player in _game_mgr.get_all_players():
		if player.is_alive and player.hex_q == hex.x and player.hex_r == hex.y:
			return player.player_id
	return -1

# ── Process ──────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _highlight_timer > 0.0:
		_highlight_timer -= delta
		if _highlight_timer <= 0.0:
			_highlight_hex = Vector2i(-999, -999)
			queue_redraw()

# ── Action callbacks ─────────────────────────────────────────────────────────────

func _on_action_gather() -> void:
	var pid := _game_mgr.get_current_turn_player_id()
	_game_mgr.submit_gather(pid)

func _on_action_attack() -> void:
	_show_attack_range = true
	queue_redraw()

func _on_action_skip() -> void:
	var pid := _game_mgr.get_current_turn_player_id()
	_game_mgr.submit_skip_action(pid)

func _on_b_skill(idx: int) -> void:
	var pid := _game_mgr.get_current_turn_player_id()
	_game_mgr.submit_b_skill(pid, idx)

# ── Signal handlers ──────────────────────────────────────────────────────────────

func _on_phase_changed(phase: HGWGameManager.Phase) -> void:
	_move_bar.visible = false
	_action_bar.visible = false

	match phase:
		HGWGameManager.Phase.MOVE_PHASE:
			_phase_label.text = "移动阶段"
			_move_bar.visible = true
			_show_movement_range = true
			_show_attack_range = false
			var pid := _game_mgr.get_current_turn_player_id()
			var player := _game_mgr.get_player(pid)
			if player:
				_reachable_cells = _game_mgr.get_reachable_cells(player)

		HGWGameManager.Phase.ACTION_PHASE:
			_phase_label.text = "行动阶段"
			_show_movement_range = false
			_show_attack_range = false
			_action_bar.visible = true
			_refresh_action_bar()

		HGWGameManager.Phase.RPS_INPUT:
			_phase_label.text = "猜拳中..."

		HGWGameManager.Phase.SKILL_SELECT:
			_phase_label.text = "选择技能"

		HGWGameManager.Phase.TURN_END:
			_phase_label.text = "回合结束"

		HGWGameManager.Phase.GAME_OVER:
			_phase_label.text = "游戏结束"

	queue_redraw()

func _refresh_action_bar() -> void:
	var pid := _game_mgr.get_current_turn_player_id()
	var player := _game_mgr.get_player(pid)
	if player == null or player.character == null:
		return

	# Remove old skill buttons (keep 3 preset: 聚气, 攻击, 跳过)
	while _action_bar.get_child_count() > 3:
		var child := _action_bar.get_child(3)
		_action_bar.remove_child(child)
		child.queue_free()

	var skills: Array = player.character.skills
	for i in range(skills.size()):
		var sk: SkillData = skills[i]
		if not _is_b_class(sk):
			continue
		var can_use := player.energy >= sk.energy_cost
		var btn := Button.new()
		btn.text = sk.skill_name
		btn.custom_minimum_size = Vector2(80, 34)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", C_GOLD if can_use else C_TEXT_DIM)
		btn.disabled = not can_use
		_style_action_btn(btn)
		if can_use:
			var sidx := i
			btn.pressed.connect(func(): _on_b_skill(sidx))
		_action_bar.add_child(btn)

func _is_b_class(skill: SkillData) -> bool:
	for effect: SkillEffect in skill.effects:
		if effect.target in [SkillEffect.EffectTarget.ENEMY_SINGLE, SkillEffect.EffectTarget.ENEMY_ALL, SkillEffect.EffectTarget.ENEMY_SPLASH]:
			return false
	return true

func _on_player_turn_started(pid: int) -> void:
	var player := _game_mgr.get_player(pid)
	if player:
		_turn_label.text = "当前: %s" % player.player_name
	_update_left_panel(pid)
	_refresh_right_panel()
	queue_redraw()

func _on_player_moved(_pid: int, _fq: int, _fr: int, _tq: int, _tr: int) -> void:
	_show_movement_range = false
	_reachable_cells.clear()
	queue_redraw()

func _on_rps_needed(attacker_id: int, defender_id: int) -> void:
	var atk := _game_mgr.get_player(attacker_id)
	var def := _game_mgr.get_player(defender_id)
	if atk == null or def == null:
		return
	if atk.is_human:
		_rps_pending_role = 0
		_rps_modal.show_for(atk.player_name, def.player_name)
	elif def.is_human:
		_rps_pending_role = 1
		_rps_modal.show_for(atk.player_name, def.player_name)
	else:
		_rps_pending_role = -1

func _on_rps_gesture(gesture: int) -> void:
	match _rps_pending_role:
		0: _game_mgr.submit_attack_rps(gesture)
		1: _game_mgr.submit_defend_rps(gesture)

func _on_combat_hit(log: Dictionary) -> void:
	_rps_modal.hide_modal()
	_skill_modal.visible = false
	var sname: String = log.get("skill_name", "")
	var dmg: int = log.get("final_damage", 0)
	var def_id: int = log.get("defender_id", -1)
	var defender := _game_mgr.get_player(def_id)
	var def_name: String = defender.player_name if defender else "?"
	_log_event("%s → %s: %s 造成 %d 伤害" % ["?", def_name, sname, dmg], C_RED)

func _on_combat_miss(attacker_id: int) -> void:
	_rps_modal.hide_modal()
	var player := _game_mgr.get_player(attacker_id)
	_log_event("%s 攻击 Miss！1气已消耗" % (player.player_name if player else "?"), C_TEXT_DIM)

func _on_terrain_effect(player_id: int, terrain: int, effect_desc: String) -> void:
	var player := _game_mgr.get_player(player_id)
	var p_name := player.player_name if player else str(player_id)
	var t_name := _terrain_display_name(terrain)
	_log_event("%s 进入%s: %s" % [p_name, t_name, effect_desc], C_GOLD)

func _on_skill_needed(attacker_id: int, skills: Array) -> void:
	_rps_modal.hide_modal()
	var player := _game_mgr.get_player(attacker_id)
	_skill_modal.show_for(skills, player.energy if player else 0)

func _on_player_eliminated(pid: int) -> void:
	var player := _game_mgr.get_player(pid)
	var name: String = player.player_name if player else "?"
	_log_event("%s 已被淘汰！" % name, C_RED)
	_refresh_right_panel()
	queue_redraw()

func _on_seal_event(seal_index: int, event_type: String, data: Dictionary) -> void:
	var unlocker_id: int = data.get("unlocker_id", -1)
	var msg: String
	match seal_index:
		1: msg = "封印1（野怪）已解封！击杀者获得：每回合+1气"
		2: msg = "封印2（祭坛）已解封！最先注入者获得：移动距离+2"
		3: msg = "封印3（废墟）已解封！拾取者获得：攻击距离+1"
		_: msg = "封印%d: %s" % [seal_index, event_type]
	if event_type == "desert_event":
		var ev: int = data.get("event", -1)
		var ev_names := {0: "沙暴-跳过下回合行动", 1: "绿洲-回复1HP", 2: "遗物-获得1气", 3: "迷失-随机传送"}
		msg = "沙漠事件: %s" % ev_names.get(ev, "未知")
	_log_event(msg, C_GOLD)
	_refresh_right_panel()

func _on_grail_opened() -> void:
	_log_event("圣杯已开启！缩圈开始！", C_GOLD_BRT)
	_refresh_right_panel()

func _on_game_over(winner_id: int, reason: String) -> void:
	var winner := _game_mgr.get_player(winner_id)
	var winner_name: String = winner.player_name if winner else "无人"
	var reason_text: String = "圣杯占领" if reason == "grail_occupation" else "最后存活"
	_log_event("游戏结束！胜者: %s (%s)" % [winner_name, reason_text], C_GOLD_BRT)
	_show_game_over_popup(winner_name, reason_text)

# ── Event log ────────────────────────────────────────────────────────────────────

func _log_event(text: String, color: Color = C_TEXT) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", color)
	_log_panel.add_child(lbl)
	# Auto-scroll to bottom
	await get_tree().process_frame
	var vbar := _log_scroll.get_v_scroll_bar()
	if vbar:
		_log_scroll.scroll_vertical = vbar.max_value

# ── Left panel ───────────────────────────────────────────────────────────────────

func _update_left_panel(pid: int) -> void:
	if _left_panel == null:
		return
	for child in _left_panel.get_children():
		child.queue_free()

	var player := _game_mgr.get_player(pid)
	if player == null:
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_panel.add_child(scroll)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG * Color(1, 1, 1, 0.9), C_PANEL_BDR * Color(1, 1, 1, 0.5), 1, 8))
	scroll.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	# Character name (always shown)
	var char_name := player.character.character_name if player.character else "?"
	var name_label := Label.new()
	name_label.text = "%s · %s" % [player.player_name, char_name]
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", C_GOLD_BRT)
	vbox.add_child(name_label)

	_add_info_line(vbox, "HP: %d / %d" % [player.hp, player.max_hp])
	_add_info_line(vbox, "气: %d" % player.energy)
	_add_info_line(vbox, "位置: (%d, %d)" % [player.hex_q, player.hex_r])
	_add_info_line(vbox, "移动力: %d" % player.get_movement())
	_add_info_line(vbox, "攻击范围: %d" % player.get_attack_range())

	# Status section
	var status_lines: Array[String] = []
	if player.skip_next_action:
		status_lines.append("⏸ 麻痹中（跳过下回合行动）")
	if player.clone_count > 0:
		status_lines.append("影分身 ×%d" % player.clone_count)
	if player.shield != 0:
		status_lines.append("护盾: %s" % ("∞" if player.shield == -1 else str(player.shield)))
	if player.on_highland:
		status_lines.append("高地加成（攻击距离+1）")
	if player.gathered_this_turn:
		status_lines.append("本回合已聚气")
	if status_lines.size() > 0:
		var sep := HSeparator.new()
		vbox.add_child(sep)
		var st_title := Label.new()
		st_title.text = "状态"
		st_title.add_theme_font_size_override("font_size", 11)
		st_title.add_theme_color_override("font_color", C_GOLD)
		vbox.add_child(st_title)
		for s in status_lines:
			_add_info_line(vbox, s, C_RED if player.skip_next_action and s.begins_with("⏸") else C_TEXT_DIM)

	# Buffs section
	var buffs: Array[String] = []
	if player.has_energy_per_turn_buff: buffs.append("封印1: +1气/回合")
	if player.has_movement_bonus:        buffs.append("封印2: +2移动")
	if player.has_range_bonus:           buffs.append("封印3: +1射程")
	if buffs.size() > 0:
		for b in buffs:
			_add_info_line(vbox, b, C_GOLD)

	# Skills section
	if player.character and player.character.skills.size() > 0:
		var sep := HSeparator.new()
		vbox.add_child(sep)
		var sk_title := Label.new()
		sk_title.text = "技能"
		sk_title.add_theme_font_size_override("font_size", 11)
		sk_title.add_theme_color_override("font_color", C_GOLD)
		vbox.add_child(sk_title)
		for sk: SkillData in player.character.skills:
			var cls_str := ""
			if _is_b_class(sk):
				cls_str = "[B]"
			else:
				cls_str = "[A]"
			_add_info_line(vbox, "%s %s (气:%d)" % [cls_str, sk.skill_name, sk.energy_cost], C_TEXT_DIM)

func _add_info_line(parent: VBoxContainer, text: String, color: Color = C_TEXT_DIM) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)

# ── Right panel ──────────────────────────────────────────────────────────────────

func _refresh_right_panel() -> void:
	if _right_panel == null:
		return
	for child in _right_panel.get_children():
		child.queue_free()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Section: Other players
	_add_section_header(vbox, "▶ 从者")
	for player in _game_mgr.get_all_players():
		if not player.is_alive:
			continue
		var pid := _game_mgr.get_current_turn_player_id()
		var marker := " →" if player.player_id == pid else ""
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG * Color(1, 1, 1, 0.6), C_PANEL_BDR * Color(1, 1, 1, 0.3), 1, 4))
		vbox.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 1)
		card.add_child(cv)

		var nl := Label.new()
		nl.text = "%s%s" % [player.player_name, marker]
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", C_GOLD_BRT if marker else C_TEXT)
		cv.add_child(nl)

		var hl := Label.new()
		hl.text = "HP %d/%d · 气 %d" % [player.hp, player.max_hp, player.energy]
		hl.add_theme_font_size_override("font_size", 9)
		hl.add_theme_color_override("font_color", C_TEXT_DIM)
		cv.add_child(hl)

		var pos = Vector2i(player.hex_q, player.hex_r)
		var cell = _game_mgr.get_cell(pos.x, pos.y)
		var terrain_name := _terrain_display_name(cell.terrain if cell else 1)
		var tl := Label.new()
		tl.text = "(%d,%d) %s" % [pos.x, pos.y, terrain_name]
		tl.add_theme_font_size_override("font_size", 9)
		tl.add_theme_color_override("font_color", C_TEXT_DIM)
		cv.add_child(tl)

	# Section: Seals
	_add_section_header(vbox, "▶ 封印")
	var seal1_pos_str := "" if _game_mgr._seal_mgr.boss_position == Vector2i(-999, -999) else " (%d,%d)" % [_game_mgr._seal_mgr.boss_position.x, _game_mgr._seal_mgr.boss_position.y]
	var seal2_pos_str := "" if _game_mgr._seal_mgr.altar_position == Vector2i(-999, -999) else " (%d,%d)" % [_game_mgr._seal_mgr.altar_position.x, _game_mgr._seal_mgr.altar_position.y]
	var seal3_pos_str := "" if _game_mgr._seal_mgr.relic_position == Vector2i(-999, -999) else " (%d,%d)" % [_game_mgr._seal_mgr.relic_position.x, _game_mgr._seal_mgr.relic_position.y]
	_build_seal_entry(vbox, 1, "封印1: 野怪" + seal1_pos_str, _game_mgr._seal_mgr.seal1_unlocked,
		"HP %d/20" % _game_mgr._seal_mgr.boss_hp, "已解封 (+1气/回合)")
	_build_seal_entry(vbox, 2, "封印2: 祭坛" + seal2_pos_str, _game_mgr._seal_mgr.seal2_unlocked,
		"进度 %d/%d" % [_get_altar_total(), _game_mgr._seal_mgr.altar_required_energy],
		"已解封 (+2移动)")
	_build_seal_entry(vbox, 3, "封印3: 遗物" + seal3_pos_str, _game_mgr._seal_mgr.seal3_unlocked,
		"未标记" if _game_mgr._seal_mgr.relic_position == Vector2i(-999, -999) else "已标记",
		"已解封 (+1射程)")

	# Section: Grail
	_add_section_header(vbox, "▶ 圣杯")
	if _game_mgr._grail_mgr.is_open:
		var occ_id := _game_mgr._grail_mgr.occupying_player_id
		if occ_id >= 0:
			var occ := _game_mgr.get_player(occ_id)
			_add_small_label(vbox, "占领中: %s (%d/%d回合)" % [occ.player_name if occ else "?", _game_mgr._grail_mgr.occupation_turns, GrailManager.REQUIRED_TURNS])
		else:
			_add_small_label(vbox, "已开启 · 等待占领")
	else:
		_add_small_label(vbox, "未开启")

	# Section: Ring
	_add_section_header(vbox, "▶ 缩圈")
	if _game_mgr._shrink_ring.active:
		_add_small_label(vbox, "激活 · 半径: %d · %d/%d回合" % [_game_mgr._shrink_ring.current_radius, _game_mgr._shrink_ring.turns_since_activation % ShrinkRing.SHRINK_INTERVAL, ShrinkRing.SHRINK_INTERVAL])
	else:
		_add_small_label(vbox, "未激活")

func _get_altar_total() -> int:
	var total := 0
	for pid in _game_mgr._seal_mgr.altar_progress:
		total += _game_mgr._seal_mgr.altar_progress[pid]
	return total

func _build_seal_entry(parent: VBoxContainer, seal_idx: int, name: String, unlocked: bool, locked_text: String, unlocked_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var info := Label.new()
	info.text = "  %s: %s" % [name, unlocked_text if unlocked else locked_text]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 9)
	info.add_theme_color_override("font_color", C_GOLD if unlocked else C_TEXT_DIM)
	row.add_child(info)

	var locate_btn := Button.new()
	locate_btn.text = "📍"
	locate_btn.custom_minimum_size = Vector2(24, 24)
	locate_btn.add_theme_font_size_override("font_size", 11)
	locate_btn.tooltip_text = "定位到地图"
	_style_small_btn(locate_btn)
	var si := seal_idx
	locate_btn.pressed.connect(func(): _on_seal_locate(si))
	row.add_child(locate_btn)

func _on_seal_locate(seal_idx: int) -> void:
	var target := Vector2i(-999, -999)
	match seal_idx:
		1:
			target = _game_mgr._seal_mgr.boss_position
		2:
			target = _game_mgr._seal_mgr.altar_position
		3:
			target = _game_mgr._seal_mgr.relic_position

	if target != Vector2i(-999, -999):
		_highlight_hex = target
		_highlight_timer = 3.0
		# Center map on target
		var pixel := _hex_to_pixel(target.x, target.y, _hex_size)
		_map_offset = _map_area_center - pixel * _map_zoom
		queue_redraw()
		_log_event("已定位封印%d → (%d, %d)" % [seal_idx, target.x, target.y], C_GOLD)

func _add_section_header(parent: VBoxContainer, text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", C_GOLD)
	parent.add_child(lbl)
	return lbl

func _add_small_label(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = "  %s" % text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	parent.add_child(lbl)

func _terrain_display_name(t: int) -> String:
	match t:
		0: return "虚空"
		1: return "平原"
		2: return "森林"
		3: return "高地"
		4: return "山脉"
		5: return "要塞"
		6: return "圣杯"
		7: return "沙漠"
		8: return "雪地"
	return "?"

func _terrain_effect_description(t: int) -> String:
	match t:
		2: return "潜行 — 此地形上的单位无法被攻击"
		3: return "高地 — 攻击距离+1"
		4: return "山脉 — 受到伤害-1"
		5: return "要塞 — 受到伤害减半，首次进入+3气"
		6: return "圣杯 — 持续占领可获得胜利"
		7: return "沙漠 — 进入时触发随机事件"
		8: return "雪地 — 进入时随机滑移"
	return ""

# ── Game over popup ──────────────────────────────────────────────────────────────

func _show_game_over_popup(winner_name: String, reason: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_GOLD * Color(1, 1, 1, 0.5), 2, 12))
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "圣杯战争 · 结束"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", C_GOLD_BRT)
	vbox.add_child(title)

	var winner_lbl := Label.new()
	winner_lbl.text = "胜者: %s" % winner_name
	winner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_lbl.add_theme_font_size_override("font_size", 18)
	winner_lbl.add_theme_color_override("font_color", C_GOLD)
	vbox.add_child(winner_lbl)

	var reason_lbl := Label.new()
	reason_lbl.text = "(%s)" % reason
	reason_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_lbl.add_theme_font_size_override("font_size", 14)
	reason_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(reason_lbl)

	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 16)
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_box)

	var retry_btn := Button.new()
	retry_btn.text = "再来一局"
	retry_btn.custom_minimum_size = Vector2(120, 40)
	retry_btn.add_theme_font_size_override("font_size", 15)
	retry_btn.add_theme_color_override("font_color", C_GOLD_BRT)
	_style_action_btn(retry_btn)
	retry_btn.pressed.connect(func():
		SceneManager.last_hgw_config = {}
		SceneManager.go_to("res://scenes/hgw/hgw_character_select.tscn"))
	btn_box.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = "返回主菜单"
	menu_btn.custom_minimum_size = Vector2(120, 40)
	menu_btn.add_theme_font_size_override("font_size", 15)
	menu_btn.add_theme_color_override("font_color", C_TEXT)
	_style_action_btn(menu_btn)
	menu_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/main_menu.tscn"))
	btn_box.add_child(menu_btn)

# ── Drawing ──────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_draw_map()
	_draw_player_tokens()
	_draw_movement_range()
	_draw_attack_range()
	_draw_highlight()

func _hex_to_screen(q: int, r: int) -> Vector2:
	var raw := _hex_to_pixel(q, r, _hex_size)
	return raw * _map_zoom + _map_offset + _map_area_center

func _draw_map() -> void:
	var cells: Dictionary = _game_mgr.get_map_cells()
	if cells.is_empty():
		return

	for pos: Vector2i in cells:
		var cell = cells[pos]
		if cell.is_void:
			continue

		var pixel := _hex_to_screen(cell.q, cell.r)
		var col := HGWMapGenerator.terrain_color(cell.terrain)

		draw_polygon(_hex_vertices(pixel.x, pixel.y, _hex_size * _map_zoom * 0.92), PackedColorArray([col]))
		draw_polyline(
			_hex_vertices(pixel.x, pixel.y, _hex_size * _map_zoom) + PackedVector2Array([_hex_vertices(pixel.x, pixel.y, _hex_size * _map_zoom)[0]]),
			C_PANEL_BDR * Color(1, 1, 1, 0.3), 0.6 * _map_zoom, true)

		if cell.is_grail:
			draw_circle(pixel, 5.0 * _map_zoom, C_GOLD_BRT)
		if cell.is_city:
			var s := 4.0 * _map_zoom
			draw_rect(Rect2(pixel.x - s, pixel.y - s, s * 2, s * 2), Color(0.863, 0.235, 0.235, 0.8))
		if cell.is_resource:
			var s := 2.0 * _map_zoom
			match cell.res_tier:
				"rare": draw_circle(pixel, s + 1.0, C_GOLD)
				"core": draw_circle(pixel, s + 1.0, C_GOLD_BRT)
				_: draw_circle(pixel, s, C_GREEN)
		if cell.is_key:
			var s := 2.5 * _map_zoom
			draw_rect(Rect2(pixel.x - s, pixel.y - s, s * 2, s * 2), C_GOLD, false, 1.0)

	_draw_seal_markers()

func _draw_seal_markers() -> void:
	var sm := _game_mgr._seal_mgr

	# Seal 1: Boss
	if not sm.seal1_unlocked and sm.boss_position != Vector2i(-999, -999):
		var p := _hex_to_screen(sm.boss_position.x, sm.boss_position.y)
		var s := 8.0 * _map_zoom
		# Triangle marker
		var pts := PackedVector2Array([
			p + Vector2(0, -s),
			p + Vector2(-s * 0.75, s * 0.5),
			p + Vector2(s * 0.75, s * 0.5),
		])
		draw_polygon(pts, PackedColorArray([Color(0.9, 0.15, 0.15, 0.8)]))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.0, true)

	# Seal 2: Altar
	if not sm.seal2_unlocked and sm.altar_position != Vector2i(-999, -999):
		var p := _hex_to_screen(sm.altar_position.x, sm.altar_position.y)
		var s := 7.0 * _map_zoom
		# Diamond marker
		var pts := PackedVector2Array([
			p + Vector2(0, -s),
			p + Vector2(s, 0),
			p + Vector2(0, s),
			p + Vector2(-s, 0),
		])
		draw_polygon(pts, PackedColorArray([Color(0.2, 0.4, 0.9, 0.8)]))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.0, true)

	# Seal 3: Relic
	if not sm.seal3_unlocked and sm.relic_position != Vector2i(-999, -999):
		var p := _hex_to_screen(sm.relic_position.x, sm.relic_position.y)
		var s := 6.0 * _map_zoom
		draw_circle(p, s, Color(1.0, 0.84, 0.18, 0.8))
		draw_circle(p, s, Color.BLACK, false, 1.0)

func _draw_player_tokens() -> void:
	for player in _game_mgr.get_all_players():
		if not player.is_alive:
			continue

		var pixel := _hex_to_screen(player.hex_q, player.hex_r)
		var is_hovered := (player.hex_q == _hovered_hex.x and player.hex_r == _hovered_hex.y)
		var token_r := (10.0 if is_hovered else 8.0) * _map_zoom

		var player_colors: Array[Color] = [
			Color(0.314, 0.706, 1.0),
			Color(0.863, 0.235, 0.235),
			Color(0.314, 1.0, 0.314),
			Color(1.0, 0.843, 0.0),
			Color(0.706, 0.314, 1.0),
			Color(1.0, 0.471, 0.157),
			Color(0.0, 0.843, 0.843),
			Color(1.0, 0.5, 0.7),
		]
		var col: Color = player_colors[player.player_id % player_colors.size()]

		draw_circle(pixel, token_r + 2.0 * _map_zoom, Color.BLACK * Color(1, 1, 1, 0.6))
		draw_circle(pixel, token_r, col)

		var initial := player.player_name.left(1)
		draw_string(get_theme_default_font(), pixel + Vector2(-4, 4) * _map_zoom, initial, HORIZONTAL_ALIGNMENT_CENTER, -1, maxi(8, int(10 * _map_zoom)))

		# Energy dots
		if player.energy > 0:
			var ex := pixel.x + token_r + 4.0 * _map_zoom
			var ey := pixel.y - token_r - 2.0 * _map_zoom
			for ei in range(mini(player.energy, 5)):
				draw_circle(Vector2(ex + ei * 5.0 * _map_zoom, ey), 2.0 * _map_zoom, C_GOLD)

		# HP bar
		var bar_w := 20.0 * _map_zoom
		var bar_h := 3.0 * _map_zoom
		var bar_y := pixel.y - token_r - 8.0 * _map_zoom
		draw_rect(Rect2(pixel.x - bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.3, 0.1, 0.1))
		var hp_ratio := float(player.hp) / float(max(1, player.max_hp))
		draw_rect(Rect2(pixel.x - bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), Color(0.2, 0.8, 0.2))

func _draw_movement_range() -> void:
	if not _show_movement_range:
		return
	for hex: Vector2i in _reachable_cells:
		var pixel := _hex_to_screen(hex.x, hex.y)
		var sz := _hex_size * _map_zoom
		draw_polygon(_hex_vertices(pixel.x, pixel.y, sz * 0.88), PackedColorArray([Color(0.2, 0.8, 0.2, 0.25)]))
		draw_polyline(
			_hex_vertices(pixel.x, pixel.y, sz) + PackedVector2Array([_hex_vertices(pixel.x, pixel.y, sz)[0]]),
			Color(0.2, 0.8, 0.2, 0.5), 1.0, true)

func _draw_attack_range() -> void:
	if not _show_attack_range:
		return
	var pid := _game_mgr.get_current_turn_player_id()
	var player := _game_mgr.get_player(pid)
	if player == null:
		return
	var ar := player.get_attack_range()
	for other in _game_mgr.get_all_players():
		if not other.is_alive or other.player_id == player.player_id:
			continue
		var dist := maxi(abs(player.hex_q - other.hex_q), maxi(abs(player.hex_r - other.hex_r), abs((player.hex_q + player.hex_r) - (other.hex_q + other.hex_r))))
		if dist <= ar:
			var pixel := _hex_to_screen(other.hex_q, other.hex_r)
			var r := 14.0 * _map_zoom
			draw_circle(pixel, r, Color(0.8, 0.2, 0.2, 0.4))
			draw_arc(pixel, r, 0, TAU, 12, Color(0.8, 0.2, 0.2, 0.7), 1.5 * _map_zoom, true)

func _draw_highlight() -> void:
	if _highlight_hex == Vector2i(-999, -999) or _highlight_timer <= 0.0:
		return
	var pixel := _hex_to_screen(_highlight_hex.x, _highlight_hex.y)
	var r := _hex_size * _map_zoom * 0.9
	var alpha := minf(1.0, _highlight_timer / 1.5)
	# Pulsing ring
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 200.0) * 0.3
	draw_circle(pixel, r * pulse, Color(1.0, 0.84, 0.18, alpha * 0.5))
	draw_circle(pixel, r * pulse, Color(1.0, 0.84, 0.18, alpha), false, 2.0)

# ── Hex math ─────────────────────────────────────────────────────────────────────

func _hex_to_pixel(q: int, r: int, sz: float) -> Vector2:
	var x := sz * (sqrt(3) * q + sqrt(3) / 2.0 * r)
	var y := sz * (1.5 * r)
	return Vector2(x, y)

func _hex_vertices(cx: float, cy: float, sz: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(6):
		var rad: float = deg_to_rad(60.0 * i - 30.0)
		pts.append(Vector2(cx + sz * cos(rad), cy + sz * sin(rad)))
	return pts

func _pixel_to_hex(px: Vector2) -> Vector2i:
	var world := (px - _map_offset - _map_area_center) / _map_zoom
	var q: float = (sqrt(3) / 3.0 * world.x - 1.0 / 3.0 * world.y) / _hex_size
	var r: float = (2.0 / 3.0 * world.y) / _hex_size
	var s: float = -q - r
	var rq: int = roundi(q)
	var rr: int = roundi(r)
	var rs: int = roundi(s)
	var q_diff: float = abs(rq - q)
	var r_diff: float = abs(rr - r)
	var s_diff: float = abs(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return Vector2i(rq, rr)

# ── Helpers ──────────────────────────────────────────────────────────────────────

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s
