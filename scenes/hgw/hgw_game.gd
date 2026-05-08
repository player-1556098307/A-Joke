## HGW Game — dark-fantasy hex map viewer
## Renders the single-continent map with beveled hexes, tooltips, and reveal animation
extends Control

# ── Dark fantasy palette ──────────────────────────────────────────────────────

const C_BG       := Color("#FFFDF5")
const C_PANEL_BG := Color("#F1EFE8")
const C_PANEL_BDR:= Color("#D3D1C7")
const C_GOLD     := Color("#C9A84C")
const C_GOLD_BRT := Color("#BA7517")
const C_TEXT     := Color("#2C2C2A")
const C_TEXT_DIM := Color("#5F5E5A")

# ── Parameters ────────────────────────────────────────────────────────────────

@export var LAND_THRESHOLD   := 0.38
@export var EDGE_DETAIL_AMP  := 0.08
@export var ELEVATION_FREQ   := 0.10
@export var MOISTURE_FREQ    := 0.12
@export var FORTRESS_COUNT   := 6
@export var NUM_PLAYERS      := 8
@export var MAP_RADIUS       := 18

var _hex_size := 18.0
var _cells: Dictionary = {}
var _radius: int
var _seed_val: int
var _stats: Dictionary = {}
var _spawns: Array[Vector2i] = []

# ── UI state ──────────────────────────────────────────────────────────────────

var _param_labels: Dictionary = {}
var _header_seed_label: Label
var _status_text_label: Label
var _zoom_label: Label
var _tooltip_panel: PanelContainer
var _tooltip_labels: Array[Label] = []
var _hovered_hex := Vector2i(-999, -999)
var _reveal_data: Dictionary = {}
var _reveal_tween: Tween
var _first_load := true

const RING_DELAY := 0.04
const CELL_DURATION := 0.15

# ── Startup ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	randomize()
	_seed_val = randi() % 99999 + 1
	_setup_ui()
	_generate_map()
	queue_redraw()

func _setup_ui() -> void:
	_build_background_layer()
	_build_header_bar()
	_build_legend()
	_build_control_panel()
	_build_status_bar()
	_build_tooltip_panel()

# ── Background ────────────────────────────────────────────────────────────────

func _build_background_layer() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

func _draw_background_art() -> void:
	var vp: Rect2 = get_viewport().get_visible_rect()
	var w: float = vp.size.x
	var h: float = vp.size.y

	var hex_color: Color = C_PANEL_BDR * Color(1, 1, 1, 0.2)
	var step: float = _hex_size * 1.8
	var row_h: float = step * 0.866
	var y: float = fmod(-_hex_size * 3.0, row_h)
	var row: int = 0
	while y < h + row_h:
		var offset: float = 0.0 if row % 2 == 0 else step * 0.5
		var x: float = fmod(-step, step) + offset
		while x < w + step:
			var pts: PackedVector2Array = _hex_vertices_static(x, y, step * 0.48)
			draw_polyline(pts + PackedVector2Array([pts[0]]), hex_color, 0.5, true)
			x += step
		y += row_h
		row += 1

	var center: Vector2 = vp.position + vp.size / 2.0
	var vignette_r: float = maxf(w, h) * 0.75
	for i: int in range(8):
		var t: float = 1.0 - float(i) / 8.0
		var r: float = vignette_r * (1.0 - t * 0.35)
		draw_circle(center, r, Color(0, 0, 0, t * t * 0.06))

	var margin: float = 32.0
	var arc_r: float = 14.0
	var arc_color: Color = C_PANEL_BDR * Color(1, 1, 1, 0.3)
	var corners: Array[Dictionary] = [
		{"pos": Vector2(margin, margin),         "start": 180.0},
		{"pos": Vector2(w - margin, margin),     "start": 270.0},
		{"pos": Vector2(w - margin, h - margin), "start": 0.0},
		{"pos": Vector2(margin, h - margin),     "start": 90.0},
	]
	for c: Dictionary in corners:
		var pos: Vector2 = c["pos"]
		var start_deg: float = c["start"]
		draw_arc(pos, arc_r,       deg_to_rad(start_deg), deg_to_rad(start_deg + 90.0), 8, arc_color, 1.5, true)
		draw_arc(pos, arc_r * 0.6, deg_to_rad(start_deg), deg_to_rad(start_deg + 90.0), 8, arc_color, 1.0, true)

# ── Header bar ────────────────────────────────────────────────────────────────

func _build_header_bar() -> void:
	var bar := PanelContainer.new()
	bar.layout_mode = 1
	bar.anchor_left = 0.0
	bar.anchor_top = 0.0
	bar.anchor_right = 1.0
	bar.offset_bottom = 38.0
	bar.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	bar.add_child(hbox)

	var title := Label.new()
	title.text = "圣杯战争"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", C_GOLD_BRT)
	hbox.add_child(title)

	var divider := Label.new()
	divider.text = "·"
	divider.add_theme_font_size_override("font_size", 14)
	divider.add_theme_color_override("font_color", C_GOLD * Color(1, 1, 1, 0.5))
	hbox.add_child(divider)

	var subtitle := Label.new()
	subtitle.text = "六边形战场"
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", C_TEXT_DIM)
	hbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var seed_panel := PanelContainer.new()
	var seed_style := StyleBoxFlat.new()
	seed_style.bg_color = Color("#2C2C2A")
	seed_style.border_color = C_GOLD * Color(1, 1, 1, 0.4)
	seed_style.set_border_width_all(1)
	seed_style.set_corner_radius_all(12)
	seed_style.content_margin_left = 10.0
	seed_style.content_margin_right = 10.0
	seed_style.content_margin_top = 2.0
	seed_style.content_margin_bottom = 2.0
	seed_panel.add_theme_stylebox_override("panel", seed_style)
	hbox.add_child(seed_panel)

	_header_seed_label = Label.new()
	_header_seed_label.add_theme_font_size_override("font_size", 10)
	_header_seed_label.add_theme_color_override("font_color", C_GOLD)
	_header_seed_label.text = "Seed: %d" % _seed_val
	seed_panel.add_child(_header_seed_label)

# ── Legend ────────────────────────────────────────────────────────────────────

func _build_legend() -> void:
	var panel := PanelContainer.new()
	panel.layout_mode = 0
	panel.offset_left = 8.0
	panel.offset_top = 46.0
	panel.offset_right = 170.0
	panel.offset_bottom = 420.0
	panel.add_theme_stylebox_override("panel",
		_make_flat(C_PANEL_BG * Color(1, 1, 1, 0.85), C_PANEL_BDR * Color(1, 1, 1, 0.5), 1, 6))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	vbox.add_child(_make_section_header("图 例"))

	_add_legend_group(vbox, "地貌", [
		["平原", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.PLAIN)],
		["森林", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.FOREST)],
		["高地", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.HIGHLAND)],
		["山脉", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.MOUNTAIN)],
		["要塞", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.FORTRESS)],
		["沙漠", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.DESERT)],
		["雪地", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.SNOW)],
	])

	_add_section_divider(vbox)

	_add_legend_group(vbox, "特殊", [
		["圣杯台座", HGWMapGenerator.terrain_color(HGWMapGenerator.Terrain.GRAIL)],
		["出生点",   Color(0.863, 0.235, 0.235, 0.85)],
		["钥匙",     Color(1.0,   0.843, 0.0,   0.85)],
		["资源·普通", Color(0.314, 0.706, 1.0,   0.85)],
		["资源·稀有", Color(0.706, 0.314, 1.0,   0.85)],
		["资源·核心", Color(1.0,   0.314, 0.314, 0.85)],
		["奖励池",   Color(1.0,   0.843, 0.0,   0.6)],
		["要道",     Color(1.0,   0.471, 0.157, 0.8)],
	])

func _add_legend_group(parent: VBoxContainer, group_name: String, items: Array) -> void:
	var hdr := Label.new()
	hdr.text = group_name
	hdr.add_theme_font_size_override("font_size", 9)
	hdr.add_theme_color_override("font_color", C_GOLD * Color(1, 1, 1, 0.7))
	parent.add_child(hdr)

	for item: Array in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		parent.add_child(row)

		var swatch := PanelContainer.new()
		swatch.custom_minimum_size = Vector2(12, 12)
		var sw_style := StyleBoxFlat.new()
		sw_style.bg_color = item[1]
		sw_style.set_corner_radius_all(2)
		swatch.add_theme_stylebox_override("panel", sw_style)
		row.add_child(swatch)

		var lbl := Label.new()
		lbl.text = item[0]
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		row.add_child(lbl)

func _add_section_divider(parent: VBoxContainer) -> void:
	var row_div := HBoxContainer.new()
	row_div.add_theme_constant_override("separation", 4)
	parent.add_child(row_div)

	var l_style := StyleBoxFlat.new()
	l_style.bg_color = C_PANEL_BDR * Color(1, 1, 1, 0.4)

	var line1 := Control.new()
	line1.custom_minimum_size = Vector2(0, 1)
	line1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_theme_stylebox_override("panel", l_style)
	row_div.add_child(line1)

	var diamond := Label.new()
	diamond.text = "◇"
	diamond.add_theme_font_size_override("font_size", 6)
	diamond.add_theme_color_override("font_color", C_GOLD * Color(1, 1, 1, 0.5))
	row_div.add_child(diamond)

	var line2 := Control.new()
	line2.custom_minimum_size = Vector2(0, 1)
	line2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line2.add_theme_stylebox_override("panel", l_style)
	row_div.add_child(line2)

func _make_section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", C_GOLD)
	return lbl

# ── Control panel ─────────────────────────────────────────────────────────────

func _build_control_panel() -> void:
	var panel := PanelContainer.new()
	panel.layout_mode = 1
	panel.anchor_left = 1.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -210.0
	panel.offset_top = 46.0
	panel.offset_right = -8.0
	panel.offset_bottom = -42.0
	panel.add_theme_stylebox_override("panel",
		_make_flat(C_PANEL_BG * Color(1, 1, 1, 0.85), C_PANEL_BDR * Color(1, 1, 1, 0.5), 1, 6))
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	vbox.add_child(_make_section_header("圣杯战争 · 参数"))

	var uline := Control.new()
	uline.custom_minimum_size = Vector2(0, 1)
	var ul_style := StyleBoxFlat.new()
	ul_style.bg_color = C_GOLD * Color(1, 1, 1, 0.4)
	uline.add_theme_stylebox_override("panel", ul_style)
	vbox.add_child(uline)

	vbox.add_child(_make_spacer(4))

	var params: Array[Dictionary] = [
		{"label": "大陆阈值", "name": "LAND_THRESHOLD",  "val": LAND_THRESHOLD,  "min": 0.25, "max": 0.55, "step": 0.01},
		{"label": "海岸细节", "name": "EDGE_DETAIL_AMP", "val": EDGE_DETAIL_AMP, "min": 0.02, "max": 0.20, "step": 0.01},
		{"label": "地形频率", "name": "ELEVATION_FREQ",  "val": ELEVATION_FREQ,  "min": 0.05, "max": 0.25, "step": 0.01},
		{"label": "湿度频率", "name": "MOISTURE_FREQ",   "val": MOISTURE_FREQ,   "min": 0.06, "max": 0.30, "step": 0.01},
		{"label": "要塞数量", "name": "FORTRESS_COUNT",  "val": FORTRESS_COUNT,  "min": 2.0,  "max": 10.0, "step": 1.0},
		{"label": "玩家数量", "name": "NUM_PLAYERS",     "val": NUM_PLAYERS,     "min": 3.0,  "max": 8.0,  "step": 1.0},
		{"label": "地图半径", "name": "MAP_RADIUS",      "val": MAP_RADIUS,      "min": 8.0,  "max": 24.0, "step": 1.0},
	]

	for entry: Dictionary in params:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var name_lbl := Label.new()
		name_lbl.text = entry["label"]
		name_lbl.custom_minimum_size = Vector2(50, 0)
		name_lbl.add_theme_font_size_override("font_size", 9)
		name_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		row.add_child(name_lbl)

		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(90, 0)
		slider.min_value = entry["min"]
		slider.max_value = entry["max"]
		slider.step     = entry["step"]
		slider.value    = entry["val"]
		_style_slider(slider)
		row.add_child(slider)

		var val_lbl := Label.new()
		val_lbl.custom_minimum_size = Vector2(34, 0)
		val_lbl.add_theme_font_size_override("font_size", 9)
		val_lbl.add_theme_color_override("font_color", C_TEXT)
		val_lbl.text = _fmt_val(entry["name"], entry["val"])
		row.add_child(val_lbl)

		var param_name: String = entry["name"]
		_param_labels[param_name] = val_lbl
		slider.value_changed.connect(func(v: float): _on_param_changed(v, param_name))

	vbox.add_child(_make_spacer(8))

	var gen_btn := Button.new()
	gen_btn.text = "重铸地图"
	gen_btn.custom_minimum_size = Vector2(0, 34)
	gen_btn.add_theme_font_size_override("font_size", 13)
	gen_btn.add_theme_color_override("font_color", C_GOLD_BRT)
	gen_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	gen_btn.add_theme_color_override("font_pressed_color", C_GOLD)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color("#F1EFE8")
	btn_normal.border_color = C_GOLD * Color(1, 1, 1, 0.5)
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(8)
	btn_normal.content_margin_top = 6.0
	btn_normal.content_margin_bottom = 6.0
	gen_btn.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover: StyleBoxFlat = btn_normal.duplicate()
	btn_hover.bg_color = Color("#E6E2D4")
	btn_hover.border_color = C_GOLD
	btn_hover.set_border_width_all(2)
	gen_btn.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed: StyleBoxFlat = btn_normal.duplicate()
	btn_pressed.bg_color = Color("#D3D1C7")
	btn_pressed.border_color = C_GOLD * Color(1, 1, 1, 0.3)
	gen_btn.add_theme_stylebox_override("pressed", btn_pressed)

	gen_btn.pressed.connect(_on_refresh_pressed)
	vbox.add_child(gen_btn)

func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#F1EFE8")
	track.border_color = C_PANEL_BDR
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	slider.add_theme_stylebox_override("slider", track)

	var grab := StyleBoxFlat.new()
	grab.bg_color = C_GOLD
	grab.border_color = C_GOLD * Color(1, 1, 1, 0.6)
	grab.set_border_width_all(1)
	grab.set_corner_radius_all(5)
	slider.add_theme_stylebox_override("grabber", grab)
	slider.add_theme_stylebox_override("grabber_highlight", grab)

func _on_param_changed(value: float, param_name: String) -> void:
	match param_name:
		"LAND_THRESHOLD":  LAND_THRESHOLD  = value
		"EDGE_DETAIL_AMP": EDGE_DETAIL_AMP = value
		"ELEVATION_FREQ":  ELEVATION_FREQ  = value
		"MOISTURE_FREQ":   MOISTURE_FREQ   = value
		"FORTRESS_COUNT":  FORTRESS_COUNT  = int(value)
		"NUM_PLAYERS":     NUM_PLAYERS     = int(value)
		"MAP_RADIUS":      MAP_RADIUS      = int(value)

	if _param_labels.has(param_name):
		(_param_labels[param_name] as Label).text = _fmt_val(param_name, value)

	_seed_val = randi() % 99999 + 1
	_generate_map()
	queue_redraw()

func _fmt_val(name: String, v: float) -> String:
	if name in ["FORTRESS_COUNT", "NUM_PLAYERS", "MAP_RADIUS"]:
		return "%d" % int(v)
	return "%.2f" % v

# ── Status bar ────────────────────────────────────────────────────────────────

func _build_status_bar() -> void:
	var bar := PanelContainer.new()
	bar.layout_mode = 1
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -38.0
	bar.add_theme_stylebox_override("panel", _make_flat(C_PANEL_BG, C_PANEL_BDR, 1, 0))
	add_child(bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	bar.add_child(hbox)

	var back_btn := Button.new()
	back_btn.text = "← 返回"
	back_btn.custom_minimum_size = Vector2(80, 28)
	back_btn.add_theme_font_size_override("font_size", 11)
	back_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	back_btn.add_theme_color_override("font_hover_color", C_TEXT)
	back_btn.pressed.connect(_on_back_pressed)
	_style_small_btn(back_btn)
	hbox.add_child(back_btn)

	var ref_btn := Button.new()
	ref_btn.text = "新地图 (R)"
	ref_btn.custom_minimum_size = Vector2(88, 28)
	ref_btn.add_theme_font_size_override("font_size", 11)
	ref_btn.add_theme_color_override("font_color", C_GOLD)
	ref_btn.add_theme_color_override("font_hover_color", C_GOLD_BRT)
	ref_btn.pressed.connect(_on_refresh_pressed)
	_style_small_btn(ref_btn)
	hbox.add_child(ref_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_status_text_label = Label.new()
	_status_text_label.add_theme_font_size_override("font_size", 9)
	_status_text_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_status_text_label.text = ""
	hbox.add_child(_status_text_label)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer2)

	var zoom_lbl := Label.new()
	zoom_lbl.text = "缩放:"
	zoom_lbl.add_theme_font_size_override("font_size", 10)
	zoom_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	hbox.add_child(zoom_lbl)

	var zslider := HSlider.new()
	zslider.custom_minimum_size = Vector2(100, 0)
	zslider.min_value = 6.0
	zslider.max_value = 40.0
	zslider.step = 2.0
	zslider.value = _hex_size
	_style_slider(zslider)
	hbox.add_child(zslider)

	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(36, 0)
	_zoom_label.add_theme_font_size_override("font_size", 10)
	_zoom_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_zoom_label.text = "%.0f" % _hex_size
	hbox.add_child(_zoom_label)

	zslider.value_changed.connect(func(v: float):
		_hex_size = v
		_zoom_label.text = "%.0f" % v
		queue_redraw())

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

# ── Tooltip panel ─────────────────────────────────────────────────────────────

func _build_tooltip_panel() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt_style := StyleBoxFlat.new()
	tt_style.bg_color = Color("#FFFDF5", 0.96)
	tt_style.border_color = C_GOLD * Color(1, 1, 1, 0.5)
	tt_style.set_border_width_all(1)
	tt_style.set_corner_radius_all(6)
	tt_style.content_margin_left = 8.0
	tt_style.content_margin_top = 5.0
	tt_style.content_margin_right = 8.0
	tt_style.content_margin_bottom = 5.0
	_tooltip_panel.add_theme_stylebox_override("panel", tt_style)
	add_child(_tooltip_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	_tooltip_panel.add_child(vbox)

	for _i: int in range(6):
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", C_TEXT)
		vbox.add_child(lbl)
		_tooltip_labels.append(lbl)

func _update_tooltip(screen_pos: Vector2) -> void:
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var screen_center: Vector2 = vp_rect.position + vp_rect.size / 2.0
	var local_pos: Vector2 = screen_pos - screen_center
	var hex: Vector2i = _pixel_to_hex(local_pos)
	if hex == _hovered_hex:
		return

	_hovered_hex = hex

	if not _cells.has(hex):
		_tooltip_panel.visible = false
		return

	var cell: HGWMapGenerator.Cell = _cells[hex]
	if cell.is_void:
		_tooltip_panel.visible = false
		return

	var lines: Array[String] = []
	lines.append(_terrain_display_name(cell.terrain))
	lines.append("坐标 (%d, %d)" % [cell.q, cell.r])
	lines.append("海拔 %.2f · 湿度 %.2f" % [cell.elevation, cell.moisture])
	var effect_text := _terrain_effect_description(cell.terrain)
	if effect_text != "":
		lines.append(effect_text)

	var flags: Array[String] = []
	if cell.is_grail:    flags.append("圣杯台座")
	if cell.is_city:     flags.append("出生点")
	if cell.is_key:      flags.append("钥匙")
	if cell.is_resource: flags.append("资源(%s)" % _tier_name(cell.res_tier))
	if cell.is_reward:   flags.append("奖励池")
	if cell.is_choke:    flags.append("战略要道")
	if not flags.is_empty():
		lines.append(" · ".join(flags))

	for i: int in range(_tooltip_labels.size()):
		if i < lines.size():
			_tooltip_labels[i].text = lines[i]
			_tooltip_labels[i].visible = true
		else:
			_tooltip_labels[i].visible = false

	var tt_w: float = 150.0
	var tt_h: float = float(lines.size()) * 15.0 + 12.0
	var tx: float = screen_pos.x + 14.0
	var ty: float = screen_pos.y - tt_h - 8.0
	if tx + tt_w > vp_rect.position.x + vp_rect.size.x - 8:
		tx = screen_pos.x - tt_w - 14.0
	if ty < vp_rect.position.y + 8:
		ty = screen_pos.y + 14.0
	_tooltip_panel.position = Vector2(tx, ty)
	_tooltip_panel.visible = true

func _terrain_display_name(t: int) -> String:
	match t:
		HGWMapGenerator.Terrain.VOID:     return "虚空"
		HGWMapGenerator.Terrain.PLAIN:    return "平原"
		HGWMapGenerator.Terrain.FOREST:   return "森林"
		HGWMapGenerator.Terrain.HIGHLAND: return "高地"
		HGWMapGenerator.Terrain.MOUNTAIN: return "山脉"
		HGWMapGenerator.Terrain.FORTRESS: return "要塞"
		HGWMapGenerator.Terrain.GRAIL:    return "圣杯台座"
		HGWMapGenerator.Terrain.DESERT:   return "沙漠"
		HGWMapGenerator.Terrain.SNOW:     return "雪地"
	return "?"

func _terrain_effect_description(t: int) -> String:
	match t:
		HGWMapGenerator.Terrain.FOREST:   return "效果: 潜行 — 此地形上的单位无法被攻击"
		HGWMapGenerator.Terrain.HIGHLAND: return "效果: 高地 — 攻击距离+1"
		HGWMapGenerator.Terrain.MOUNTAIN: return "效果: 山脉 — 受到伤害-1"
		HGWMapGenerator.Terrain.FORTRESS: return "效果: 要塞 — 受到伤害减半，首次进入+3气"
		HGWMapGenerator.Terrain.GRAIL:    return "效果: 圣杯 — 持续占领可获得胜利"
		HGWMapGenerator.Terrain.DESERT:   return "效果: 沙漠 — 进入时触发随机事件"
		HGWMapGenerator.Terrain.SNOW:     return "效果: 雪地 — 进入时随机滑移"
	return ""

func _tier_name(tier: String) -> String:
	match tier:
		"common": return "普通"
		"rare":   return "稀有"
		"core":   return "核心"
	return tier

# ── Generation ────────────────────────────────────────────────────────────────

func _generate_map() -> void:
	var gen := HGWMapGenerator.new(MAP_RADIUS, _seed_val, NUM_PLAYERS)
	gen.LAND_THRESHOLD  = LAND_THRESHOLD
	gen.EDGE_DETAIL_AMP = EDGE_DETAIL_AMP
	gen.ELEVATION_FREQ  = ELEVATION_FREQ
	gen.MOISTURE_FREQ   = MOISTURE_FREQ
	gen.FORTRESS_COUNT  = FORTRESS_COUNT
	gen.generate()

	_cells  = gen.cells
	_radius = MAP_RADIUS
	_stats  = gen.stats
	_spawns = gen.spawns

	_header_seed_label.text = "Seed: %d" % _stats.get("seed", _seed_val)

	var terrain_count: Dictionary = {}
	var total_land: int = _stats.get("land", 0)
	for cell: HGWMapGenerator.Cell in _cells.values():
		if not cell.is_void:
			var tname: String = _terrain_abbr(cell.terrain)
			terrain_count[tname] = terrain_count.get(tname, 0) + 1

	var dist_lines: Array[String] = []
	for tname: String in terrain_count:
		var cnt: int = terrain_count[tname] as int
		dist_lines.append("%s:%d(%.0f%%)" % [tname, cnt, float(cnt) * 100.0 / float(max(total_land, 1))])

	var fair_str: String = "通过" if _stats.get("fair", false) else "未通过"
	var issues: Array = _stats.get("issues", [])
	var issue_str: String = "" if issues.is_empty() else " [%s]" % ", ".join(PackedStringArray(issues))

	_status_text_label.text = "Seed:%d | R=%d | P=%d | 陆地:%d/%d | %s%s | %s" % [
		_stats.get("seed", _seed_val),
		_radius,
		NUM_PLAYERS,
		total_land,
		_cells.size(),
		fair_str,
		issue_str,
		" ".join(PackedStringArray(dist_lines)),
	]

	if _first_load:
		_first_load = false
		for pos: Vector2i in _cells:
			_reveal_data[pos] = 1.0
	else:
		_start_reveal_animation()

func _terrain_abbr(t: int) -> String:
	match t:
		HGWMapGenerator.Terrain.VOID:     return "VOID"
		HGWMapGenerator.Terrain.PLAIN:    return "PLN"
		HGWMapGenerator.Terrain.FOREST:   return "FOR"
		HGWMapGenerator.Terrain.HIGHLAND: return "HIG"
		HGWMapGenerator.Terrain.MOUNTAIN: return "MTN"
		HGWMapGenerator.Terrain.FORTRESS: return "FRT"
		HGWMapGenerator.Terrain.GRAIL:    return "GRL"
		HGWMapGenerator.Terrain.DESERT:   return "DST"
		HGWMapGenerator.Terrain.SNOW:     return "SNW"
	return "?"

# ── Reveal animation ──────────────────────────────────────────────────────────

func _start_reveal_animation() -> void:
	if _reveal_tween and _reveal_tween.is_valid():
		_reveal_tween.kill()

	_reveal_data.clear()
	for pos: Vector2i in _cells:
		_reveal_data[pos] = 0.0

	var rings: Dictionary = {}
	for pos: Vector2i in _cells:
		var d: int = HGWMapGenerator.hex_distance(pos.x, pos.y, 0, 0)
		if not rings.has(d):
			rings[d] = []
		rings[d].append(pos)

	var sorted_dists: Array = rings.keys()
	sorted_dists.sort()

	_reveal_tween = create_tween()
	_reveal_tween.set_parallel(true)

	var ring_idx: int = 0
	for d: int in sorted_dists:
		var ring: Array = rings[d]
		for pos: Vector2i in ring:
			var t := _reveal_tween.tween_method(
				func(v: float): _reveal_data[pos] = v,
				0.0, 1.0, CELL_DURATION
			)
			t.set_delay(ring_idx * RING_DELAY)
			t.set_ease(Tween.EASE_OUT)
		ring_idx += 1

	_reveal_tween.finished.connect(
		func() -> void:
			for p: Vector2i in _cells:
				_reveal_data[p] = 1.0
			queue_redraw(),
		CONNECT_ONE_SHOT
	)

# ── Hex math ──────────────────────────────────────────────────────────────────

func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x: float = _hex_size * (sqrt(3) * q + sqrt(3) / 2.0 * r)
	var y: float = _hex_size * (1.5 * r)
	return Vector2(x, y)

func _hex_vertices(cx: float, cy: float, sz: float = -1.0) -> PackedVector2Array:
	var s: float = sz if sz > 0 else _hex_size
	var pts := PackedVector2Array()
	for i: int in range(6):
		var rad: float = deg_to_rad(60.0 * i - 30.0)
		pts.append(Vector2(cx + s * cos(rad), cy + s * sin(rad)))
	return pts

func _hex_vertices_static(cx: float, cy: float, sz: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(6):
		var rad: float = deg_to_rad(60.0 * i - 30.0)
		pts.append(Vector2(cx + sz * cos(rad), cy + sz * sin(rad)))
	return pts

func _pixel_to_hex(px: Vector2) -> Vector2i:
	var q: float = (sqrt(3) / 3.0 * px.x - 1.0 / 3.0 * px.y) / _hex_size
	var r: float = (2.0 / 3.0 * px.y) / _hex_size
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

# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _cells.is_empty():
		return

	_draw_background_art()

	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	var screen_center: Vector2 = vp_rect.position + vp_rect.size / 2.0

	# Cache neighbor colors for terrain blending
	var neighbor_cache: Dictionary = {}
	for pos: Vector2i in _cells:
		var cell: HGWMapGenerator.Cell = _cells[pos]
		if cell.is_void:
			continue
		var nbs: Array[Color] = []
		for nb: Vector2i in HGWMapGenerator.hex_neighbors(cell.q, cell.r):
			if _cells.has(nb) and not (_cells[nb] as HGWMapGenerator.Cell).is_void:
				nbs.append(HGWMapGenerator.terrain_color((_cells[nb] as HGWMapGenerator.Cell).terrain))
		neighbor_cache[pos] = nbs

	# Draw terrain layer
	for pos: Vector2i in _cells:
		var cell: HGWMapGenerator.Cell = _cells[pos]
		if cell.is_void:
			continue

		var reveal: float = _reveal_data.get(pos, 1.0)
		if reveal <= 0.01:
			continue

		var pixel: Vector2 = _hex_to_pixel(cell.q, cell.r) + screen_center
		var col: Color = HGWMapGenerator.terrain_color(cell.terrain)
		var alpha: float = reveal
		var scale: float = 0.7 + 0.3 * reveal

		# Bevel base
		draw_polygon(
			_hex_vertices(pixel.x, pixel.y, _hex_size * 1.0 * scale),
			PackedColorArray([col * Color(0.7, 0.7, 0.7, alpha)])
		)
		# Main fill
		draw_polygon(
			_hex_vertices(pixel.x, pixel.y, _hex_size * 0.92 * scale),
			PackedColorArray([Color(col, alpha)])
		)
		# Highlight arc
		var hl_r: float = _hex_size * 0.85 * scale
		var hl_col: Color = col * Color(1.3, 1.3, 1.3, alpha)
		var arc_pts := PackedVector2Array()
		for i: int in range(4):
			var rad: float = deg_to_rad(60.0 * i - 30.0)
			arc_pts.append(Vector2(pixel.x + hl_r * cos(rad), pixel.y + hl_r * sin(rad)))
		draw_polyline(arc_pts, hl_col, 1.2, true)

		# Terrain transition border
		var border_color: Color = C_PANEL_BDR * Color(1, 1, 1, 0.25 * alpha)
		var nbs: Array = neighbor_cache.get(pos, [])
		if not nbs.is_empty():
			var avg_c := Color.BLACK
			for nc: Color in nbs:
				avg_c += nc
			avg_c /= nbs.size()
			border_color = lerp(col, avg_c, 0.3) * Color(1, 1, 1, 0.4 * alpha)
		draw_polyline(
			_hex_vertices(pixel.x, pixel.y, _hex_size * scale) + PackedVector2Array([_hex_vertices(pixel.x, pixel.y, _hex_size * scale)[0]]),
			border_color, 0.8, true
		)

	# Draw special markers
	for pos: Vector2i in _cells:
		var cell: HGWMapGenerator.Cell = _cells[pos]
		if cell.is_void:
			continue

		var reveal: float = _reveal_data.get(pos, 1.0)
		if reveal <= 0.01:
			continue

		var pixel: Vector2 = _hex_to_pixel(cell.q, cell.r) + screen_center
		var alpha: float = reveal

		if cell.is_grail:
			for ri: int in range(3):
				var rr: float = _hex_size * (0.55 - ri * 0.15)
				draw_arc(pixel, rr, 0, TAU, 20, Color(1.0, 0.843, 0.0, (0.75 - ri * 0.25) * alpha), 1.5, true)
			draw_circle(pixel, 3.0, C_GOLD_BRT * Color(1, 1, 1, alpha))

		if cell.is_city:
			var r: float = _hex_size * 0.38
			var tower_color: Color = Color(0.863, 0.235, 0.235, 0.9 * alpha)
			draw_rect(Rect2(pixel.x - r * 0.8,  pixel.y + r * 0.1,  r * 1.6, r * 0.8), tower_color)
			draw_rect(Rect2(pixel.x - r * 0.5,  pixel.y - r * 0.4,  r * 1.0, r * 0.6), tower_color)
			draw_rect(Rect2(pixel.x - r * 0.25, pixel.y - r * 0.8,  r * 0.5, r * 0.5), tower_color)
			draw_polyline(PackedVector2Array([
				Vector2(pixel.x, pixel.y - r * 0.8),
				Vector2(pixel.x, pixel.y - r * 1.2),
			]), tower_color, 1.2, true)
			draw_polygon(PackedVector2Array([
				Vector2(pixel.x,           pixel.y - r * 1.2),
				Vector2(pixel.x + r * 0.6, pixel.y - r * 1.05),
				Vector2(pixel.x,           pixel.y - r * 0.9),
			]), PackedColorArray([Color(1.0, 0.843, 0.0, 0.9 * alpha)]))

		if cell.is_choke:
			draw_circle(pixel, _hex_size * 0.28, Color(1.0, 0.471, 0.157, 0.85 * alpha))
			draw_arc(pixel, _hex_size * 0.28, 0, TAU, 12, Color.BLACK * Color(1, 1, 1, 0.2 * alpha), 1.0, true)

		if cell.is_key:
			var s: float = _hex_size * 0.35
			var tri: PackedVector2Array = PackedVector2Array([
				Vector2(pixel.x,            pixel.y - s),
				Vector2(pixel.x + s * 0.866, pixel.y + s * 0.5),
				Vector2(pixel.x - s * 0.866, pixel.y + s * 0.5),
			])
			draw_polygon(tri, PackedColorArray([Color(1.0, 0.843, 0.0, 0.9 * alpha)]))
			draw_polyline(tri + PackedVector2Array([tri[0]]), Color.BLACK * Color(1, 1, 1, 0.2 * alpha), 0.8, true)

		if cell.is_resource:
			var dot_r: float = _hex_size * 0.20
			var dot_col: Color
			match cell.res_tier:
				"common": dot_col = Color(0.314, 0.706, 1.0,   0.9 * alpha)
				"rare":   dot_col = Color(0.706, 0.314, 1.0,   0.9 * alpha)
				"core":   dot_col = Color(1.0,   0.314, 0.314, 0.9 * alpha)
				_:        dot_col = Color(0.314, 0.706, 1.0,   0.9 * alpha)
			draw_circle(pixel, dot_r, dot_col)
			draw_arc(pixel, dot_r, 0, TAU, 12, Color.WHITE * Color(1, 1, 1, 0.25 * alpha), 0.6, true)

		if cell.is_reward:
			var rr: float = _hex_size * 0.30
			draw_polygon(PackedVector2Array([
				Vector2(pixel.x,            pixel.y - rr),
				Vector2(pixel.x + rr * 0.7, pixel.y),
				Vector2(pixel.x,            pixel.y + rr),
				Vector2(pixel.x - rr * 0.7, pixel.y),
			]), PackedColorArray([Color(1.0, 0.843, 0.0, 0.7 * alpha)]))

# ── Input ─────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _reveal_tween and _reveal_tween.is_valid() and _reveal_tween.is_running():
		queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_tooltip(event.position)
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_on_back_pressed()
		if event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_R):
			_seed_val = randi() % 99999 + 1
			_generate_map()
			queue_redraw()

func _on_back_pressed() -> void:
	SceneManager.go_to("res://scenes/main_menu.tscn")

func _on_refresh_pressed() -> void:
	_seed_val = randi() % 99999 + 1
	_generate_map()
	queue_redraw()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_flat(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s

func _make_spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
