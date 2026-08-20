## TowerFloorTransition — 慈悲尖塔层间过渡动画
## 全屏暗色叠加，显示层号+敌人名，支持对话和打字机效果
## 用法：add_child(TowerFloorTransition.new()) → start(floor_num, enemy_name, dialogue_data) → 连接 transition_finished
class_name TowerFloorTransition
extends Control

signal transition_finished

## ---- 配色 ----
const C_BG       := Color("#12100D")
const C_GOLD     := Color("#FAC775")
const C_TEXT     := Color("#E8E2D5")
const C_TEXT_DIM := Color("#9A9182")

var _overlay: ColorRect
var _floor_label: Label
var _enemy_label: Label
var _subtitle_label: Label
var _dialogue_box: DialogueBox
var _fade_duration: float = 0.6
var _hold_duration: float = 1.5
var _elapsed: float = 0.0
var _phase: String = ""  ## "fade_in", "hold", "dialogue", "fade_out", "done"
var _has_dialogue: bool = false

func _ready() -> void:
	_build_ui()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(delta: float) -> void:
	if _phase == "fade_in":
		_elapsed += delta
		var alpha := clampf(_elapsed / _fade_duration, 0.0, 1.0)
		_overlay.color = Color(C_BG, alpha)
		if alpha >= 1.0:
			_phase = "hold"
			_elapsed = 0.0
			_floor_label.visible = true
			_enemy_label.visible = true
			_subtitle_label.visible = not _has_dialogue
	elif _phase == "hold" and not _has_dialogue:
		_elapsed += delta
		if _elapsed >= _hold_duration:
			_fade_out()

## 启动过渡动画
## dialogue_data: 可选，传入 { speaker, lines } 则在hold后显示对话
func start(floor_num: int, enemy_name: String, dialogue_data: Dictionary = {}) -> void:
	_floor_label.text = "第 %d 层" % floor_num
	_enemy_label.text = enemy_name
	_has_dialogue = dialogue_data.is_empty() == false
	visible = true
	_phase = "fade_in"
	_elapsed = 0.0
	_overlay.color = Color(C_BG, 0.0)
	_floor_label.visible = false
	_enemy_label.visible = false
	_subtitle_label.visible = false
	_dialogue_box.visible = false

	if _has_dialogue:
		# 在淡入完成后显示对话
		await _wait_for_phase("hold")
		_subtitle_label.visible = false
		_dialogue_box.visible = true
		_dialogue_box.start(dialogue_data)
		await _dialogue_box.dialogue_finished
		# 对话结束后短暂停顿再淡出
		await get_tree().create_timer(0.3).timeout
		_fade_out()
	else:
		# 无对话时，hold阶段自动淡出
		pass

func _fade_out() -> void:
	_phase = "fade_out"
	var tween := create_tween()
	tween.tween_property(_overlay, "color", Color(C_BG, 0.0), 0.5)
	tween.tween_callback(func():
		visible = false
		_phase = "done"
		transition_finished.emit()
	)

func _wait_for_phase(target: String) -> void:
	while _phase != target and _phase != "done":
		await get_tree().process_frame

func _build_ui() -> void:
	# 全屏黑色遮罩
	_overlay = ColorRect.new()
	_overlay.color = Color(C_BG, 0.0)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	# 层号（大金字，上方）
	_floor_label = Label.new()
	_floor_label.add_theme_font_size_override("font_size", 36)
	_floor_label.add_theme_color_override("font_color", C_GOLD)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floor_label.anchor_left = 0.0; _floor_label.anchor_right = 1.0
	_floor_label.anchor_top = 0.25; _floor_label.anchor_bottom = 0.35
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_label.visible = false
	add_child(_floor_label)

	# 敌人名（白色，下方）
	_enemy_label = Label.new()
	_enemy_label.add_theme_font_size_override("font_size", 20)
	_enemy_label.add_theme_color_override("font_color", C_TEXT)
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_enemy_label.anchor_left = 0.0; _enemy_label.anchor_right = 1.0
	_enemy_label.anchor_top = 0.38; _enemy_label.anchor_bottom = 0.48
	_enemy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_label.visible = false
	add_child(_enemy_label)

	# 副标题提示"点击继续"
	_subtitle_label = Label.new()
	_subtitle_label.text = "点击继续"
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", C_TEXT_DIM)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.anchor_left = 0.0; _subtitle_label.anchor_right = 1.0
	_subtitle_label.offset_top = 490.0; _subtitle_label.offset_bottom = 510.0
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.visible = false
	add_child(_subtitle_label)

	# 嵌入 DialogueBox（用于层间对话）
	_dialogue_box = DialogueBox.new()
	_dialogue_box.visible = false
	add_child(_dialogue_box)

func _input(event: InputEvent) -> void:
	if not visible or _phase == "done":
		return
	# 无对话模式下，hold阶段点击可加速淡出
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _phase == "hold" and not _has_dialogue:
			_fade_out()
			accept_event()
