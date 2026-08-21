## TowerRewardUI — 慈悲尖塔层间奖励选择界面
## 通关每层后弹出 3 选 1 增益卡片，红黑黑暗风格 + 悬停发光特效
## 用法：add_child(TowerRewardUI.new()) → start() → 连接 reward_selected 信号
## 信号参数：reward_selected(buff: Dictionary)，buff 含 id/name/desc/value
class_name TowerRewardUI
extends Control

signal reward_selected(buff: Dictionary)
signal reward_closed

## ---- 配色（红黑黑暗风格） ----
const C_BG       := Color("#0D0A08")
const C_CARD_BG  := Color("#1A0A0A")
const C_CARD_HOVER := Color("#2A1010")
const C_BORDER   := Color("#8B2020")
const C_BORDER_HOVER := Color("#FF4040")
const C_GOLD     := Color("#FAC775")
const C_TEXT     := Color("#E8E2D5")
const C_TEXT_DIM := Color("#9A9182")
const C_RED      := Color("#C83030")
const C_RED_GLOW := Color("#FF6060")

## ---- 奖励池定义 ----
## tier: "normal"=小怪层可出；"elite"=仅精英层可出
const REWARD_POOL := [
	# ── 普通祝福（小怪层/精英层均可出）──
	{ "id": "blade_power",  "name": "锋刃之力", "icon": "⚔", "desc": "普攻伤害 +1", "value": 1.0, "color": Color("#C83030"), "tier": "normal" },
	{ "id": "charge_bonus", "name": "蓄锐",     "icon": "✦", "desc": "每回合额外聚气 +1（唯一）", "value": 1, "color": Color("#FAC775"), "tier": "normal", "unique": true },
	{ "id": "clone",        "name": "影分身",   "icon": "◆", "desc": "开局获得 1 个影分身", "value": 1, "color": Color("#A060C0"), "tier": "normal" },
	{ "id": "swift",        "name": "神速",     "icon": "⚡", "desc": "开局获得 2 点气（可叠加）", "value": 2, "color": Color("#FAC775"), "tier": "normal" },
	{ "id": "protect",      "name": "庇护",     "icon": "❂", "desc": "开局获得 2 点护盾", "value": 2, "color": Color("#C0C0A0"), "tier": "normal" },
	{ "id": "vitality",     "name": "生机",     "icon": "✚", "desc": "生命上限 +3", "value": 3, "color": Color("#60C060"), "tier": "normal" },
	# ── 高级祝福（仅精英层可出）──
	{ "id": "blade_power_2", "name": "锋芒",     "icon": "⚔", "desc": "普攻伤害 +2", "value": 2.0, "color": Color("#E04040"), "tier": "elite" },
	{ "id": "shield_wall",  "name": "坚壁",     "icon": "▣", "desc": "受到伤害 -0.5（唯一）", "value": 0.5, "color": Color("#6080A0"), "tier": "elite", "unique": true },
	{ "id": "regen",        "name": "回生",     "icon": "♥", "desc": "自己回合开始时回复 1 点生命（唯一）", "value": 1.0, "color": Color("#60C060"), "tier": "elite", "unique": true },
	{ "id": "regen_2",      "name": "再生",     "icon": "♥", "desc": "自己回合开始时回复 2 点生命", "value": 2.0, "color": Color("#40A040"), "tier": "elite" },
	{ "id": "swift_2",      "name": "疾风",     "icon": "⚡", "desc": "开局获得 5 点气", "value": 5, "color": Color("#FAC775"), "tier": "elite" },
	{ "id": "vitality_2",   "name": "龙血",     "icon": "✚", "desc": "生命上限 +5", "value": 5, "color": Color("#40C060"), "tier": "elite" },
	{ "id": "protect_2",    "name": "铁壁",     "icon": "❂", "desc": "开局获得 5 点护盾", "value": 5, "color": Color("#90B0C0"), "tier": "elite" },
]

## ---- UI 引用 ----
var _overlay: ColorRect
var _title_label: Label
var _subtitle_label: Label
var _card_container: HBoxContainer
var _cards: Array[Panel] = []
var _card_tweens: Array[Tween] = []
var _glow_timer: float = 0.0
var _is_active: bool = false
var _current_choices: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	visible = false

func _process(delta: float) -> void:
	if not _is_active:
		return
	_glow_timer += delta
	# 卡片边框呼吸光效
	for i in range(_cards.size()):
		if i < _card_tweens.size() and _card_tweens[i] != null and is_instance_valid(_card_tweens[i]):
			continue  # 悬停中的卡片跳过呼吸
		var card := _cards[i]
		if card == null or not is_instance_valid(card):
			continue
		var stylebox := card.get_theme_stylebox("panel") as StyleBoxFlat
		if stylebox == null:
			continue
		var pulse := 0.5 + 0.5 * sin(_glow_timer * 2.0 + i * 0.5)
		var border_color := C_BORDER.lerp(C_BORDER_HOVER, pulse * 0.3)
		stylebox.border_color = border_color

## 启动奖励选择：随机 3 种不重复奖励
## allow_elite：true=允许高级祝福（精英层通关后），false=仅普通祝福
## obtained_ids：已获取的奖励 id 列表（unique 奖励已获取后不再出现）
func start(allow_elite: bool = false, obtained_ids: Array = []) -> void:
	_current_choices = _pick_random_rewards(3, allow_elite, obtained_ids)
	_show_cards(_current_choices)
	_is_active = true
	visible = true

## 指定奖励选择（测试用）
func start_with_choices(choices: Array[Dictionary]) -> void:
	_current_choices = choices
	_show_cards(_current_choices)
	_is_active = true
	visible = true

## 随机抽取 n 个不重复奖励
## allow_elite=false：仅从 normal 池抽取；true：从 normal+elite 全池抽取
## obtained_ids：已获取的奖励 id 列表。unique 奖励已获取后不再出现
func _pick_random_rewards(count: int, allow_elite: bool = false, obtained_ids: Array = []) -> Array[Dictionary]:
	var pool: Array = []
	for reward in REWARD_POOL:
		if allow_elite or reward.get("tier", "normal") == "normal":
			# unique 奖励已获取过 → 跳过
			if reward.get("unique", false) and reward.get("id", "") in obtained_ids:
				continue
			pool.append(reward)
	pool.shuffle()
	var result: Array[Dictionary] = []
	for i in range(min(count, pool.size())):
		result.append(pool[i])
	return result

## 显示卡片
func _show_cards(choices: Array[Dictionary]) -> void:
	# 清除旧卡片
	for i in range(_cards.size()):
		var card := _cards[i]
		if card != null and is_instance_valid(card):
			card.queue_free()
		if i < _card_tweens.size():
			var tw := _card_tweens[i]
			if tw != null and is_instance_valid(tw):
				tw.kill()
	_cards.clear()
	_card_tweens.clear()

	for i in range(choices.size()):
		var reward: Dictionary = choices[i]
		var card := _build_card(reward, i)
		_card_container.add_child(card)
		_cards.append(card)
		_card_tweens.append(null)

	# 入场动画
	_play_entrance_animation()

func _build_card(reward: Dictionary, index: int) -> Panel:
	var card := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = C_CARD_BG
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = C_BORDER
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", style)

	# 卡片尺寸
	card.custom_minimum_size = Vector2(200, 280)

	# 图标（大号符号）
	var icon_label := Label.new()
	icon_label.text = reward.get("icon", "?")
	icon_label.add_theme_font_size_override("font_size", 48)
	icon_label.add_theme_color_override("font_color", reward.get("color", C_GOLD))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.anchor_left = 0.0
	icon_label.anchor_right = 1.0
	icon_label.anchor_top = 0.08
	icon_label.anchor_bottom = 0.25
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_label)

	# 名称
	var name_label := Label.new()
	name_label.text = reward.get("name", "")
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", C_GOLD)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.anchor_left = 0.0
	name_label.anchor_right = 1.0
	name_label.anchor_top = 0.30
	name_label.anchor_bottom = 0.38
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_label)

	# 分隔线
	var sep := ColorRect.new()
	sep.color = C_BORDER
	sep.anchor_left = 0.2
	sep.anchor_right = 0.8
	sep.anchor_top = 0.42
	sep.anchor_bottom = 0.425
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep)

	# 描述
	var desc_label := Label.new()
	desc_label.text = reward.get("desc", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", C_TEXT)
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.anchor_left = 0.05
	desc_label.anchor_right = 0.95
	desc_label.anchor_top = 0.48
	desc_label.anchor_bottom = 0.70
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_label)

	# 选择提示
	var hint_label := Label.new()
	hint_label.text = "点击选择"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", C_TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.anchor_left = 0.0
	hint_label.anchor_right = 1.0
	hint_label.anchor_top = 0.85
	hint_label.anchor_bottom = 0.95
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hint_label)

	# 鼠标悬停信号
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.gui_input.connect(_on_card_input.bind(index))
	card.mouse_exited.connect(_on_card_unhover.bind(index))

	return card

## 入场动画：卡片从下方滑入 + 淡入
func _play_entrance_animation() -> void:
	for i in range(_cards.size()):
		var card := _cards[i]
		if card == null:
			continue
		card.modulate.a = 0.0
		card.position.y += 40
		var tw := create_tween()
		tw.tween_interval(i * 0.1)
		tw.parallel().tween_property(card, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(card, "position:y", card.position.y - 40, 0.4).set_trans(Tween.TRANS_SINE)
	# 标题淡入
	_title_label.modulate.a = 0.0
	_subtitle_label.modulate.a = 0.0
	var tw_title := create_tween()
	tw_title.tween_property(_title_label, "modulate:a", 1.0, 0.4)
	tw_title.tween_property(_subtitle_label, "modulate:a", 1.0, 0.3)

## 卡片输入处理
func _on_card_input(event: InputEvent, index: int) -> void:
	if not _is_active or index >= _current_choices.size():
		return
	if event is InputEventMouseMotion:
		_on_card_hover(index)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_card_clicked(index)

## 卡片悬停效果
func _on_card_hover(index: int) -> void:
	var card := _cards[index]
	if card == null:
		return
	var stylebox := card.get_theme_stylebox("panel") as StyleBoxFlat
	if stylebox == null:
		return
	# 如果已有悬停动画在播放，不重复
	if _card_tweens[index] != null and is_instance_valid(_card_tweens[index]):
		return
	# 悬停：边框变亮 + 背景加深 + 轻微放大
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(
		func(c: Color): stylebox.border_color = c,
		stylebox.border_color, C_BORDER_HOVER, 0.2
	)
	tw.tween_method(
		func(c: Color): stylebox.bg_color = c,
		stylebox.bg_color, C_CARD_HOVER, 0.2
	)
	tw.tween_property(card, "scale", Vector2(1.05, 1.05), 0.2).set_trans(Tween.TRANS_SINE)
	_card_tweens[index] = tw

## 卡片离开悬停：恢复原样式
func _on_card_unhover(index: int) -> void:
	var card := _cards[index]
	if card == null:
		return
	var stylebox := card.get_theme_stylebox("panel") as StyleBoxFlat
	if stylebox == null:
		return
	# 清除悬停动画
	var tw := _card_tweens[index]
	if tw != null and is_instance_valid(tw):
		tw.kill()
	_card_tweens[index] = null
	# 恢复边框/背景/缩放
	var rt := create_tween()
	rt.set_parallel(true)
	rt.tween_method(
		func(c: Color): stylebox.border_color = c,
		stylebox.border_color, C_BORDER, 0.2
	)
	rt.tween_method(
		func(c: Color): stylebox.bg_color = c,
		stylebox.bg_color, C_CARD_BG, 0.2
	)
	rt.tween_property(card, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)

## 卡片离开悬停（通过 mouse_entered/exited 也可以，这里简化处理）
## 卡片点击：选中奖励
func _on_card_clicked(index: int) -> void:
	if not _is_active or index >= _current_choices.size():
		return
	_is_active = false
	var reward: Dictionary = _current_choices[index]
	# 选中动画：卡片放大 + 其他卡片淡出
	var selected_card := _cards[index]
	var tw := create_tween()
	tw.tween_property(selected_card, "scale", Vector2(1.15, 1.15), 0.15).set_trans(Tween.TRANS_SINE)
	for i in range(_cards.size()):
		if i != index:
			var c := _cards[i]
			if c != null and is_instance_valid(c):
				tw.parallel().tween_property(c, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		visible = false
		reward_selected.emit(reward)
	)

## 构建 UI
func _build_ui() -> void:
	# 全屏半透明暗色遮罩
	_overlay = ColorRect.new()
	_overlay.color = Color(C_BG, 0.85)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# 标题
	_title_label = Label.new()
	_title_label.text = "选择祝福"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", C_GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.anchor_top = 0.08
	_title_label.anchor_bottom = 0.16
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.text = "神官·梅塔特隆将赐予你一项力量"
	_subtitle_label.add_theme_font_size_override("font_size", 13)
	_subtitle_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.anchor_left = 0.0
	_subtitle_label.anchor_right = 1.0
	_subtitle_label.anchor_top = 0.16
	_subtitle_label.anchor_bottom = 0.22
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle_label)

	# 卡片容器（水平排列，居中）
	_card_container = HBoxContainer.new()
	_card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_container.anchor_left = 0.1
	_card_container.anchor_right = 0.9
	_card_container.anchor_top = 0.28
	_card_container.anchor_bottom = 0.88
	_card_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_container)

## 获取全部奖励池（测试用）
func get_reward_pool() -> Array:
	return REWARD_POOL.duplicate(true)

## 关闭界面（不选择）
func close() -> void:
	_is_active = false
	visible = false
	reward_closed.emit()
