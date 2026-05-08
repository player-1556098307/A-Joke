## Room — 房间内页，主机创建/客户端加入/角色选择/准备/开始
extends Control

## 游戏模式定义表：key = 模式 ID，value = 配置字典
## min_players: 开始所需最少玩家数（含 AI）
## max_players: 房间上限人数
## team_count:  队伍数（0 = 自由混战，无队伍）
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
var is_host: bool = false
var is_spectator: bool = false
var mode: String = ""
var max_players: int = 8
var team_size: int = 0
var room_code: String = ""

var _my_name: String = ""
var _my_char: String = ""
var _my_ready: bool = false
var _slots: Array[Dictionary] = []
var _selected_char_id: String = ""
var _create_btn: Button
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
	is_host = config.get("is_host", false)
	var _name_from_config: String = config.get("player_name", "")
	_my_name = _name_from_config if _name_from_config != "" else _default_name()

	_nickname_input.text = _my_name
	_connect_signals()

	if is_host:
		_setup_host()
	else:
		_auto_connect_or_show_entry()

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
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

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

	# Top accent strip
	var accent := ColorRect.new()
	accent.name = "TopAccent"
	accent.color = C_BORDER
	accent.custom_minimum_size = Vector2(0, 4)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(accent)

	# Avatar area — Panel（非 Container）支持绝对定位子节点
	var av := Panel.new()
	av.name = "AvatarRect"
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.size_flags_vertical = Control.SIZE_EXPAND_FILL
	av.add_theme_stylebox_override("panel", _make_flat(bg_color, Color(color, 0.25), 0, 2))
	inner.add_child(av)

	# 加载 CharacterData 头像贴图
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

	# 职业徽章：覆盖在头像底部（14px 半透明色条）
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

	# Name bar (colored bg strip at card bottom)
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

	# Toggle to detail view
	_char_grid_scroll.visible = false
	_detail_panel.visible = true
	_update_detail_panel(char_id)

	if is_host:
		_set_my_slot_char(char_id)
		_sync_all_slots()
	else:
		rpc_id(1, "rpc_request_select_character", char_id)

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

	# Skill name (top half when description exists, centered otherwise)
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

	# Description (bottom half, only when non-empty)
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

	# Cost badge (right side)
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

	# Load CharacterData (portrait + real skills)
	var res_path: String = data.get("res_path", "")
	var char_res: CharacterData = null
	if res_path != "":
		char_res = load(res_path) as CharacterData

	# Update avatar panel style and portrait
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

	# Rebuild skill rows from CharacterData
	for child in _skill_vbox.get_children():
		child.queue_free()
	var unlocked_skills: Array[SkillData] = []
	if char_res != null:
		for skill in char_res.skills:
			_skill_vbox.add_child(_make_skill_row_detail(skill as SkillData))
			# Scan for unlockable skills
			for effect in skill.effects:
				if effect.effect_type == SkillEffect.EffectType.UNLOCK_SKILL and effect.unlock_skill != null:
					var us := effect.unlock_skill as SkillData
					if us != null:
						unlocked_skills.append(us)

	# Show unlocked skills section with header
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

	_btn_add_ai.visible = is_host and _slots.size() < max_players
	if is_host:
		_start_btn.disabled = _slots.size() < 2

func _make_slot_card(idx: int) -> Control:
	var is_occupied := idx < _slots.size()
	var slot := _slots[idx] if is_occupied else {}

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 54)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_occupied:
		var is_ready: bool = slot.get("is_ready", false)
		var slot_color: Color = C_GREEN_BORDER if is_ready else (C_GOLD if idx == 0 else C_BLUE_TEXT)
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

		# Avatar box — Panel for absolute child positioning
		var av := Panel.new()
		av.custom_minimum_size = Vector2(36, 36)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av.add_theme_stylebox_override("panel", _make_flat(av_bg, Color(av_color, 0.25), 0, 2))
		row.add_child(av)

		# Load CharacterData for portrait
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

		# Class badge overlay (bottom strip)
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

		# Info column
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation", 2)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)

		# Name + badges row
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

		if idx == 0:
			name_row.add_child(_make_badge("房主", C_GOLD_BG, C_GOLD, C_GOLD))
		if slot.get("is_ai", false):
			name_row.add_child(_make_badge("AI", C_BLUE_BG, C_BLUE_TEXT, C_BLUE_TEXT))

		# Character / role
		if not char_data.is_empty():
			var ch_lbl := Label.new()
			ch_lbl.text = "%s · %s" % [char_data.get("name", ""), char_data.get("role", "")]
			ch_lbl.add_theme_color_override("font_color", C_TEXT_MID)
			ch_lbl.add_theme_font_size_override("font_size", 10)
			ch_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_child(ch_lbl)

		# Ready / waiting badge on right
		var badge: Control
		if slot.get("is_ready", false):
			badge = _make_badge("✓ 已准备", C_GREEN_BG, C_GREEN_BORDER, C_GREEN_TEXT)
		else:
			badge = _make_badge("… 等待中", Color("#fdf0f0"), Color("#d4a0a0"), C_TEXT_MID)
		row.add_child(badge)
	else:
		# Empty slot: centered placeholder text
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

	if is_host:
		for slot in _slots:
			var peer_id = slot.get("peer_id", -1)
			if peer_id > 1:
				rpc_id(peer_id, "rpc_chat_message", my_name, msg)
	else:
		rpc_id(1, "rpc_chat_message", my_name, msg)

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

@rpc("any_peer", "reliable")
func rpc_chat_message(sender_name: String, message: String) -> void:
	_add_chat_line(sender_name + "：" + message, C_TEXT_DARK)
	if is_host:
		var sender_id = multiplayer.get_remote_sender_id()
		for slot in _slots:
			var peer_id = slot.get("peer_id", -1)
			if peer_id > 1 and peer_id != sender_id:
				rpc_id(peer_id, "rpc_chat_message", sender_name, message)

# ─────────────────────────────────────────────────────────────
# Name
# ─────────────────────────────────────────────────────────────

func _on_name_changed(new_name: String) -> void:
	_my_name = new_name.strip_edges()
	if _my_name == "":
		_my_name = _default_name()
	if is_host:
		if _slots.size() > 0:
			_slots[0]["player_name"] = _my_name
		_sync_all_slots()
	else:
		rpc_id(1, "rpc_request_set_name", _my_name)

# ─────────────────────────────────────────────────────────────
# Host Setup
# ─────────────────────────────────────────────────────────────

func _setup_host() -> void:
	_status_label.text = "正在启动房间..."
	_room_title_label.text = "我的房间"
	_room_id_label.text = ""
	_room_info_label.text = "模式：%s  |  最大玩家：%d" % [mode, max_players]

	_btn_spectate.visible = false
	_ready_btn.visible = false
	_btn_add_ai.visible = true
	_start_btn.visible = true

	var err = NetworkManager.start_game_server()
	if err != OK:
		_status_label.text = "启动房间失败！端口被占用"
		return

	var ip = NetworkManager.get_local_ip()
	room_code = _gen_code()
	_room_id_label.text = "RM-%s" % room_code
	_room_info_label.text = "模式：%s  |  最大玩家：%d  |  IP：%s:7777  |  房间码：%s" % [mode, max_players, ip, room_code]

	_add_slot(1, _my_name)
	_status_label.text = "等待其他玩家加入..."
	_update_slot_display()
	_build_character_grid()

	if not NetworkManager.is_authenticated():
		await NetworkManager.login_device()
	await NetworkManager.publish_room(room_code, {
		"host_ip": ip,
		"port": 7777,
		"mode": mode,
		"name": "我的房间",
		"player_count": 1,
		"max_players": max_players,
		"room_code": room_code,
		"status": "waiting",
	})

func _add_slot(peer_id: int, player_name: String) -> void:
	_slots.append({
		"peer_id": peer_id,
		"player_name": player_name,
		"character": "",
		"is_ready": false,
		"is_ai": false,
	})

func _set_my_slot_char(char_id: String) -> void:
	if _slots.size() > 0:
		_slots[0]["character"] = char_id

# ─────────────────────────────────────────────────────────────
# Client Setup
# ─────────────────────────────────────────────────────────────

func _auto_connect_or_show_entry() -> void:
	var host_ip: String = SceneManager.last_game_config.get("host_ip", "")
	if host_ip != "":
		_status_label.text = "正在连接 %s..." % host_ip
		_btn_spectate.visible = true
		_ready_btn.visible = true
		_start_btn.visible = false
		_btn_add_ai.visible = false
		NetworkManager.connect_to_game_server(host_ip, 7777, "")
		await NetworkManager.connected_to_game_server
		_connected_to_host()
	else:
		_setup_client()

func _setup_client() -> void:
	_status_label.text = "输入房主 IP 地址加入房间"
	_room_title_label.text = "加入房间"
	_room_id_label.text = ""
	_room_info_label.text = ""

	_start_btn.visible = false
	_btn_add_ai.visible = false
	_ready_btn.visible = false
	_btn_spectate.visible = false

	var join_panel := PanelContainer.new()
	join_panel.name = "JoinPanel"
	join_panel.anchor_left = 0.5; join_panel.anchor_right = 0.5
	join_panel.anchor_top = 0.5; join_panel.anchor_bottom = 0.5
	join_panel.offset_left = -300; join_panel.offset_top = -70
	join_panel.offset_right = 300; join_panel.offset_bottom = 70
	join_panel.add_theme_stylebox_override("panel", _make_flat(C_WHITE, C_BORDER, 1, 6))
	add_child(join_panel)

	var jv := VBoxContainer.new()
	jv.add_theme_constant_override("separation", 10)
	jv.anchor_right = 1.0; jv.anchor_bottom = 1.0
	jv.offset_left = 20; jv.offset_top = 16
	jv.offset_right = -20; jv.offset_bottom = -16
	join_panel.add_child(jv)

	var jl := Label.new()
	jl.text = "加入房间"
	jl.add_theme_color_override("font_color", C_TEXT_DARK)
	jl.add_theme_font_size_override("font_size", 16)
	jl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jv.add_child(jl)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	jv.add_child(ip_row)

	var ip_input := LineEdit.new()
	ip_input.name = "IpInput"
	ip_input.placeholder_text = "输入主机 IP 地址..."
	ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_input.add_theme_font_size_override("font_size", 13)
	ip_row.add_child(ip_input)

	var connect_btn := Button.new()
	connect_btn.text = "连接"
	connect_btn.focus_mode = Control.FOCUS_NONE
	connect_btn.custom_minimum_size = Vector2(80, 0)
	connect_btn.add_theme_stylebox_override("normal", _make_flat(C_BLUE_BG, C_BLUE_TEXT, 1, 4))
	connect_btn.add_theme_color_override("font_color", C_BLUE_TEXT)
	connect_btn.add_theme_font_size_override("font_size", 13)
	connect_btn.pressed.connect(func():
		var ip = ip_input.text.strip_edges()
		if ip == "":
			return
		_status_label.text = "正在连接 %s..." % ip
		NetworkManager.connect_to_game_server(ip, 7777, "")
		await NetworkManager.connected_to_game_server
		join_panel.queue_free()
		_connected_to_host()
	)
	ip_row.add_child(connect_btn)

	var hint := Label.new()
	hint.text = "输入房主的 IP 地址后点击连接"
	hint.add_theme_color_override("font_color", C_TEXT_LIGHT)
	hint.add_theme_font_size_override("font_size", 10)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jv.add_child(hint)

	_create_btn = Button.new()
	_create_btn.name = "BtnCreateRoom"
	_create_btn.text = "创建房间"
	_create_btn.focus_mode = Control.FOCUS_NONE
	_create_btn.anchor_left = 0.5; _create_btn.anchor_right = 0.5
	_create_btn.anchor_top = 0.5; _create_btn.anchor_bottom = 0.5
	_create_btn.offset_left = -300; _create_btn.offset_top = 80
	_create_btn.offset_right = 300; _create_btn.offset_bottom = 140
	_style_accent_btn(_create_btn, C_GOLD, C_GOLD, C_GOLD_BG)
	_create_btn.pressed.connect(_on_create_room_pressed)
	add_child(_create_btn)

func _on_connect_pressed() -> void:
	pass

func _connected_to_host() -> void:
	_btn_spectate.visible = true
	_ready_btn.visible = true
	_status_label.text = "已连接！选择角色并准备"
	_build_character_grid()
	rpc_id(1, "rpc_request_set_name", _my_name)

func _on_create_room_pressed() -> void:
	is_host = true
	for child in get_children():
		if child.name == "JoinPanel" or child.name == "BtnCreateRoom":
			child.queue_free()
	if _create_btn:
		_create_btn.queue_free()
		_create_btn = null
	_setup_host()

# ─────────────────────────────────────────────────────────────
# Host Peer Management
# ─────────────────────────────────────────────────────────────

func _on_peer_connected(peer_id: int) -> void:
	if not is_host:
		return
	if _slots.size() >= max_players:
		rpc_id(peer_id, "rpc_room_full")
		return
	_add_slot(peer_id, "")
	_status_label.text = "玩家加入 (%d/%d)" % [_slots.size(), max_players]
	_update_slot_display()

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	for i in range(_slots.size()):
		if _slots[i]["peer_id"] == peer_id:
			_slots.remove_at(i)
			break
	_sync_all_slots()
	_status_label.text = "玩家离开 (%d/%d)" % [_slots.size(), max_players]
	_update_slot_display()

# ─────────────────────────────────────────────────────────────
# Host RPC Receivers
# ─────────────────────────────────────────────────────────────

@rpc("any_peer", "reliable")
func rpc_request_set_name(name: String) -> void:
	if not is_host:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	for slot in _slots:
		if slot["peer_id"] == peer_id:
			slot["player_name"] = name
			break
	_update_slot_display()
	_sync_all_slots()

@rpc("any_peer", "reliable")
func rpc_request_select_character(char_id: String) -> void:
	if not is_host:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	for slot in _slots:
		if slot["peer_id"] == peer_id:
			slot["character"] = char_id
			break
	_sync_all_slots()

@rpc("any_peer", "reliable")
func rpc_request_toggle_ready() -> void:
	if not is_host:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	for slot in _slots:
		if slot["peer_id"] == peer_id:
			slot["is_ready"] = not slot["is_ready"]
			break
	_sync_all_slots()

@rpc("any_peer", "reliable")
func rpc_request_spectate() -> void:
	if not is_host:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	rpc_id(peer_id, "rpc_spectate_ack", {"mode": mode, "max_players": max_players})

# ─────────────────────────────────────────────────────────────
# Client RPC Receivers
# ─────────────────────────────────────────────────────────────

@rpc("authority", "reliable")
func rpc_room_sync(data: Dictionary) -> void:
	_slots.clear()
	mode = data.get("mode", "ffa")
	max_players = data.get("max_players", 8)
	for s in data.get("slots", []):
		_slots.append(s)
	var code: String = data.get("room_code", "")
	if code != "" and _room_id_label != null:
		room_code = code
		_room_id_label.text = "RM-%s" % code
	_update_slot_display()

@rpc("authority", "reliable")
func rpc_room_game_starting(config: Dictionary) -> void:
	SceneManager.last_game_config = config
	SceneManager.go_to("res://scenes/main.tscn")

@rpc("authority", "reliable")
func rpc_room_full() -> void:
	_status_label.text = "房间已满！"
	NetworkManager.disconnect_from_game()

@rpc("authority", "reliable")
func rpc_spectate_ack(_info: Dictionary) -> void:
	pass

# ─────────────────────────────────────────────────────────────
# Button Handlers
# ─────────────────────────────────────────────────────────────

func _on_ready_pressed() -> void:
	_my_ready = not _my_ready
	if _slots.size() > 0:
		_slots[0]["is_ready"] = _my_ready
	if _my_ready:
		_style_btn(_ready_btn, C_GREEN_BORDER, C_GREEN_TEXT)
		_ready_btn.text = "✓ 已准备"
	else:
		_style_btn(_ready_btn, C_GREEN_BORDER, C_TEXT_MID)
		_ready_btn.text = "准 备"
	if is_host:
		_sync_all_slots()
	else:
		rpc_id(1, "rpc_request_toggle_ready")

func _on_spectate_pressed() -> void:
	is_spectator = true
	_btn_spectate.visible = false
	_ready_btn.visible = false
	_status_label.text = "观战模式 — 等待主机开始游戏"
	rpc_id(1, "rpc_request_spectate")

func _on_add_ai_pressed() -> void:
	if not is_host or _slots.size() >= max_players:
		return
	var ai_name = "AI-%d" % (_slots.size() + 1)
	var ai_char = Characters.LIST[randi() % Characters.LIST.size()]["id"]
	_slots.append({
		"peer_id": -(_slots.size() + 10),
		"player_name": ai_name,
		"character": ai_char,
		"is_ready": true,
		"is_ai": true,
	})
	_sync_all_slots()
	_update_slot_display()
	_status_label.text = "已添加 %s (%d/%d)" % [ai_name, _slots.size(), max_players]

func _on_start_pressed() -> void:
	if not is_host:
		return
	var min_needed: int = GAME_MODES.get(mode, GAME_MODES["ffa"])["min_players"]
	if _slots.size() < min_needed:
		_status_label.text = "模式 [%s] 需要至少 %d 名玩家" % [mode, min_needed]
		return
	if not _all_ready():
		_status_label.text = "等待所有玩家准备就绪..."
		return

	var players = []
	for i in range(_slots.size()):
		var slot = _slots[i]
		var char_data = Characters.get_by_id(slot["character"])
		if char_data.is_empty():
			char_data = Characters.LIST[randi() % Characters.LIST.size()]
		var char_res = load(char_data.get("res_path", "")) if char_data.get("res_path", "") != "" else null
		if char_res == null:
			char_res = load(Characters.LIST[0]["res_path"])
		var team_id := 0
		var tc: int = GAME_MODES.get(mode, GAME_MODES["ffa"])["team_count"]
		if tc > 0:
			var per_team: int = max(1, max_players / tc)
			team_id = (i / per_team) + 1
		players.append({
			"id": i,
			"name": slot["player_name"],
			"is_human": not slot["is_ai"],
			"character": char_res,
			"team_id": team_id,
			"peer_id": slot["peer_id"],
		})

	var game_config = {
		"mode": mode,
		"max_players": max_players,
		"players": players,
		"is_network": true,
		"is_host": true,
	}

	for i in range(_slots.size()):
		var slot = _slots[i]
		if slot["peer_id"] > 1:
			var client_config = game_config.duplicate(true)
			client_config["my_player_id"] = i
			client_config["is_host"] = false
			rpc_id(slot["peer_id"], "rpc_room_game_starting", client_config)

	var old_host = NetworkManager.get_node_or_null("CurrentGameHost")
	if old_host:
		old_host.queue_free()
		await get_tree().process_frame

	var host = preload("res://core/net/NetworkGameHost.gd").new()
	host.name = "CurrentGameHost"
	host.room_config = game_config
	NetworkManager.add_child(host)

	SceneManager.last_game_config = game_config
	SceneManager.go_to("res://scenes/main.tscn")

func _on_back_pressed() -> void:
	if is_host:
		NetworkManager.stop_game_server()
		NetworkManager.unpublish_room(room_code)
	else:
		NetworkManager.disconnect_from_game()
	SceneManager.go_to("res://scenes/net/lobby.tscn")

# ─────────────────────────────────────────────────────────────
# Slot / Sync Helpers
# ─────────────────────────────────────────────────────────────

func _all_ready() -> bool:
	var min_needed: int = GAME_MODES.get(mode, GAME_MODES["ffa"])["min_players"]
	if _slots.size() < min_needed:
		return false
	for slot in _slots:
		if slot["peer_id"] == 1:
			continue
		if not slot["is_ready"] and not slot["is_ai"]:
			return false
	return true

func _sync_all_slots() -> void:
	if not is_host:
		return
	_update_slot_display()
	for slot in _slots:
		var peer_id = slot["peer_id"]
		if peer_id > 1:
			rpc_id(peer_id, "rpc_room_sync", _serialize_slots())

func _serialize_slots() -> Dictionary:
	var result = {"slots": [], "mode": mode, "max_players": max_players, "room_code": room_code}
	for slot in _slots:
		result["slots"].append({
			"player_name": slot["player_name"],
			"character": slot["character"],
			"is_ready": slot["is_ready"],
			"is_ai": slot["is_ai"],
		})
	return result

func _gen_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code
