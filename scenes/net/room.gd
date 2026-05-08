## Room — 纯客户端房间页，通过 RoomManager RPC 与 ECS 权威服务器交互
extends Control

const GAME_MODES := {
	"ffa": {"label": "自由对战", "min_players": 2, "max_players": 4, "team_count": 0},
	"2v2": {"label": "2v2 团队", "min_players": 4, "max_players": 4, "team_count": 2},
}

# ── Color Palette ──
const C_BG           := Color("#f5f2eb")
const C_TOPBAR_BG    := Color("#2a2418")
const C_GOLD         := Color("#c8860a")
const C_GOLD_LIGHT   := Color("#f5c842")
const C_TEXT_DARK    := Color("#2a2418")
const C_TEXT_MID     := Color("#888480")
const C_TEXT_LIGHT   := Color("#a09878")
const C_BORDER       := Color("#dedad0")
const C_WHITE        := Color("#ffffff")
const C_RED_BG       := Color("#fdf0f0")
const C_RED_BORDER   := Color("#d4537e")
const C_RED_TEXT     := Color("#993556")
const C_GREEN_BG     := Color("#edf8f0")
const C_GREEN_BORDER := Color("#6aab80")
const C_GREEN_TEXT   := Color("#3b7a40")
const C_GOLD_BG      := Color("#fdf6e8")
const C_BLUE_BG      := Color("#eef4fb")
const C_BLUE_TEXT    := Color("#2a6ab0")

# ── State ──
var mode: String = ""
var max_players: int = 8
var team_size: int = 0
var room_code: String = ""

var _is_host: bool = false     # derived from server sync
var _host_peer_id: int = 0     # from server sync
var _my_name: String = ""
var _my_char: String = ""
var _my_ready: bool = false
var _slots: Array[Dictionary] = []
var _selected_char_id: String = ""
var _card_nodes: Array = []

# ── UI refs (from room.tscn) ──
@onready var _room_title_label: Label       = $TopBar/TitleVBox/RoomTitle
@onready var _room_id_label: Label          = $TopBar/TitleVBox/RoomId
@onready var _nickname_input: LineEdit      = $TopBar/NickRow/NicknameInput
@onready var _player_count_label: Label     = $MainLayout/LeftPanel/PlayerHeader/PlayerCountLabel
@onready var _player_vbox: VBoxContainer    = $MainLayout/LeftPanel/PlayerScroll/PlayerVBox
@onready var _room_info_label: Label        = $MainLayout/LeftPanel/RoomInfoPanel/InfoInner/RoomInfoLabel
@onready var _char_grid_scroll: ScrollContainer = $MainLayout/RightPanel/CharScrollContainer
@onready var _char_grid: GridContainer      = $MainLayout/RightPanel/CharScrollContainer/CharGrid
@onready var _detail_panel: PanelContainer  = $MainLayout/RightPanel/CharDetailPanel
@onready var _detail_avatar: PanelContainer = $MainLayout/RightPanel/CharDetailPanel/DetailVBox/DetailRow/DetailAvatar
@onready var _detail_avatar_label: Label    = $MainLayout/RightPanel/CharDetailPanel/DetailVBox/DetailRow/DetailAvatar/DetailAvatarLabel
@onready var _detail_name_label: Label      = $MainLayout/RightPanel/CharDetailPanel/DetailVBox/DetailRow/DetailText/DetailNameLabel
@onready var _detail_role_label: Label      = $MainLayout/RightPanel/CharDetailPanel/DetailVBox/DetailRow/DetailText/DetailRoleLabel
@onready var _skill_vbox: VBoxContainer     = $MainLayout/RightPanel/CharDetailPanel/DetailVBox/DetailRow/DetailText/SkillScroll/SkillVBox
@onready var _chat_scroll: ScrollContainer  = $MainLayout/RightPanel/ChatPanel/ChatInner/ChatLog
@onready var _chat_vbox: VBoxContainer      = $MainLayout/RightPanel/ChatPanel/ChatInner/ChatLog/ChatVBox
@onready var _chat_input: LineEdit          = $MainLayout/RightPanel/ChatPanel/ChatInner/InputRow/ChatInput
@onready var _status_label: Label           = $BottomBar/BtnRow/StatusLabel
@onready var _leave_btn: Button             = $BottomBar/BtnRow/LeaveBtn
@onready var _ready_btn: Button             = $BottomBar/BtnRow/ReadyBtn
@onready var _start_btn: Button             = $BottomBar/BtnRow/StartBtn
@onready var _btn_add_ai: Button            = $BottomBar/BtnRow/AddAIBtn
@onready var _btn_spectate: Button          = $BottomBar/BtnRow/SpectateBtn

func _ready() -> void:
	var config = SceneManager.last_game_config
	mode = config.get("mode", "ffa")
	var mode_cfg: Dictionary = GAME_MODES.get(mode, GAME_MODES["ffa"])
	max_players = config.get("max_players", mode_cfg["max_players"])
	team_size = mode_cfg["team_count"]
	var _name_from_config: String = config.get("player_name", "")
	_my_name = _name_from_config if _name_from_config != "" else _default_name()

	_nickname_input.text = _my_name
	_connect_signals()

	# 隐藏所有操作按钮，等待服务器 sync
	_start_btn.visible = false
	_ready_btn.visible = false
	_btn_add_ai.visible = false
	_btn_spectate.visible = false
	_status_label.text = "正在连接服务器..."

	_build_character_grid()

	# 连接 RoomManager 信号
	RoomManager.lobby_sync_received.connect(_on_lobby_sync)
	RoomManager.game_starting.connect(_on_game_starting)
	RoomManager.join_failed.connect(_on_join_failed)
	RoomManager.chat_received.connect(_on_chat_received)

	# 连接到 ECS 游戏服务器
	if NetworkManager.is_connected_to_game:
		_on_server_connected()
	else:
		NetworkManager.connected_to_game_server.connect(_on_server_connected, CONNECT_ONE_SHOT)
		NetworkManager.disconnected_from_game_server.connect(_on_server_disconnected, CONNECT_ONE_SHOT)
		NetworkManager.connect_to_game_server(NetworkManager.GAME_SERVER_IP, NetworkManager.GAME_SERVER_PORT, "")

func _exit_tree() -> void:
	# 显式断开 RoomManager 信号，防止场景切换后残留无效回调
	if RoomManager.lobby_sync_received.is_connected(_on_lobby_sync):
		RoomManager.lobby_sync_received.disconnect(_on_lobby_sync)
	if RoomManager.game_starting.is_connected(_on_game_starting):
		RoomManager.game_starting.disconnect(_on_game_starting)
	if RoomManager.join_failed.is_connected(_on_join_failed):
		RoomManager.join_failed.disconnect(_on_join_failed)
	if RoomManager.chat_received.is_connected(_on_chat_received):
		RoomManager.chat_received.disconnect(_on_chat_received)

# ─────────────────────────────────────────────────────────────
# Signals
# ─────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_leave_btn.pressed.connect(_on_back_pressed)
	_ready_btn.pressed.connect(_on_ready_pressed)
	_btn_spectate.pressed.connect(_on_spectate_pressed)
	_start_btn.pressed.connect(_on_start_pressed)
	_btn_add_ai.pressed.connect(_on_add_ai_pressed)
	_nickname_input.text_changed.connect(_on_name_changed)
	$TopBar/NickRow/EditBtn.pressed.connect(func(): _nickname_input.grab_focus())
	$MainLayout/RightPanel/ChatPanel/ChatInner/InputRow/SendBtn.pressed.connect(_on_send_chat)
	$MainLayout/RightPanel/CharDetailPanel/DetailVBox/BackBtn.pressed.connect(_on_back_to_grid)
	_chat_input.text_submitted.connect(func(_t: String): _on_send_chat())
	_char_grid_scroll.resized.connect(func():
		var w := _char_grid_scroll.size.x
		if w > 0:
			_char_grid.columns = max(3, int(w / 84))
	)

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

func _make_flat(bg: Color, border: Color, bw: float, radius: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

func _make_badge(text: String, bg: Color, border: Color, text_color: Color) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(54, 20)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _make_flat(bg, border, 1, 10))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	badge.add_child(lbl)
	return badge

func _style_btn(btn: Button, border: Color, text_color: Color) -> void:
	btn.add_theme_stylebox_override("normal", _make_flat(C_WHITE, border, 1, 5))
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_font_size_override("font_size", 13)

func _style_accent_btn(btn: Button, border: Color, text_color: Color, bg: Color = C_WHITE) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 4
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.set_corner_radius_all(5)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_font_size_override("font_size", 13)

func _default_name() -> String:
	if NetworkManager._session != null and NetworkManager._session.username != "":
		return NetworkManager._session.username
	var id = str(randi()).right(4)
	return "Player_" + id

# ─────────────────────────────────────────────────────────────
# Character Cards
# ─────────────────────────────────────────────────────────────

func _build_character_grid() -> void:
	for child in _char_grid.get_children():
		child.queue_free()
	_card_nodes.clear()

	for data in Characters.LIST:
		var card := _make_character_card(data)
		_char_grid.add_child(card)
		_card_nodes.append({"card": card, "char_id": data.get("id", "")})

func _make_character_card(data: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(76, 100)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var color: Color = Color(data.get("color", "#c8860a"))
	var bg_color: Color = Color(data.get("bg_color", "#fdf6e8"))

	card.add_theme_stylebox_override("panel", _make_flat(C_WHITE, C_BORDER, 1, 5))

	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.anchor_right = 1.0; inner.anchor_bottom = 1.0
	inner.add_theme_constant_override("separation", 0)
	card.add_child(inner)

	var accent := ColorRect.new()
	accent.name = "TopAccent"
	accent.color = C_BORDER
	accent.custom_minimum_size = Vector2(0, 4)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(accent)

	var av := Panel.new()
	av.name = "AvatarRect"
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.size_flags_vertical = Control.SIZE_EXPAND_FILL
	av.add_theme_stylebox_override("panel", _make_flat(bg_color, Color(color, 0.25), 0, 2))
	inner.add_child(av)

	var res_path: String = data.get("res_path", "")
	var char_res: CharacterData = null
	if res_path != "":
		char_res = load(res_path) as CharacterData

	if char_res != null and char_res.portrait != null:
		var tr := TextureRect.new()
		tr.texture = char_res.portrait
		tr.anchor_right = 1.0; tr.anchor_bottom = 1.0
		tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av.add_child(tr)
	else:
		var avl := Label.new()
		avl.text = data.get("name", "?")[0]
		avl.add_theme_color_override("font_color", color)
		avl.add_theme_font_size_override("font_size", 26)
		avl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avl.anchor_right = 1.0; avl.anchor_bottom = 1.0
		av.add_child(avl)

	var role: String = data.get("role", "")
	if role != "":
		var role_bg := ColorRect.new()
		role_bg.color = Color(color, 0.82)
		role_bg.anchor_left = 0.0; role_bg.anchor_right = 1.0
		role_bg.anchor_top = 1.0; role_bg.anchor_bottom = 1.0
		role_bg.offset_top = -14
		role_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		av.add_child(role_bg)
		var role_lbl := Label.new()
		role_lbl.text = role
		role_lbl.add_theme_color_override("font_color", C_WHITE)
		role_lbl.add_theme_font_size_override("font_size", 8)
		role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		role_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		role_lbl.anchor_right = 1.0; role_lbl.anchor_bottom = 1.0
		role_bg.add_child(role_lbl)

	var nbar := ColorRect.new()
	nbar.name = "NameBar"
	nbar.color = color
	nbar.custom_minimum_size = Vector2(0, 18)
	nbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(nbar)

	var nlbl := Label.new()
	var full_name: String = data.get("name", "")
	nlbl.text = full_name if full_name.length() <= 5 else full_name.left(4) + "…"
	nlbl.add_theme_color_override("font_color", C_WHITE)
	nlbl.add_theme_font_size_override("font_size", 9)
	nlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nlbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nlbl.anchor_right = 1.0; nlbl.anchor_bottom = 1.0
	nbar.add_child(nlbl)

	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_char_selected(data.get("id", ""))
	)

	return card

func _on_char_selected(char_id: String) -> void:
	_selected_char_id = char_id
	_my_char = char_id

	for entry in _card_nodes:
		var card: PanelContainer = entry["card"]
		var cid: String = entry["char_id"]
		var data: Dictionary = Characters.get_by_id(cid)
		var color: Color = Color(data.get("color", "#c8860a"))
		var bg: Color = Color(data.get("bg_color", "#fdf6e8"))
		var selected := cid == char_id

		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(5)
		if selected:
			s.bg_color = bg
			s.border_color = color
			s.set_border_width_all(2)
		else:
			s.bg_color = C_WHITE
			s.border_color = C_BORDER
			s.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", s)
		card.get_node("Inner/TopAccent").color = color if selected else C_BORDER

	_char_grid_scroll.visible = false
	_detail_panel.visible = true
	_update_detail_panel(char_id)

	RoomManager.rpc_id(1, "select_character", char_id)

func _on_back_to_grid() -> void:
	_char_grid_scroll.visible = true
	_detail_panel.visible = false

func _make_skill_row_detail(skill: SkillData, is_unlocked: bool = false) -> Control:
	var has_desc := skill.description != ""
	var row_height: int = 44 if has_desc else 28
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, row_height)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var accent_color: Color = C_BLUE_TEXT if is_unlocked else C_BORDER
	var row_s := StyleBoxFlat.new()
	row_s.bg_color = Color.WHITE; row_s.border_color = accent_color
	row_s.set_border_width_all(1); row_s.set_corner_radius_all(3)
	row.add_theme_stylebox_override("panel", row_s)

	var name_lbl := Label.new()
	name_lbl.text = skill.skill_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", C_BLUE_TEXT if is_unlocked else C_TEXT_DARK)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_desc:
		name_lbl.anchor_right = 1.0; name_lbl.anchor_bottom = 0.0
		name_lbl.offset_left = 8.0; name_lbl.offset_top = 3.0
		name_lbl.offset_right = -80.0; name_lbl.offset_bottom = 23.0
	else:
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.anchor_right = 1.0; name_lbl.anchor_bottom = 1.0
		name_lbl.offset_left = 8.0; name_lbl.offset_right = -80.0
	row.add_child(name_lbl)

	if has_desc:
		var desc_lbl := Label.new()
		desc_lbl.text = skill.description
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", C_TEXT_MID)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.anchor_right = 1.0; desc_lbl.anchor_bottom = 0.0
		desc_lbl.offset_left = 8.0; desc_lbl.offset_top = 22.0
		desc_lbl.offset_right = -80.0; desc_lbl.offset_bottom = 42.0
		desc_lbl.clip_text = true
		row.add_child(desc_lbl)

	var cost_str: String
	if is_unlocked:
		cost_str = "解锁技"
	elif skill.energy_cost > 0:
		cost_str = "⚡%d" % skill.energy_cost
	else:
		cost_str = "被动"
	var cost_lbl := Label.new()
	cost_lbl.text = cost_str
	cost_lbl.add_theme_font_size_override("font_size", 9)
	cost_lbl.add_theme_color_override("font_color", C_BLUE_TEXT if is_unlocked else C_TEXT_MID)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_lbl.anchor_left = 1.0; cost_lbl.anchor_right = 1.0
	cost_lbl.anchor_bottom = 1.0
	cost_lbl.offset_left = -78.0; cost_lbl.offset_right = -4.0
	row.add_child(cost_lbl)

	return row

func _update_detail_panel(char_id: String) -> void:
	var data: Dictionary = Characters.get_by_id(char_id)
	if data.is_empty():
		_on_back_to_grid()
		return

	var color: Color = Color(data.get("color", "#c8860a"))
	var bg: Color = Color(data.get("bg_color", "#fdf6e8"))

	var dp_s := StyleBoxFlat.new()
	dp_s.bg_color = C_WHITE
	dp_s.border_color = color
	dp_s.border_width_left = 4
	dp_s.border_width_top = 1
	dp_s.border_width_right = 1
	dp_s.border_width_bottom = 1
	dp_s.set_corner_radius_all(5)
	_detail_panel.add_theme_stylebox_override("panel", dp_s)

	var res_path: String = data.get("res_path", "")
	var char_res: CharacterData = null
	if res_path != "":
		char_res = load(res_path) as CharacterData

	_detail_avatar.add_theme_stylebox_override("panel", _make_flat(bg, color, 1, 4))
	var portrait_rect := _detail_avatar.get_node_or_null("PortraitRect") as TextureRect
	if portrait_rect == null:
		portrait_rect = TextureRect.new()
		portrait_rect.name = "PortraitRect"
		portrait_rect.anchor_right = 1.0; portrait_rect.anchor_bottom = 1.0
		portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_avatar.add_child(portrait_rect)
	if char_res != null and char_res.portrait != null:
		portrait_rect.texture = char_res.portrait
		portrait_rect.visible = true
		_detail_avatar_label.visible = false
	else:
		portrait_rect.visible = false
		_detail_avatar_label.visible = true
		_detail_avatar_label.text = data.get("name", "?")[0]
		_detail_avatar_label.add_theme_color_override("font_color", color)

	_detail_name_label.text = data.get("name", "")
	_detail_name_label.add_theme_color_override("font_color", color)
	_detail_role_label.text = "HP%d  ·  %s" % [data.get("hp", 0), data.get("role", "")]
	_detail_role_label.add_theme_color_override("font_color", C_TEXT_DARK)

	for child in _skill_vbox.get_children():
		child.queue_free()
	var unlocked_skills: Array[SkillData] = []
	if char_res != null:
		for skill in char_res.skills:
			_skill_vbox.add_child(_make_skill_row_detail(skill as SkillData))
			for effect in skill.effects:
				if effect.effect_type == SkillEffect.EffectType.UNLOCK_SKILL and effect.unlock_skill != null:
					var us := effect.unlock_skill as SkillData
					if us != null:
						unlocked_skills.append(us)

	if unlocked_skills.size() > 0:
		var sep := HSeparator.new()
		sep.custom_minimum_size = Vector2(0, 1)
		_skill_vbox.add_child(sep)
		var uc_hdr := Label.new()
		uc_hdr.text = "解锁技能"
		uc_hdr.add_theme_color_override("font_color", C_BLUE_TEXT)
		uc_hdr.add_theme_font_size_override("font_size", 10)
		uc_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_skill_vbox.add_child(uc_hdr)
		for us in unlocked_skills:
			_skill_vbox.add_child(_make_skill_row_detail(us, true))

# ─────────────────────────────────────────────────────────────
# Player Slots
# ─────────────────────────────────────────────────────────────

func _update_slot_display() -> void:
	for child in _player_vbox.get_children():
		child.queue_free()

	for i in range(max_players):
		_player_vbox.add_child(_make_slot_card(i))

	if _player_count_label:
		_player_count_label.text = "%d / %d 人" % [_slots.size(), max_players]

	_btn_add_ai.visible = _is_host and _slots.size() < max_players
	if _is_host:
		var min_needed: int = (GAME_MODES.get(mode, GAME_MODES["ffa"]) as Dictionary)["min_players"]
		_start_btn.disabled = _slots.size() < min_needed

func _make_slot_card(idx: int) -> Control:
	var is_occupied := idx < _slots.size()
	var slot := _slots[idx] if is_occupied else {}

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 54)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_occupied:
		var is_ready: bool = slot.get("is_ready", false)
		var is_host_slot: bool = slot.get("peer_id", 0) == _host_peer_id
		var slot_color: Color = C_GREEN_BORDER if is_ready else (C_GOLD if is_host_slot else C_BLUE_TEXT)
		var slot_bg: Color = C_GREEN_BG if is_ready else C_WHITE
		var s := StyleBoxFlat.new()
		s.bg_color = slot_bg
		s.border_color = slot_color
		s.border_width_left = 4
		s.border_width_top = 1
		s.border_width_right = 1
		s.border_width_bottom = 1
		s.set_corner_radius_all(4)
		card.add_theme_stylebox_override("panel", s)
	else:
		card.add_theme_stylebox_override("panel", _make_flat(Color("#faf8f4"), C_BORDER, 1, 4))

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_right = 1.0; row.anchor_bottom = 1.0
	row.add_theme_constant_override("separation", 8)
	row.offset_left = 10; row.offset_top = 6
	row.offset_right = -8; row.offset_bottom = -6
	card.add_child(row)

	if is_occupied:
		var char_data := _get_slot_char_data(slot)
		var av_color: Color = Color(char_data.get("color", "#c8860a")) if not char_data.is_empty() else C_GOLD
		var av_bg: Color = Color(char_data.get("bg_color", "#fdf6e8")) if not char_data.is_empty() else C_GOLD_BG

		var av := Panel.new()
		av.custom_minimum_size = Vector2(36, 36)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av.add_theme_stylebox_override("panel", _make_flat(av_bg, Color(av_color, 0.25), 0, 2))
		row.add_child(av)

		var res_path: String = char_data.get("res_path", "")
		var char_res: CharacterData = null
		if res_path != "":
			char_res = load(res_path) as CharacterData

		if char_res != null and char_res.portrait != null:
			var tr := TextureRect.new()
			tr.texture = char_res.portrait
			tr.anchor_right = 1.0; tr.anchor_bottom = 1.0
			tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			av.add_child(tr)
		else:
			var avl := Label.new()
			avl.text = char_data.get("name", "?")[0] if not char_data.is_empty() else "?"
			avl.add_theme_color_override("font_color", av_color)
			avl.add_theme_font_size_override("font_size", 16)
			avl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			avl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			avl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			avl.anchor_right = 1.0; avl.anchor_bottom = 1.0
			av.add_child(avl)

		var role: String = char_data.get("role", "")
		if role != "":
			var role_bg := ColorRect.new()
			role_bg.color = Color(av_color, 0.82)
			role_bg.anchor_left = 0.0; role_bg.anchor_right = 1.0
			role_bg.anchor_top = 1.0; role_bg.anchor_bottom = 1.0
			role_bg.offset_top = -10
			role_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			av.add_child(role_bg)
			var role_lbl := Label.new()
			role_lbl.text = role
			role_lbl.add_theme_color_override("font_color", C_WHITE)
			role_lbl.add_theme_font_size_override("font_size", 6)
			role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			role_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			role_lbl.anchor_right = 1.0; role_lbl.anchor_bottom = 1.0
			role_bg.add_child(role_lbl)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation", 2)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)

		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 4)
		name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name_row)

		var name_lbl := Label.new()
		name_lbl.text = slot.get("player_name", "玩家")
		name_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(name_lbl)

		if slot.get("peer_id", 0) == _host_peer_id:
			name_row.add_child(_make_badge("房主", C_GOLD_BG, C_GOLD, C_GOLD))
		if slot.get("is_ai", false):
			name_row.add_child(_make_badge("AI", C_BLUE_BG, C_BLUE_TEXT, C_BLUE_TEXT))

		if not char_data.is_empty():
			var ch_lbl := Label.new()
			ch_lbl.text = "%s · %s" % [char_data.get("name", ""), char_data.get("role", "")]
			ch_lbl.add_theme_color_override("font_color", C_TEXT_MID)
			ch_lbl.add_theme_font_size_override("font_size", 10)
			ch_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(ch_lbl)

		var badge: Control
		if slot.get("is_ready", false):
			badge = _make_badge("✓ 已准备", C_GREEN_BG, C_GREEN_BORDER, C_GREEN_TEXT)
		else:
			badge = _make_badge("… 等待中", Color("#fdf0f0"), Color("#d4a0a0"), C_TEXT_MID)
		row.add_child(badge)
	else:
		var sp1 := Control.new()
		sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp1)

		var empty_lbl := Label.new()
		empty_lbl.text = "空槽 — 等待玩家加入"
		empty_lbl.add_theme_color_override("font_color", C_BORDER)
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(empty_lbl)

		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sp2)

	return card

func _get_slot_char_data(slot: Dictionary) -> Dictionary:
	var char_path: String = slot.get("character", "")
	if char_path == "":
		return {}
	for d in Characters.LIST:
		if d.get("id") == char_path or d.get("name") == char_path:
			return d
	return {}

# ─────────────────────────────────────────────────────────────
# Chat
# ─────────────────────────────────────────────────────────────

func _on_send_chat() -> void:
	var msg := _chat_input.text.strip_edges()
	if msg.is_empty():
		return
	_chat_input.text = ""
	var my_name := _my_name if _my_name != "" else "我"
	_add_chat_line(my_name + "：" + msg, C_TEXT_DARK)
	RoomManager.rpc_id(1, "send_chat", my_name, msg)

func _add_chat_line(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 11)
	_chat_vbox.add_child(lbl)
	await get_tree().process_frame
	var vbar := _chat_scroll.get_v_scroll_bar()
	if vbar:
		_chat_scroll.scroll_vertical = vbar.max_value

# ─────────────────────────────────────────────────────────────
# 服务器连接
# ─────────────────────────────────────────────────────────────

func _on_server_connected() -> void:
	var config = SceneManager.last_game_config
	var creating: bool = config.get("is_host", false)
	_status_label.text = "已连接，正在%s..." % ("创建房间" if creating else "加入房间")

	if creating:
		RoomManager.rpc_id(1, "create_room", {
			"mode":        mode,
			"max_players": max_players,
			"player_name": _my_name,
		})
	else:
		var join_code: String = config.get("room_code", "")
		if join_code == "":
			_status_label.text = "错误：房间码为空"
			return
		RoomManager.rpc_id(1, "join_room", join_code, _my_name)

# ─────────────────────────────────────────────────────────────
# RoomManager 信号处理
# ─────────────────────────────────────────────────────────────

func _on_lobby_sync(data: Dictionary) -> void:
	room_code    = data.get("room_code", "")
	mode         = data.get("mode", "ffa")
	max_players  = data.get("max_players", 4)
	_host_peer_id = data.get("host_peer_id", 0)
	_is_host     = (_host_peer_id == multiplayer.get_unique_id())

	_slots.clear()
	for s in data.get("slots", []):
		_slots.append(s)

	if _room_id_label:
		_room_id_label.text = "RM-%s" % room_code if room_code != "" else ""
	if _room_info_label:
		_room_info_label.text = "模式：%s  |  最大玩家：%d" % [mode, max_players]
	if _room_title_label:
		_room_title_label.text = "游戏房间"

	_start_btn.visible   = _is_host
	_ready_btn.visible   = not _is_host
	_btn_add_ai.visible  = _is_host
	_btn_spectate.visible = false  # 暂不支持观战

	_update_slot_display()
	_status_label.text = "%d / %d 人就绪" % [_slots.size(), max_players]

func _on_game_starting(config: Dictionary) -> void:
	SceneManager.last_game_config = config
	SceneManager.go_to("res://scenes/main.tscn")

func _on_server_disconnected() -> void:
	_status_label.text = "连接断开，返回大厅..."
	get_tree().create_timer(2.0).timeout.connect(func():
		SceneManager.go_to("res://scenes/net/lobby.tscn")
	, CONNECT_ONE_SHOT)

func _on_join_failed(reason: String) -> void:
	_status_label.text = "加入失败：" + reason
	get_tree().create_timer(2.0).timeout.connect(func():
		NetworkManager.disconnect_from_game()
		SceneManager.go_to("res://scenes/net/lobby.tscn")
	, CONNECT_ONE_SHOT)

func _on_chat_received(sender_name: String, message: String) -> void:
	_add_chat_line(sender_name + "：" + message, C_TEXT_DARK)

# ─────────────────────────────────────────────────────────────
# 按钮处理
# ─────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	_my_ready = not _my_ready
	if _my_ready:
		_style_btn(_ready_btn, C_GREEN_BORDER, C_GREEN_TEXT)
		_ready_btn.text = "✓ 已准备"
	else:
		_style_btn(_ready_btn, C_GREEN_BORDER, C_TEXT_MID)
		_ready_btn.text = "准 备"
	RoomManager.rpc_id(1, "toggle_ready")

func _on_spectate_pressed() -> void:
	_status_label.text = "暂不支持观战模式"

func _on_add_ai_pressed() -> void:
	if not _is_host:
		return
	RoomManager.rpc_id(1, "add_ai")

func _on_start_pressed() -> void:
	if not _is_host:
		return
	_start_btn.disabled = true
	_status_label.text = "正在开始游戏..."
	RoomManager.rpc_id(1, "start_game")

func _on_back_pressed() -> void:
	RoomManager.rpc_id(1, "leave_room")
	NetworkManager.disconnect_from_game()
	SceneManager.go_to("res://scenes/net/lobby.tscn")

func _on_name_changed(new_name: String) -> void:
	_my_name = new_name.strip_edges()
	if _my_name == "":
		_my_name = _default_name()
	RoomManager.rpc_id(1, "set_player_name", _my_name)
