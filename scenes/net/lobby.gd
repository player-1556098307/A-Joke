## Lobby — 房间列表大厅页（场景树驱动，节点结构见 lobby.tscn）
extends Control

const PAGE_SIZE := 8

var _rooms: Array = []
var _current_page: int = 0
var _search_text: String = ""
var _mode_filter: String = "all"

# ── 节点引用 ──
@onready var _search_input: LineEdit     = $SearchRow/SearchInput
@onready var _list_vbox: VBoxContainer   = $RoomListScroll/ListVBox
@onready var _empty_row: Control         = $RoomListScroll/ListVBox/EmptyRow
@onready var _page_label: Label          = $BottomBar/BtnRow/PaginationRow/PageLabel
@onready var _btn_prev: Button           = $BottomBar/BtnRow/PaginationRow/BtnPrev
@onready var _btn_next: Button           = $BottomBar/BtnRow/PaginationRow/BtnNext
@onready var _status_label: Label        = $BottomBar/BtnRow/StatusLabel
@onready var _filter_btns: Array[Button] = [
	$TopBar/FilterRow/BtnAll,
	$TopBar/FilterRow/BtnFFA,
	$TopBar/FilterRow/Btn2v2,
]

# ── 颜色常量（仅供动态创建的行节点使用）──
const C_TEXT_DARK   := Color("#2a2418")
const C_TEXT_MID    := Color("#888480")
const C_BORDER      := Color("#dedad0")
const C_WHITE       := Color("#ffffff")
const C_RED_BG      := Color("#fdf0f0")
const C_RED_BORDER  := Color("#993556")
const C_RED_TEXT    := Color("#993556")
const C_GREEN_BG    := Color("#edf8f0")
const C_GREEN_TEXT  := Color("#3b7a40")
const C_BLUE_BG     := Color("#eef4fb")
const C_BLUE_TEXT   := Color("#2a6ab0")
const C_GOLD        := Color("#c8860a")
const C_GOLD_BG     := Color("#fdf6e8")

# ─────────────────────────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_ui_signals()
	_refresh_filter_styles()
	await _ensure_session()
	_refresh_rooms()

func _ensure_session() -> void:
	if NetworkManager.is_authenticated():
		return
	_status_label.text = "正在连接服务器..."
	await NetworkManager.login_device()
	if not NetworkManager.is_authenticated():
		_status_label.text = "连接失败，请检查 Nakama 是否运行"

func _connect_ui_signals() -> void:
	$SearchRow/SearchInput.text_changed.connect(_on_search_changed)
	$SearchRow/BtnSearch.pressed.connect(_on_search_pressed)
	$SearchRow/BtnCreate.pressed.connect(_on_create_room_pressed)
	$BottomBar/BtnRow/BtnBack.pressed.connect(_on_back_pressed)
	$BottomBar/BtnRow/BtnRefresh.pressed.connect(_refresh_rooms)
	$BottomBar/BtnRow/PaginationRow/BtnPrev.pressed.connect(_on_prev_page)
	$BottomBar/BtnRow/PaginationRow/BtnNext.pressed.connect(_on_next_page)
	$TopBar/FilterRow/BtnAll.pressed.connect(func(): _on_mode_filter("all"))
	$TopBar/FilterRow/BtnFFA.pressed.connect(func(): _on_mode_filter("ffa"))
	$TopBar/FilterRow/Btn2v2.pressed.connect(func(): _on_mode_filter("2v2"))

# ─────────────────────────────────────────────────────────────
# 房间列表渲染
# ─────────────────────────────────────────────────────────────

func _build_room_rows() -> void:
	for child in _list_vbox.get_children():
		if child.name != "EmptyRow":
			child.queue_free()

	var filtered: Array = _rooms.filter(func(r):
		var ok_search: bool = _search_text == "" or r.get("name","").to_lower().contains(_search_text.to_lower())
		var ok_mode: bool   = _mode_filter == "all" or r.get("mode","") == _mode_filter
		return ok_search and ok_mode
	)

	var total_pages: int = max(1, ceili(float(filtered.size()) / PAGE_SIZE))
	_current_page = min(_current_page, total_pages - 1)

	if filtered.is_empty():
		_empty_row.visible = true
		_update_pagination(0, 0)
		return

	_empty_row.visible = false
	var start := _current_page * PAGE_SIZE
	for i in range(start, min(start + PAGE_SIZE, filtered.size())):
		_list_vbox.add_child(_make_room_row(filtered[i]))

	_update_pagination(filtered.size(), total_pages)

func _make_room_row(data: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 36)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rs := StyleBoxFlat.new()
	rs.bg_color = C_WHITE
	rs.border_color = C_BORDER
	rs.set_border_width_all(1)
	rs.set_corner_radius_all(3)
	row.add_theme_stylebox_override("panel", rs)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.anchor_right = 1.0; hbox.anchor_bottom = 1.0
	hbox.offset_left = 8; hbox.offset_right = -8
	row.add_child(hbox)

	_row_label(hbox, data.get("name", data.get("room_code","???")), C_TEXT_DARK, 13, 2.5)
	_row_label(hbox, _truncate(data.get("host_user_id","---"), 10), C_TEXT_MID, 11, 1.5)
	var mode_map := {"ffa":"自由对战","2v2":"2v2团队"}
	_row_label(hbox, mode_map.get(data.get("mode",""), "?"), C_TEXT_MID, 11, 1.0)
	_row_label(hbox, "%d/%d" % [data.get("player_count",1), data.get("max_players",8)], C_TEXT_MID, 11, 0.8)

	var badge_wrap := Control.new()
	badge_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_wrap.custom_minimum_size = Vector2(0, 36)
	hbox.add_child(badge_wrap)
	var badge := _make_status_badge(data.get("status","waiting"))
	badge.anchor_top = 0.5; badge.anchor_bottom = 0.5
	badge.offset_top = -11; badge.offset_bottom = 11
	badge_wrap.add_child(badge)

	var status: String = data.get("status","waiting")
	var pc: int = data.get("player_count",1)
	var mc: int = data.get("max_players",8)
	var can_join := status == "waiting" and pc < mc
	var btn := Button.new()
	btn.text = "加入" if can_join else ("观战" if status == "playing" else "已满")
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(60, 26)
	btn.disabled = (status == "full")
	var bs := StyleBoxFlat.new()
	var btn_color := C_GREEN_TEXT if can_join else (C_BLUE_TEXT if status == "playing" else C_TEXT_MID)
	bs.bg_color = C_WHITE; bs.border_color = btn_color
	bs.set_border_width_all(1); bs.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_color_override("font_color", btn_color)
	btn.add_theme_font_size_override("font_size", 11)
	if can_join:
		btn.pressed.connect(func(): _on_join_room(data))
	elif status == "playing":
		btn.pressed.connect(func(): _on_spectate_room(data))
	hbox.add_child(btn)

	return row

func _row_label(parent: Control, text: String, color: Color, size: int, ratio: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_stretch_ratio = ratio
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

func _make_status_badge(status: String) -> PanelContainer:
	var c := PanelContainer.new()
	c.offset_right = 62
	var s := StyleBoxFlat.new()
	match status:
		"waiting": s.bg_color = C_GREEN_BG; s.border_color = C_GREEN_TEXT
		"full":    s.bg_color = C_RED_BG;   s.border_color = C_RED_BORDER
		"playing": s.bg_color = C_BLUE_BG;  s.border_color = C_BLUE_TEXT
		_:         s.bg_color = Color("#f5f2eb"); s.border_color = C_BORDER
	s.set_border_width_all(1); s.set_corner_radius_all(3)
	c.add_theme_stylebox_override("panel", s)
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 10)
	match status:
		"waiting": lbl.text = "等待中"; lbl.add_theme_color_override("font_color", C_GREEN_TEXT)
		"full":    lbl.text = "已满";   lbl.add_theme_color_override("font_color", C_RED_TEXT)
		"playing": lbl.text = "游戏中"; lbl.add_theme_color_override("font_color", C_BLUE_TEXT)
	lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	c.add_child(lbl)
	return c

func _update_pagination(total: int, pages: int) -> void:
	_status_label.text = "共 %d 个房间" % total if total > 0 else "暂无房间"
	_page_label.text = "第 %d / %d 页" % [_current_page + 1, max(1, pages)]
	_btn_prev.disabled = _current_page <= 0
	_btn_next.disabled = _current_page >= pages - 1

func _refresh_filter_styles() -> void:
	var modes := ["all", "ffa", "2v2"]
	for i in range(_filter_btns.size()):
		var btn: Button = _filter_btns[i]
		var active: bool = modes[i] == _mode_filter
		var s := StyleBoxFlat.new()
		if active:
			s.bg_color = Color("#1e1a10"); s.border_color = C_GOLD; s.border_width_left = 3
		else:
			s.bg_color = Color(0,0,0,0); s.border_color = C_GOLD; s.set_border_width_all(1)
		s.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", s)
		btn.add_theme_color_override("font_color", Color("#f5c842") if active else C_GOLD)

# ─────────────────────────────────────────────────────────────
# 数据
# ─────────────────────────────────────────────────────────────

func _refresh_rooms() -> void:
	if not NetworkManager.is_authenticated():
		_status_label.text = "未连接到服务器"; return
	_status_label.text = "正在刷新..."
	_rooms = await NetworkManager.list_rooms()
	_build_room_rows()

# ─────────────────────────────────────────────────────────────
# 回调
# ─────────────────────────────────────────────────────────────

func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges(); _current_page = 0; _build_room_rows()

func _on_search_pressed() -> void:
	_current_page = 0; _build_room_rows()

func _on_mode_filter(mode: String) -> void:
	_mode_filter = mode; _current_page = 0; _refresh_filter_styles(); _build_room_rows()

func _on_prev_page() -> void:
	if _current_page > 0: _current_page -= 1; _build_room_rows()

func _on_next_page() -> void:
	_current_page += 1; _build_room_rows()

func _on_join_room(data: Dictionary) -> void:
	var player_name := ""
	if NetworkManager._session != null:
		player_name = NetworkManager._session.username
	SceneManager.last_game_config = {
		"mode": data.get("mode","ffa"), "max_players": data.get("max_players",8),
		"team_size": data.get("team_size",0), "is_network": true, "is_host": false,
		"player_name": player_name, "host_ip": data.get("host_ip","8.130.49.62"),
		"port": data.get("port",7777),
	}
	SceneManager.go_to("res://scenes/net/room.tscn")

func _on_spectate_room(data: Dictionary) -> void:
	_on_join_room(data)

func _on_create_room_pressed() -> void:
	_show_mode_picker()

func _show_mode_picker() -> void:
	var screen := get_viewport_rect().size
	var overlay := ColorRect.new()
	overlay.color = Color(0,0,0,0.45)
	overlay.position = Vector2.ZERO; overlay.size = screen
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 230)
	panel.position = (screen - Vector2(340,230)) / 2.0
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("#f5f2eb"); ps.border_color = C_GOLD
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", ps)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择游戏模式"
	title.add_theme_color_override("font_color", Color("#2a2418"))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for m in [["ffa","自由对战","2–4 人混战"],["2v2","2v2 团队","固定 4 人 2 队"]]:
		var btn := Button.new()
		btn.text = "%-6s  ·  %s" % [m[1], m[2]]
		btn.focus_mode = Control.FOCUS_NONE
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#fdf6e8"); bs.border_color = C_GOLD
		bs.set_border_width_all(1); bs.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_color_override("font_color", C_GOLD)
		btn.add_theme_font_size_override("font_size", 13)
		var mode_id: String = m[0]
		btn.pressed.connect(func(): overlay.queue_free(); _launch_create_room(mode_id))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "取消"; cancel.focus_mode = Control.FOCUS_NONE
	var cs := StyleBoxFlat.new()
	cs.bg_color = C_WHITE; cs.border_color = C_BORDER
	cs.set_border_width_all(1); cs.set_corner_radius_all(4)
	cancel.add_theme_stylebox_override("normal", cs)
	cancel.add_theme_color_override("font_color", C_TEXT_MID)
	cancel.add_theme_font_size_override("font_size", 12)
	cancel.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(cancel)

func _launch_create_room(selected_mode: String) -> void:
	var player_name := ""
	if NetworkManager._session != null:
		player_name = NetworkManager._session.username
	SceneManager.last_game_config = {
		"mode": selected_mode, "max_players": {"ffa":4,"2v2":4}.get(selected_mode,4),
		"is_network": true, "is_host": true, "player_name": player_name,
	}
	SceneManager.go_to("res://scenes/net/room.tscn")

func _on_back_pressed() -> void:
	SceneManager.go_to("res://scenes/main_menu.tscn")

func _truncate(s: String, max_len: int) -> String:
	return s if s.length() <= max_len else s.left(max_len - 1) + "…"
